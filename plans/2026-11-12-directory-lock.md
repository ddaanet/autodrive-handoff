# The sentinel's lock moves onto `.claude/` itself

2026-11-12. Implementation plan, approved in session by my human partner.

## Problem

Every root where a checkpoint runs gets a `.claude/autodrive.lock` that is
never deleted. Of the 14 repositories under `~/code` that have one, 12 do not
ignore it, so it shows as untracked there. The file is kept on purpose:
removing it would let a second actor lock a new inode while the first still
holds the old one.

## Decision

The advisory lock is taken on the directory that holds the sentinel,
`.claude/`, and no lock file exists. A probe on Linux (2026-11-12): bash opens
fd 9 on the directory, a `python3` child takes `flock` on it, a second locker
is refused while the shell holds fd 9, and the lock is free once fd 9 closes.
macOS is not probed; `flock(2)` there takes any descriptor, and a root where
it does not fails closed as `unavailable`, as today.

Rejected: deleting the file with the sentinel (every acquirer re-checks the
inode after locking and retries, and the file still shows while a sentinel is
armed); a lock outside the tree (the checkpoint runs in the command sandbox
and the hooks do not, so they share no writable location but the root).

> **Corrected at review, 2026-11-12.** "a lock outside the tree (the
> checkpoint runs in the command sandbox and the hooks do not, so they share
> no writable location but the root)" was wrong: `/tmp/claude` is writable
> from the command sandbox and the hooks already write their markers there
> (`HANDOFF_POINTER_DIR` in `scripts/_lib.sh`). What still stands is the
> rejection, on another ground: such a lock leaves one file per root in that
> directory, named by a mapping from the root every actor must share.

## Contract

1. **What is locked.** Each of the lock's actors takes `flock` on the
   directory `.claude/` of its root. A `.claude` that is a link to a directory
   is followed, as the sentinel's own writes follow it, so every actor locks
   the same inode. Nothing creates, opens or names `.claude/autodrive.lock`.
2. **Setup.** The checkpoint still creates `.claude/` before taking the lock.
   The bash actors create nothing: they lock only when a sentinel is on disk,
   so the directory is there. `_drive_lock.py`'s `create` command and
   `_create` go; `handoff_lock_take` is one spawn every time.
3. **Unavailable.** A `.claude` that is absent or not a directory, a failing
   `python3` or helper, and a file system with no `flock` are `unavailable`.
   Bash must not open a non-directory at the name (a FIFO there would block
   the redirection): it tests for a directory first. `wait` keeps its check
   that fd 9 is what the path names now, comparing device and inode, with the
   path resolved through a link.
4. **Unchanged.** The busy/unavailable split, the exit codes, the bound, the
   fail-closed behaviour of every actor, `HANDOFF_LOCK_MSG`, the
   `HANDOFF_LOCK_BLOCKED_FILE` seam, the hook timeouts, and which span each
   actor holds the lock across.
5. **Names.** One constant per language names the lock's path, and its name
   says it is a directory; every in-repo caller is patched, with no alias.
   User-facing messages that named `.claude/autodrive.lock` name `.claude/`.
6. **Old files.** The plugin does not remove an `autodrive.lock` an earlier
   version left. The release note says it is safe to delete.

## Tests

- Every existing lock row keeps its assertion with the lock taken on the
  directory: ordering, contention, fail-closed reports, the loaders' frame.
- New, in `tests/test_drive_lock.py`: after `locked()` on a directory and
  after a bash `handoff_lock_take`, the directory holds no new entry; a
  `.claude` that is a link to a directory locks the target (a holder through
  the real path blocks a taker through the link).
- The rows that planted a link at the lock file's name are replaced, per
  actor, by an `unavailable` row with a cause that can still occur. For the
  bash actors, which lock only with a sentinel on disk, that is a failing
  helper or `python3`; the red author picks the seam and states it in the
  report. For `checkpoint.py` it is a refused `flock`.
- A row over the whole suite's fixtures or a grep-style assertion is not
  wanted for "no lock file": the two new rows above pin it.
- Mutants to record in the commit body: `locked()` opening
  `<dir>/autodrive.lock` again (reds the no-new-entry row); `wait` skipping the
  device/inode comparison; `handoff_lock_take` dropping the directory test.

## Prose to rewrite in the same commit

`docs/design/sentinel-lock.md` (the lock's object, setup, the link residual,
"never deleted", the unavailable causes, the row descriptions),
`docs/design/driving-the-transition.md:226`, the README's file table row,
`.claude/rules/tests.md` if a row description changes, the module and
function docstrings in `_drive_lock.py`, `_lib.sh`, `checkpoint.py` and
`tests/lock_holder.py`, and a line in `docs/design/rejected-alternatives.md`
with its hub index entry for the two rejected options. `.gitignore`'s
`.claude/autodrive*` stays: it still covers the sentinel and its siblings.

## Execution

One commit. Red author (Sonnet) rewrites the tests; a second agent reviews
that the red is genuine; green (Haiku) changes `_drive_lock.py`, `_lib.sh`,
`checkpoint.py` and the call sites; a Sonnet agent rewrites the prose; then
`just precommit`, the commit, and a delegated `/code-review medium`.
