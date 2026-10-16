# Stashed-prompt sweep: reproduction

2026-10-16, Claude Code 2.1.301, same rig as
[the queued-prompt report](2026-10-16-queued-prompt-sweep-repro.md): interactive
`claude --model haiku --permission-mode default --plugin-dir <this repo>` in the
`-L qrepro` tmux server, throwaway repo `/tmp/claude/qrepro/repo`, installed copy
disabled, `UserPromptSubmit`/`Stop`/`PreToolUse(Bash)` stdin logged. Every run's
first turn is the arming prompt: it writes `armed <session>` / `rename` /
`/rename qrepro-title` to `.claude/autodrive` and then runs
`python3 -c 'import time; time.sleep(25)'`; the variant action is taken while
that sleep runs. UTC times from `date -u` in the driver, the hook logs and
`debug.log`.

The stash binding is `ctrl+s`, action `chat:stash` (`~/.claude/keybindings.json`,
Chat context). In the pane, stashing typed text empties the composer and shows
a `› stashed` hint right-aligned above the composer rule.

One earlier run was discarded: the coordinator's leftover background command
ran `tmux -L qrepro kill-server` when `stop.log` became non-empty, killing
claude mid-`turn.complete`. Nothing below uses it.

## Variant 1: type text, stash it (`ctrl+s`), let the turn end

| UTC | event |
| --- | --- |
| 14:51:30.9 | `UserPromptSubmit`, arming prompt (the only one in the run) |
| 14:51:36.0 | sentinel on disk, `armed` (mtime) |
| 14:51:36.4 | `say banana` typed into the composer |
| 14:51:37.5 | `ctrl+s`; pane: composer empty, `› stashed`, tool still running |
| 14:51:37.5 to 14:52:03 | `.claude/autodrive` still present, no `UserPromptSubmit`, no `.claude/autodrive.swept` |
| 14:52:02.9 | `Stop` (`prompt_id` `22af0e6f…`, the arming turn's) |
| 14:52:03.7 | mod `scripts/drive-take.sh` runs (`$.process.run`); file taken and removed (`rename`) |
| 14:52:04.0 | toast `will run /rename qrepro-title once the turn ends` |
| 14:52:04.1 | `$.command.run`: 20 chars queued |
| 14:52:04.8 | `turn.complete` settled; pane: `/rename qrepro-title`, `Session renamed to: qrepro-title` |
| 14:52:15 | pane: composer empty, `› stashed` still shown |
| 14:52:27.7 | `ctrl+s` again: `say banana` returns to the composer |

Observed, answering the questions:

1. Stashing fires no `UserPromptSubmit` (one entry in `ups.log`, the arming
   prompt), has no `prompt_id`, sweeps nothing (`autodrive.swept` never created,
   file intact until the mod took it).
2. At turn end the stashed text is not restored. It stayed stashed through
   `Stop` and `turn.complete` and for at least 12 s after; it came back only
   when `ctrl+s` was pressed again. The composer was empty when the mod
   checked, so it did not bail: `/rename` ran, a `"type":"custom-title"` entry
   is in the transcript, and no `autodrive*` file remains.
3. A stash is a real feature here, so no reinterpretation is needed.

Verdict: a stashed prompt does not defeat the drive.

## Variant 1b: type text, stash, un-stash (`ctrl+s` twice) before the turn ends

Not asked for, run because it is what a user who changes their mind does, and
the one path where text is in the composer at `turn.complete` without a submit.

| UTC | event |
| --- | --- |
| 14:53:47.6 | `UserPromptSubmit`, arming prompt (the only one) |
| 14:53:57.0 | `say banana` typed, then `ctrl+s`: stashed |
| 14:53:58.5 | `ctrl+s`: `say banana` back in the composer |
| 14:54:21.8 | `Stop` |
| 14:54:22.7 | mod `drive-take.sh` runs; file taken and removed |
| 14:54:23.1 | toast `will run /rename qrepro-title once the turn ends` |
| 14:54:23.2 | `turn.complete` settled: no `$.command.run` line in `debug.log` |
| 14:54:27 | pane: `say banana` still in the composer, no `/rename`, no `Session renamed` |

Observed: no sweep (no `UserPromptSubmit`, no `autodrive.swept`), but the
transition is lost. The mod took the sentinel, announced the rename by toast,
saw non-empty composer text, and ran nothing. `custom-title` count in the
transcript: 0. No `autodrive` and no `autodrive.failed` is left. The toast is
the only trace and it says the opposite of what happened.

Inferred, not observed: the bail is the `$.prompt.read().text !== ''` check
(the log shows only the absence of `$.command.run` after the toast). For
`clear`/`compact` the take leaves `pending` rather than removing the file
(per `drive-take.sh`), which the next prompt's sweep would clear with a failure
report; this run used `rename` only.

## Variant 2: submit while the tool runs, then press Up to edit the queued message

| UTC | event | `prompt_id` |
| --- | --- | --- |
| 14:52:49.3 | `UserPromptSubmit` arming prompt | arming turn's |
| 14:52:58.9 | `say banana` typed and Enter; pane: `say banana`, `ctrl+x ctrl+s to send now`, composer hint `Press up to edit queued messages` | |
| 14:52:59.0 | `UserPromptSubmit` "say banana" | not extracted; same as the queued-prompt report's finding, not re-checked |
| 14:52:59 | `autodrive.swept`: `sweeper=owner state=armed kind=rename age=4s` | |
| 14:53:06.0 | `Up`: `say banana` moves from the queue into the composer; hint gone; no new `UserPromptSubmit` | |
| 14:53:22.8 | the only `Stop` | |
| 14:53:23.8 | mod `turn.complete`: no `drive-take.sh` call, nothing to take | |
| 14:53:27.7 | pane: `ok`, `say banana` still in the composer; no `/rename` | |

Observed:

1. Submitting into a running turn fires `UserPromptSubmit` at once and the
   sweep removes the owner's `armed` file, exactly as in the queued-prompt
   report. This is the defect, not a new finding.
2. Pressing Up afterwards withdraws the message from the queue (it never ran:
   one `Stop`, one answer, no "banana" reply) and puts the text in the
   composer. It does not undo the sweep, and fires no second
   `UserPromptSubmit`.
3. The text stays in the composer through turn end. `custom-title`: 0.

The sweep had already deleted the file, so this run cannot say whether the mod
would have bailed on the restored text; variant 1b is the clean test of that,
and it bailed.

## Not established

- `prompt_id` of the variant-2 `UserPromptSubmit` (the log was inspected for
  timing only); the earlier report's finding is not contradicted.
- Behaviour under `clear` and `compact` kinds: only `rename` was driven. The
  inferred end state after a bail is `pending`, unobserved.
- What the next prompt's sweep does with a `pending` left by a bail: not run.
- Whether the bail on 1b is the composer check or some other guard: only the
  absence of `$.command.run` was observed.
- Variants of un-stashing close to `Stop` (before vs after the mod's
  `$.prompt.read()`): not timed; 1b un-stashed 23 s before `Stop`.
- Other bindings (`ctrl+x ctrl+s` send-now, the external editor) not tried.
