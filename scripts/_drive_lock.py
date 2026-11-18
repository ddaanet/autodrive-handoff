"""The advisory lock around the sentinel, taken on the `.claude/` directory.

The sentinel is read, judged and rewritten or removed by several actors that
nothing serialises: the checkpoint and `handoff-approved` write it, the mod's
`drive-take.sh` takes it at a turn's end and the prompt-time sweep (`report-
drive-failure.sh`) discards it. Each holds this lock across its own read-decide-
write, so the decision it made and the write it makes are one step.

`flock(2)` through `fcntl`, which Linux and macOS share (`flock(1)` is not on
macOS). The lock is on the directory, opened read-only; no file is created for
it, and a link to a directory is followed.

Two ways in. Python (`checkpoint.py`) uses `locked`, which raises when the lock
is not taken. Bash holds a lock across several steps through this file's `wait`
command, because a lock lives on an open file description and a child shares the
description of a file descriptor its parent opened: bash opens fd 9 on the
directory, `wait` takes the lock on it, and the lock then lasts until the shell
closes fd 9 or exits (`handoff_lock_take` in _lib.sh, which holds the sequence).

Bounds. The wait is bounded (`HANDOFF_LOCK_WAIT_SECS`, default 5 seconds), and a
lock that cannot be taken fails closed: the caller does not act on the sentinel,
because acting unlocked reopens the race the lock closes. Two causes are told
apart. `LockBusyError` (bash: rc 75) is the bound passing with another actor
still holding it; `LockUnavailableError` (bash: any other failure) is a lock
that could not be set up at all: no `.claude/`, a non-directory at its name, a
file system with no `flock`, a failing helper. `wait` refuses a descriptor that
is not the directory the path now names (equal device and inode), so a directory
swapped in between bash's open and `wait` is unavailable.

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
from pathlib import Path


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
def locked(directory: str | os.PathLike[str]) -> Iterator[None]:
    """Hold the lock on `directory` for the body.

    Raises `LockBusyError` when the bound passes with the lock held elsewhere
    and `LockUnavailableError` when it cannot be set up (a non-directory at
    `directory`, no such directory, no `flock`). Either is raised on entry, so
    the body never runs unlocked.
    """
    fd = _open_directory(os.fspath(directory))
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
    """Run the `wait` command; any other use is rc 64."""
    if len(argv) == 4 and argv[1] == "wait":
        return _command_wait(argv[2], argv[3])
    print("usage: _drive_lock.py wait <fd> <directory>", file=sys.stderr)
    return EXIT_USAGE


def _command_wait(fd_text: str, path: str) -> int:
    """Lock the descriptor the parent opened (`wait <fd> <directory>`).

    Refused as unavailable when the descriptor is not a directory or is not the
    directory the path now names (equal device and inode), so bash's open cannot
    have been led elsewhere unnoticed. rc 0 held, `EXIT_BUSY` for the bound
    passing.
    """
    try:
        fd = int(fd_text)
        held = os.fstat(fd)
        named = Path(path).stat()
    except (ValueError, OSError):
        return EXIT_UNAVAILABLE
    if not stat.S_ISDIR(held.st_mode) or not stat.S_ISDIR(named.st_mode):
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


def _open_directory(path: str) -> int:
    """Open the directory read-only, following a link to a directory."""
    try:
        return os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    except OSError as e:
        raise LockUnavailableError(path, e) from e


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
