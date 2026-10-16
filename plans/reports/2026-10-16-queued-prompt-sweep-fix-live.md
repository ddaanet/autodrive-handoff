# Queued-prompt sweep: live verification of the fix

2026-10-16, Claude Code 2.1.301, interactive `claude --model haiku
--permission-mode default --plugin-dir /Users/david/code/handoff` in a dedicated
tmux server (`-L qrepro`), throwaway repo `/tmp/claude/qrepro/repo`, installed
`autodrive-handoff@ddaanet` disabled there and `CLAUDE_CODE_PLUGIN_DIRS` unset,
so the working tree's plugin (uncommitted fix: `report-drive-failure.sh`,
`inject-checkpoint-root.sh`, `_lib.sh`, `session-pointer.sh`, `handoff.ts`) was
the only copy loaded. Project-level `UserPromptSubmit`, `Stop` and
`PreToolUse(Bash)` hooks logged timestamp and stdin. Each case used a fresh
claude process and fresh logs. The repo was already trusted (no trust dialog).
Evidence copies: `/tmp/claude/qrepro/case{1,2,3}/` (`ups.log`, `stop.log`,
`pre.log`; case 2 also `pane.txt`). Times are UTC.

Arming went through the real skills and `handoff-checkpoint` in every case
(the prompt asked the skill to run a 30 to 60 s `python3 time.sleep` Bash call
after the checkpoint, which haiku did each time). The marker was written by
the `PreToolUse(Bash)` hook each time.

## Result: all three cases behave as the plan says

### Case 1: queued rename is spared and driven

Session `326cdfe9-61b9-4b1c-b44c-d280eb507f26`.

| UTC | event | `prompt_id` |
| --- | --- | --- |
| 17:49:22.8 | `UserPromptSubmit` `/autodrive-handoff:autoname …` | `41fe1b41…` |
| 17:49:42 | `.claude/autodrive` on disk: `armed 326cdfe9…` / `rename` / `/rename qrepro-case1` | |
| ~17:49:44 | sleep Bash call (30 s) starts | |
| 17:49:51.4 | "say banana" typed; shown as queued ("Press up to edit queued messages") | |
| 17:49:51.5 | `UserPromptSubmit` "say banana" | `41fe1b41…` (same) |
| 17:49:54 | sentinel unchanged, no `.claude/autodrive.swept` | |
| 17:50:16.05 | the only `Stop`, `prompt_id` `41fe1b41…` | |
| 17:50:16.7 | `/rename qrepro-case1` ran: pane `Session renamed to: qrepro-case1`; `custom-title.json` written | |
| 17:50:24 | `.claude/autodrive` gone; no `autodrive.swept`, no `autodrive.failed` | |

Marker `/tmp/claude/handoff-prompt-326cdfe9-…` (`od -c`): `41fe1b41-fe36-4bb5-8285-fc4088e7c5b0\0`,
the arming turn's id, NUL-terminated.
The transcript `326cdfe9….jsonl` holds one `custom-title` entry,
`qrepro-case1`. The pane scrollback holds neither "stale autodrive discarded"
nor "cancelled". The agent answered banana in the same turn.

Result: pass on every expectation.

### Case 2: queued clear is cancelled

Session `f3805dd8-6482-42d3-890e-744b7ffc4664`, `/autodrive-handoff:handoff`
with `clear: true, continue: true, commit: without-commit`; state `armed`
(not `held`), kind `clear`, lines `/rename qrepro-case2`, `/clear`, `Continue
where the previous context stopped.`

