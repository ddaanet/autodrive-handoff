# Directory lock: red phase report (2026-11-12)

Only files under `tests/` changed. Run against the unchanged scripts: pytest 25 failed / 359 passed; the bats lock files (sentinel-lock, drive-take, bin-commands, drive-cancel) fail on every ordering and contention row and pass on the `unavailable` rows.

## Files changed

tests/test_drive_lock.py, tests/lock_holder.py (docstrings only), tests/lock-helpers.bash, tests/sentinel-lock.bats, tests/drive-take.bats, tests/bin-commands.bats, tests/test_checkpoint_readback.py, tests/test_checkpoint_root_files.py. tests/drive-cancel.bats needed no edit: it uses `hold_drive_lock`, now locking `$root/.claude`.

## Names the green implementer must provide

- bash, `_lib.sh`: `HANDOFF_REL_DRIVE_LOCK_DIR=".claude"`; the old `HANDOFF_REL_DRIVE_LOCK` is gone. `handoff_lock_take "<dir>"` keeps its signature and the callers pass `"$root/$HANDOFF_REL_DRIVE_LOCK_DIR"`. Return 0 held, 1 busy, 2 unavailable, `HANDOFF_LOCK_MSG` as today.
- Python, `checkpoint.py`: `HANDOFF_REL_DRIVE_LOCK_DIR = ".claude"`, equal to the bash value.
- `_drive_lock.py`: `locked(directory)` opens the directory read-only with no `O_NOFOLLOW` (a link to a directory is followed). It raises `LockUnavailableError` for an absent path, a regular file, or a dangling link or link to a file. It creates nothing. `wait <fd> <path>` returns `EXIT_UNAVAILABLE` unless fd and the path (resolved through links, so `stat`, not `lstat`) are both directories with the same device and inode. `create` and `_create` are removed: `create` gives a usage error, `EXIT_USAGE` (64), and creates nothing. Existing `EXIT_*`, `WAIT_ENV`, `BLOCKED_ENV` and `DEFAULT_WAIT_SECS` are used by the tests as before.
- `handoff_lock_take` must test `[[ -d "$lock" ]]` before opening. It must open with a plain read-only `exec 9<"$lock"` on the directory, and a FIFO, file or absent name returns 2 without blocking.
- `checkpoint.py` still `mkdir`s `.claude` before locking.

## pytest rows (red = fails against unchanged code)

tests/test_drive_lock.py
- `test_locked_holds_the_lock_for_the_body_on_the_directory`: RED, `LockUnavailableError` (O_RDWR|O_CREAT on a directory).
- `test_locked_leaves_no_new_entry_in_the_directory`: RED, same exception on entry (the entry-list assertion is not reached).
- `test_locked_waits_for_another_holder...`, `test_locked_raises_busy...`: RED, the holder cannot lock a directory, so `lock_holder.py` fails and `readline() == "held"` is an assertion error.
- `test_locked_follows_a_link_to_a_directory_and_locks_the_target`: RED, same holder failure.
- `test_locked_is_unavailable_for_what_is_not_a_directory[absent|file]`: RED (old code creates a lock file or locks the file, so no exception). The `dangling_link` and `link_to_file` variants stay green, since the old code also refuses links.
- `test_wait_locks_a_directory_descriptor_named_through_a_link`: RED, rc is 2 where 0 is wanted.
- `test_wait_refuses_a_regular_file`: RED, rc is 0 where 2 is wanted.
- `test_wait_refuses_a_descriptor_that_is_not_what_the_path_names`: green now, for the wrong reason (the old code refuses non-regular files). It reds the "skip the device/inode comparison" mutant once the implementation accepts directories.
- `test_the_create_command_is_gone`: RED, rc 0 and the file is created.
- `test_bash_take_holds_the_lock_until_the_shell_exits`, `test_bash_take_leaves_no_new_entry_in_the_directory`, `test_bash_take_follows_a_link_to_a_directory`, `test_bash_take_is_busy_after_the_bound_and_says_so`: RED (rc 2 where 0 or 1 is wanted).
- `test_bash_take_is_unavailable_without_a_directory_and_never_blocks[absent|file]`: RED (rc 0, the old code creates or opens a file there). The `fifo`, `dangling_link` and `link_to_file` variants are green (the old code returns 2 as well). The run has a 30 s subprocess timeout, not a wait, so a FIFO hang fails the row.
- `test_bash_take_is_unavailable_when_the_helper_fails`: green (stub `python3` exits 1; also asserts the directory is left empty).
- `test_the_python_constant_mirrors_the_bash_one`: RED (empty bash variable, missing attribute). It pins both names and the value `.claude`.
- The three blocked-file rows, over a directory: RED.
- The PROBE now opens read-only, as a directory requires.

tests/test_checkpoint_readback.py (the lock is `repo/.claude`; `_tree` no longer excludes `autodrive.lock`)
- `test_sentinel_write_waits_on_the_lock`, `test_an_edit_is_planned_after_the_wait_not_before_it`, `test_a_lock_held_past_the_wait_fails_closed_and_writes_nothing`: RED (holder cannot lock a directory).
- `test_a_lock_that_cannot_be_set_up_fails_closed_and_writes_nothing`: refused `flock` seam, a wrapper script passed through `run_checkpoint(command=...)` that replaces `fcntl.flock` with a raiser of ENOLCK and runs checkpoint.py via `runpy`. RED only on the last assertion, `.claude` must hold no entry: the old code leaves `autodrive.lock`. The returncode, stderr and `_tree` assertions pass on unchanged code. The expected message is `lock: ... could not be set up`, not `busy`.

tests/test_checkpoint_root_files.py: `test_a_dangling_symlinked_sentinel_creates_nothing_through_it` now expects `.claude` to hold only `autodrive`. RED (the old code also leaves `autodrive.lock`).

## bats rows

`tests/lock-helpers.bash`: `hold_drive_lock` runs the holder on `$root/.claude`. Every ordering and contention row (sentinel-lock, drive-take, bin-commands, drive-cancel: 20 rows) is RED through `[ "$line" = held ]` in `hold_drive_lock`, since the holder cannot lock a directory today.

The link-at-lock rows (report-drive-failure, load-handoff, load-compact, drive-take, handoff-approved) are replaced by `unavailable` rows named "the lock helper fails". They are green against the unchanged code, which has the same outcome through a different cause.

Seam chosen for the bash `unavailable` rows: the new helper `fail_lock_helper` in tests/lock-helpers.bash puts a `python3` shim first on PATH. It exits 1 when its arguments mention `_drive_lock.py` and `exec`s the real interpreter otherwise. Why: a bash actor locks only with a sentinel on disk, so `.claude` is a real directory and a bad name cannot occur. A failing `python3` for everything would trip the sentinel reader before the lock call and test a different path. The shim fails only the lock's helper, so the actor reaches the lock call and reports the lock message. A FIFO or non-directory at `.claude` is covered at `handoff_lock_take` level in tests/test_drive_lock.py, not through the actors.

## Not pinned

- Mutant "`wait` skipping the device/inode comparison" is caught only by the swapped-directory row, which is green now and pins nothing until the implementation accepts directories.
- Mutant "`locked()` opening `<dir>/autodrive.lock`" reds the two no-new-entry rows and the root-files row. Mutant "`handoff_lock_take` dropping the directory test" reds the absent and file rows, and a FIFO would hang the FIFO row until its 30 s timeout.
- A symlinked `.claude` through `checkpoint.py` is not tested at the actor level, only through `locked()` and `handoff_lock_take`.
- The full `bats tests/*.bats` run was not re-read end to end. I ran the four lock files only; no other bats file takes the lock.
