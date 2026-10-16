# A queued prompt when the mod drives clear or compact

2026-10-16, Claude Code 2.1.301, same rig as
[the queued-prompt report](2026-10-16-queued-prompt-sweep-repro.md): interactive
haiku in the `-L qrepro` tmux server, throwaway repo `/tmp/claude/qrepro/repo`,
hook logs, `--debug-file`, transcripts. The plugin is a copy at
`/tmp/claude/qrepro/plugin` (deleted afterwards) with two edits: the
`UserPromptSubmit` entry that runs `report-drive-failure.sh` removed from
`hooks/hooks.json`, so nothing sweeps, and the `$.prompt.read()` bail line
removed from `hooks/handoff.ts`. The repo's own files are untouched.

Each run's first turn writes `.claude/autodrive` (`armed <session>`, the kind,
its lines, the continuation `Continue where the previous context stopped.`,
the `CONTINUATION` constant at `scripts/checkpoint.py:214`) through `printf`.
Then `say banana` + Enter is sent:

- variant 1, mid-tool: while `time.sleep(25)` runs;
- variant 2, mid-reply: after the tool result, while the model writes a 600-word
  essay on tides (`time.sleep(3)`).

The variants were checked from the transcripts and the logs, not assumed
(below). `clear` lines: `/rename qrepro-title`, `/clear`, continuation.
`compact` lines: `/compact keep the word PINEAPPLE`, continuation.

## Result

In all four runs the queued prompt was answered once, in the old context,
before the transition; the mod's commands then ran and the continuation arrived
in the fresh or compacted context. No `$.command.run` rejection, no toast other
than "will run … once the turn ends", no `.claude/autodrive.failed`, and the
`autodrive` file was gone at the end (taken by the mod). Nothing lost, nothing
delivered twice.

| Run | Host behaviour for `say banana` | Answered in | Transition ran | Continuation |
| --- | --- | --- | --- | --- |
| clear 1 | folded into the running turn (one `Stop`) | old session, before `Stop` | `/rename`, `/clear`: new session transcript | first prompt of the new session, after `/clear` |
| clear 2 | its own turn, started right after the arming turn's `Stop` | old session, as that turn | `/rename` ran after that turn, then `/clear` | after `/clear` |
| compact 1 | folded into the running turn | old session, before `Stop` | `/compact`: `isCompactSummary` entry | after the compaction |
| compact 2 | its own turn | old session, as that turn | `/compact` after that turn | after the compaction |

## clear, variant 1 (folded)

| UTC | event |
| --- | --- |
| 16:03:22.7 | `UserPromptSubmit`, arming prompt (`prompt_id` `9e264452…`) |
| 16:03:32.96 | `UserPromptSubmit` `say banana`, same `prompt_id`; no sweep exists in this copy |
| 16:03:33.5 | transcript: `queue-operation enqueue` |
| 16:03:55.6 | tool result in; 16:03:55.8 `queue-operation remove` |
| 16:03:57.0 | assistant text `banana` |
| 16:03:57.2 | the only `Stop` of the old session |
| 16:03:57.7 | mod `drive-take.sh`; toast; 16:03:58.1 `$.command.run` `/rename` queued |
| 16:03:58.7 | `/clear` queued |
| 16:03:59.7 | `$.prompt.submit` of the continuation (new session `7a280bcc…`) |
| 16:04:00.3 | `UserPromptSubmit` continuation, fresh `prompt_id` `17cf56ab…` |
| 16:04:01.1 | `turn.complete` settled (3.5 s); 16:04:25.7 `Stop` of the new session |

Old transcript: `custom-title qrepro-title`, `banana` answered. New transcript:
`/clear` command entries, then the continuation as the first user prompt;
`banana` does not occur in it.

## clear, variant 2 (own turn)

| UTC | event |
| --- | --- |
| 16:04:41.1 | arming prompt (`9daa2f87…`) |
| 16:04:58.7 | `UserPromptSubmit` `say banana`, same `prompt_id`, mid-essay; 16:04:59.2 `enqueue` |
| 16:05:04.0 | `Stop` of the arming turn (`9daa2f87…`) |
| 16:05:05.0 | queue `dequeue`; 16:05:05.3 transcript user entry `say banana`; 16:05:05.5 `turn 2 start` |
| 16:05:05.3 to .9 | mod `drive-take.sh` runs inside that window; 16:05:05.98 `/rename` queued (not yet run) |
| 16:05:11.5 | assistant `Banana` |
| 16:05:11.6 | `Stop` of banana's turn (`7a4c0290…`) |
| 16:05:12.06 | `/rename` runs (`custom-title`, "named this session" reminder); 12.29 `/clear` queued; 12.46 `/clear` entries |
| 16:05:13.1 | `$.prompt.submit` of the continuation; 16:05:13.6 `UserPromptSubmit` (`6a08e658…`) |
| 16:05:14.4 | `turn.complete` settled (9.5 s); a second `turn.complete` settles in 95 ms (nothing to take) |
| 16:05:22.4 | `Stop` of the new session's turn |

