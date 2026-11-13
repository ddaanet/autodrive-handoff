# Directory lock: green report (2026-11-12)

## Files changed

- `scripts/_drive_lock.py`: `locked()` opens the directory `O_RDONLY|O_DIRECTORY` (`_open_directory`, replaces `_create`); `create` command removed; `wait <fd> <directory>` requires both fd and `os.stat(path)` to be directories with equal dev/ino. Module docstring and `locked` docstring rewritten.
- `scripts/_lib.sh`: constant `HANDOFF_REL_DRIVE_LOCK_DIR=".claude"` (no alias); `handoff_lock_take` does `[[ -d ]] || return 2`, `exec 9<"$lock"`, `wait`; comment block rewritten.
- `scripts/checkpoint.py`: constant `HANDOFF_REL_DRIVE_LOCK_DIR = ".claude"`; both `lock:` messages say `.claude/`; docstring and mirror comment updated.
- Call sites renamed to `$HANDOFF_REL_DRIVE_LOCK_DIR`: `scripts/drive-take.sh`, `scripts/drive-cancel.sh`, `scripts/load-handoff.sh`, `scripts/load-compact.sh`, `scripts/report-drive-failure.sh`, `bin/handoff-approved`. Their comments name only the lock, not a file, so are unchanged.

## Results

- `pytest -q`: 384 passed, 3 deselected, 0 failed.
- `bats tests/*.bats`: 347 ok, 0 not ok.
- `shellcheck` on the changed shell files: info-level SC1091/SC2153 only, in code I did not touch.
- No remaining `autodrive.lock` / `HANDOFF_REL_DRIVE_LOCK` (without `_DIR`) under scripts, bin, hooks, skills.

## Mutants (each reverted afterwards; diff against backup confirmed)

- (a) `locked()` opens `<dir>/autodrive.lock`: 9 red, in `tests/test_drive_lock.py`:
  - `test_locked_holds_the_lock_for_the_body_on_the_directory`
  - `test_locked_leaves_no_new_entry_in_the_directory`
  - `test_locked_follows_a_link_to_a_directory_and_locks_the_target`
  - `test_bash_take_follows_a_link_to_a_directory`
  - `test_bash_take_is_busy_after_the_bound_and_says_so`
  - `test_the_blocked_file_is_written_by_the_bash_wait_too`

  In `tests/test_checkpoint_readback.py`:
  - `test_a_lock_held_past_the_wait_fails_closed_and_writes_nothing`
  - `test_a_lock_that_cannot_be_set_up_fails_closed_and_writes_nothing`

  In `tests/test_checkpoint_root_files.py`:
  - `test_a_dangling_symlinked_sentinel_creates_nothing_through_it`
- (b) `wait` skips the dev/ino comparison: 1 red, `test_drive_lock.py::test_wait_refuses_a_descriptor_that_is_not_what_the_path_names`.
- (c) `handoff_lock_take` without `-d`: 1 red, `test_bash_take_is_unavailable_without_a_directory_and_never_blocks[fifo]` (30 s timeout, as expected).

## Not done

Nothing outside the contract. Mutants were run against the pytest files only (bats not re-run per mutant). Nothing removes an old `autodrive.lock` file, as specified.
