# Step 1: mod live smoke (red) and spike

Host: Claude Code 2.1.295, `claude -p --model haiku`. Probe: a throwaway scratch
plugin (not in the repo) with a classic `SessionStart` hook that logs and a mod
that logs every step and rejection to a file. Evidence comes from the probe log
and the session transcripts. Probe runs used the same restrictions as the test:
`--permission-mode default`, `--disallowedTools=Bash,Edit,Write,NotebookEdit`,
an allowlisted env.

## Verdicts

**a. `command.run` from `clock.after(0)` inside `classic.Stop`: FAILS.**
- `after(0)` and `after(300)` both reject:
  `HooksError: probe: command.run: called from a classic.Stop hook, it would
  wait on the turn this hook is holding; run it from a later event
  (turn.complete) (host check)`.
- The check follows the call context that the timer inherits. It is not
  time-based.
- `after(2000)` ran after `-p` had torn down: `$.command.run is not available
  in this mode: no session is bound in this process`.
- The right deferral is the `turn.complete` handler, called directly with no
  timer. It fires 0.4-1.7s after `classic.Stop`, and the payload is
  `answer, durationMs, isAborted, turnId, reason, usage`. It has no `cwd`, so
  the Stop handler must record `e.cwd`, or use `$.session`.
- A timer started from `turn.complete` also fails under `-p` (session unbound).
  Run the drive inline in the `turn.complete` handler.
- Plan consequence: the drive moves to `on('turn.complete')`.
  - Keep `classic.Stop` as the "Esc arms nothing" gate: it records that a
    Stop fired for this turn.
  - `turn.complete` carries `isAborted`, which may replace that gate. This is
    unverified.
  - The deferral (`$.clock.after`) is dropped from the design and from step 3's
    stubs.
  - Awaiting `command.run` inline in `turn.complete` did not deadlock.

**b. `SessionStart(clear)` fires for a mod-run `/clear`: HOLDS.**
- A classic hook logged `SessionStart {"source":"clear", session_id: <new>,
  transcript_path: <new>}` about 0.3s after `run /clear`. The new session id and
  transcript differ from the old ones.
- `load-handoff.sh` consuming `pending` is therefore reachable. It was not run
  here, because the probe plugin carries no sentinel.
- The new transcript has the `SessionStart:clear` `hook_success` attachments and
  `hook_additional_context`, so frame injection works after a mod-run clear.
- `/compact` fires `SessionStart(compact)` the same way, same session id.

**c. `prompt.submit({asUser:true})` lands in the fresh conversation: HOLDS.**
- The new session's transcript has a `queue-operation` enqueue/dequeue, then a
  non-meta `user` entry with exactly the submitted text, then the assistant
  reply `CONTINUED`.
- After `/compact`, the submitted text ran as the next turn the same way.
- `submit` resolves as `{"text":..., "origin":{"kind":"plugin","name":"probe",
  "asUser":true}}`. It resolves when the turn starts.

**d. `-p` keeps the process alive for the deferred drive: PARTIAL.**
- Not for a timer: the process outlives `Stop` by only about 1.5-2s, and a
  timer past that finds no session.
- Driving inline from `turn.complete` works, and `-p` stays alive until the
  submitted continuation turn finishes: 13s for clear + continuation, 23s with
  compact.
- No tmux fallback (question 3) was needed. The live host is `-p`.

## API shapes used (for step 3 stubs)

- Hooks module: `export function register(on)`, with
  `on('<event>', async ($, e, next) => { ... return next(e) })`.
  `$` is the first argument.
- A static check at load rejects `$` passed to anything but a top-level
  `function`/const-function declaration. A module-level `async function
  log($, ...)` is fine. An inner `const log = ...` is not: "hooks module did not
  load".
- `classic.Stop` `e` keys: `session_id, transcript_path, cwd, scratchpad_dir,
  prompt_id, permission_mode, agent_id, agent_type, effort, hook_event_name,
  stop_hook_active, last_assistant_message, background_tasks, session_crons`.
- `$.fs.exists(p)`, `$.fs.read(p)`, `$.fs.write(p, text)`: as documented.
- `$.command.run({command: 'rename', args: 'title'})` resolves
  `{text: 'Session renamed to: title'}`.
  - `/clear` resolves `{text: ''}`.
  - `/compact <focus>` resolves `{}` after about 7.5s. It awaits the whole
    compaction.
  - The command name has no leading slash, and `args` is a string.
- `$.prompt.submit({text, asUser: true})`: see c.
- `$.clock.after(ms, fn)`: usable, but not for `command.run` (see a).
- Not exercised: `prompt.read`, `process.run`, `model.fork`, `ui.toast`.
- Transcript shapes:
  - Rename writes `{"type":"custom-title","customTitle":"<t>","sessionId":...}`
    with no uuid or timestamp.
  - `/clear` is a `<command-name>/clear</command-name>` user entry with
    `isMeta` caveat before it.
  - `/compact` produces an entry with `isCompactSummary:true`. The focus string
    appears in the command-args entry.

## Test

- `tests/test_mod_live.py` has three rows: `rename`; `clear` + continuation
  (the first user prompt of a different session equals the continuation);
  `compact` + focus (an `isCompactSummary` entry, the focus, and the
  continuation).
- Fixtures sit in the module: a temp git repo, a pre-armed
  `.claude/autodrive`, and cleanup of the repo's `~/.claude/projects/<encoded>`
  directory.
- The `claude` subprocess runs `-p --model haiku --plugin-dir <repo>
  --permission-mode default --disallowedTools=Bash,Edit,Write,NotebookEdit`
  (`=` form: the flag is variadic and swallows the prompt otherwise) and the
  prompt "Reply with the single word ok. Use no tools.". Its env is
  allowlisted: PATH, HOME, TMPDIR, LANG, LC_ALL, USER, CLAUDE_CONFIG_DIR,
  ANTHROPIC_*, CLAUDE_CODE_OAUTH_TOKEN. TMUX* is therefore never passed.
- `just mod-smoke` runs `pytest -m live tests/test_mod_live.py -v -rs`. The
  `live` marker text in pyproject now covers `claude -p` as well as the tmux
  TUI.
- Cost and latency: about 37s for the three rows on haiku. A single probe run
  takes 10-25s. Each row is one trivial turn, plus a continuation turn for the
  clear and compact rows, plus one compaction.
- Red today (genuine, on assertion; the repo's classic `stop-drive.sh` arms
  the sentinel outside tmux and types nothing):

```
test_rename_row:   AssertionError: assert 'mod-smoke-title' in []
test_clear_row...: AssertionError: {'20080bbc-...': ['Reply with the single word ok. Use no tools.']}
                   assert 0 == 1   (no fresh session with the continuation)
test_compact_row...: AssertionError: no compaction
3 failed in 36.36s
```

- `just precommit` is green (285 passed, 17 deselected).
- Commit subject: `test: Step 1 — mod live smoke (red)`

## Plan deltas (docs win)

1. The Design's "defer with `$.clock.after(0, …)`" is wrong for this host.
   `command.run` has to be called from `turn.complete` (inline), per the
   host's own error message.
2. Under `-p`, timers do not outlive the turn. The inline drive is also what
   keeps the process alive.
3. `command.run('compact', focus)` blocks until compaction ends, and the
   following `prompt.submit` then works. The sequence can run in order inside
   one handler.
4. The unit tests of step 3 should use `turn.complete` plus a recorded cwd
   (`turn.complete` has none).
