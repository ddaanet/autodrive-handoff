# Step 3 (RED): mod tests

Status: red as intended. Nothing committed.

## Files
- `tests/mod/handoff.test.ts` (22 tests), `tests/mod/rig.ts` (stub rig), `tests/mod/fixtures.ts` (GENERATED copy of `fixtures/*.json`, see constraints)
- `hooks/handoff.ts`: skeleton, `export function register(on: any) {}`, registers nothing
- `hooks/hooks.json`: added ONE line, `"modules": ["./handoff.ts"]` (the runner refuses with "no hooks module to load" without it; classic hooks untouched)

## Invocation
`cd /Users/david/code/handoff && claude plugin test` (needs `dangerouslyDisableSandbox`). Runs every `*.test.ts` under the plugin dir. Result: 2 pass, 20 fail, all failures `AssertionError` on the expected call sequence. The 2 passes (Stop drives nothing; aborted turn drives nothing) are vacuous against an empty module; mutation-checked in a scratch copy (drive in Stop reds the first, ungated turn.complete drive reds the second and the consume-once test).

## Tests
- `classic.Stop records the cwd and drives nothing` — Stop makes no process.run/command.run/fs.exists call (vacuously green against the skeleton; mutation: driving in Stop reds it)
- `turn.complete with no Stop before it (aborted turn) drives nothing` — Esc/aborted turn: nothing (vacuous vs skeleton; mutation: ungated drive reds it)
- `a recorded cwd is consumed once` — Stop + two turn.completes with a sentinel: exactly one process.run
- `project-root cwd without a sentinel never spawns` — only fs.exists(<cwd>/.claude/autodrive) is called; no process.run
- `a sentinel makes it run drive-take.sh with the cwd` — argv = ['bash', '<...>/scripts/drive-take.sh', cwd], exactly 3 entries
- `a worktree or subdir cwd runs the script even without a sentinel there` — cwd != session root: script runs although fs.exists is false
- `empty stdout is a no-op` — only process.run; no toast, no write
- `compact with focus: ...` — armed-compact: process.run, read, command.run compact [keep the parser work], read, prompt.submit asUser=true; toast = message; no write
- `clear: rename, then clear (no args), then the continuation, in order` — armed-clear: 3 lines each preceded by prompt.read; clear has empty args
- `rename kind runs the single rename line` — armed-rename
- `FR-G: empty before and after toasts ...` — prepare-only-compact: only process.run, one toast with the message
- `malformed plan toasts its message and runs nothing` — malformed fixture: one toast containing 'autodrive malformed'
- `text in the prompt box before the first line bails out of everything` — [process.run, prompt.read], no write
- `text typed mid-sequence bails before the next line` — second prompt.read non-empty: stops after first line, no write
- `first rejected line ends the sequence and writes failFile` — /rename rejected: log ends with fs.write <root>/.claude/autodrive.failed; text and 2nd toast name the failed line
- `a rejected continuation prompt is recorded the same way` — prompt.submit rejects: fs.write failFile last
- `session.start registers /autoname` — one command.register {name:'autoname', description non-empty}
- `a taken /autoname name does not fail session.start` — register rejects; the hook still reaches next(e) (stub beneath it counts)
- `/autoname forks, then renames to the trimmed reply` — fork prompt contains 'Title Case' and 'trailing punctuation'; log = [command.run rename [Driven Transitions Mod]]
- `/autoname with a null fork result ...` — no rename, one toast
- `/autoname with an empty reply ...` — no rename, one toast
- `/autoname with a rejected fork ...` — no rename, one toast

## Red excerpts
```
(fail) a recorded cwd is consumed once
  Expected: ["process.run"]   Received: []
(fail) compact with focus: ...
  Expected: ["process.run","prompt.read","command.run compact [keep the parser work]","prompt.read","prompt.submit continue with task 3 asUser=true"]
  Received: []
(fail) first rejected line ends the sequence and writes failFile
  Expected: [..., "command.run rename [A Title]", "fs.write /work/proj/.claude/autodrive.failed"]  Received: []
(fail) session.start registers /autoname   Expected: 1  Received: 0
(fail) /autoname with a null fork result renames nothing and toasts
  Expected: []  Received: ["command.run autoname []"]   (also the toasts length check follows)
 2 pass / 20 fail
```

## Satisfiability
The suite was run green (22/22) against a scratch reference implementation (below) in `/tmp/probe` (ephemeral), so GREEN can start from it.