| UTC | event | `prompt_id` |
| --- | --- | --- |
| 17:50:46.8 | `UserPromptSubmit` `/autodrive-handoff:handoff …` | `e03b5c14…` |
| 17:51:04 | sentinel `armed` / `clear` on disk | |
| 17:51:06 | sleep Bash call (40 s) starts | |
| 17:51:12.7 | "say banana" typed | |
| 17:51:12.8 | `UserPromptSubmit` "say banana" | `e03b5c14…` (same) |
| 17:51:12 | `.claude/autodrive` removed; `.claude/autodrive.swept` gets `sweeper=f3805dd8… state=armed owner=f3805dd8… kind=clear age=9s cwd=/tmp/claude/qrepro/repo` | |
| 17:51:46.9 | queued prompt delivered to the model with the sleep's tool result, carrying the hook's note as additional context: `The driven /clear did not run. Answer this prompt, then run the handoff skill again with the same transition, unless this prompt changes that.` | |
| 17:51:51 | agent re-runs `handoff-checkpoint` with the same payload (pane: `Re-running handoff checkpoint with the same driven clear`); I approved it | |
| 17:53:52.4 | the only `Stop` (`e03b5c14…`); last message "Banana. The clear did not run the first time, so I re-armed…" | |
| 17:53:52+ | the re-armed transition runs: pane `/clear`, `Prompt from the autodrive-handoff plugin`, `Continue where the previous context stopped.` (new `UserPromptSubmit` `24706828…`) | |

Pane (verbatim, under the `❯ say banana` line): `UserPromptSubmit says:
handoff: transition cancelled — a prompt arrived before it ran.` No lines were
offered ("Type in order" absent), no "stale autodrive discarded". The marker
held `e03b5c14-fe66-4113-b006-c6aae26d1bc2\0`. `/clear` ran once, only after
the re-arm; nothing in `autodrive.failed`.

Result: pass. Observation, not a defect of the fix: the model answered banana
only in its final message, after re-running the skill and a second 40 s sleep
(the original instruction in my prompt), so the "answer, then re-run" order is
not pinned by this run. The re-armed clear and continuation did land in the
fresh session.

### Case 3: Esc then a prompt at the idle composer is swept as stale

Session `bbc510d3-9926-431d-b7be-7bfe7699a6de`, `autoname`, rename.

| UTC | event | `prompt_id` |
| --- | --- | --- |
| 17:54:26.5 | `UserPromptSubmit` `/autodrive-handoff:autoname …`; the checkpoint `PreToolUse(Bash)` carries the same id | `305f953c…` |
| 17:54:38 | sentinel `armed` / `rename` on disk; sleep (60 s) running | |
| 17:54:41.8 | Esc: pane `Interrupted · What should Claude do instead?`; no `Stop` | |
| 17:54:45.9 | "say banana" typed at the idle composer | |
| 17:54:46.0 | `UserPromptSubmit` "say banana" | `fffa64d4…` (fresh) |
| 17:54:46 | sentinel removed; `autodrive.swept`: `sweeper=bbc510d3… state=armed owner=bbc510d3… kind=rename age=14s …` | |

Marker held `305f953c-e9b1-46b8-94a9-b89917a6f971\0`, differing from the
input's id. Pane: `UserPromptSubmit says: handoff: stale autodrive discarded
— the drive mod did not run it. Type in order: /rename qrepro-case3`. No
`custom-title` entry in the session transcript. Hence the sweep still catches
the aborted turn.

Result: pass.

## What is settled

- The discriminator works live on 2.1.301 in both directions: a prompt queued
  into the arming turn shares its `prompt_id` with the checkpoint's
  `PreToolUse(Bash)` input and the marker; a prompt after an Esc has a fresh one.
- Queued `rename` is spared silently and the mod's end-of-turn drive renames
  (case 1), with the mod no longer reading the composer (the queued text had
  left it anyway).
- Queued `clear` is swept and recorded, shows the cancel fragment, offers no
  lines, and the directive reaches the model as hook additional context; the
  agent re-armed (case 2).
- The unloaded-mod sweep and its "Type in order" lines are unchanged for the
  aborted-turn case (case 3).
- The marker is a NUL-terminated file at `/tmp/claude/handoff-prompt-<session>`,
  written at the checkpoint call.

## What is not settled

- Queued `compact` and queued `rename` where the queued prompt becomes its own
  turn (the second table of the repro report) were not exercised; the prompt
  here was always injected into the running turn (`queue-operation` entries,
  one `Stop`).
- Model behaviour after the cancel note varies: here it re-ran the skill before
  answering. Only the hook output is pinned.
- Behaviour on 2.1.287 (the minimum), where `prompt_id` may be absent, was not
  run; that path is covered only by the bats row.
- One run per case on haiku; no repetition.
