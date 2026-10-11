# Step 2 (Checkpoint migration) — RED report

Changed: `tests/test_checkpoint.py` only (an `import re` and one block appended
at the end, "Legacy path migration", ~808 lines). No production code, nothing
staged or committed. `tests/checkpoint.bats` untouched: no row belongs there.

## Counts

| | rows | passed | failed |
|---|---|---|---|
| before (`pytest -q tests/test_checkpoint.py`) | 212 | 212 | 0 |
| after | 301 | 233 | 68 |

89 new rows: 68 red, 21 expected-green guards (below). All 212 pre-existing
rows still pass. `ruff check`, `ruff format --check`, `docformatter --check`,
`mypy`, `ty check` are clean (the justfile runs them over `tests/`).

All 68 failures are `AssertionError`s (junit XML read: zero errors, no import
or fixture failure). A fixture mistake would show as a different exception.

## Validation beyond "red": a scratch GREEN

To prove the rows are satisfiable and discriminate, I wrote a throwaway
implementation in a COPY of the repo under `$TMPDIR` (the repo's `scripts/` is
untouched). Against it: 301 passed. Mutants of it, each run over the whole file:

| mutant | rows that go red |
|---|---|
| root-wins dropped (a root with a body never counts) | 14: the ignored rows (todo x6, task x2, both-halves), edit-strike, both git-rm negatives, the kind row |
| task plan applied before the todo half resolves ("migrating before validation") | 10, 6 of them new: the todo-edit-fails-after-task row, 2 of the 5 rejection ids (the two edit ids), the three todo-directory ids; plus four pre-existing edit-failure rows |
| reports printed after the directive parts (closing line no longer last) | 9: all 8 tail-matrix ids and the ordering row |
| `exists()` instead of `is_file()` for the legacy path | 4: the dir and dangling-symlink ids |
| git rm lists ignored files too | 2 |

Planned for the GREEN review (not run on the real code, there is none yet): the
same five mutations, plus "`with-commit` act missing" (the `with-commit`/legacy
git-rm ids) and "held tail not last".

## Interface the rows fix for GREEN

Stdout wording is NOT pinned beyond this, constants at the top of the block:

- `LEGACY_TASK_REL = ".claude/handoff-task.md"`, `LEGACY_TODO_REL =
  ".claude/handoff-todo.md"` (relative to the root; a mirror of the `_lib.sh`
  constants, by hand). A report may use an absolute path, since the match is a
  substring.
- A **report is one line of stdout** that contains the legacy path and one
  action word, matched whole and lower-case: `MOVED = \bmoved\b`, `REMOVED =
  \bremoved\b`, `IGNORED = \bignored\b` ("removed" contains "moved", hence the
  word boundary). Exactly one such line per legacy file per call. Lines
  containing `git rm` are not reports. Why this much: the plan says stdout
  "names the legacy path and says what happened"; a path and a verb is the
  least that lets a row tell a move from a removal from an ignore.
- An ignored line carries neither `moved` nor `removed`; a moved or removed
  line does not carry `ignored`.
- Which word: `keep` and `edit` of a legacy-only half: `moved`. `clear`, a
  content write that leaves the root without a body, and the removal of a
  legacy file by `precompact`'s task removal: `removed`. A content write with a
  body over a legacy-only (or body-less-root) half: `moved` OR `removed`, the
  plan being ambiguous (see Open questions). A root with a body beside a legacy
  file, any action: `ignored`.
- **Order**: every report line comes before every directive part (memory text,
  todo boundary / SDD nudge, the commit act, the closing or arming line). The
  last line group of stdout stays the closing line (armed) or the arming line
  (held), exactly once.
- **Git act**: the literal `git rm --cached --ignore-unmatch -q --` followed by
  the legacy paths space-separated, relative, task before todo, only those
  moved or removed (never an ignored one). Printed once, under `with-commit`
  only, before the closing/arming line; surrounding wording (backticks, a
  sentence) is free. Lines with it are matched on that substring.
