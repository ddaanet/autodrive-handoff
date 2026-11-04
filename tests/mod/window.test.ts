// Mod tests for a prompt after the arming turn's Stop (hooks/handoff.ts,
// docs/design/queued-prompts.md). The stubs and the call log live in rig.ts;
// the rest of the mod's rows are in handoff.test.ts.
import { expect, test } from 'claude-code/testing'
import { CONTINUATION } from './fixtures'
import { endTurn, fixture, rig, ROOT } from './rig'

const CWD = ROOT

// --- a prompt after Stop ----------------------------------------------------
// The window runs from classic.Stop to the transition command being issued. A
// prompt in it asks drive-cancel.sh once; a cancel stops the take's lines.
// `PROMPT` is what a person typed; the rig's prompt.submit stub beneath the
// mod records what reached it (r.submitted).

const PROMPT = { text: 'say banana' }
const CANCEL_CLEAR = (c: string) => fixture('cancel-clear', c)
const { note: CANCEL_NOTE, message: CANCEL_MSG } = JSON.parse(CANCEL_CLEAR(CWD))
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
  await endTurn($, null)
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

test('a prompt after the last command is issued: no drive-cancel spawn, the continuation still runs', async ($, on) => {
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
  await endTurn($, null)
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
  await endTurn($, null)
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
  await endTurn($, null)
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
  await endTurn($, null)
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
  await endTurn($, null)
  expect(r.log).toEqual(['process.run cancel', SAY, 'command.run rename [Driven Transitions]'])
  expect(r.submitted).toEqual([{ text: 'say banana', context: [] }])
  expect(r.toasts).toEqual(['handoff: will run /rename Driven Transitions once the turn ends.'])
})

test('a rename answer with the take printing empty: the rename runs from the answer', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: '', cancelStdout: fixture('armed-rename', CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await endTurn($, null)
  expect(r.log).toEqual(['process.run cancel', SAY, 'process.run', 'command.run rename [Driven Transitions]'])
  expect(r.submitted[0].context).toEqual([])
  expect(r.toasts).toEqual(['handoff: will run /rename Driven Transitions once the turn ends.'])
})

// The continuation is a prompt like any other to the handler: a later Stop
// still unconsumed when it arrives opens a window for it. Skipping it would
// leave the armed file to the UserPromptSubmit sweep, which discards it. The
// later window's rename is taken by its answer and run by its own drive, after
// the outer drive's finally has run.
test("a later Stop before the continuation: the continuation's rename answer still runs after the outer drive ends", async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: [fixture('armed-clear', CWD), ''],
    cancelStdout: fixture('armed-rename', CWD),
    holdLine: '/clear',
  })
  const done = endTurn($)
  await until(() => r.log.includes('command.run clear []'))
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  r.release.line()
  await done
  expect(r.log).toEqual([
    'process.run',
    'command.run rename [A Title]',
    'command.run clear []',
    'process.run cancel',
    `prompt.submit ${CONTINUATION} asUser=true`,
  ])
  await endTurn($, null, 't2')
  expect(r.log.slice(5)).toEqual(['process.run', 'command.run rename [Driven Transitions]'])
  expect(r.submitted[0].context).toEqual([])
})

// The outer drive's finally closes only its own window. Here the continuation
// is in flight when the next turn ends and its drive starts; a person's prompt
// after the outer drive ended still finds that drive's window open.
test("the outer drive's end leaves the next drive's window open: a prompt after it still cancels", async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: [fixture('armed-compact', CWD), fixture('armed-clear', CWD)],
    cancelStdout: CANCEL_CLEAR(CWD),
    holdSubmit: CONTINUATION,
    holdLine: '/rename A Title',
  })
  const done1 = endTurn($)
  await until(() => r.log.includes(`prompt.submit ${CONTINUATION} asUser=true`))
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  const done2 = endTurn($, null, 't2')
  await until(() => r.log.includes('command.run rename [A Title]'))
  r.release.submit()
  await done1
  await $.prompt.submit(PROMPT)
  r.release.line()
  await done2
  expect(r.log).toEqual([
    'process.run',
    'command.run compact [keep the parser work]',
    `prompt.submit ${CONTINUATION} asUser=true`,
    'process.run',
    'command.run rename [A Title]',
    'process.run cancel',
    SAY,
  ])
  expect(r.submitted[1].context).toEqual([CANCEL_NOTE])
})

// Likewise the outer drive closing its window at its last command: here the
// next turn's drive is already in flight, and its window stays open.
test("the outer drive's /clear being issued leaves the next drive's window open: a prompt after it still cancels", async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: [fixture('armed-clear', CWD), fixture('armed-clear', CWD)],
    cancelStdout: CANCEL_CLEAR(CWD),
    holdLine: ['/rename A Title', '/rename A Title', '/clear'],
  })
  const done1 = endTurn($)
  await until(() => r.log.includes('command.run rename [A Title]'))
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  const done2 = endTurn($, null, 't2')
  await until(() => r.log.filter((l: string) => l === 'command.run rename [A Title]').length === 2)
  r.release.line('/rename A Title')
  await until(() => r.log.includes('command.run clear []'))
  await $.prompt.submit(PROMPT)
  r.release.line()
  await done1
  await done2
  expect(r.log.filter((l: string) => l === 'command.run clear []').length).toBe(1)
  expect(r.submitted.find((s: any) => s.text === 'say banana').context).toEqual([CANCEL_NOTE])
})

// The window's answer lives on the window. A later Stop opens a new window while
// the earlier drive is still in flight; the earlier drive reads its own answer
// before its next command, so a cancel it received still stops it.
test("a later Stop opened while a drive is in flight leaves that drive's own cancel answer in force", async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: [fixture('armed-clear', CWD), ''],
    cancelStdout: CANCEL_CLEAR(CWD),
    holdLine: '/rename A Title',
  })
  const done = endTurn($)
  await until(() => r.log.includes('command.run rename [A Title]'))
  await $.prompt.submit(PROMPT)
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  r.release.line()
  await done
  expect(r.log).toEqual(['process.run', 'command.run rename [A Title]', 'process.run cancel', SAY])
})

// A window asks once, and the next window asks again: its answer is not the
// earlier window's.
test('a prompt in a later window spawns drive-cancel again', async ($, on) => {
  const r = rig(on, { sentinelExists: true, stdout: fixture('armed-clear', CWD), cancelStdout: CANCEL_CLEAR(CWD) })
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  await endTurn($, null)
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  expect(r.cancelArgv.length).toBe(2)
})

// The converse: a cancel answered in a later window is that window's, and an
// earlier drive that never got one runs on.
test("a cancel answered in a later window does not stop an earlier drive that was not asked", async ($, on) => {
  const r = rig(on, {
    sentinelExists: true,
    stdout: [fixture('armed-clear', CWD), ''],
    cancelStdout: CANCEL_CLEAR(CWD),
    holdLine: '/rename A Title',
  })
  const done = endTurn($)
  await until(() => r.log.includes('command.run rename [A Title]'))
  await $.classic.Stop({ cwd: CWD, session_id: 's1' })
  await $.prompt.submit(PROMPT)
  r.release.line()
  await done
  expect(r.log).toEqual([
    'process.run',
    'command.run rename [A Title]',
    'process.run cancel',
    SAY,
    'command.run clear []',
    `prompt.submit ${CONTINUATION} asUser=true`,
  ])
})
