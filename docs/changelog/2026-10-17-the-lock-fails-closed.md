# 2026-10-17 — The lock fails closed

A Codex review of the branch found that every caller of the sentinel's lock
went ahead without it when it could not be taken within the wait (`|| true`,
and `locked` yielding `False`). That reopens the race the lock closes, in the
exact case where another actor is mid-step on the sentinel, so the lock is
now a gate, not a courtesy. My human partner decided the policy below.

## Decision

A lock that is not taken means the actor does not act on the sentinel:

- `checkpoint.py` exits 2 (`lock: …`) before writing anything. It now takes
  the lock ahead of `TASK.md` and `TODO.md`, not only around the sentinel, so
  a refused call leaves all three as they were and can be repeated (an `edit`
  cannot be, once applied). Other sentinel-write failures still leave the frame
  files written, as before.
- `handoff-approved` exits 2 naming the lock; the held file stays held.
- `drive-take.sh` takes nothing and prints a `kind: null` plan naming the lock
  (`lock-busy.json`); the file stays `armed` for the next sweep.
- The sweep judges nothing, reports on both channels that it was not judged,
  and leaves a `.claude/autodrive.failed` record for the next prompt, since the
  record's report and the clearing of a stranded `pending` go together.
- `load-handoff.sh` and `load-compact.sh` do not read or consume the
  sentinel, still inject the frame, and note on both channels that the
  transition state was left. `load-compact.sh` cannot tell whether a
  compaction was pending, and injects: a frame missing from a driven compaction
  costs more than a todo re-injected after an auto-compaction.

Busy past the wait and unable to set up (no `.claude/`, a link at the lock, a
failing `python3`, no `flock`) are told apart in the code (`LockBusyError` /
`LockUnavailableError`, `handoff_lock_take` rc 1 / 2, `wait` exit 75 for busy) and in
the message, and both fail closed. The cost is that a link planted at the lock's
name, or a file system with no `flock`, stops every actor until fixed, where it
used to run unlocked; the message says why each time.

The wait stays 5 s. The hook budgets rise to cover it: `report-drive-failure.sh`
and `load-handoff.sh` from 5 to 10, `load-compact.sh` stays at 10, each the
default wait plus at least 5 s, asserted against the default read from
`_drive_lock.py`. The mod's `$.process.run` for `drive-take.sh` has the host's
default 30 s timeout, which covers the wait and the take, so it is unchanged.

## Tests

Each actor has a contention row (lock held for the whole run, wait 0.05 s,
sentinel byte-identical, fail-closed report, frame injected for the loaders) and
a link-at-the-lock row. The lock tests no longer sleep or poll: the holder waits
for a signal and is killed, the holder's readiness and the waiters' "blocked"
report travel over FIFOs read with a bounded blocking `read`/`select`, and the
one timed row (`locked` waits for a holder) releases it on the report instead.

Supersedes the "fails open" bound of
[The sentinel takes a lock](2026-10-16-the-sentinel-takes-a-lock.md).
