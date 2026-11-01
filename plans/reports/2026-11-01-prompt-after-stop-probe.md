# A prompt sent just after the arming turn's `Stop`

2026-11-01, Claude Code 2.1.316, interactive `claude --model haiku` in a
dedicated tmux server per run, a throwaway git repo and a plugin copy whose
`hooks/handoff.ts` logged each event, with sleeps inside `drive()` to widen the
window, and which attached a `PROBE` line through `e.context`. A log line at the
top of `report-drive-failure.sh` showed the sentinel's state as the settings
hook saw it. The arming turn wrote an `armed` sentinel through one `printf`
call; `say banana` was then typed by the harness on a log trigger. One run per
row. The copy and the logs are gone.

## Result

| Run | Prompt sent | `prompt.submit` fired | Sentinel at `UserPromptSubmit` | What happened |
| --- | --- | --- | --- | --- |
| clear, sleep before the take | 1.5 s after `Stop` | at Enter, window open | `armed` | swept, the unloaded-mod note; the take found nothing |
| clear, sleep after the take | 0.6 s after the take | at Enter, window open | `pending` | answered in the old context, then `/rename`, `/clear`: the answer lost |
| compact, no sleep | 0.08 s after `/compact` was issued | after the compaction | none | answered in the compacted context, then the continuation |
| clear, no sleep | 0.08 s after `/clear` was issued | after `/clear` resolved | none | answered in the fresh session, then the continuation |

## What the runs establish

- Observed: both outcomes the todo names, with the same prompt at two points of
  the same window.
- Observed: in the window the mod's `prompt.submit` hook runs at Enter, and
  `next(e)` reaches the `UserPromptSubmit` settings hook after it (log order in
  every row), so the mod can act on the sentinel before the sweep reads it.
- Observed: `$.process.run` works inside that hook, and a line added to
  `e.context` reached the model (`banana` then `KIWI`, as the line asked).
- Observed: a prompt sent after the transition command was issued is not lost:
  the host held it until the command resolved, and it was answered in the new
  context, ahead of the continuation.
- Observed: `$.command.run` raises no `prompt.submit` for `/rename`, `/clear` or
  `/compact`, so the drive cannot cancel itself. The continuation does raise one,
  and it can arrive with a later `Stop` still unconsumed.

## With the change

The same harness, the mod's `prompt.submit` handler and `drive-cancel.sh` in the
copy, `say banana` sent inside the window; 2026-11-01, one run per row. The sleep
sat in `drive()` ahead of the take, either before or after its fast-path look at
the file.

| Kind | Who reached the sentinel first | Sweep record | What happened |
| --- | --- | --- | --- |
| `rename` | the cancel, take on the fast path | none | answered, then titled `probe-title` |
| `rename` | the cancel, take finding nothing | none | answered, then titled `probe-title` |
| `clear` | the cancel, take on the fast path | `state=armed` | answered; no `/clear`, no title |
| `clear` | the take | `state=pending` | answered, no `/clear`; the agent re-ran the skill |
| `compact` | the take | `state=pending` | answered, no `/compact`; the agent re-ran the skill |

The note leaves the re-run to the agent: Haiku re-ran the skill in the two runs
above and only reported in the first `clear` one, so that part is not pinned.

## Not established

- Whether a prompt can reach `prompt.submit` between the transition command being
  issued and the host starting it. 0.08 s was too late to hit it in these runs.
- A Claude Code older than 2.1.310, the oldest installed here. The mod's stated
  minimum is 2.1.287.
