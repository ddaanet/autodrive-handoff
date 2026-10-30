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
share). The checkpoint holds it over its whole read-plan-write: the read of
`TASK.md` and `TODO.md` that resolves each half, the application of the plans and
the sentinel's write and read-back,
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

Bounds. The wait is bounded (`HANDOFF_LOCK_WAIT_SECS`, 5 s by default), and a
lock that cannot be taken **fails closed**: the actor does not act on the
sentinel, because acting unlocked reopens the very race the lock closes, and a
hook that waits for ever is worse than a refused one. Two causes are told
apart, in the code (`LockBusyError` and `LockUnavailableError`; `handoff_lock_take`
returns 1 and 2) and in what the user reads. *Busy*: the wait passed with
another actor still holding the lock. *Unavailable*: it could not be set up at
all (no `.claude/`, a link or a non-file at the name, a failing `python3` or
helper, a file system with no `flock`). Both fail closed, so a link planted at
the lock's name or a file system with no `flock` stops every actor until it is
fixed, and says why each time; that is chosen over running unlocked there,
because the sentinel's other readers stop on a failing `python3` anyway and a
second, silent mode that runs without the lock is the fail-open that reopens
the race.

What each actor does when it does not get the lock, with the sentinel left
exactly as it was in every case:

- `checkpoint.py` exits 2 through `lib.err` (`lock: …`, naming the lock and the
  cause) before it writes anything. It takes the lock before `TASK.md` and
  `TODO.md` are read to be planned, not only around the sentinel, so an `edit`
  that waited resolves against the body it finds once it has the lock, never
  against one read before the wait, and a refused call leaves all three
  untouched and the same call can be made again (an `edit` could not be, once
  applied). What stays outside the lock is what reads only the payload or the
  environment (validation, `HANDOFF_ROOT`, `CLAUDE_CODE_SESSION_ID`), the memory
  directive's read of the gitlore submodule, which no actor of the sentinel
  writes, and `check_sentinel_target`, which has to refuse a `.claude` that is a
  file before the lock's own `mkdir` meets it. The only thing a refused call may
  leave is an empty `.claude/`. The lock does not guard `TODO.md` against direct
  edits: the agent's Edit tool takes no lock, and concurrent sessions in one
  root stay a non-goal (`CLAUDE.md`, "Non-goals").
- `handoff-approved` exits 2 naming the lock; the held file stays held.
- `drive-take.sh` takes nothing and prints a `kind: null` plan whose message
  names the lock (`tests/mod/fixtures/lock-busy.json`, `failFile` empty as for
  an unread sentinel); the mod toasts it and runs nothing, and the file stays
  `armed` for the next prompt's sweep.
- The sweep judges nothing: the file is neither read nor removed, no line is
  offered, and both channels say it was not judged because of the lock
  (`autodrive not judged — …; left in place`). A `.claude/autodrive.failed`
  record is left too, since its report and the clearing of a stranded `pending`
  belong together; the next prompt reads both.
- `load-handoff.sh` and `load-compact.sh` do not read or consume the sentinel,
  and still assemble and inject the frame, with a note on both channels that
  the transition state was left in place. `load-compact.sh` cannot tell then
  whether a compaction was pending, and a frame missing from a driven
  compaction is the costlier error than a todo re-injected after an
  auto-compaction while a sentinel is on disk.

The hook budgets in `hooks/hooks.json` cover the wait: the three lock-taking
hooks have a `timeout` of 10 s, the default wait plus 5 s for the hook's own
work, which `tests/test_drive_lock.py` asserts against the default read from
`_drive_lock.py`. The mod's `$.process.run` of `drive-take.sh` has the host's
default timeout of 30 s (the mods API's `ProcessRunInit.timeoutMs`), which
already covers the wait and the take.

The lock file is created 0600 and never followed through a link
(`O_NOFOLLOW`); a link put there in the instant between the create and bash's
open is the residual: the lock call compares the descriptor with the path and
refuses on a mismatch, but bash has by then opened what the link named,
read-write. The file is never deleted
(removing it would let a second actor lock a new inode) and `.claude/autodrive*`
already ignores it. The loaders take it too: the checkpoint replaces whatever
sentinel is there, `pending` included, so a loader that read `pending` and then
removed it could remove a checkpoint's new file unread. The lock orders the
actors; which outcome wins is still
decided by arrival order. A prompt sent just after the arming turn's `Stop` can
still have the transition run after it, or be swept (tracked in `TODO.md`).
Rows, none of which sleeps or polls. An ordering row holds the lock from a
background process (`tests/lock_holder.py`, which takes it through
`_drive_lock.locked` and says `held` on a pipe), starts the actor, blocks until
the actor reports that it is waiting, changes the sentinel under the lock and
kills the holder. The report is the one test-only seam in the lock: when
`HANDOFF_LOCK_BLOCKED_FILE` names a FIFO the row has open, a wait writes a byte
to it as soon as it finds the lock held (`_signal_blocked`) and the row's
bounded blocking `read` returns. A fixed sleep before the change would let an
actor with no lock call pass by starting late; with the signal such an actor
never reports and the row fails, whatever the speed of the box. Nothing sets
the variable in use. A contention row needs no signal: the holder holds for the
whole run, the actor runs with `HANDOFF_LOCK_WAIT_SECS` of 0.05 so its wait ends
at once, and the row asserts the sentinel byte-identical, the actor's
fail-closed report or exit and, for the loaders, the frame still injected; a
second row per actor puts a link at the lock for the unavailable cause. They are
in `tests/drive-take.bats`, `tests/sentinel-lock.bats`, `tests/bin-commands.bats`
and `tests/test_checkpoint_readback.py`, and `tests/test_drive_lock.py` covers
the lock itself.
[The sentinel takes a lock](../changelog/2026-10-16-the-sentinel-takes-a-lock.md),
[The lock fails closed](../changelog/2026-10-17-the-lock-fails-closed.md)
