"""A stand-in for another actor that holds the sentinel's lock.

Shared by every test that shows the lock at work: the pytest files import
`held_elsewhere` and `blocked_signal`, and the bats files run this file as a
script (`tests/lock-helpers.bash`). The holder takes the lock through
`_drive_lock.locked`, the code under test's own, so no test restates how the
lock is taken.

Nothing here sleeps or polls. The holder says `held` once it holds the lock and
then waits for a signal, which is also how a row releases it (a held lock is
released by the process ending, its descriptor closing). A row that needs to
know an actor is *waiting* on the lock is given a pipe, not a file to poll: the
actor under test is started with `HANDOFF_LOCK_BLOCKED_FILE` naming a FIFO the
row has open, `_drive_lock._signal_blocked` writes a byte to it once the wait
has found the lock held, and the row blocks on a read of it (`blocked_signal`).
A row changes the sentinel only after that, so the actor cannot have read it
yet; an actor with no lock call never writes, and the row fails when its bound
passes, whatever the speed of the box.

Run as `lock_holder.py <lockfile>`: takes the lock, prints `held`, waits for a
signal (SIGALRM after a minute, so a row that forgets to release does not leave
it for ever), exits 1 when it could not take it.
"""

from __future__ import annotations

import os
import select
import signal
import subprocess
import sys
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Protocol

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
LOCK_LIFETIME_SECS = 60


@contextmanager
def held_elsewhere(lock: Path) -> Iterator[Callable[[], None]]:
    """Hold the lock from another process for the body.

    Yields `release`, which ends the holder (so the lock is free) before the
    body is done; the body's end releases it too.
    """
    holder = subprocess.Popen(
        [sys.executable, "-I", __file__, str(lock)],
        stdout=subprocess.PIPE,
        text=True,
    )

    def release() -> None:
        holder.kill()
        holder.wait()

    try:
        assert holder.stdout is not None
        assert holder.stdout.readline().strip() == "held"
        yield release
    finally:
        release()


class Waiter(Protocol):
    """What `blocked_signal` yields: wait for the report, `timeout` seconds."""

    def __call__(self, timeout: float = 10) -> bool: ...


@contextmanager
def blocked_signal(path: Path) -> Iterator[Waiter]:
    """Make `path` a FIFO the lock's wait writes to; yield a waiter on it.

    The caller sets `HANDOFF_LOCK_BLOCKED_FILE` to `path` for the actor under
    test. The yielded function blocks until the wait has found the lock held,
    and returns False when `timeout` seconds pass first: the actor never waited
    on the lock.
    """
    os.mkfifo(path)
    # Read-write, so the open does not wait for a writer and a writer's open
    # does not wait for this reader.
    fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)

    def wait(timeout: float = 10) -> bool:
        ready, _, _ = select.select([fd], [], [], timeout)
        return bool(ready)

    try:
        yield wait
    finally:
        os.close(fd)


def hold(lock: str) -> int:
    """Take the lock, say so, and sit on it until a signal."""
    sys.path.insert(0, str(SCRIPTS))
    import _drive_lock  # noqa: PLC0415 -- the path above is what makes it importable

    with _drive_lock.locked(lock):
        print("held", flush=True)
        signal.alarm(LOCK_LIFETIME_SECS)
        signal.pause()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(hold(sys.argv[1]))
    except Exception:  # noqa: BLE001 -- any failure to take it is the one exit code
        sys.exit(1)