## Stub idioms (all registered via `rig(on, opts)` before the first `$` call)
- Event-style stubs return the event result: `classic.Stop -> {}`, `turn.complete -> {text:''}`, `session.start -> {cwd}`, `command.run -> {text:''}`, `prompt.submit -> {text:e.text}`.
- API-call stubs return `{value}`: `process.run -> {value:{exitCode:0,stdout,stderr:''}}`, `fs.exists`, `fs.write`, `session.root` (project root = `/work/proj`), `prompt.read -> {value:{text,cursor}}`, `ui.toast`, `command.register`, `model.fork -> {value:{text,usage}|null}`.
- Firing: `$.classic.Stop({cwd, session_id})`, `$.turn.complete({turnId, answer, durationMs, isAborted, usage:null})`, `$.session.start({surface,isInteractive,cwd})`, `$.command.run({command:'autoname',args:''})`.
- The mod sees `prompt.submit` with `e.origin = {kind:'plugin',name,asUser}` (no top-level `asUser`); the rig logs `e.origin?.asUser`.
- Rejecting a call: `{deny}` / `{drop}` do NOT reject `command.run` / `prompt.submit` (event-backed calls). A stub that THROWS is skipped, nothing answers, and the mod's call rejects with a generic message (`no implementation for command.run`); the stub's own message is not carried. So tests assert the failFile text / toast name the failed LINE, not a custom reason. `command.register` and `model.fork` reject via throw as well.
- `prompt.read` assumed shape: `{text: string, cursor: number}` (d.ts `PromptBox`); "user has text" = `text !== ''`.
- The mod reads the project root with `$.session.root()` (stub `session.root`); fast path = `cwd === root && !exists(<cwd>/.claude/autodrive)`. `$.plugin.root` is used for the script path; the tests only check the `/scripts/drive-take.sh` suffix.
- `model.fork` in d.ts (written by 2.1.277) resolves to `{text, usage} | null` (null on cold snapshot or API error); the docs page says "reply text". Tests use the object form; the mod should accept `null` and a thrown rejection as failure, and trim `.text`.

## Findings that change the plan
1. AUTONAME CANNOT RENAME INLINE. Inside a `command.run` hook the host refuses `$.command.run`: "called from a command.run hook, it would wait on the turn this hook is holding; answer { text } instead, or run it from a later event (turn.complete) (host check)" (reproduced in the kit). So `/autoname` cannot fork-then-rename in its own command hook. The reference impl stores the title and issues `rename` from the next `turn.complete`; the autoname tests therefore end with a stray `turn.complete` (no Stop) and assert on the whole log, pinning behaviour not mechanism. UNVERIFIED: whether a local slash command ends in a `turn.complete` in the live host; if not, autoname needs another route (live probe required in GREEN or the plan changes, e.g. a registered command that returns text asking the model, or `$.prompt.fill`). Fork inside the command hook is fine (not blocked in the kit).
2. A hooks-module test file may import only relative `.ts/.js` files and `claude-code`: no `node:fs`, no JSON imports. Fixtures are therefore inlined in the GENERATED `tests/mod/fixtures.ts`, from `fixtures/*.json`. Nothing checks they agree; step 5 should add a check or generate it in the gate (the Python/bats side can regenerate and diff).
3. The kit's `$.plugin.root` for the mod is not asserted (value unknown in the kit).
4. Not mutation-checked yet (as the plan wants for GREEN): the prompt bail and stop-on-failure rows (each reds against an impl that omits the check, by construction of exact-sequence assertions), and the deferral row is moot (no deferral timer).
5. Hook for a taken name: the taken-name test uses a stub beneath `session.start` that only runs if the mod reached `next(e)`; a throwing hook is otherwise silently skipped by the kit.

## Scratch reference implementation (22/22 green in the kit)
```ts
let pendingCwd: string | null = null
let pendingTitle: string | null = null

export function register(on: any) {
  on('classic.Stop', async ($: any, e: any, next: any) => {
    pendingCwd = e.cwd
    return next(e)
  })

  on('turn.complete', async ($: any, e: any, next: any) => {
    const cwd = pendingCwd
    pendingCwd = null
    if (pendingTitle !== null) {
      const title = pendingTitle
      pendingTitle = null
      await $.command.run({ command: 'rename', args: title })
    }
    if (cwd !== null) await drive($, cwd)
    return next(e)
  })

  on('session.start', async ($: any, e: any, next: any) => {
    try {
      await $.command.register({ name: 'autoname', description: 'Name the session', })
    } catch (_err) {
      // taken name: leave it
    }
    return next(e)
  })

  on('command.run', { command: 'autoname' }, async ($: any, e: any) => {
    return autoname($)
  })
}

async function autoname($: any) {
  let reply: any = null
  try {
    reply = await $.model.fork({ prompt: 'Title Case, no trailing punctuation, at most ~50 characters' })
  } catch (_err) {
    reply = null
  }
  const title = reply && typeof reply.text === 'string' ? reply.text.trim() : ''
  if (title === '') {
    $.ui.toast('autoname: no title')
    return {}
  }
  pendingTitle = title
  return { text: 'naming' }
}

async function drive($: any, cwd: string) {
  const root = await $.session.root()
  const sentinel = `${cwd}/.claude/autodrive`
  if (cwd === root && !(await $.fs.exists(sentinel))) return
  const out = await $.process.run(['bash', `${$.plugin.root}/scripts/drive-take.sh`, cwd])
  if (out.stdout.trim() === '') return
  const plan = JSON.parse(out.stdout)
  $.ui.toast(plan.message)
  for (const line of [...plan.before, ...plan.after]) {
    const box = await $.prompt.read()
    if (box.text !== '') return
    try {
      if (line.startsWith('/')) {
        const sp = line.indexOf(' ')
        const command = sp < 0 ? line.slice(1) : line.slice(1, sp)
        const args = sp < 0 ? '' : line.slice(sp + 1)
        await $.command.run({ command, args })
      } else {
        await $.prompt.submit({ text: line, asUser: true })
      }
    } catch (err: any) {
      const reason = `handoff: ${line} failed: ${err && err.message ? err.message : String(err)}`
      await $.fs.write(plan.failFile, reason + '\n')
      $.ui.toast(reason)
      return
    }
  }
}
```
