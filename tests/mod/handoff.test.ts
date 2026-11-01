// Mod tests for hooks/handoff.ts. Run from the plugin root: `claude plugin test`.
// The stubs and the call log live in rig.ts; fixtures are the exact stdout of
// scripts/drive-take.sh (tests/mod/fixtures), with @ROOT@ substituted.
import { expect, test } from 'claude-code/testing'
import { CONTINUATION } from './fixtures'
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
    'command.run compact [keep the parser work]',
    `prompt.submit ${CONTINUATION} asUser=true`,
  ])
  expect(r.toasts).toEqual(['handoff: will run /compact keep the parser work once the turn ends.'])
  expect(r.writes).toEqual([])
})

test('clear: rename, then clear (no args), then the continuation, in order', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD) })
  await endTurn($)
  expect(r.log).toEqual([
    'process.run',
    'command.run rename [A Title]',
    'command.run clear []',
    `prompt.submit ${CONTINUATION} asUser=true`,
  ])
  expect(r.toasts).toEqual(['handoff: will run /rename A Title once the turn ends.'])
})

test('rename kind runs the single rename line', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-rename', CWD) })
  await endTurn($)
  expect(r.log).toEqual(['process.run', 'command.run rename [Driven Transitions]'])
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

test('lock-busy plan toasts its message and runs nothing', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('lock-busy', CWD) })
  await endTurn($)
  expect(r.log).toEqual(['process.run'])
  expect(r.toasts.length).toBe(1)
  expect(r.toasts[0]).toContain("the sentinel's lock was busy")
})

// --- failure ---------------------------------------------------------------

test('first rejected line ends the sequence and writes failFile', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-clear', CWD),
    rejectLines: { '/rename A Title': 'unknown command' },
  })
  await endTurn($)
  expect(r.log).toEqual([
    'process.run',
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
    rejectLines: { [CONTINUATION]: 'queue full' },
  })
  await endTurn($)
  expect(r.log).toEqual([
    'process.run',
    'command.run compact [keep the parser work]',
    `prompt.submit ${CONTINUATION} asUser=true`,
    `fs.write ${FAIL_FILE}`,
  ])
  expect(r.writes[0].text).toContain(CONTINUATION)
})

// A Stop with no session id drives nothing (drive-take.sh cannot tell whose
// file it is), but says so on the rejected-line path: failFile written, toast.
test('a Stop with no session id writes failFile and toasts', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('no-session', CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: undefined })
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.processArgv[0][3]).toBe('')
  expect(r.log).toEqual(['process.run', `fs.write ${FAIL_FILE}`])
  expect(r.writes[0].text).toContain('no session id')
  expect(r.toasts).toEqual([r.writes[0].text.trimEnd()])
})

// A link at the failure record, dangling or not, is not written through: the
// record is skipped and the toast says so. The check is one stat ahead of the
// write, a window a link put there in between still has.
test('a link at failFile is not written through', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-clear', CWD),
    rejectLines: { '/rename A Title': 'unknown command' },
    statIsLink: true,
  })
  await endTurn($)
  expect(r.statPaths).toEqual([FAIL_FILE])
  expect(r.writes).toEqual([])
  expect(r.toasts.length).toBe(2)
  expect(r.toasts[1]).toContain('/rename A Title')
  expect(r.toasts[1]).toContain('symbolic link')
})

// --- a prompt after Stop ----------------------------------------------------
// The window runs from classic.Stop to the transition command being issued. A
// prompt in it asks drive-cancel.sh once; a cancel stops the take's lines.
// `PROMPT` is what a person typed; the rig's prompt.submit stub beneath the
// mod records what reached it (r.submitted).

const PROMPT = { text: 'say banana' }
const CANCEL_CLEAR = (c: string) => fixture('cancel-clear', c)
const CANCEL_NOTE = 'The driven /clear did not run. Answer this prompt, then run the handoff skill again with the same transition, unless this prompt changes that.'
const CANCEL_MSG = 'handoff: transition cancelled — a prompt arrived before it ran.'
const SAY = 'prompt.submit say banana asUser=undefined'

// Lets the mod's pending awaits run until `done`, yielding to the event loop
// (the kit's dispatch is not microtask-only); no fixed delay is waited.
async function until(done: () => boolean) {
  for (let i = 0; i < 1000 && !done(); i++) await new Promise((res) => setTimeout(res, 0))
  expect(done()).toBe(true)
}

test('a prompt after Stop, before turn.complete, with a cancel: the take runs no line and the prompt carries the note', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD), cancelStdout: CANCEL_CLEAR(CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toEqual(['process.run cancel', SAY, 'process.run'])
  expect(r.cancelArgv.length).toBe(1)
  const [bash, script, cwd, session, ...rest] = r.cancelArgv[0]
  expect(bash).toBe('bash')
  expect(script.endsWith('/scripts/drive-cancel.sh')).toBe(true)
  expect([cwd, session, rest]).toEqual([CWD, 's1', []])
  expect(r.submitted).toEqual([{ text: 'say banana', context: [CANCEL_NOTE] }])
  expect(r.toasts).toEqual([CANCEL_MSG])
  expect(r.writes).toEqual([])
})

test('a prompt during the take, held open, with a cancel: no line runs', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-clear', CWD),
    cancelStdout: CANCEL_CLEAR(CWD),
    hold: { take: true },
  })
  const done = endTurn($)
  await until(() => r.log.includes('process.run'))
  await $.prompt.submit(PROMPT)
  r.release.take()
  await done
  expect(r.log).toEqual(['process.run', 'process.run cancel', SAY])
  expect(r.submitted[0].context).toEqual([CANCEL_NOTE])
  expect(r.toasts).toEqual([CANCEL_MSG])
})

