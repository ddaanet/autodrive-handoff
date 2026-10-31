"""The advisory lock around the sentinel, `.claude/autodrive.lock`.

The sentinel is read, judged and rewritten or removed by several actors that
nothing serialises: the checkpoint and `handoff-approved` write it, the mod's
`drive-take.sh` takes it at a turn's end and the prompt-time sweep (`report-
drive-failure.sh`) discards it. Each holds this lock across its own read-decide-
write, so the decision it made and the write it makes are one step.

`flock(2)` through `fcntl`, which Linux and macOS share (`flock(1)` is not on
macOS). The lock file is never deleted: removing it would let a second actor
lock a new inode while the first still holds the old one.

Two ways in. Python (`checkpoint.py`) uses `locked`, which raises when the lock
is not taken. Bash holds a lock across several steps through two calls of this
file's command line, because a lock lives on an open file description and a
child shares the description of a file descriptor its parent opened: bash opens
fd 9 on the lock file, `wait` takes the lock on it, and the lock then lasts
until the shell closes fd 9 or exits (`handoff_lock_take` in _lib.sh, which
holds the sequence).

Bounds. The wait is bounded (`HANDOFF_LOCK_WAIT_SECS`, default 5 seconds), and a
lock that cannot be taken fails closed: the caller does not act on the sentinel,
because acting unlocked reopens the race the lock closes. Two causes are told
apart. `LockBusyError` (bash: rc 75) is the bound passing with another actor
still holding it; `LockUnavailableError` (bash: any other failure) is a lock
that could not be set up at all: no `.claude/`, a link or a non-file at the
name, a file system with no `flock`, a failing helper. A link at the lock file
is never followed (`O_NOFOLLOW`, and a check of the open descriptor against the
path), so a link there is unavailable, not no lock; the lock file is created
0600. A link put at the name between the two bash calls is the residual: `wait`
compares the descriptor with the path and refuses on a mismatch, but bash has
already opened what the link named, read-write.

`HANDOFF_LOCK_BLOCKED_FILE`, when set, names a file touched as soon as a wait
finds the lock held. It exists for the tests (see `_signal_blocked`); nothing
sets it in use.
"""

from __future__ import annotations

import contextlib
import fcntl
import os
import stat
import sys
import time
from collections.abc import Iterator


class LockError(Exception):
    """The lock was not taken."""


class LockBusyError(LockError):
    """The bound passed with another actor still holding the lock."""

    def __init__(self) -> None:
        super().__init__("held elsewhere past the wait")


class LockUnavailableError(LockError):
    """The lock could not be set up at all (the reason is the message)."""

    def __init__(self, what: str, reason: OSError | str) -> None:
        text = reason.strerror if isinstance(reason, OSError) else reason
        super().__init__(f"{what}: {text or reason}")


@contextlib.contextmanager
def locked(lock_path: str | os.PathLike[str]) -> Iterator[None]:
    """Hold the lock for the body.

    Raises `LockBusyError` when the bound passes with the lock held elsewhere
    and `LockUnavailableError` when it cannot be set up (a link or a non-file at
    the name, an unwritable directory, no `.claude/`, no `flock`). Either is
    raised on entry, so the body never runs unlocked.
    """
    fd = _create(os.fspath(lock_path))
    try:
        _flock_within_bound(fd)
    except LockError:
        os.close(fd)
        raise
    try:
        yield
    finally:
        os.close(fd)  # closing the descriptor releases the lock


def main(argv: list[str]) -> int:
    """Run the `create` or `wait` command; any other use is rc 64."""
    if len(argv) == 3 and argv[1] == "create":
        return _command_create(argv[2])
    if len(argv) == 4 and argv[1] == "wait":
        return _command_wait(argv[2], argv[3])
    print(
        "usage: _drive_lock.py create <lockfile> | wait <fd> <lockfile>",
        file=sys.stderr,
    )
    return EXIT_USAGE


def _command_create(path: str) -> int:
    """`create <lockfile>`: make sure a regular lock file is there."""
    try:
        os.close(_create(path))
    except LockUnavailableError as e:
        print(e, file=sys.stderr)
        return EXIT_UNAVAILABLE
    return 0


def _command_wait(fd_text: str, path: str) -> int:
    """Lock the descriptor the parent opened (`wait <fd> <lockfile>`).

    Refused as unavailable when the descriptor is not the regular file the path
    now names (a link, or another file swapped in), so bash's open cannot have
    been led elsewhere unnoticed. rc 0 held, `EXIT_BUSY` for the bound passing.
    """
    try:
        fd = int(fd_text)
        held = os.fstat(fd)
        named = os.lstat(path)
    except (ValueError, OSError):
        return EXIT_UNAVAILABLE
    if not stat.S_ISREG(held.st_mode) or not stat.S_ISREG(named.st_mode):
        return EXIT_UNAVAILABLE
    if (held.st_dev, held.st_ino) != (named.st_dev, named.st_ino):
        return EXIT_UNAVAILABLE
    try:
        _flock_within_bound(fd)
    except LockBusyError:
        return EXIT_BUSY
    except LockUnavailableError as e:
        print(e, file=sys.stderr)
        return EXIT_UNAVAILABLE
    return 0


def _create(path: str) -> int:
    """Open (creating, 0600) the lock file without following a link."""
    flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as e:
        raise LockUnavailableError(path, e) from e
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise LockUnavailableError(path, "not a regular file")
    return fd


def _flock_within_bound(fd: int) -> None:
    """Lock fd, polling until the bound.

    Raises `LockBusyError` when it passes and `LockUnavailableError` when the
    file system refuses the lock.
    """
    deadline = time.monotonic() + _wait_secs()
    delay = 0.005
    signalled = False
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as e:
            if not signalled:
                _signal_blocked()
                signalled = True
            if time.monotonic() >= deadline:
                raise LockBusyError from e
            time.sleep(delay)
            delay = min(delay * 2, 0.1)
        except OSError as e:
            # a file system with no flock, say
            raise LockUnavailableError("flock", e) from e
        else:
            return


def _signal_blocked() -> None:
    """Write a byte to the file `HANDOFF_LOCK_BLOCKED_FILE` names, if it is set.

    A readiness signal for the tests and nothing else: it says that this
    process has found the lock held and is now waiting for it. The tests make
    the name a FIFO they block on, so nothing polls. Opened non-blocking, so a
    FIFO with no reader is no hang (the open fails and is ignored). A test cannot
    tell from outside that an actor is waiting, and a fixed sleep passes with
    the lock removed whenever the actor starts late.
    """
    path = os.environ.get(BLOCKED_ENV)
    if path:
        flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NONBLOCK
        with contextlib.suppress(OSError):
            fd = os.open(path, flags, 0o600)
            try:
                os.write(fd, b"b")
            finally:
                os.close(fd)


def _wait_secs() -> float:
    try:
        return max(float(os.environ[WAIT_ENV]), 0.0)
    except (KeyError, ValueError):
        return DEFAULT_WAIT_SECS


WAIT_ENV = "HANDOFF_LOCK_WAIT_SECS"
BLOCKED_ENV = "HANDOFF_LOCK_BLOCKED_FILE"
DEFAULT_WAIT_SECS = 5.0

# `wait`'s exit codes: 0 held, 75 (EX_TEMPFAIL) the bound passed with the lock
# held elsewhere, anything else — 2 here, 127 for no python3, 1 for a crash —
# unavailable. Busy has a code of its own that a crash cannot produce.
EXIT_BUSY = 75
EXIT_UNAVAILABLE = 2
EXIT_USAGE = 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
