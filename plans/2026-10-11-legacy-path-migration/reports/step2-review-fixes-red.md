# Step 2 (Checkpoint migration) — RED part of the review fix wave

Changed: `tests/test_checkpoint.py` only. No `scripts/`, `bin/`, staging or
commits. Clean: `ruff check scripts tests`, `ruff format --check scripts tests`,
`docformatter --check scripts/*.py tests/*.py`, `mypy`, `ty check`.

## Counts (`pytest -q tests/test_checkpoint.py`)

| | rows | passed | failed |
|---|---|---|---|
| before | 309 | 309 | 0 |
| after | 331 | 311 | 20 |
| reference (scratch copy with the decisions applied) | 331 | 331 | 0 |

22 rows added. 15 are red today, 7 are green guards. 5 pre-existing ids go red
because their `GIT_RM` expectations moved to the `:/` form.

## Pre-existing rows whose expectations changed (now red, F1)

`GIT_RM`-based expectations use `git_act(*rels)` (`git rm --cached
--ignore-unmatch -q -- :/<rel> ...`, task before todo):

- `test_reports_and_the_git_rm_act_print_ahead_of_the_clause_file_refusal[with-commit]`
- `test_git_rm_act_is_owed_only_to_with_commit_over_a_legacy_file[with-commit-legacy-handoff]`
- `test_git_rm_act_is_owed_only_to_with_commit_over_a_legacy_file[with-commit-legacy-precompact]`
- `test_git_rm_act_names_only_the_files_that_moved_or_went`
- `test_checkpoint_leaves_a_tracked_legacy_file_to_the_printed_git_act[with-commit]`:
  `run_printed_git_rm` now runs the printed act from `repo/sub` (created),
  accepting a `:/` prefix on each token and running each token as printed. It
  asserts `D  .claude/handoff-todo.md` is staged after the act, then
  `R  .claude/handoff-todo.md -> TODO.md` once `TODO.md` is added.

Fails at: `assert 'git rm ... -- :/.claude/handoff-todo.md' in 'Before committing, run ...-- .claude/handoff-todo.md'` for the four text rows; for the tracked row, `assert 'D  .claude/handoff-todo.md' in [' D .claude/handoff-todo.md', ...]` (bare pathspec from `sub/` matches nothing, rc 0).
Also changed, helper only: `run_checkpoint` gained a keyword-only `command`
argument (default unchanged) for the F5 harness. The block comment above
`GIT_RM` states the `:/` form.

## New red rows (15) and the assertion each fails on

| finding | row | fails at |
|---|---|---|
| F3 | `test_root_files_that_cannot_be_read_stay_unread_with_no_legacy_file[keep, clear]` | `ok(result)`: `assert 1 == 0`, PermissionError reading `TASK.md` in `read_half` (the todo half is reached only once the task half is fixed) |
| F4 | `test_todo_symlinked_at_the_legacy_path_is_refused_and_nothing_moves` x {keep, edit, content, clear} x {relative, absolute} (8) | `assert result.returncode != 0` (`0 != 0`: the link is moved or removed) |
| F4 | `test_task_symlinked_at_the_legacy_path_is_refused_and_nothing_moves` x {content, clear} x {relative, absolute} (4) | same |
| F5 | `test_keep_moves_a_legacy_todo_across_devices_with_its_modification_time` | `ok(result)`: `assert 1 == 0`, `OSError: [Errno 18] Invalid cross-device link` from `legacy.path.replace` |

The F4 todo rows also carry a legacy task file and a task content write, so a
refusal that applied the task half first would fail the snapshot comparison.

## New green guards (7)

| finding | row | pairing and discrimination |
|---|---|---|
| F2 | `test_a_root_write_that_fails_leaves_the_legacy_file_as_it_was[todo_edit, todo_content, task_content]` | Correct today (write precedes unlink), so it cannot be red. Mutation-checked: the mutant that unlinks the legacy file before the root write (write and remove arms, move unchanged) fails all three ids and nothing else in the migration rows. Skipped when euid is 0. Positive: the move and replace rows. |
| F1 | `test_printed_git_act_over_an_untracked_legacy_file_is_a_silent_no_op` | rc 0 and status unchanged, run from `sub/`. Positive: the tracked row. Green with either pathspec form by design. |
| F5 | `test_the_cross_device_harness_fails_a_rename_of_a_legacy_file` | Control: under the harness both `os.rename` and `os.replace` of `.claude/handoff-*` raise EXDEV. Without it the F5 row would pass if the patch missed. |
| F7 | `test_clear_over_a_directory_with_a_legacy_file_is_refused_naming_it[todo, task]` | Names the root path, says "directory", no assertion on "move", snapshot unchanged. Green today because the message already contains both; it pins the clear action the earlier rows did not cover. The two existing directory rows gained `"directory" in stderr.lower()`. |

## Choices for GREEN to know

- F4 refuses only a symlink that resolves to a file (`is_symlink() and
  is_file()`), for every action, in `read_half` beside the directory refusal,
  naming the legacy rel in the message. A dangling symlink stays "no legacy
  file, nothing happens": the existing
  `test_only_a_regular_file_at_the_legacy_path_counts[dangling_symlink]` rows
  require rc 0 and an untouched tree. The rows do not cover a symlink behind a
  root file with a body, or an unrelated half.
- F5 harness: `tests/test_checkpoint.py` writes a wrapper to `tmp_path` that
  replaces `os.rename` and `os.replace` (raising EXDEV when the source path
  contains `.claude/handoff-`) and `runpy`-runs `checkpoint.py`. A fallback by
  `shutil.move`, or `os.replace` plus `shutil.copy2` on `OSError`, both pass. A
  fallback using `os.link` or `os.copy_file_range` would also; only `rename` and
  `replace` are blocked. mtime is asserted by `st_mtime_ns` equality.
- F3: the only requirement is that a half with no legacy file reads nothing
  and stats nothing for `keep`, and does not read for `clear`.
- F7: GREEN must keep the word "directory" and the root path in the message;
  the "cannot move" text is free to go.

## Satisfiability

`$TMPDIR/ref`: a copy of `scripts/`, `tests/`, `pyproject.toml` with, minimally:
`:/` on each path in `legacy_unstage_directive`; `read_half` refusing a legacy
file that `is_symlink()`, rewording the directory message to "`<rel> is a
directory, not a file`", and computing `counts` only when the legacy file is a
file; `shutil.move` in place of `Path.replace`. All 331 rows pass there
(66 s). The F2 mutant over that reference: 3 failed, 85 passed in the
migration selection; reference restored byte for byte afterwards.
