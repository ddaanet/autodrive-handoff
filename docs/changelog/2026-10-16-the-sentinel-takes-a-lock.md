# 2026-10-16 — The sentinel takes a lock

A review of the queued-prompt change found a race between the prompt-time sweep
and the mod's take that neither clean order explains, and fixed it with an
advisory lock. The same review folded two smaller corrections to the queued
prompt's note and one shared marker reader.

## The defect

`report-drive-failure.sh` read the sentinel once and later ran a bare `rm -f`
with no second look (the queued cancel and the stale sweep). `drive-take.sh`,
at the turn's end, takes an `armed` file by rewriting it to `pending` or, for
`rename`, removing it. The host does not order a new prompt's
`UserPromptSubmit` hook against the mod's `turn.complete` handler that runs the
take: the queued-prompt report, variant 2, saw the next turn start while the
take ran. So this interleaving was possible: the sweep read `armed`, the take
rewrote it to `pending` and handed the plan to the mod, the sweep deleted the
`pending` file. The transition ran anyway, and the user was told the mod had
not run it and was offered the lines, so could type `/clear` twice. Either
clean order is consistent. The checkpoint's write and `handoff-approved`'s move
out of `held` raced the same way.

## What was decided

**An advisory `flock` on `.claude/autodrive.lock`, held across each actor's
read-decide-write.** The checkpoint holds it over the sentinel's write and
read-back, `handoff-approved` from its read to its rewrite, `drive-take.sh`
from its read to its exit, and the sweep from its read to its exit. The sweep's
`record_sweep` stays inside the lock: it reads the sentinel's mtime, which is
better read under the lock than outside it, and the sweep's whole decision is
then one step. `scripts/_drive_lock.py` is the one implementation, used by
`checkpoint.py` as a context manager and by bash through `handoff_lock_take`.
`flock(1)` is not on macOS, so Python's `fcntl.flock` is the portable form.

**Bash holds the lock by file-descriptor inheritance, not by re-executing.**
The first shape considered was a Python wrapper that takes the lock and
`exec`s the script under it. It needs the script to run twice (the sweep has
read its stdin and the root before it knows what to lock), and a `python3` that
fails to start leaves nothing run at all, where every caller's rule is to go
ahead without the lock. A lock lives on an open file description, which a child
shares with the descriptor its parent opened. So the shell opens fd 9 on the
lock file, a child takes the lock on that descriptor, and the lock stays with
the shell until it exits. A failure at any step is a lock not taken and the
script carries on, as it did before. `handoff_drive_read` stays the one parser.

**Fails open, bounded, never follows a link.** The wait is bounded at 5 s
(`HANDOFF_LOCK_WAIT_SECS`) and then the actor goes ahead unlocked. The file is
created 0600 by a step that opens it with `O_NOFOLLOW`, and the locking step
refuses when fd 9 is not the regular file the path names. It is never deleted.
The sweep and the take take the lock only when a sentinel is on disk, so an
ordinary prompt forks nothing.

## Folded in the same pass

- **The queued-clear note.** The note's "a prompt typed while that turn was
  still running" cause is now also named when the input carries a `prompt_id`
  but the marker could not settle it: its directory fails `marker_dir_ok`, or
  the read is a link, a directory, another user's file or a failed helper. The
  sweep and the lines are unchanged. [A prompt queued into the arming
  turn](2026-10-16-a-prompt-queued-into-the-arming-turn.md) is not edited;
  `docs/design/queued-prompts.md` states the behaviour.
- **`handoff_read_marker`** in `_lib.sh` replaces the marker-read block that
  `report-drive-failure.sh` had twice, for the drift marker and the prompt
  marker.
- The sweep's comment that an `armed` file "has not run, and unless that
  prompt was queued it never will" now says it has not been taken.

## Residual bounds

- The lock orders the actors; which outcome wins is still decided by arrival
  order. A prompt sent just after the arming turn's `Stop` can still have the
  transition run after it, or be swept. It is tracked in `TODO.md` and not
  fixed here.
- A link put at the lock's name in the instant between the creating step and
  bash's open is opened read-write by bash before the locking step refuses it.
- The loaders consume `pending` without the lock: no actor rewrites that
  state.
- `TASK.md` and `TODO.md` are still last-writer-wins, and two sessions in one
  root are still unsupported: the lock orders the actors of one sentinel.
