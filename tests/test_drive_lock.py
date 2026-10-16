"""Tests for scripts/_drive_lock.py, the sentinel's advisory lock, through both
its ways in: `locked` (checkpoint.py) and `handoff_lock_take` (the bash callers,
over the module's command line).

The rows that show the lock *ordering* actors, a checkpoint, a take, a sweep and
an approval each waiting on a held lock, are with the actor: tests/
test_checkpoint_hold.py, tests/drive-take.bats, tests/hook-test.bats and
tests/checkpoint.bats.
"""

import stat
import subprocess
import sys
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import _drive_lock as drive_lock
import checkpoint
import pytest

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
LIB = SCRIPTS / "_lib.sh"

# What a second process runs to ask whether the lock is free: exit 0 when it
# could take it, 1 when it is held.
PROBE = (
    "import fcntl, os, sys\n"
    "fd = os.open(sys.argv[1], os.O_RDWR)\n"
    "try:\n"
    "    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)\n"
    "except BlockingIOError:\n"
    "    sys.exit(1)\n"
)


def lock_is_free(lock: Path) -> bool:
    result = subprocess.run([sys.executable, "-I", "-c", PROBE, str(lock)], check=False)
    return result.returncode == 0


@contextmanager
def held_elsewhere(lock: Path, seconds: float = 60) -> Iterator[None]:
    """Hold the lock from another process for the body, or `seconds`."""
    holder = subprocess.Popen(
        [
            sys.executable,
            "-I",
            "-c",
            "import fcntl, os, sys, time\n"
            "fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)\n"
            "fcntl.flock(fd, fcntl.LOCK_EX)\n"
            "print('held', flush=True)\n"
            "time.sleep(float(sys.argv[2]))\n",
            str(lock),
            str(seconds),
        ],
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


def take_in_bash(lock: Path, then: str) -> subprocess.CompletedProcess[str]:
    """Run handoff_lock_take in a shell, then `then` (shell text), same
    shell."""
    script = f'source "{LIB}"; handoff_lock_take "$1"; echo "rc=$?"; {then}'
    return subprocess.run(
        ["bash", "-c", script, "_", str(lock)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_locked_holds_the_lock_for_the_body_and_creates_the_file_0600(
    tmp_path: Path,
) -> None:
    lock = tmp_path / "autodrive.lock"
    with drive_lock.locked(lock) as held:
        assert held
        assert not lock_is_free(lock)
    assert lock_is_free(lock)
    assert stat.S_IMODE(lock.stat().st_mode) == 0o600


def test_locked_waits_for_another_holder(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    lock = tmp_path / "autodrive.lock"
    monkeypatch.setenv(drive_lock.WAIT_ENV, "30")
    with held_elsewhere(lock, seconds=0.5):
        started = time.monotonic()
        with drive_lock.locked(lock) as held:
            assert held
        assert time.monotonic() - started >= 0.3


def test_locked_gives_up_at_the_bound_and_goes_ahead_without_it(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    lock = tmp_path / "autodrive.lock"
    monkeypatch.setenv(drive_lock.WAIT_ENV, "0.3")
    with held_elsewhere(lock):
        started = time.monotonic()
        with drive_lock.locked(lock) as held:
            assert not held
        assert time.monotonic() - started < 5


@pytest.mark.parametrize(
    "shape", ["dangling_link", "link_to_file", "directory", "no_dir"]
)
def test_locked_does_not_follow_or_use_what_is_not_a_regular_file(
    tmp_path: Path, shape: str
) -> None:
    target = tmp_path / "target"
    lock = tmp_path / "autodrive.lock"
    if shape == "dangling_link":
        lock.symlink_to(target)
    elif shape == "link_to_file":
        target.write_text("kept")
        lock.symlink_to(target)
    elif shape == "directory":
        lock.mkdir()
    else:
        lock = tmp_path / "missing" / "autodrive.lock"
    with drive_lock.locked(lock) as held:
        assert not held
    if shape == "dangling_link":
        assert not target.exists()
    if shape == "link_to_file":
        assert target.read_text() == "kept"


def test_bash_take_holds_the_lock_until_the_shell_exits(tmp_path: Path) -> None:
    lock = tmp_path / "autodrive.lock"
    probe = f"{sys.executable} -I -c '{PROBE}' {lock}; echo probe=$?"
    result = take_in_bash(lock, probe)
    assert result.stdout.split() == ["rc=0", "probe=1"]
    assert lock_is_free(lock)
    assert stat.S_IMODE(lock.stat().st_mode) == 0o600


def test_bash_take_is_not_held_after_the_bound(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    lock = tmp_path / "autodrive.lock"
    monkeypatch.setenv(drive_lock.WAIT_ENV, "0.3")
    with held_elsewhere(lock):
        assert take_in_bash(lock, "").stdout.split() == ["rc=1"]


@pytest.mark.parametrize("shape", ["dangling_link", "link_to_file", "no_dir"])
def test_bash_take_refuses_a_link_and_creates_nothing_through_it(
    tmp_path: Path, shape: str
) -> None:
    target = tmp_path / "target"
    lock = tmp_path / "autodrive.lock"
    if shape == "dangling_link":
        lock.symlink_to(target)
    elif shape == "link_to_file":
        target.write_text("kept")
        lock.symlink_to(target)
    else:
        lock = tmp_path / "missing" / "autodrive.lock"
    assert take_in_bash(lock, "").stdout.split() == ["rc=1"]
    assert not target.exists() or target.read_text() == "kept"
    assert lock.is_symlink() or not lock.exists()


def test_the_python_constant_mirrors_the_bash_one() -> None:
    result = subprocess.run(
        ["bash", "-c", f'source "{LIB}"; printf %s "$HANDOFF_REL_DRIVE_LOCK"'],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.stdout == checkpoint.HANDOFF_REL_DRIVE_LOCK
