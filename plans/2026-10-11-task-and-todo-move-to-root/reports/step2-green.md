# Step 2 GREEN report: task shape (body cap, no list items)

## Changes

- `scripts/checkpoint.py`
  - `validate_task_shape(content)`: new. Body is the non-heading lines (right-stripped line fully matching `lib.ATX_HEADING` is dropped), joined with `\n`, stripped. First non-heading list line is named by 1-based line number, quote is the stripped line cut to 40. One `err("task", ...)` with facts joined by `; `, then `. ` and the fixed sentence.
  - `validate_task`: calls `validate_task_shape` on the content-string branch only. `main` order untouched (both validated before any `apply_plan`).
  - `_LIST_ITEM` (module regex `^\s*([-*+]|\d+[.)])\s`) and `TASK_BODY_LIMIT = 1000`: new, defined after the function that reads them.
- `scripts/_checkpoint_lib.py`: `_ATX_HEADING` renamed `ATX_HEADING` (the only in-code users were `is_empty_body` and its docstring; no alias); comment above it corrected. `docformatter -i` re-wrapped the `is_empty_body` docstring (a line-length consequence of the rename).
- `tests/test_checkpoint.py`: no assertion changed. `docformatter -i` re-wrapped five docstrings of the new tests (they exceeded its wrap width and `docformatter --check` was failing on them); this is the 229 vs 224 insertion difference.
- `tests/*.bats`: untouched.

## Existing tests whose fixtures changed

None. All 195 tests in the file pass, and `just hook-test` passes without a fixture change.

## Mutations (each applied with Edit, confirmed in `git diff`, run, undone with the inverse edit, green re-run)

Test ids below are shortened from `tests/test_checkpoint.py::`.

1. `>` to `>=`: 5 red: `test_task_body_cap_boundary[exactly_the_limit_accepted]`, `..._does_not_count_headings[headings_around_the_body]`, `[heading_splits_the_body]`, `test_task_body_cap_ignores_blank_lines_and_whitespace_around_the_body`, `test_task_body_cap_counts_characters_not_bytes[1000_characters_are_2000_bytes_accepted]`. All are rows accepting exactly 1000. As expected.
2. Headings counted (`"\n".join(lines)`): 7 red: `test_task_body_cap_boundary[exactly_the_limit_accepted]` and `[one_over_rejected]`, both `test_task_body_cap_does_not_count_headings` rows, `test_task_body_cap_counts_characters_not_bytes` both rows, `test_task_hash_without_space_is_body_not_a_heading`. The two expected rows are red. The extra five are unexpected but explained: their fixtures carry a `## Current task` heading, so counting it shifts the boundary or the quoted count. `..._ignores_blank_lines_...` stayed green.
3. Final `.strip()` dropped: 9 red: `test_task_body_cap_boundary` both rows, both `does_not_count_headings` rows, `test_task_body_cap_ignores_blank_lines_and_whitespace_around_the_body` (the expected one), `counts_characters_not_bytes` both rows, `test_task_hash_without_space_is_body_not_a_heading`, `test_task_over_the_cap_with_a_list_item_is_one_error_with_both_facts`. Extras are explained: removing heading lines leaves their surrounding newlines in the body, so every fixture with a heading overshoots by a few characters.
4. Bytes (`len(body.encode()) >` in the comparison only): 1 red: `counts_characters_not_bytes[1000_characters_are_2000_bytes_accepted]`. As expected.
5. List regex loses the `\s` after the marker: 3 red: `test_task_lines_that_are_not_list_items_accepted[bold]`, `[marker_without_space]`, `[decimal]`. As expected.
6. List regex loses `^\s*` and is searched (`.search`; dropping the anchor alone with `.match` would not match indented lines): 2 red: `test_task_lines_that_are_not_list_items_accepted[mid_line_hyphen]` (expected) and `[bold]`. `bold` is unexpected but explained: `**bold** x` contains `* ` mid-line.
7. `\d+[.)]?`: 1 red: `test_task_lines_that_are_not_list_items_accepted[year]`. As expected.
8. Shape check moved to `main` after `apply_plan(todo_plan)`: 12 red: `test_task_shape_failure_writes_nothing[over_the_cap]` and `[list_item]` (expected), plus `boundary[one_over_rejected]`, `test_task_hash_without_space_is_body_not_a_heading` and the 8 `test_task_list_item_rejected_naming_its_line` rows. Extras are explained: those tests assert the task file is absent after rejection, which no longer holds once the plan has been applied.

No expected row stayed green. No surviving mutation.

Mutation 2's first run overlapped an Edit issued in the same tool block as the green re-run of mutation 1. That run's result (195 green) was not trusted; mutation 2 was rerun alone and a clean green re-run followed the undo.

## Final gates

- `.venv/bin/pytest tests/test_checkpoint.py -q`: 195 passed.
- `just py-test`: 207 passed, 3 deselected.
- `just hook-test`: 148 ok, 0 not ok.
- ruff check, ruff format --check (8 files), docformatter --check (scripts/*.py tests/*.py), mypy (exit 0), ty check: all clean.

## Surprises

- `docformatter --check` failed on two files before any mutation: the red phase's one-line test docstrings were over its wrap width, and the rename shortened a line in `is_empty_body`'s docstring. Fixed with `docformatter -i` on those two files.
- `git` is sandbox-excluded, so `git diff` needed `dangerouslyDisableSandbox`.
- `plans/2026-10-11-task-and-todo-move-to-root/plan.md` still names `lib._ATX_HEADING` at line 93 (not editable by me; it is prospective text that said "made public").

## Review

Reviewed in the dispatching session, which changed two things before the
commit.

- The list loop tested each line against `lib.ATX_HEADING` before
  `_LIST_ITEM`. A heading line opens with `#` after at most three spaces and
  `_LIST_ITEM` wants a bullet or a digit there, so the clause could never
  decide anything; it is gone, and the docstring's "non-heading" with it.
- Naming the first list item alone was asserted by containment, which a
  version reporting every item also satisfies.
  `test_task_list_item_rejected_naming_its_line` now also asserts the phrase
  `is a list item` occurs once. Mutation 9, dropping the `break`: 1 red,
  `[first_of_two_items_is_named]`; restored, 195 green.