test('a prompt answered after the take returned, before the first line: no line runs', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-clear', CWD),
    cancelStdout: CANCEL_CLEAR(CWD),
    hold: { cancel: true },
  })
  const done = endTurn($)
  const said = $.prompt.submit(PROMPT)
  await until(() => r.log.includes('process.run cancel') && r.log.includes('process.run'))
  r.release.cancel()
  await said
  await done
  expect(r.log).not.toContain('command.run rename [A Title]')
  expect(r.log.filter((l: string) => l.startsWith('command.run') || l.includes(CONTINUATION))).toEqual([])
  expect(r.toasts).toEqual([CANCEL_MSG])
})

test('a prompt while /rename is in flight under clear: /clear and the continuation do not run', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-clear', CWD),
    cancelStdout: CANCEL_CLEAR(CWD),
    holdLine: '/rename A Title',
  })
  const done = endTurn($)
  await until(() => r.log.includes('command.run rename [A Title]'))
  await $.prompt.submit(PROMPT)
  r.release.line()
  await done
  expect(r.log).toEqual(['process.run', 'command.run rename [A Title]', 'process.run cancel', SAY])
  expect(r.submitted[0].context).toEqual([CANCEL_NOTE])
})

test('a prompt after the last before-line is issued: no drive-cancel spawn, the continuation still runs', async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: fixture('armed-clear', CWD),
    cancelStdout: CANCEL_CLEAR(CWD),
    holdLine: '/clear',
  })
  const done = endTurn($)
  await until(() => r.log.includes('command.run clear []'))
  await $.prompt.submit(PROMPT)
  r.release.line()
  await done
  expect(r.cancelArgv).toEqual([])
  expect(r.submitted[0]).toEqual({ text: 'say banana', context: [] })
  expect(r.log).toContain(`prompt.submit ${CONTINUATION} asUser=true`)
})

test('a prompt with no recorded Stop (mid-turn): no spawn, the prompt passes unchanged', async ($, on) => {
  const r = rig(on, { sentinelExists: true, cancelStdout: CANCEL_CLEAR(CWD) })
  await $.prompt.submit(PROMPT)
  expect(r.cancelArgv).toEqual([])
  expect(r.submitted).toEqual([{ text: 'say banana', context: [] }])
  expect(r.toasts).toEqual([])
})

test('a prompt after a turn ended and its drive finished: no spawn', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-rename', CWD), cancelStdout: CANCEL_CLEAR(CWD) })
  await endTurn($)
  await $.prompt.submit(PROMPT)
  expect(r.cancelArgv).toEqual([])
})

test('drive-cancel prints nothing: the plan runs in full and the prompt passes unchanged', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD), cancelStdout: '' })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toEqual([
    'process.run cancel',
    SAY,
    'process.run',
    'command.run rename [A Title]',
    'command.run clear []',
    `prompt.submit ${CONTINUATION} asUser=true`,
  ])
  expect(r.submitted[0]).toEqual({ text: 'say banana', context: [] })
  expect(r.toasts).toEqual(['handoff: will run /rename A Title once the turn ends.'])
})

test('the drive-cancel spawn rejects: the plan runs in full and the prompt passes unchanged', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD), cancelRejects: true })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toEqual([
    'process.run cancel',
    SAY,
    'process.run',
    'command.run rename [A Title]',
    'command.run clear []',
    `prompt.submit ${CONTINUATION} asUser=true`,
  ])
  expect(r.submitted[0]).toEqual({ text: 'say banana', context: [] })
})

test('drive-cancel prints bad JSON: the same as nothing', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-compact', CWD), cancelStdout: 'not json' })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toContain('command.run compact [keep the parser work]')
  expect(r.submitted[0].context).toEqual([])
})

test("the mod's own continuation never spawns drive-cancel", async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-compact', CWD) })
  await endTurn($)
  expect(r.log).toContain(`prompt.submit ${CONTINUATION} asUser=true`)
  expect(r.cancelArgv).toEqual([])
})

test('a second prompt in the window spawns drive-cancel once', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD), cancelStdout: CANCEL_CLEAR(CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.prompt.submit({ text: 'and kiwi' })
  expect(r.cancelArgv.length).toBe(1)
  expect(r.submitted[0].context).toEqual([CANCEL_NOTE])
  expect(r.submitted[1].context).toEqual([])
})

test('a prompt in the window of a rename: nothing to cancel, the rename still runs', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-rename', CWD), cancelStdout: '' })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toContain('command.run rename [Driven Transitions]')
})

// A rename is not cancelled. The window can have the sweep read the file before
// the take does, so drive-cancel.sh takes it and answers with the take's plan;
// the drive runs that plan, whether the fast path would have skipped the take
// (the script just removed the file) or the take printed nothing.
test('a rename answer, prompt before turn.complete, no sentinel (fast path): the rename still runs', async ($, on) => {
  const r = rig(on, { sentinelExists: false, stdout: '', cancelStdout: fixture('armed-rename', CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toEqual(['process.run cancel', SAY, 'command.run rename [Driven Transitions]'])
  expect(r.submitted).toEqual([{ text: 'say banana', context: [] }])
  expect(r.toasts).toEqual(['handoff: will run /rename Driven Transitions once the turn ends.'])
})

test('a rename answer with the take printing empty: the rename runs from the answer', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: '', cancelStdout: fixture('armed-rename', CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, usage: null })
  expect(r.log).toEqual(['process.run cancel', SAY, 'process.run', 'command.run rename [Driven Transitions]'])
  expect(r.submitted[0].context).toEqual([])
  expect(r.toasts).toEqual(['handoff: will run /rename Driven Transitions once the turn ends.'])
})
