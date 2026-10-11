# Step 4 report: the move and the cut

Done inline, after my human partner ruled "all defaults" on the plan's six
defaults.

## Where it departs from the plan

- **`handoff_match_target` is gone, not slimmed.** The plan kept it with one
  (basename, rel) pair. With `write-stage.sh` deleted it had one caller and one
  file, and `handoff_hook_fields` had no other reader, so both are inlined into
  `write-guard.sh` (one `jq` parse, the basename test, the resolved-path
  comparison). `handoff_resolve` and `handoff_deny` stay in `_lib.sh`.
- **`clear` plans a removal without a stat.** The plan said "`none` when the
  file is absent". That distinction existed to keep a `D` line out of the
  manifest; with no manifest, `apply_plan`'s tolerant unlink covers the absent
  file and `none` is `keep`'s plan alone.
- **`_plan_file` is gone.** Its job was to pair a body with its manifest line.
  `plan_task` and `plan_todo` build their `FilePlan` directly.
- **`.gitignore` also loses `.claude/handoff.md`**, an entry for an artifact
  nothing has written since the task frame replaced it.
- **The emptiness rule's spellings are tested on `is_empty_body` itself**
  (13 rows) and on its CLI's exit codes (4 rows). They used to be reached
  through the checkpoint's removal, which no longer exists; step 5 gives the
  rule its reader back in `handoff_frame`.

## Mutations

Each applied by script, the file restored and compared with the original
afterwards. `tests/test_checkpoint.py`, 212 tests:

| Mutation | Red |
| --- | --- |
| a task content with no body removes the file | the 3 `test_content_with_no_body_is_written_as_given[*-task]` rows |
| the same on the todo half | the 3 `[*-todo]` rows |
| an edit that leaves no body removes the file | `test_todo_edit_striking_the_last_item_leaves_the_headings` |
| the unlink does not tolerate an absent file | the 3 `never_existed` rows, and every row whose payload clears an absent task file |
| `compose_sentinel` does not create `.claude/` | `test_root_without_a_claude_directory_gets_one_for_the_sentinel` |
| `keep` writes an empty file | the 3 `test_todo_keep_leaves_the_list_as_it_is` rows and 2 others |
| task `clear` does nothing | the 2 `pre_existing` rows for the task and 4 others |
| todo `clear` does nothing | `test_todo_clear_leaves_no_file[pre_existing]` |
| blank judged without stripping trailing whitespace | `test_is_empty_body[spaces_alone]`, `[whitespace_lines]` |
| a heading is any line opening with `#` | `[three_spaces_indent_a_heading]`, `[shebang]`, `[hash_without_space]`, `[seven_hashes]` |
| a heading judged on the fully stripped line | `[four_spaces_open_a_code_block]` |

`tests/hook-test.bats`, the nine `write-guard` rows:

| Mutation | Red |
| --- | --- |
| the basename filter passes every file | `TASK.md`, `TODO.md` and `autodrive.md` allow rows |
| the cross-project comparison is skipped | the cross-project row and the worktree row |
| the root is the raw hook cwd | the `CLAUDE_PROJECT_DIR` drift row |

## Counts

`just precommit`: 133 bats rows (148 before: the 5 `write-stage` and 10
`bash-post` rows went, and the guard section has 9 rows before and after),
224 pytest (207 before).

## Left for step 6

`CLAUDE.md`, `README.md`, the design docs and the skill prose still describe
the old paths, the guard on the task file and the staging hooks.
