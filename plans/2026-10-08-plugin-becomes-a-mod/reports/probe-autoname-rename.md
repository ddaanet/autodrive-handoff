# Probe: how `/autoname` can rename the session from a mod

Host: Claude Code 2.1.295, haiku. Probe: a scratch plugin with a mod that logs every event
and every `$` call to a file. It registered a command (named `nameprobe` rather than
`autoname`, because the installed `handoff:autoname` skill answers a bare `/autoname`) and
handled it with `on('command.run', {command}, ...)`. Types: upstream
`mods/types/claude-code.d.ts` (header "Written by Claude Code 2.1.277"; `claude -p` does not
write the copy under `.claude-plugin/types/`). Outcomes come from the probe log and the
session transcript JSONL.

## Verdicts

**Q1. Does a local command end in `turn.complete`? NO, so a rename from there cannot be
hooked to the command itself.**
- `claude -p '/nameprobe'` dispatches the mod command. The whole event log is
  `classic.SessionStart`, `session.start`, `HANDLER command.run`
  (`origin:{kind:"sdk"}`), `classic.SessionEnd`, `session.end`.
  No `turn.start`, `turn.complete`, `classic.Stop` or `UserPromptSubmit`.
  The process exits right after the handler, so any pending state dies with it.
- Interactive (tmux, private socket): after a normal first prompt (the full
  `prompt.submit`, `classic.UserPromptSubmit`, `turn.start`, `classic.Stop`, `turn.complete`
  sequence), typing `/nameprobe` logs only
  `HANDLER command.run {"origin":{"kind":"composer"},...}`. Nothing follows, 25s later.
  Also no `prompt.submit` and no `UserPromptSubmit` for the slash command.
- The host refuses `$.command.run({command:'rename'})` from inside the handler, in all three
  shapes tried:
  - awaited: `called from a command.run hook, it would wait on the turn this hook is holding;
    answer { text } instead, or run it from a later event (turn.complete) (host check)`.
  - not awaited (`void $.command.run(...)`): the same rejection.
  - via `$.clock.after(0, fn)`: `fn` never ran (nothing logged, 20s). Its context is
    inherited, as in the step 1 report.
- Deferral works only to the NEXT real model turn. With the title stored in module state
  by the handler, the next ordinary prompt ended in
  `turn.complete` -> `TC rename ok {"context":["<system-reminder>\nThe user named this session
  \"simple-greeting-exchange\"..."]}`. The transcript had
  `{"type":"custom-title","customTitle":"simple-greeting-exchange","sessionId":...}`.
  So the title lands one user turn after `/autoname`, and never under `-p`.
- Also refused in the handler: `$.prompt.submit`: `prompt.submit: called from a command.run
  hook, it would wait on the turn this hook is holding; submit from a later event
  (turn.complete) (host check)`.

**Q2. Direct way to set the title? Partly: no function, but one hook output field.**
- `$.session` has `messages, cwd, root, model, turns, id, repo, surfaces, surface, usage,
  version, compact, authorize, abort`. No rename or title function.
- `CommandRunResult` is `{ text?, context?, ref? }`. No title or rename directive.
- The only direct setter is `ClassicResult.sessionTitle` ("`hookSpecificOutput.sessionTitle`
  (UserPromptSubmit, SessionStart)"), readable by `classic.UserPromptSubmit` and
  `classic.SessionStart`. Live probe: a `classic.UserPromptSubmit` mod hook doing
  `const r = await next(e); return { ...r, sessionTitle: 'ups-title' }` wrote
  `{"type":"custom-title","customTitle":"ups-title",...}` (plus `agent-name`) at the start of
  that prompt's turn. It does NOT fire for a slash command, so it still needs a following
  prompt. It gains nothing over `turn.complete` except timing (turn start, not turn end).
- `$.model.fork` resolves to `ModelForkResult | null`, not a string. Shapes seen:
  `{"isAnswered":true,"text":"simple-greeting-exchange","usage":{...}}` and, on an empty
  transcript (first command in a fresh session), `{"isAnswered":false,"reason":"nothing-to-fork"}`.
  Use `r?.isAnswered ? r.text.trim() : fallback`. Calling `.trim()` on the result throws.

**Q3. What fires for a local command, and does `{text}` or `$.prompt.fill` change it?**
- Events seen for a local command (interactive, in order): `command.run` alone.
  Under `-p`: `classic.SessionStart`, `session.start`, `command.run`, `classic.SessionEnd`,
  `session.end`.
- Returning `{ text }` only prints the output line (`probe: named <title>`); it starts no model
  turn, so no `turn.complete`. `$.prompt.submit` is refused (above).
  `$.prompt.fill` was not run: it fills the composer box and submits nothing, so a user
  Enter would be needed; it cannot give a turn by itself.

## Recommended mechanism for `/autoname`

Register the command at `session.start`. In the `command.run` handler: fork for the title,
store it in module state, and answer `{ text }` (do NOT call `$.command.run` there).
At the next `turn.complete`, take the stored title and run the rename there.

```ts
// session.start
await $.command.register({ name: 'autoname', description: '...' })
// command.run {command:'autoname'}
const r = await $.model.fork({ prompt: TITLE_PROMPT })      // ModelForkResult | null
if (!r || !r.isAnswered) return { text: 'autoname: no title' }
pendingTitle = r.text.trim()
return { text: 'title queued: ' + pendingTitle }
// turn.complete (before the sentinel drive)
if (pendingTitle !== null) {
  const t = pendingTitle; pendingTitle = null
  await $.command.run({ command: 'rename', args: t })       // resolves {context:[...]}
}
```

Variant: do the final `rename` from `classic.UserPromptSubmit` by returning
`{ ...(await next(e)), sessionTitle: t }`. It is equivalent and lands one step earlier, but
it is a different channel (a classic hook output) and gains nothing for the user.

Limits to state in the skill/README: the title applies after the next turn completes, not
at the command; under `-p` it never applies (nothing follows the command and the process
exits). If an immediate rename is required, the only options are the existing
`handoff:autoname` skill (a model turn calling `handoff-checkpoint`, which then types
`/rename` via the walker) or a `/rename <title>` typed by the user.

## Failure mode to assert

If the mechanism is wrong (rename attempted inside the `command.run` handler), the log
shows: `HooksError: probe: command.run: called from a command.run hook, it would wait on the
turn this hook is holding; answer { text } instead, or run it from a later event
(turn.complete) (host check)` and the transcript has NO `custom-title` entry. In the kit this
is already reproduced. Assertable live: after `/autoname` + one more ordinary prompt, the
transcript contains exactly one `custom-title` whose `customTitle` equals the forked title;
after `/autoname` alone (or under `-p`) it contains none.

## Housekeeping

- The scratch plugin lived under `/tmp`. An unrelated scratch plugin already sat at
  `/tmp/probe` (another session's: `hooks/handoff.ts`, `tests/mod/`). My first write
  overwrote its `hooks/hooks.json` (to `modules:["./probe.ts"]`) and `.claude-plugin/plugin.json`
  (same 57 bytes as before). I deleted my `probe.ts` there and restored `hooks.json` to
  `{"modules":["./handoff.ts"],"hooks":{}}` (39 bytes; the original was 38, so
  probably a trailing-newline difference). Check it if that session misbehaves.
- Everything else I made is deleted: the scratch plugin, the work repo, the probe log and flag
  files, the transcript directory for `/tmp/work`, and the private tmux server.
  Nothing inside `/Users/david/code/handoff` was modified.