- **Refusal for a directory root** (`TASK.md`/`TODO.md` a directory, legacy file
  with a body): non-zero exit (not pinned to 2), no `Traceback` in stderr, the
  root name (`TASK.md` / `TODO.md`) in stderr, tree byte-identical afterwards
  (sentinel absent).
- **Nothing legacy** (no file, a directory, or a dangling symlink at the legacy
  path): stdout byte-identical to today, i.e. `[commit_directive().rstrip +
  "\n\n"] + closing_directive|arming_directive`, built from the lib functions
  with their current zero-extra-argument call.
- **Rejection rows** require `stderr` to still carry today's tokens: `bogus`,
  `list item` (FR13), `not found`, `ambiguous`, `CLAUDE_CODE_SESSION_ID`. The
  `edit` messages must therefore examine the effective file (the legacy one
  when the root has no body): today the legacy-only case says `TODO.md does not
  exist`, which the rows reject.
- Moves are rename-equivalent for bytes: the root file gets the legacy bytes
  (or the edited/written content), the legacy file is gone.

## Rows and the assertion each fails on today

(Test names abbreviated; each id is one row. Line numbers are in the current
`tests/test_checkpoint.py`.)

| item | row (ids) | fails today at |
|---|---|---|
| 1 todo moved | `test_legacy_todo_with_no_root_file_is_moved_to_the_root_name` [keep, content, edit] x [plain, spaced] | keep: `read(TODO.md) == expected` is `None`; content: legacy file still exists; edit: `returncode == 0` (stderr `edit requested but TODO.md does not exist`) |
| 1 task, both | `..._legacy_task_..._replaced_by_the_written_task`; `test_both_halves_migrate_in_one_call_each_reported`; `..._legacy_todo_with_no_body_and_no_root_file_is_still_moved` | legacy task still exists; `TODO.md` is `None` (both rows) |
| 2 body-less root | `test_bodyless_root_todo_is_replaced_by_the_move` [keep, edit, content] x [headings_only, whitespace_only, empty]; `test_bodyless_root_task_...` x3 | keep: root still holds its body-less bytes; edit: `returncode == 0` (`not found`); content/task: legacy still exists |
| 3 root wins | `test_root_todo_with_a_body_wins_...ignored` [keep, edit, content] x [legacy_body, legacy_bodyless]; `test_root_task_with_a_body_wins_...` x2; `test_each_ignored_legacy_file_is_reported_once` | `assert_reported`: `want one line naming <legacy path>, got []` (the rows' file assertions pass today, the report is what is missing) |
| 4 body-less after write | `test_bodyless_todo_content_removes_the_legacy_file_and_says_so` [root_absent, root_with_body]; `test_edit_that_strikes_the_last_item_...`; `test_bodyless_task_content_...` x2 | legacy file still exists |
| 5 clear | `test_todo_clear_removes_the_legacy_file_too_and_says_so` x2; `test_task_clear_...` x2; `test_precompact_task_removal_takes_the_legacy_task_file_too` x2; `test_precompact_carries_a_legacy_todo_by_the_todo_rules` [keep, content] | legacy file still exists; keep: `TODO.md` is `None` |
| 6 rejection | `test_a_rejected_payload_moves_nothing_and_the_fixed_one_migrates` [schema_error, task_shape_error, held_without_a_session_id]: fixed run leaves `TODO.md` unwritten (`read(TODO.md) is not None`); [edit_old_string_absent, edit_old_string_ambiguous]: rejected run's stderr lacks `not found` / `ambiguous`; `test_a_failing_todo_edit_does_not_remove_a_legacy_task_the_task_half_would` | as stated; the last: the fixed second call leaves the legacy task |
| 7 stdout | `test_reports_come_first_and_the_tail_stays_last` x8 (skill x typed x commit); `test_reports_precede_every_directive_part` | `want one line naming .claude/handoff-task.md, got []` |
| 8 git rm | `test_git_rm_act_is_owed_only_to_with_commit_over_a_legacy_file` [with-commit/legacy] x [handoff, precompact]; `..._names_only_the_files_that_moved_or_went`; `..._is_not_owed_to_a_legacy_file_that_is_only_ignored` | the `git rm ...` string absent from stdout; the last two reach `assert_reported` and fail on the missing report |
| 9 exotic | `test_only_a_regular_file_at_the_legacy_path_counts` [file x root_absent, file x root_with_body]; `test_todo_directory_with_a_legacy_body_is_refused_not_a_traceback` [keep, content]; `test_task_directory_...` | file/root_absent: `TODO.md` is `None`; file/root_with_body: no ignored report; dir keep: `returncode != 0` (it exits 0); dir content and task dir: `"Traceback" not in stderr` (IsADirectoryError) |
| 10 idempotence | `test_a_second_identical_call_changes_and_reports_nothing` | first call leaves `TODO.md` `None` |

## Expected-green guards (pass today by construction, 21)

Each is paired with a red row over the same fixture shape:

- `test_stdout_with_no_legacy_file_anywhere_is_what_it_was` x8: today's
  stdout, pinned. Positive: every migrating row of item 7 (same call, over a
  legacy file).
- `test_git_rm_act_is_owed_only_to_with_commit_over_a_legacy_file`: the 6
  non-(with-commit, legacy) ids. Positive: the two with-commit/legacy ids,
  the same parametrization.
- `test_only_a_regular_file_at_the_legacy_path_counts`: the 4 `dir` and
  `dangling_symlink` ids. Positive: the two `file` ids, the same
  parametrization. Mutation-checked: `exists()` instead of `is_file()` reds
  exactly these 4.
- `test_todo_directory_with_a_legacy_body_is_refused_not_a_traceback[edit]`:
  green today for the wrong reason (`TODO.md does not exist`), which stays
  acceptable (non-zero, no traceback, names `TODO.md`, tree untouched). Positive:
  the `keep` and `content` ids.
- `test_clear_with_no_legacy_file_says_nothing_about_one`. Positive: the four
  `clear` rows over a legacy file.
- `test_edit_applies_to_the_root_file_never_to_the_ignored_legacy_one`:
  `old_string` only in the legacy file is refused today because edit reads the
  root. It guards the root-wins rule against a GREEN that edits the legacy file
  (mutation-checked: root-wins dropped reds it). Positive: the `edit` ids of
  the item 3 row.

## Open questions

1. **A content write over a legacy-only half**: "moved" or "removed"? The plan
   says "a content write simply writes the root file and removes the legacy
   one" and "reports each move ... and each legacy removal". The rows accept
   either word there (`moved_or_removed`) and require `removed` where the root
   had a body or the clear/body-less-after-write rules apply. If GREEN or the
   review prefers one word, tighten `TODO_OVER_LEGACY["content"]` and the task
   rows.
2. **Body-less legacy file, root absent, `keep`**: the rows say it is moved
   (`test_legacy_todo_with_no_body_and_no_root_file_is_still_moved`), reading
   the Amended note ("replacing a body-less root file", "the next checkpoint
   moves it") and the step 1 probe ("step 2 will still move it"). The plan does
   not state the case outright. If the intent is "a body-less legacy file is
   not worth moving", that one row flips.
3. **Body-less root beside a body-less legacy file** is not pinned (the plan is
   silent and the result is the same frame either way).
4. A symlink at the legacy path that points at a real file with a body counts
   (`is_file()` follows it, as the loader's `-f`); the move is then a rename of
   the link or a copy of the target, unpinned and not exercised. Only the
   dangling and directory cases are rows.
5. The held rejection row (`CLAUDE_CODE_SESSION_ID` unset) depends on the
   existing check running before plan resolution; it is the "migrating before
   validation" guard for that path.
6. File size: `tests/test_checkpoint.py` is 3488 lines, already 2680 before; the
   new block is a cohesive section at the end. The 400-line soft cap would
   argue for a `tests/test_checkpoint_legacy.py`; it would need the helpers
   (`run_checkpoint`, `make_repo`, `frame_payload`, ...) moved or imported, so I
   left it for a decision.
