"""Tests for scripts/_drive_lock.py, the sentinel's advisory lock, through both
its ways in: `locked` (checkpoint.py) and `handoff_lock_take` (the bash callers,
over the module's command line).

The rows that show the lock *ordering* actors, a checkpoint, a take, a sweep and
an approval each waiting on a held lock, are with the actor: tests/
test_checkpoint_readback.py, tests/drive-take.bats, tests/hook-test.bats and
tests/checkpoint.bats.
"""

import json
import os
import stat
import subprocess
import sys
import threading
from pathlib import Path

import _drive_lock as drive_lock
import checkpoint
import pytest
from lock_holder import blocked_signal, held_elsewhere

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


def take_in_bash(lock: Path, then: str) -> subprocess.CompletedProcess[str]:
    """Run handoff_lock_take in a shell, then `then` (shell text), same shell.

    Stdout carries `rc=<its return>`, stderr HANDOFF_LOCK_MSG.
    """
    script = (
        f'source "{LIB}"; handoff_lock_take "$1"; echo "rc=$?"; '
        f'echo "$HANDOFF_LOCK_MSG" >&2; {then}'
    )
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
    with drive_lock.locked(lock):
        assert not lock_is_free(lock)
    assert lock_is_free(lock)
    assert stat.S_IMODE(lock.stat().st_mode) == 0o600


def test_locked_waits_for_another_holder_and_takes_it_when_released(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """No sleep: the waiter reports it is waiting, then the holder is killed."""
    lock = tmp_path / "autodrive.lock"
    blocked = tmp_path / "blocked"
    monkeypatch.setenv(drive_lock.WAIT_ENV, "30")
    monkeypatch.setenv(drive_lock.BLOCKED_ENV, str(blocked))
    outcome: list[str] = []

    def take() -> None:
        try:
            with drive_lock.locked(lock):
                outcome.append("held")
        except drive_lock.LockError as e:
            outcome.append(type(e).__name__)

    with blocked_signal(blocked) as wait, held_elsewhere(lock) as release:
        thread = threading.Thread(target=take)
        thread.start()
        assert wait()
        assert outcome == []
        release()
    thread.join(timeout=20)
    assert outcome == ["held"]


def test_locked_raises_busy_at_the_bound_and_never_runs_the_body(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    lock = tmp_path / "autodrive.lock"
    monkeypatch.setenv(drive_lock.WAIT_ENV, "0.05")
    ran = False
    with (
        held_elsewhere(lock),
        pytest.raises(drive_lock.LockBusyError),
        drive_lock.locked(lock),
    ):
        ran = True
    assert not ran


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
    with pytest.raises(drive_lock.LockUnavailableError), drive_lock.locked(lock):
        pass
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


def test_bash_take_is_busy_after_the_bound_and_says_so(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    lock = tmp_path / "autodrive.lock"
    monkeypatch.setenv(drive_lock.WAIT_ENV, "0.05")
    with held_elsewhere(lock):
        result = take_in_bash(lock, "")
    assert result.stdout.split() == ["rc=1"]
    assert result.stderr.strip() == "the sentinel's lock was busy"


@pytest.mark.parametrize("shape", ["dangling_link", "link_to_file", "no_dir"])
def test_bash_take_is_unavailable_for_a_link_and_creates_nothing_through_it(
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
    result = take_in_bash(lock, "")
    assert result.stdout.split() == ["rc=2"]
    assert result.stderr.strip() == "the sentinel's lock could not be set up"
    assert not target.exists() or target.read_text() == "kept"
    assert lock.is_symlink() or not lock.exists()


def test_bash_take_is_unavailable_when_python3_fails(tmp_path: Path) -> None:
    """A crashed helper is `unavailable`, never read as busy."""
    lock = tmp_path / "autodrive.lock"
    lock.touch()
    stub = tmp_path / "bin"
    stub.mkdir()
    (stub / "python3").write_text("#!/bin/sh\nexit 1\n")
    (stub / "python3").chmod(0o755)
    script = f'source "{LIB}"; PATH="{stub}:$PATH" handoff_lock_take "$1"; echo "rc=$?"'
    result = subprocess.run(
        ["bash", "-c", script, "_", str(lock)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.stdout.split() == ["rc=2"]


def test_the_python_constant_mirrors_the_bash_one() -> None:
    result = subprocess.run(
        ["bash", "-c", f'source "{LIB}"; printf %s "$HANDOFF_REL_DRIVE_LOCK"'],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.stdout == checkpoint.HANDOFF_REL_DRIVE_LOCK


def test_a_wait_that_finds_the_lock_held_writes_to_the_blocked_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The readiness signal the ordering rows block on: a byte written once the
    wait has found the lock held, and by nothing else."""
    lock = tmp_path / "autodrive.lock"
    blocked = tmp_path / "blocked"
    monkeypatch.setenv(drive_lock.BLOCKED_ENV, str(blocked))
    monkeypatch.setenv(drive_lock.WAIT_ENV, "0.05")
    with blocked_signal(blocked) as wait:
        with drive_lock.locked(lock):
            pass
        assert not wait(0)
        with (
            held_elsewhere(lock),
            pytest.raises(drive_lock.LockBusyError),
            drive_lock.locked(lock),
        ):
            pass
        assert wait(0)


def test_the_blocked_file_is_written_by_the_bash_wait_too(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    lock = tmp_path / "autodrive.lock"
    blocked = tmp_path / "blocked"
    monkeypatch.setenv(drive_lock.BLOCKED_ENV, str(blocked))
    monkeypatch.setenv(drive_lock.WAIT_ENV, "0.05")
    with blocked_signal(blocked) as wait, held_elsewhere(lock):
        take_in_bash(lock, "")
        assert wait(0)


def test_a_blocked_fifo_with_no_reader_is_no_hang(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The signal opens non-blocking: a FIFO nobody reads costs nothing."""
    lock = tmp_path / "autodrive.lock"
    blocked = tmp_path / "blocked"
    os.mkfifo(blocked)
    monkeypatch.setenv(drive_lock.BLOCKED_ENV, str(blocked))
    monkeypatch.setenv(drive_lock.WAIT_ENV, "0.05")
    with (
        held_elsewhere(lock),
        pytest.raises(drive_lock.LockBusyError),
        drive_lock.locked(lock),
    ):
        pass


def test_the_lock_hooks_budget_covers_the_wait(tmp_path: Path) -> None:
    """Every hook that takes the lock may run for the wait and its own work.

    The default wait is read from the lock module. A hook's `timeout` in
    hooks.json is the host's cut-off; one at or under the wait is killed while
    it waits, which is the fail-open the wait's bound exists to avoid. Five
    seconds is the headroom for what the hook does after the wait.
    """
    plugin = SCRIPTS.parent
    hooks = json.loads((plugin / "hooks" / "hooks.json").read_text())
    budgets: dict[str, float] = {}
    for groups in hooks["hooks"].values():
        for group in groups:
            for hook in group["hooks"]:
                script = Path(hook["command"].split("/scripts/")[1].split('"')[0])
                if "handoff_lock_take" in (SCRIPTS / script).read_text():
                    budgets[script.name] = hook["timeout"]
    assert set(budgets) == {
        "report-drive-failure.sh",
        "load-handoff.sh",
        "load-compact.sh",
    }, "a hook that takes the lock was added or dropped: check its timeout"
    for name, timeout in budgets.items():
        assert timeout >= drive_lock.DEFAULT_WAIT_SECS + 5, name
