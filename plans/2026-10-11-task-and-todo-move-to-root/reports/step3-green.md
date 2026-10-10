# Step 3 GREEN report: precompact forbids `task`, removes the task file

## scripts/checkpoint.py (the only source file touched)

- Module docstring: adds a sentence saying only `handoff` carries `task`; `precompact` forbids the key and removes any task file.
- `main`: passes `skill` to `validate_task`. The call site is unchanged otherwise, so the check runs before `plan_task`/`apply_plan`, i.e. before anything is written.
- `validate_task(payload, skill)`: under `precompact`, a `task` key (any value, including null) is `err("task", 'forbidden when skill is "precompact"')`; no key returns `("clear", "")`. Under `handoff` the old body is untouched (same messages).
- `plan_task`, `_plan_file`, `_checkpoint_lib.py`, `autoname`: unchanged. The removal reuses the `clear` route, so a missing file yields a no-op with no manifest line.
- `_checkpoint_lib.py` has no string saying precompact takes `task`; no edit. The `bin/handoff-checkpoint` comment only mentions a probe; no edit.

## Migration (tests/test_checkpoint.py; bats needed nothing)

`grep -n precompact tests/*.bats` shows one hit (`expected_closing precompact True`, a closing-line check with no payload), so no bats edit.

18 precompact payload dicts carried `task_clear()`. All were of the "about something else" kind, and `"task": task_clear(),` was dropped from each:

| test | decision |
|---|---|
| test_each_of_two_skill_values_accepted (precompact half) | dropped key |
| test_rename_present_under_precompact_errors | dropped key |
| test_empty_or_null_rename_under_precompact_errors | dropped key |
| test_precompact_with_rename_omitted_accepted | dropped key |
| test_top_level_unknown_key_errors_under_precompact | dropped key |
| test_precompact_nothing_touched_manifest_still_written_empty | dropped key |
| test_clear_present_under_precompact_errors | dropped key |
| test_compact_missing_under_precompact_errors | dropped key |
| test_compact_neither_boolean_nor_string_errors | dropped key |
| test_empty_compact_directive_errors | dropped key |
| test_multiline_compact_directive_errors | dropped key |
| test_continue_missing_errors_at_either_boundary (precompact half) | dropped key |
| test_continuation_against_untyped_transition_errors (precompact half) | dropped key |
| test_precompact_compact_false_two_line_marker | dropped key |
| test_precompact_compact_true_no_continuation_bare_compact | dropped key |
| test_precompact_focus_directive_and_continuation_both_carried | dropped key |
| the dirty-memory precompact test near old line 1909 (name not recorded; the test after test_sentinel_typing_nothing_arms_even_with_memory_gate_pending) | dropped key |
| helper `precompact_payload` | dropped key; used by about 14 callers, all unchanged |

Tests that failed after the key drop (7 failures), with the decision:

| test | decision | covered by |
|---|---|---|
| test_each_boundary_composes_own_directive_not_the_others[precompact] | dropped key in the `else` payload (about directives) | n/a |
| test_todo_write_creates_file_manifest_records_w[precompact] | dropped key (task added only for the handoff branch); docstring reworded (it referenced the task test's note) | n/a |
| test_task_or_todo_null_or_absent_errors_naming_field[task_null-precompact] | removed from the parametrization (precompact x task combos excluded by a comprehension; `todo` rows still run at both boundaries; task rows at handoff). Not deleted as a test | task null under precompact: test_task_present_under_precompact_errors[null] |
| ...[task_absent-precompact] | same, removed from the parametrization | absent task under precompact is the new removal tests (test_precompact_without_task_*) |
| ...[todo_null-precompact], [todo_absent-precompact] | kept, dropped key | n/a |
| test_task_write_creates_file_manifest_records_w[precompact] | the `skill` parametrization is deleted; the test now runs handoff only (no handoff row duplicates it, so it is kept). Docstring rewritten | precompact side: test_task_present_under_precompact_errors[content] |

Helper merge: `precompact_taskless_payload` deleted; `precompact_payload(commit, todo=None)` is the single helper (todo defaults to `todo_keep()`), and the four red tests now call `precompact_payload("with-commit", ...)`. No alias. The helper stays beside `handoff_payload` near the bottom (callers above it, as in the file's existing layout).

Net test count: 173 collected before the migration (166 passed + 7 failing), 170 after. The three missing are the three parametrization rows removed above.

## Mutations (each restored by inverting the same edit, re-run green: 170 passed)

1. Forbidden check disabled (`if "task" in payload:` replaced with `if False:`): 3 failed, 167 passed. Failing: `test_task_present_under_precompact_errors[content]`, `[clear]`, `[null]`. Nothing else failed, and all three of the expected rows failed.
2. Task plan made a no-op under precompact. Changing only `validate_task` to return `"keep"` would not do it, because `plan_task` treats any non-`clear` action as content `""`, which still removes. So the mutation was two edits: `validate_task` returns `("keep", "")` under precompact, and `plan_task` returns `FilePlan("none", ...)` on `keep`. Result: 3 failed, 167 passed. Failing: `test_precompact_without_task_removes_pre_existing_file_manifest_records_d`, `test_precompact_task_removal_leaves_kept_todo_byte_identical`, `test_precompact_task_removal_with_todo_content_writes_the_todo`. `test_precompact_without_task_never_existed_writes_nothing_no_d` stayed green, as expected. Both edits were reverted (`grep` shows the only remaining `"keep"` in plan paths is the existing todo one).

## Final gates (all after the mutations were restored)

- `.venv/bin/pytest tests/test_checkpoint.py -q`: 170 passed
- `just py-test`: 182 passed, 3 deselected
- `just hook-test`: 148 ok, 0 not ok
- `ruff check scripts tests`: clean; `ruff format --check scripts tests`: 8 files already formatted
- `mypy` (bare, as the justfile runs it): rc 0; `ty check`: clean; `docformatter --check scripts/*.py tests/*.py`: rc 0
- `just precommit` not run (as instructed); `claude plugin test`/`validate-plugin` not run.

## Surprises

- `test_each_boundary_composes_own_directive_not_the_others` builds its payload with `"skill": skill` in an if/else, so a grep for `"skill": "precompact"` would have missed it; the failing run caught it.
- The `precompact_payload` helper and the two null/absent task rows were not literally "test about task" but the parametrization crossed skills; handled by excluding precompact x task rather than deleting test functions.
- `ruff format` reflowed only my edits (git diff stat: checkpoint.py 18 lines, test_checkpoint.py about 173 lines); nothing else in the tree was touched. The pre-existing uncommitted files (plans/.../plan.md, .claude/handoff-*) were left alone.
- git commands are in `excludedCommands` here and need `dangerouslyDisableSandbox`.
