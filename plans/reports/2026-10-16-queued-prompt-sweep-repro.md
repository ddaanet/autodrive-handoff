# Queued-prompt sweep: reproduction

2026-10-16, Claude Code 2.1.301, interactive `claude --model haiku
--permission-mode default --plugin-dir <this repo>` in a dedicated tmux server
(`-L qrepro`), throwaway repo `/tmp/claude/qrepro/repo`, installed
`autodrive-handoff@ddaanet` disabled there and `CLAUDE_CODE_PLUGIN_DIRS` unset,
so this repo's plugin was the only copy loaded. Project-level
`UserPromptSubmit` and `Stop` hooks appended a timestamp and their stdin to a
log. The stub rig cannot show this: `claude plugin test` never runs the
`hooks.json` command hooks, and the defect is in how the host orders those
hooks against `turn.complete`. `just mod-smoke` cannot either, because `-p`
takes one prompt.

## Result: reproduced, in both places a prompt can be queued

Each run's first turn wrote `armed <session>` / `rename` / `/rename
qrepro-title` to `.claude/autodrive` through `printf`, then did more work while
`say banana` was typed into the composer.

**Queued during a tool call** (`python3 -c 'import time; time.sleep(25)'`):

| UTC | event | `prompt_id` |
| --- | --- | --- |
| 14:17:26.7 | `UserPromptSubmit` "Reply with … ok" (idle turn) | `3f877078…` |
| 14:17:36.9 | `Stop` of that turn | `3f877078…` |
| 14:17:40.7 | `UserPromptSubmit` arming prompt | `cc101efd…` |
| 14:17:46 | sentinel on disk, `armed` | |
| 14:17:50.7 | `UserPromptSubmit` "say banana", while the tool runs | `cc101efd…` |
| 14:17:50 | `.claude/autodrive.swept`: `sweeper=owner state=armed kind=rename age=4s` | |
| 14:18:15.5 | the only `Stop`, its last message answers both prompts | `cc101efd…` |
| 14:18:16.0 | mod `turn.complete`, nothing left to take | |

The queued prompt was injected into the running turn: one `Stop` for both
prompts. Its `UserPromptSubmit` fired at queue time, and the sweep ran
then.

**Queued during the final generation** (a run where the sleep was blocked
and the turn was already finishing):

| UTC | event | `prompt_id` |
| --- | --- | --- |
| 14:16:07.1 | `UserPromptSubmit` arming prompt | `90463013…` |
| 14:16:16 | sentinel on disk, `armed` | |
| 14:16:21.3 | `UserPromptSubmit` "say banana" | `90463013…` |
| 14:16:21 | `.claude/autodrive.swept`: `sweeper=owner state=armed kind=rename age=5s` | |
| 14:16:21.8 | `Stop` of the arming turn | `90463013…` |
| 14:16:23.9 | mod `turn.complete`, nothing left to take | |
| 14:16:24.9 | "say banana" recorded as its own user entry, its own turn | `9a14b767…` |

Here the queued prompt became a turn of its own, but its `UserPromptSubmit`
still fired before the arming turn's `Stop`.

In both runs no `custom-title` entry was written, and the pane showed `handoff:
stale autodrive discarded — the drive mod did not run it`, with the note
blaming an unloaded mod and the lines offered for the user to type.

## What the evidence settles

- The header comment's premise in `scripts/report-drive-failure.sh` ("The
  owner's own UserPromptSubmit … cannot fire between the write and that turn's
  own end") is false on 2.1.301: a queued prompt fires it inside the turn,
  before `Stop`.
- The same header already names the case ("Prose injected into a still-running
  turn … fails safe — the transition is cancelled and said so, not deferred").
  The cancel happens, but "said so" does not: the note blames an unloaded mod.
- **A lock-free discriminator exists in the hook input.** A prompt queued into
  a running turn carries that turn's `prompt_id`, in both places a prompt can be
  queued; a prompt typed at an idle composer carried a fresh one. No other field
  differs (`session_id`, `transcript_path`, `cwd`, `permission_mode`,
  `hook_event_name`, `prompt`).

## Not established

- That `prompt_id` behaves this way on purpose: it is observed on one version,
  not documented.
- Whether `prompt_id` is in the hook input on 2.1.287, the minimum supported
  version. Whatever the fix, an input without it has to sweep as today.
- What the drive does when the sweep spares the file and the queued prompt then
  starts its own turn (the second table). The mod's bail tests the composer
  (`$.prompt.read().text`), and a queued prompt has already left it, so the
  drive would run its lines with the queued turn about to start. For `rename`
  that is harmless. For `clear` or `compact`, nobody has observed whether the
  queued prompt lands in the fresh context, is lost, or collides with
  `$.command.run`. Needs one more run with the file spared.

Settled in a fourth run: the `PreToolUse(Bash)` hook input carries `prompt_id`,
the same value as that turn's `UserPromptSubmit`, so `inject-checkpoint-root.sh`
could pass the arming turn's id to the checkpoint.

## The negative: Esc, then a prompt

The case the sweep exists for, in a third run: the arming turn
(`prompt_id` `b831c608…`) was interrupted with Esc during its tool call at
14:22:08, so no `Stop` fired (zero `Stop` entries for the whole run), and `say
banana` was typed at the idle composer at 14:22:12. Its `UserPromptSubmit`
carried a fresh `prompt_id` (`d64eb9cd…`), and the sweep removed the owner's
`armed` file at 14:22:13 as it should. So "same `prompt_id` as the arming turn"
separates the queued prompt from the aborted turn in all three runs.
