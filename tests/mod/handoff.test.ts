// Mod tests for hooks/handoff.ts. Run from the plugin root: `claude plugin test`.
// The stubs and the call log live in rig.ts; fixtures are the exact stdout of
// scripts/drive-take.sh (tests/mod/fixtures), with @ROOT@ substituted.
import { expect, test } from 'claude-code/testing'
import { fixture, rig, ROOT } from './rig'

const CWD = ROOT
const SENTINEL = `${CWD}/.claude/autodrive`
const FAIL_FILE = `${CWD}/.claude/autodrive.failed`

async function endTurn($: any, cwd: string | null = CWD) {
  if (cwd !== null) await $.classic.Stop({ cwd, session_id: 's1' })
  return $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
}

// --- Stop records, turn.complete drives -----------------------------------

test('classic.Stop records the cwd and drives nothing', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  expect(r.log).toEqual([])
  expect(r.existsPaths).toEqual([])
})

test('turn.complete with no Stop before it (aborted turn) drives nothing', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD) })
  await $.turn.complete({ turnId: 't1', answer: '', durationMs: 1, isAborted: true, usage: null })
  expect(r.log).toEqual([])
  expect(r.existsPaths).toEqual([])
})

test('a recorded cwd is consumed once', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('prepare-only-compact', CWD) })
  await endTurn($)
  await $.turn.complete({ turnId: 't2', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toEqual(['process.run'])
})

// --- fast path and process.run ---------------------------------------------

test('project-root cwd without a sentinel never spawns', async ($, on) => {
  const r = rig(on, { sentinelExists: false })
  await endTurn($)
  expect(r.existsPaths).toEqual([SENTINEL])
  expect(r.log).toEqual([])
})

// The session id is what lets drive-take.sh take only this session's armed
// file: every session sharing the root ends turns there.
test('a sentinel makes it run drive-take.sh with the cwd and the Stop session id', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: '' })
  await endTurn($)
  expect(r.log).toEqual(['process.run'])
  expect(r.processArgv.length).toBe(1)
  const [bash, script, cwd, session, ...rest] = r.processArgv[0]
  expect(bash).toBe('bash')
  expect(script.endsWith('/scripts/drive-take.sh')).toBe(true)
  expect(cwd).toBe(CWD)
  expect(session).toBe('s1')
  expect(rest).toEqual([])
})

test('a worktree or subdir cwd runs the script even without a sentinel there', async ($, on) => {
  const wt = '/work/proj-wt'
  const r = rig(on, { sentinelExists: false, stdout: '' })
  await endTurn($, wt)
  expect(r.log).toEqual(['process.run'])
  expect(r.processArgv[0][2]).toBe(wt)
})

test('empty stdout is a no-op', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: '' })
  await endTurn($)
  expect(r.log).toEqual(['process.run'])
  expect(r.toasts).toEqual([])
  expect(r.writes).toEqual([])
})

// --- executing the plan ----------------------------------------------------

test('compact with focus: command compact + args, then the continuation prompt', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-compact', CWD) })
  await endTurn($)
  expect(r.log).toEqual([
    'process.run',
    'prompt.read',
    'command.run compact [keep the parser work]',
    'prompt.read',
    'prompt.submit continue with task 3 asUser=true',
  ])
  expect(r.toasts).toEqual(['handoff: will run /compact keep the parser work once the turn ends.'])
  expect(r.writes).toEqual([])
})

test('clear: rename, then clear (no args), then the continuation, in order', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD) })
  await endTurn($)
  expect(r.log).toEqual([
    'process.run',
    'prompt.read',
    'command.run rename [A Title]',
    'prompt.read',
    'command.run clear []',
    'prompt.read',
    'prompt.submit pick up per the task file asUser=true',
  ])
  expect(r.toasts).toEqual(['handoff: will run /rename A Title once the turn ends.'])
})

test('rename kind runs the single rename line', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-rename', CWD) })
  await endTurn($)
  expect(r.log).toEqual(['process.run', 'prompt.read', 'command.run rename [Driven Transitions]'])
})

test('FR-G: empty before and after toasts the message and runs nothing', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('prepare-only-compact', CWD) })
  await endTurn($)
  expect(r.log).toEqual(['process.run'])
  expect(r.toasts).toEqual(['handoff: prepared for compact; nothing to run, frame will be re-injected.'])
})

test('malformed plan toasts its message and runs nothing', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('malformed', CWD) })
  await endTurn($)
  expect(r.log).toEqual(['process.run'])
  expect(r.toasts.length).toBe(1)
  expect(r.toasts[0]).toContain('autodrive malformed')
})

// --- bail and failure ------------------------------------------------------

test('text in the prompt box before the first line bails out of everything', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD), promptTexts: ['half-typed'] })
  await endTurn($)
  expect(r.log).toEqual(['process.run', 'prompt.read'])
  expect(r.writes).toEqual([])
})

test('text typed mid-sequence bails before the next line', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD), promptTexts: ['', 'half-typed'] })
  await endTurn($)
  expect(r.log).toEqual(['process.run', 'prompt.read', 'command.run rename [A Title]', 'prompt.read'])
  expect(r.writes).toEqual([])
})

test('first rejected line ends the sequence and writes failFile', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-clear', CWD),
    rejectLines: { '/rename A Title': 'unknown command' },
  })
  await endTurn($)
  expect(r.log).toEqual([
    'process.run',
    'prompt.read',
    'command.run rename [A Title]',
    `fs.write ${FAIL_FILE}`,
  ])
  expect(r.writes.length).toBe(1)
  expect(r.writes[0].path).toBe(FAIL_FILE)
  // the reason names the line that failed (the stub's own message is not carried
  // through a rejected event-backed call)
  expect(r.writes[0].text).toContain('/rename A Title')
  expect(r.toasts.length).toBe(2)
  expect(r.toasts[1]).toContain('/rename A Title')
})

test('a rejected continuation prompt is recorded the same way', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-compact', CWD),
    rejectLines: { 'continue with task 3': 'queue full' },
  })
  await endTurn($)
  expect(r.log).toEqual([
    'process.run',
    'prompt.read',
    'command.run compact [keep the parser work]',
    'prompt.read',
    'prompt.submit continue with task 3 asUser=true',
    `fs.write ${FAIL_FILE}`,
  ])
  expect(r.writes[0].text).toContain('continue with task 3')
})
