# Step 1 (Loader) — RED review fixes

Only `tests/hook-test.bats` and `reports/step1-red.md` changed. Nothing committed or staged; no production code touched.
Applied F1, F3, F4, F5, F6, F8. Not applied: F2 (pending decision, no test change) and F7 (the "Delete it once nothing in it is still needed." sentence stays in `shadowed_task_ctx` / `shadowed_todo_ctx`, both variables untouched).

## Counts

| | rows | ok | not ok |
|---|---|---|---|
| before (`bats tests/hook-test.bats`) | 152 | 130 | 22 |
| after | 155 | 130 | 25 |

- The 25 are the 22 earlier reds plus three new red rows (F1, F4, F5). Compared by name, nothing else changed: every row that passed before still passes, and the only additions to the red list are the three new rows.
- F3 replaced an already red row, so it does not change the count.
- `shellcheck -x tests/hook-test.bats` is clean.
- Satisfiability: the review's reference implementation (`$TMPDIR/ref`, outside the repo) passes the edited file at 155/155, so no new row is red because of a typo or fixture slip.

## Rows added or changed

| finding | row | line | red today at |
|---|---|---|---|
| F1 (new) | `load-compact (root task shadows a legacy task, todo only legacy): from-legacy note first, then the ignored one` | 1561 | the `$MSG` equality: today it is `compacted — No todo.`, since the legacy todo is ignored |
| F3 (changed) | `handoff_frame (a second call): resets the legacy and shadowed flags` | 458 | the first call's `[ "${FRAME_TASK_LEGACY:-unset}" = "0" ]`, because the variable is unset (was red before, still red) |
| F4 (new) | `handoff_frame (root with a body beside a legacy file with no body): still shadowed, by existence` | 412 (comment at 407) | `[ "${FRAME_TASK_LEGACY:-unset}" = "0" ]`, because the variable is unset today. Its discriminating assertions, `FRAME_*_SHADOWED=1`, come after it and are covered by the mutation run |
| F5 (new) | `load-handoff (worktree cwd: reads the worktree's legacy task, not main's)` | 1198 (comment at 1194) | `[ "$framed" != "$CTX" ]`: legacy is ignored today, so the context is `No task frame or todo.` and the suffix strip changes nothing |
| F8 (comment) | the comment above the first `load-handoff (legacy task alone)` row | 1089 | not a row |

None of the new rows is a pure guard; all three are red from a failed assertion about the missing behaviour.

- F1: root `TASK.md` with a body, legacy task, legacy todo, no `TODO.md`, pending `compact`. Message `compacted — todo re-injected; $legacy_todo_msg; $shadowed_task_msg.`; context is header, root task, legacy todo, then `$legacy_todo_ctx`, `$shadowed_task_ctx`, `\n`. It also asserts the legacy task body is absent from the context. The root task is written in the row rather than taken from the seeded file, so the expected frame is explicit.
- F3: the three-call form. Call 1 (root task, legacy task, legacy todo) asserts all four flags: `TODO_LEGACY=1`, `TASK_SHADOWED=1`, the other two 0. Call 2 in `frame-leg-reset-2` (legacy task, root todo, legacy todo) asserts `TASK_LEGACY=1`, `TODO_SHADOWED=1`, the other two 0. Call 3 (the `gone-*` paths) asserts rc 1 and all four 0.
- F4: one row, both halves, with a different kind of body-less legacy file for each. Root task with a body beside a headings-only legacy task, and root todo with a body beside a zero-byte legacy todo. Expected: `FRAME` is the root frame whole, `*_LEGACY=0`, `FRAME_TASK_SHADOWED=1` and `FRAME_TODO_SHADOWED=1`.
- F5: modelled on "load-handoff (worktree cwd: reads worktree task, not main)" with `make_worktree`. The worktree has a legacy task (`worktree legacy task body`), `$tmp/.claude` has another (`main legacy task body`), and `$tmp/TASK.md` is removed. It runs `run_load_handoff "$wt" clear` and asserts the whole frame (worktree body), `$legacy_task_ctx`, `assert_notes` with `$legacy_task_msg; No todo`, and that the main body is absent.

## Decision pinned by F4, for Step 2

F4 pins existence: a legacy file that exists with no body behind a root file with a body counts as shadowed (`FRAME_*_SHADOWED=1`, so an ignored note is emitted). This is the choice the review recommended, taken so that the loader and the checkpoint decide "ignored" the same way. Step 2's checkpoint must mirror it: "both present" there is existence of the legacy file, whatever it holds. If my human partner prefers silence for a body-less legacy file, this row changes and the plan says so.

## F6

`reports/step1-red.md` now opens with a `> **Corrected at review, 2026-10-11.**` blockquote. It quotes "130 ok, 20 not ok", names the two omitted age rows with their red line, and gives the totals after these edits: 155 rows, 130 ok, 25 not ok.

## Mutation results

Each mutant is applied in place in the scratch reference (`$TMPDIR/ref`, edited test file copied in, originals kept in `$TMPDIR/ref-orig`). The reference passes 155/155 before each mutation and after the last restore. The `diff` against the original showed each mutation landed.

| mutant | rows that fail |
|---|---|
| F1: `load-compact.sh` zeroes `FRAME_TASK_SHADOWED` before building the notes (drops the task-shadowed note) | the new load-compact row, alone |
| F3: `FRAME_TASK_LEGACY` and `FRAME_TODO_SHADOWED` reset with `: "${X:=0}"`, the other two with `X=0` | `handoff_frame (a second call): resets the legacy and shadowed flags`, alone |
| F4: `*_SHADOWED=1` only when the legacy file also has a body, both halves | the new `handoff_frame` row, alone |
| F5: `load-handoff.sh` passes the legacy paths from `$CLAUDE_PROJECT_DIR/.claude/` instead of `$cwd/.claude/` | the new worktree row, alone |

For F1, F3 and F4 I did not re-run the old versions of the rows to show they survive the mutants. That survival is the review's measurement, and the new row killing each mutant is what I measured.

## Skipped

- F2: pending decision (Step 2 treating a body-less root file as absent), no test change.
- F7: the "Delete it once nothing in it is still needed." wording, left as is.
- F1's second review mutant (a load-compact note order that differs from load-handoff's): the same row should kill it, because the order is pinned whole in both channels, but I did not build that mutant separately.
