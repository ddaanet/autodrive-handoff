# Step 3 RED report: `task` forbidden under precompact

Only tests/test_checkpoint.py changed. The new tests sit just before `test_rename_not_a_string_errors`. `precompact_payload` is untouched. The local helper `precompact_taskless_payload(todo)` builds the payloads with no `task` key.

## Tests added and why each fails today

Stderr below is the checkpoint's own line on the unchanged code.

1. `test_task_present_under_precompact_errors[content]`
   - Fails at `assert result.returncode == 2` (test line 429); the checkpoint exits 0 and applies the task write.
   - stderr is empty.
   - Wrong-reason pass: an exit 2 from any unrelated validation error would satisfy the exit-code check. The assertions that stderr names `task` and contains `forbidden when skill is "precompact"` rule that out. The unchanged-bytes and no-manifest assertions rule out an implementation that rejects only after applying the task half.
2. `test_task_present_under_precompact_errors[clear]`
   - Fails at `assert result.returncode == 2` (line 429); the checkpoint exits 0 and removes the file.
   - stderr is empty.
   - Same wrong-reason note as 1.
3. `test_task_present_under_precompact_errors[null]`
   - Fails at `assert 'forbidden when skill is "precompact"' in result.stderr` (line 431). The exit code is already 2 and stderr already names `task`.
   - stderr: `handoff-checkpoint: task: must be a content string or {"action": "clear"}, got null`
   - Wrong-reason pass: a "null is invalid" message that mentions `task` would pass the exit-code and `"task"` assertions. The `forbidden ... "precompact"` text assertion closes that gap.
4. `test_precompact_without_task_removes_pre_existing_file_manifest_records_d`
   - Fails at `assert result.returncode == 0` (line 454).
   - stderr: `handoff-checkpoint: task: required, a content string or {"action": "clear"}`
   - Wrong-reason pass: an implementation that accepts the payload but never deletes the file would pass the exit check. The file-gone assertion and the `D .claude/handoff-task.md` manifest line catch it. The `W .claude/handoff-todo.md` line shows the manifest is live.
5. `test_precompact_without_task_never_existed_writes_nothing_no_d`
   - Fails at `assert result.returncode == 0` (line 470).
   - stderr is the same `task: required` line as test 4.
   - Wrong-reason pass: an implementation that emits a spurious `D` or `W` line for an absent task file is caught by `"handoff-task.md" not in manifest`. That absence claim only means something because the todo `W` line proves the manifest is non-empty. A green implementation that wrote no manifest at all would fail the `read_text` call, which is intended while the manifest still exists at this step.
6. `test_precompact_task_removal_leaves_kept_todo_byte_identical`
   - Fails at `assert result.returncode == 0` (line 485).
   - stderr is the same `task: required` line as test 4.
   - Wrong-reason pass: an implementation that leaves the todo untouched but does not remove the task file is caught by the task-file-gone assertion. One that rewrites or removes the todo is caught by the byte-identical check.
7. `test_precompact_task_removal_with_todo_content_writes_the_todo`
   - Fails at `assert result.returncode == 0` (line 498).
   - stderr is the same `task: required` line as test 4.
   - The todo file is pre-seeded with different content, so the final content equality cannot hold unless the new content was actually written.
   - Wrong-reason pass: none beyond what tests 4 and 6 note; the task-gone and todo-equals-new-content assertions both bind.

## Whole-file run

`.venv/bin/pytest tests/test_checkpoint.py -q` gave 7 failed, 166 passed.

The 7 failures are exactly the new tests: 3 parametrized rows of test 1, plus tests 4 to 7. No existing test fails. ruff check and ruff format --check pass on the file.
