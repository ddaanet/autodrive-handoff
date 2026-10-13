# No root passes through a capture

2026-10-13.

## The defect

The NUL-delimited reads of the hook input and of the resolver's answer kept a
path holding a newline whole as far as `handoff_root_read`, and four places
past it still cut one:

- `handoff_root` printed the root with a trailing newline for callers to take
  through `$(...)`, and a command substitution strips every trailing newline,
  so a root *ending* in one came back naming a sibling directory.
  `load-handoff.sh`, `load-compact.sh`, `write-guard.sh`,
  `inject-checkpoint-root.sh` and `drive-take.sh` all took it that way: a
  worktree whose path ends in a newline had its frame unread, its pending
  compact left unconsumed, its sentinel denied as another project's, its armed
  transition untaken and a sibling exported as `HANDOFF_ROOT`.
- `load-compact.sh` and `inject-checkpoint-root.sh` read `.cwd` through
  `$(jq -r …)`, the same loss one step earlier.
- The drift marker in `report-drive-failure.sh` was written with
  `printf '%s\n'` and compared through `head -n1`, so a foreign cwd holding a
  newline never matched its own marker and drift was announced on every prompt.
- `_read_gitdir` in `worktree_root.py` read a worktree's `.git` file line by
  line and stripped the path, so a project whose path holds a newline (git
  links such a worktree: `gitdir: /…/pr<LF>oj /.git/worktrees/wt2`, probed with
  git 2.47) could not be linked, and the worktree read as foreign.

## The change

- `handoff_root` is gone; every caller calls `handoff_root_read` and reads
  `HANDOFF_ROOT`, so the root never passes through stdout.
- Both `jq -r` reads become one `jq -j … "\u0000"` pass read with
  `read -r -d ''`; in `inject-checkpoint-root.sh` the command and the cwd now
  share that one parse.
- The drift marker holds the cwd NUL-terminated and is read back whole.
- `_read_gitdir` reads the file as git's `read_gitfile_gently` does: it must
  begin with `gitdir: `, and the path is everything after that prefix with
  trailing CR and LF stripped. A `gitdir:` line that is not first no longer
  links, since git does not accept it either. A path *ending* in a newline
  cannot be represented in that file at all, by git or here, so the worktree
  name ending in one is the case rows exercise, not the gitdir.

## Rows

Red before the change on an assertion each: a worktree whose path ends in a
newline through `load-handoff.sh` (frame not injected), `load-compact.sh`
(sentinel not consumed), `write-guard.sh` (cross-project message instead of
checkpoint-only), `drive-take.sh` (empty plan) and `inject-checkpoint-root.sh`
(`HANDOFF_ROOT` lost its newline); drift to a cwd holding a newline and to one
ending in one (reported again on the second prompt); a project path holding a
newline and a space linking its worktree, and a late `gitdir:` line not
linking (`tests/test_worktree_root.py`). The `handoff_root` rows now pin
`handoff_root_read`, plus a root ending in a newline surviving with nothing
printed. Mutation: putting back `$(jq -r)` for `load-compact.sh`'s cwd alone
reds its row. In `inject-checkpoint-root.sh` the cwd read alone is not
load-bearing for the row (a cwd stripped of its newline still resolves to the
project); the capture of the root was.
