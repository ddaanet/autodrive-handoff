# An unresolved root is reported

2026-10-13.

## The defect

`handoff_root_read` read the resolver's answer from a process substitution,
whose exit status bash 3.2 cannot reach. When `worktree_root.py` crashed (any
cwd off the fast path: a worktree, a subdirectory, a drifted cwd), both reads
hit end of file, the function returned 1, and every caller under `set -e`
exited 1 with nothing on stdout. For `PreToolUse` a non-zero exit other than 2
is non-blocking, so the write guard let a write to the sentinel through; the
loaders, the prompt-time hook, `inject-checkpoint-root.sh` and `drive-take.sh`
each did nothing and said nothing.

## The decision

Judge the answer, since the status is out of reach: a branch label other than
the four the resolver has, or an empty root, is `unresolved`. The function
returns 0 with an empty root, so a caller under `set -e` reaches its own report
instead of dying, and each caller reports on its own channel, in one wording
(`HANDOFF_UNRESOLVED_MSG`):

- `write-guard.sh` denies a write whose path names `autodrive`. Fail closed:
  it can no longer tell this project's sentinel from another's, and the path
  already matched the name. Every other write still leaves at the substring
  test, before the resolver runs.
- `load-handoff.sh` says on both channels that no frame was loaded;
  `load-compact.sh` says a pending compaction was not checked, breaking its
  silence because whether one was pending is what cannot be known.
- `report-drive-failure.sh` says on both channels that its three checks were
  skipped. It says so every prompt while the resolver stays broken, which is
  the point.
- `inject-checkpoint-root.sh` leaves the command unrewritten and says why in a
  `systemMessage`; the checkpoint and `handoff-approved` already refuse an
  unset `HANDOFF_ROOT` naming it.
- `drive-take.sh` prints a plan with `kind: null`, no lines and the message,
  the malformed file's shape, so the mod toasts it.

## Rows

Each with a `python3` stub that exits 97 and a cwd off the fast path, red
before the change on the exit status (1): `handoff_root_read` itself,
`write-guard.sh` on the sentinel, both loaders, the prompt-time hook,
`drive-take.sh` (sentinel left `armed`) and `inject-checkpoint-root.sh`
(`tests/checkpoint.bats`). A write not naming the sentinel stays silent under
the same stub. Mutations: dropping the guard's branch reds its row; dropping
the `unresolved` label reds the five rows in `tests/hook-test.bats` that
expect it.
