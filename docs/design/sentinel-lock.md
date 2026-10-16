# The sentinel's lock

Part of [handoff — Design](../design.md). The sentinel's states and the
actors that move it are in [Driving the transition](driving-the-transition.md).

The sentinel has four actors that nothing orders: the checkpoint and
`handoff-approved` write it, `drive-take.sh` takes it at a turn's end, and the
prompt-time sweep discards it. The host does not serialise a new prompt's
`UserPromptSubmit` hook against the mod's `turn.complete` handler, which runs
the take (observed: [the queued-prompt
report](../../plans/reports/2026-10-16-queued-prompt-with-clear-compact.md),
variant 2, the next turn starting while the take runs). The sweep read `armed`
once and later removed the file with no second look, so this interleaving was
possible: the sweep reads `armed`, the take rewrites it to `pending` and hands
the plan to the mod, the sweep deletes the `pending` file. The transition then
runs anyway, and the user is told the mod did not run it and is offered the
lines, so may type `/clear` twice. Either clean order is consistent; only the
interleaving is wrong.

Each actor holds an advisory lock, `.claude/autodrive.lock`, across its own
read-decide-write, so the decision and the write are one step
(`scripts/_drive_lock.py`, `flock(2)` through `fcntl`, which Linux and macOS
share). The checkpoint holds it over the sentinel's write and read-back,
`handoff-approved` from its read to its rewrite, `drive-take.sh` from its read
to its exit, and the sweep from its read to its exit, so `record_sweep` and the
failure branch's removal of a stranded `pending` are inside it. Python takes
it with a context manager. Bash holds it across many steps because a lock lives
on an open file description a child shares with its parent's descriptor: the
shell opens fd 9 on the file (`handoff_lock_take` in `_lib.sh`), a child takes
the lock on it, and the shell keeps it until it exits. The sweep and the take
lock only when a sentinel is on disk, so an ordinary prompt forks nothing.

Bounds. The wait is bounded (`HANDOFF_LOCK_WAIT_SECS`, 5 s by default) and a
lock that cannot be taken, for any reason, is gone without: the actor behaves
as it did before the lock, because a hook that waits for ever is worse than the
race. The lock file is created 0600 and never followed through a link
(`O_NOFOLLOW`); a link at the name means no lock. A link put there in the
instant between the create and bash's open is the residual: the lock call
compares the descriptor with the path and refuses on a mismatch, but bash has
by then opened what the link named, read-write. The file is never deleted
(removing it would let a second actor lock a new inode) and `.claude/autodrive*`
already ignores it. The loaders do not take it: they consume `pending`, which
no actor rewrites. The lock orders the actors; which outcome wins is still
decided by arrival order. A prompt sent just after the arming turn's `Stop` can
still have the transition run after it, or be swept (tracked in `TODO.md`).
Rows: each actor's own test file holds the lock from a background process,
starts, changes the sentinel under it and releases (`tests/drive-take.bats`,
`tests/hook-test.bats`, `tests/checkpoint.bats`,
`tests/test_checkpoint_hold.py`), and `tests/test_drive_lock.py` covers the
lock itself.
[The sentinel takes a lock](../changelog/2026-10-16-the-sentinel-takes-a-lock.md)

