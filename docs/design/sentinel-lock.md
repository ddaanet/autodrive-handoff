# The sentinel's lock

Part of [handoff — Design](../design.md). The sentinel's states and the
actors that move it are in [Driving the transition](driving-the-transition.md).

The sentinel has five actors that nothing orders: the checkpoint and
`handoff-approved` write it, `drive-take.sh` takes it at a turn's end, the
prompt-time sweep discards it, and the two `SessionStart` loaders consume
`pending`. The host does not serialise a new prompt's
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
to its exit, the sweep from its read to its exit, so `record_sweep` and the
failure branch's removal of a stranded `pending` are inside it, and each loader
from its read of `pending` to its removal of it, letting go before it assembles
the frame. Python takes
it with a context manager. Bash holds it across many steps because a lock lives
on an open file description a child shares with its parent's descriptor: the
shell opens fd 9 on the file (`handoff_lock_take` in `_lib.sh`), a child takes
the lock on it, and the shell keeps it until it exits or closes fd 9 (the loaders close it once the
sentinel is consumed). The sweep, the take and
the loaders lock only when a sentinel is on disk, so an ordinary prompt forks
nothing, and the file is created by a first spawn only when it is not there
yet.

Bounds. The wait is bounded (`HANDOFF_LOCK_WAIT_SECS`, 5 s by default) and a
lock that cannot be taken, for any reason, is gone without: the actor behaves
as it did before the lock, because a hook that waits for ever is worse than the
race. The lock file is created 0600 and never followed through a link
(`O_NOFOLLOW`); a link at the name means no lock. A link put there in the
instant between the create and bash's open is the residual: the lock call
compares the descriptor with the path and refuses on a mismatch, but bash has
by then opened what the link named, read-write. The file is never deleted
(removing it would let a second actor lock a new inode) and `.claude/autodrive*`
already ignores it. The loaders take it too: the checkpoint replaces whatever
sentinel is there, `pending` included, so a loader that read `pending` and then
removed it could remove a checkpoint's new file unread. The lock orders the
actors; which outcome wins is still
decided by arrival order. A prompt sent just after the arming turn's `Stop` can
still have the transition run after it, or be swept (tracked in `TODO.md`).
Rows: each actor's own test file holds the lock from a background process
(`tests/lock_holder.py`, which takes it through `_drive_lock.locked`), starts
the actor, waits until the actor reports that it is blocked, changes the
sentinel under the lock and releases (`tests/drive-take.bats`,
`tests/hook-test.bats`, `tests/checkpoint.bats`,
`tests/test_checkpoint_hold.py`), and `tests/test_drive_lock.py` covers the
lock itself. The report is the one test-only seam in the lock: when
`HANDOFF_LOCK_BLOCKED_FILE` names a file, a wait touches it as soon as it finds
the lock held (`_signal_blocked`). A fixed sleep before the change would let an
actor with no lock call pass by starting late; with the signal such an actor
never reports and the row fails, whatever the speed of the box. Nothing sets the
variable in use.
[The sentinel takes a lock](../changelog/2026-10-16-the-sentinel-takes-a-lock.md)

