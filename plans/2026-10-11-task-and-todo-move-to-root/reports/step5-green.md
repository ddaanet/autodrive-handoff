# Step 5 GREEN report

## Changes

- `scripts/_lib.sh`, `handoff_frame`: prints nothing; resets then sets `FRAME`, `FRAME_TASK`, `FRAME_TODO` in the caller's scope on every call (`# shellcheck disable=SC2034` above the function, as `handoff_drive_read` does). A file counts when `-f` holds and `python3 _checkpoint_lib.py --is-empty-body < file` exits non-zero. Returns 1 when neither counts, leaving `FRAME` empty. Comment rewritten to say so. Both parameters are now required (`$2`, no default).
- `scripts/load-handoff.sh`: calls `handoff_frame … || true`, reads the variables. Always emits one JSON object (only an unresolved root exits silently). Notes order: transition note first, then `loaded — <size>, saved <age>` (size is `${#FRAME}`, age from only the files that count, passed through a `counted` array), then `No todo` (task alone) or `No task frame` (todo alone); neither counts gives `No task frame or todo.`. `additionalContext` is FRAME plus `\n\nNo todo.` / `\n\nNo task frame.` plus `\n`, or `No task frame or todo.\n` for neither. Header comment and the frame comment rewritten.
- `scripts/load-compact.sh`: `handoff_frame … || true`; message is `handoff: compacted — todo re-injected.` when `FRAME_TODO` is 1, else `handoff: compacted — No todo.`; frame injected whenever `FRAME` is non-empty, no `hookSpecificOutput` otherwise. The comment above the call rewritten (it states that the checkpoint removes the task file at this boundary, so a task file here was hand-written).

## Results

- `bats tests/hook-test.bats`: 124 ok, 0 not ok.
- `bats tests/checkpoint.bats tests/drive-take.bats`: 28 ok, 0 not ok.
- `shellcheck -x bin/* scripts/*.sh tests/*.bats`: no output (rc 0).
- After every mutation was undone, a full run was green (0 not ok) before the next mutation.

## Mutations (row numbers are bats numbers)

| # | mutation | red rows | as expected |
|---|---|---|---|
| 1 | body test replaced by `-s` | 18, 19, 20 (handoff_frame: headings-only task beside todo; headings-only both; whitespace-only task); 71, 72 (load-handoff headings-only task beside todo / both); 73 (age); 88 (load-compact headings-only todo) | yes. The `#tag` / `#!/bin/sh` row stays green, as it should (both are non-empty files) |
| 2 | `FRAME_TASK` always 1 (reset value 1) | 14, 16, 17, 18, 19, 20, 22 (handoff_frame); 67, 70, 71, 72, 73, 77 (load-handoff); 86, 87, 88 (load-compact) | yes (broad; also breaks rc 1 and the neither state) |
| 3 | `FRAME_TODO` always 1 | 15, 16, 17, 19, 22, 23 (handoff_frame); 66, 67, 69, 72, 74, 75, 76-84 (load-handoff, nearly all); 87, 88, 90, 92, 93 (load-compact) | yes |
| 4 | reset removed entirely | 14-20, 22 (handoff_frame); 66-67, 69-77, 78-84 (load-handoff); 86-88, 90, 92-94 (load-compact) | red, but mostly from `set -u` unbound variables in the loaders, not from staleness |
| 4b | reset replaced by "default only when unset" (isolates staleness) | 22 only (handoff_frame second call: resets FRAME and both flags) | yes: only the second-call row pins the reset, no loader row would catch it (each loader runs one call per process) |
| 5 | `-f` dropped | 14, 15, 16, 22, 23 (handoff_frame); 66, 67, 69, 70, 74-84 (load-handoff); 86, 87, 88, 90, 92, 93 (load-compact) | yes (a failed redirect makes `! python3 …` true, so a missing file counts) |
| 6 | neither-counts branch exits silently | 67 (no file at all), 72 (headings-only both), 77 (driven clear with no frame) | yes |
| 7 | the two one-half notes swapped on both channels | 69 (task alone), 70 (todo alone), 71 (headings-only task beside todo), 73 (age), 83 (malformed note precedes) | yes |
| 8 | note dropped from `additionalContext`, kept in `systemMessage` | 69, 70, 71, 73 | yes |
| 9 | age from both paths whenever they exist | 73 (age) only | yes |
| 10 | `loaded` note prepended before the transition note | 83 (malformed pending: note precedes the frame notes) only | yes |
| 11 | compact message keyed on `FRAME` non-empty | 90 (hand-written TASK.md alone), 92, 93 | yes |
| 12 | compact frame injected only when `FRAME_TODO` is 1 | 90, 92, 93 | yes |

## Surviving mutations

None: every mutation turned at least one row red.

## Notes

- Mutation 4 as literally specified is noisy: the loaders run under `set -u`, so removing the reset fails them with unbound variables. Mutation 4b isolates the staleness and shows a single row (22) pins it.
- Mutation 10 also leaves `No todo` after the transition note in the mutated script (only `loaded` moved); the one row that pins ordering caught it.
- Mutation 12 was written with a command substitution that shellcheck flagged (SC2015) while it was applied; it was undone and the final shellcheck is clean.
- Nothing outside the three scripts was touched. No test was changed.

## Review

Reviewed in the dispatching session. Two comments were reworded before the
commit: the `handoff_frame` comment named `write-stage.sh`, deleted in step 4,
as a sharer of the emptiness rule, and the `load-compact.sh` comment was cut
to what the code does. No code changed.

The `write-guard` rows the red report saw fail once belong to a guard fix the
dispatching session was mutation-checking in the same tree at the time; they
are not a flake.