Three `Stop`s: arming turn, banana's turn, continuation turn. The sentinel was
taken at the first `turn.complete`, while banana's turn was already starting;
the queued commands waited for that turn to finish.

## compact, variant 1 (folded)

| UTC | event |
| --- | --- |
| 16:05:53.3 | arming prompt (`7ff9298a…`) |
| 16:06:01.5 | `UserPromptSubmit` `say banana`, same `prompt_id` |
| 16:06:24.8 | `queue remove`; 16:06:25.9 assistant `banana` |
| 16:06:26.0 | `Stop` (the only one of the old context) |
| 16:06:26.9 | toast; `$.command.run` `/compact …` queued |
| 16:06:27.5 | compaction request (`source=compact`) |
| 16:06:30.2 | `isCompactSummary` entry |
| 16:06:30.6 | `$.prompt.submit` continuation; 16:06:30.8 `UserPromptSubmit` (`0d0690b7…`) |
| 16:06:31.4 | `turn.complete` settled (5.1 s); 16:06:47.4 `Stop` |

The summary text mentions `banana` and does not contain `PINEAPPLE`.

## compact, variant 2 (own turn)

| UTC | event |
| --- | --- |
| 16:08:38.2 | arming prompt (`2bba5c9f…`) |
| 16:08:53.0 | `UserPromptSubmit` `say banana`, same `prompt_id`, mid-essay |
| 16:08:59.6 | `Stop` of the arming turn |
| 16:08:59.9 | mod `drive-take.sh`; 16:08:59.98 transcript `say banana`; 16:09:00.0 `turn 2 start` |
| 16:09:00.2 | toast; `/compact …` queued |
| 16:09:04.1 | assistant `banana`; 16:09:04.2 `Stop` of banana's turn (`752333db…`) |
| 16:09:04.5 | `/compact` runs; 16:09:13.9 `isCompactSummary` |
| 16:09:14.4 | `$.prompt.submit` continuation; 16:09:15.1 `UserPromptSubmit` (`22d970bb…`) |
| 16:09:16.0 | `turn.complete` settled (16.1 s), then a second in 63 ms; 16:09:20.9 `Stop` |

The summary mentions `banana` and contains `PINEAPPLE`.

## What the runs establish

- Observed: the banana prompt's `UserPromptSubmit` carries the arming turn's
  `prompt_id` in both variants, as in the earlier report, and neither the
  absence of the sweep nor the later drive changed that.
- Observed: the drive's `$.command.run` calls queue and run only after the turn
  that is in flight ends, including a banana turn that began after the mod had
  taken the sentinel (variant 2).
- Observed: the continuation is a separate `UserPromptSubmit` with a fresh
  `prompt_id`, arriving after the clear or compaction in every run; banana is
  never in the continuation's turn.
- Inferred, not checked: that with the real `report-drive-failure.sh` spared
  for the owner's mid-turn prompt (the fix under discussion) the behaviour is
  the same, since this copy only removes the hook outright.

## Not established

- Only `say banana`, a short prompt. A queued prompt that itself starts a long
  turn, or issues tool calls that touch `.claude/`, was not tried.
- Several queued prompts, or a prompt sent in the window between `Stop` and the
  drive's first command (about 0.5 s for `clear`/`compact`), were not tried;
  the variant 2 prompt was sent 5 to 6 s before `Stop`.
- A user submit after the mod has taken the sentinel but before the queued
  command runs (variant 2's window) could in principle reorder; not tested.
- The compact summary's `PINEAPPLE` is present in variant 2 and absent in
  variant 1: whether focus text reliably survives was not investigated (haiku,
  one run each).
- One attempt at compact 2 lost its first Enter in tmux (the prompt sat in the
  composer, nothing ran) and was redone from a fresh server; it is not counted.
- Only 2.1.301; `rename` was not rerun (covered by the earlier reports).
