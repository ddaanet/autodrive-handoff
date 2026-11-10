# Live run: a prompt in the window after the rework

2026-11-10, Claude Code 2.1.322, interactive `claude --model haiku` in a tmux
server per run, with this repo as `--plugin-dir`, a fixed `--session-id`, in a
throwaway git repo. The plan is
[the cancel acts on the window's own take](../2026-11-10-cancel-from-the-take.md).
The arming turn wrote an `armed` sentinel through one allowed `printf` call.
To widen the window, the driver held `.claude/autodrive.lock` on its own file
descriptor from before the arming prompt until 2 s after it sent `say banana`.
It sent `say banana` 1 s after the reply showed. One run per row. The driver
script and the logs are gone.

## Result

| Kind | Sentinel at release | Afterwards | Sweep record | What happened |
| --- | --- | --- | --- | --- |
| `clear` | `armed` | removed | `state=pending owner=- kind=clear` | answered banana; no `/clear`; the agent re-ran the handoff skill and armed a new clear |
| `rename` | `armed` | removed | none | answered banana, then `/rename live-test` ran |

Both are the outcomes the plan names. The take ran first and left `pending`,
and the cancel removed only that file.

## Host budgets the invalid runs showed

The first runs held the lock for about 30 s. That is not a test of the
mechanism, but it showed these limits on 2.1.322:

- The mod's `prompt.submit` hook is skipped once it runs past a 10 s budget,
  and the prompt then passes untouched.
- `$.process.run` aborts a child still running after 30 s, and the hook that
  awaited it throws.
- The `UserPromptSubmit` hook times out at its `hooks.json` `timeout` (10 s),
  and its output is discarded.

The rework puts the take on the prompt handler's path. A prompt now waits on
the take's lock wait (up to `HANDOFF_LOCK_WAIT_SECS`, 5 s) and then the
cancel's, so under lock contention the handler can reach the 10 s budget. When
it does, the prompt passes, which is the racy outcome from before the cancel
existed. This is not observed at the default wait.
