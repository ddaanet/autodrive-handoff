"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the sentinel's lock
(the write waits on it, a refused lock fails closed and writes nothing) and the
read-back of the sentinel just written (a reader that cannot run or fails
removes the unverified file).

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

import shutil
import subprocess
import threading
from pathlib import Path

import _checkpoint_payload as validation
import _drive_lock as drive_lock
import checkpoint
import pytest
from conftest import handoff_payload, make_repo, run_checkpoint, todo_edit
from lock_holder import blocked_signal, held_elsewhere

pytestmark = pytest.mark.usefixtures("_session_id")


# ==========================================================================
# The sentinel's lock
# ==========================================================================


def test_sentinel_write_waits_on_the_lock(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Another actor holds the lock; the checkpoint writes the sentinel only
    once it is free.

    The row changes nothing until the checkpoint has reported, through a pipe it
    blocks on, that it is waiting on the lock, so an unlocked write, which never
    waits, fails the row however late it starts. Without the lock it lands at
    once, under the other actor.
    """
    repo = make_repo(tmp_path)
    lock = repo / ".claude" / "autodrive.lock"
    blocked = tmp_path / "blocked"
    monkeypatch.setenv("HANDOFF_LOCK_WAIT_SECS", "30")
    monkeypatch.setenv(drive_lock.BLOCKED_ENV, str(blocked))
    payload = handoff_payload("without-commit")
    result: list[subprocess.CompletedProcess[str]] = []
    thread = threading.Thread(
        target=lambda: result.append(run_checkpoint(repo, payload))
    )
    with blocked_signal(blocked) as wait, held_elsewhere(lock):
        thread.start()
        assert wait()
        assert not (repo / ".claude" / "autodrive").exists()
    thread.join(timeout=20)
    assert result
    assert result[0].returncode == 0, result[0].stderr
    assert (repo / ".claude" / "autodrive").exists()


def test_an_edit_is_planned_after_the_wait_not_before_it(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The lock covers the read-plan-write: an `edit` resolves against the
    TODO.md the checkpoint finds once it has the lock.

    The holder's change lands while the checkpoint waits, keeps the edit's
    `old_string` and alters another line. A checkpoint that planned before it
    waited applies the edit to the old body and writes it over the holder's
    change; one that plans under the lock keeps both. The wait is the normal
    one: the row releases the holder after the blocked signal, so nothing
    sleeps or polls.
    """
    repo = make_repo(tmp_path)
    todo = repo / "TODO.md"
    todo.write_text("## Remaining\n\n- target item\n- other item\n")
    lock = repo / ".claude" / "autodrive.lock"
    blocked = tmp_path / "blocked"
    monkeypatch.setenv("HANDOFF_LOCK_WAIT_SECS", "30")
    monkeypatch.setenv(drive_lock.BLOCKED_ENV, str(blocked))
    payload = handoff_payload("without-commit")
    payload["todo"] = todo_edit("- target item", "- edited item")
    result: list[subprocess.CompletedProcess[str]] = []
    thread = threading.Thread(
        target=lambda: result.append(run_checkpoint(repo, payload))
    )
    with blocked_signal(blocked) as wait, held_elsewhere(lock) as release:
        thread.start()
        assert wait()
        todo.write_text("## Remaining\n\n- target item\n- holder item\n")
        release()
    thread.join(timeout=20)
    assert result
    assert result[0].returncode == 0, result[0].stderr
    assert todo.read_text() == "## Remaining\n\n- edited item\n- holder item\n"


def _writing_payload() -> dict[str, object]:
    """A call that would write both frame files and the sentinel."""
    payload = handoff_payload("without-commit")
    payload["task"] = "## Current task\n\nfresh task\n"
    payload["todo"] = "## Remaining\n\n- fresh item\n"
    return payload


def _tree(repo: Path) -> dict[str, bytes]:
    """Every file under the root outside .git and the lock file, by path."""
    return {
        str(path.relative_to(repo)): path.read_bytes()
        for path in sorted(repo.rglob("*"))
        if path.is_file()
        and ".git" not in path.relative_to(repo).parts
        and path.name != "autodrive.lock"
    }


def test_a_lock_held_past_the_wait_fails_closed_and_writes_nothing(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The bound: with the lock held elsewhere for the whole run and the wait
    tiny, the checkpoint exits 2 naming the lock before it writes anything.

    The lock is taken ahead of the frame files, so a refused call leaves
    TASK.md, TODO.md and the sentinel exactly as they were, and the same call
    can be made again (an `edit` could not be, once applied). The holder is
    killed when the body ends: no sleep.
    """
    repo = make_repo(tmp_path)
    (repo / "TODO.md").write_text("## Remaining\n\n- old item\n")
    (repo / ".claude" / "autodrive").write_text("armed sess-other\nrename\nX\n")
    before = _tree(repo)
    monkeypatch.setenv("HANDOFF_LOCK_WAIT_SECS", "0.05")
    with held_elsewhere(repo / ".claude" / "autodrive.lock"):
        result = run_checkpoint(repo, _writing_payload())
    assert result.returncode == 2
    assert result.stderr.startswith("handoff-checkpoint: lock: ")
    assert "busy" in result.stderr
    assert result.stdout == ""
    assert _tree(repo) == before


def test_a_lock_that_cannot_be_set_up_fails_closed_and_writes_nothing(
    tmp_path: Path,
) -> None:
    """A link at the lock's name is `unavailable`, told apart from busy, and
    fails closed the same way; nothing is written through it."""
    repo = make_repo(tmp_path)
    elsewhere = tmp_path / "elsewhere"
    elsewhere.write_text("kept")
    (repo / ".claude").mkdir(exist_ok=True)
    (repo / ".claude" / "autodrive.lock").symlink_to(elsewhere)
    before = _tree(repo)
    result = run_checkpoint(repo, _writing_payload())
    assert result.returncode == 2
    assert result.stderr.startswith("handoff-checkpoint: lock: ")
    assert "could not be set up" in result.stderr
    assert "busy" not in result.stderr
    assert elsewhere.read_text() == "kept"
    assert _tree(repo) == before


def test_a_read_back_that_cannot_run_removes_the_sentinel_and_says_so(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The read-back is bash; with none on PATH it cannot answer.

    The sentinel just written is unverified, so it must not stay on disk for the
    mod to drive, and the error is about the read-back, not a failed write.
    """
    repo = make_repo(tmp_path)
    git = shutil.which("git")
    assert git
    bin_dir = tmp_path / "bin-with-git-only"
    bin_dir.mkdir()
    (bin_dir / "git").symlink_to(git)
    monkeypatch.setenv("PATH", str(bin_dir))
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode != 0
    assert "cannot read back" in result.stderr
    assert "cannot write .claude/autodrive" not in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()


def _stub_reader(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, body: str) -> None:
    """Put a `bash` ahead of the real one that runs `body`, in place of the
    sentinel read-back (the one `bash` the checkpoint spawns)."""
    bin_dir = tmp_path / "stub-bin"
    bin_dir.mkdir()
    stub = bin_dir / "bash"
    stub.write_text(f"#!/bin/sh\n{body}\n")
    stub.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{Path('/usr/bin')}:/bin")


def test_a_reader_that_fails_silently_still_gives_the_message_a_reason(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A reader that exits non-zero with empty stderr leaves no dangling
    dash."""
    repo = make_repo(tmp_path)
    _stub_reader(tmp_path, monkeypatch, "exit 1")
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode != 0
    assert "cannot read back" in result.stderr
    assert not result.stderr.rstrip().endswith("—")
    assert "with no reason" in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()


def test_a_reader_whose_stderr_does_not_decode_leaves_no_sentinel(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Any failure of the read-back, not only an OSError, removes the sentinel.

    Invalid UTF-8 on the reader's stderr is one that is not an OSError: the
    unverified `armed` file must not stay on disk for the mod to drive.
    """
    repo = make_repo(tmp_path)
    _stub_reader(tmp_path, monkeypatch, "printf '\\377bad' >&2; exit 1")
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode != 0
    assert "cannot read back" in result.stderr
    assert "Traceback" not in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()


def test_an_unexpected_read_back_failure_removes_the_sentinel(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Whatever the read-back raises, the sentinel it was to verify goes
    first."""
    repo = make_repo(tmp_path)
    (repo / ".claude").mkdir(exist_ok=True)

    def boom(_drive_path: Path) -> tuple[bool, str]:
        raise RuntimeError("boom")

    monkeypatch.setattr(checkpoint, "_read_back_drive", boom)
    transition = validation.Transition(kind="rename", arg="X", typed=False)
    with pytest.raises(RuntimeError):
        checkpoint.compose_sentinel(
            repo, transition, continuation=False, owner="sess-x", held=False
        )
    assert not (repo / ".claude" / "autodrive").exists()
