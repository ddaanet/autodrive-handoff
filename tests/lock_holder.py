"""A stand-in for another actor that holds the sentinel's lock.

Shared by every test that shows the lock ordering actors: the pytest files
import `held_elsewhere` and `wait_until_blocked`, and the bats files run this
file as a script (`tests/lock-helpers.bash`). The holder takes the lock through
`_drive_lock.locked`, the code under test's own, so no test restates how the
lock is taken.

`wait_until_blocked` is what makes an ordering row deterministic. The actor
under test is started with `HANDOFF_LOCK_BLOCKED_FILE` naming a file, which the
lock's wait touches once it has found the lock held
(`_drive_lock._signal_blocked`). A row changes the sentinel only after that, so
the actor cannot have read it yet; an actor with no lock call never touches the
file, and the row fails instead of passing because the actor happened to start
late.

Run as `lock_holder.py <lockfile> <seconds>`: takes the lock, prints `held`,
holds it for `seconds` (or until killed), exits 1 when it could not take it.
"""

from __future__ import annotations

import subprocess
import sys
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
BLOCKED_ENV = "HANDOFF_LOCK_BLOCKED_FILE"


@contextmanager
def held_elsewhere(lock: Path, seconds: float = 60) -> Iterator[None]:
    """Hold the lock from another process for the body, or `seconds`."""
    holder = subprocess.Popen(
        [sys.executable, "-I", __file__, str(lock), str(seconds)],
        stdout=subprocess.PIPE,
        text=True,
    )
    try:
        assert holder.stdout is not None
        assert holder.stdout.readline().strip() == "held"
        yield
    finally:
        holder.kill()
        holder.wait()


def wait_until_blocked(
    blocked_file: Path, running: Callable[[], bool], timeout: float = 20
) -> bool:
    """Wait for the actor to report it is blocked on the lock.

    False when it ended without reporting, or `timeout` passed: the actor never
    waited on the lock.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if blocked_file.exists():
            return True
        if not running():
            return blocked_file.exists()
        time.sleep(0.02)
    return False


def hold(lock: str, seconds: float) -> int:
    """Take the lock, say so, and sit on it."""
    sys.path.insert(0, str(SCRIPTS))
    import _drive_lock  # noqa: PLC0415 -- the path above is what makes it importable

    with _drive_lock.locked(lock) as held:
        if not held:
            return 1
        print("held", flush=True)
        time.sleep(seconds)
    return 0


if __name__ == "__main__":
    sys.exit(hold(sys.argv[1], float(sys.argv[2])))
