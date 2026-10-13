"""Tests for scripts/checkpoint.py (handoff-checkpoint) — what may sit at the
root names `TASK.md` and `TODO.md`, and how a write lands on them.

A symlink or a directory at either name is refused naming the field, exit 2,
nothing written; so is a root file that cannot be read or decoded where the call
has to read it. A write goes through a sibling temporary file and `os.replace`,
which swaps a link at the name rather than writing through it, and keeps an
existing file's mode. The legacy-path counterparts are in
tests/test_checkpoint_legacy.py; the shared helpers in tests/conftest.py.
"""

import os
import subprocess
from pathlib import Path

import pytest
from conftest import (
    frame_payload,
    make_repo,
    run_checkpoint,
    task_clear,
    task_content,
    todo_clear,
    todo_content,
    todo_edit,
    todo_keep,
)

pytestmark = pytest.mark.usefixtures("_session_id")

NOT_ROOT = pytest.mark.skipif(
    os.geteuid() == 0, reason="root ignores file modes, so no read fails"
)
TARGET_BODY = "## Remaining\n\n- the link target's own item\n"
TASK_WRITTEN = "## Current task\n\nwritten task prose\n"
TODO_WRITTEN = "## Remaining\n\n- written item\n"
SENTINEL_REL = ".claude/autodrive"

# Each case: the root name, and the task and todo of a call that reaches it.
# The other half is a plain write, so a refusal is the whole call's.
REACHING = {
    "task_content": ("TASK.md", task_content(TASK_WRITTEN), todo_keep()),
    "task_clear": ("TASK.md", task_clear(), todo_keep()),
    "todo_content": (
        "TODO.md",
        task_content(TASK_WRITTEN),
        todo_content(TODO_WRITTEN),
    ),
    "todo_edit": (
        "TODO.md",
        task_content(TASK_WRITTEN),
        todo_edit("- the link target's own item", "- edited"),
    ),
    "todo_clear": ("TODO.md", task_content(TASK_WRITTEN), todo_clear()),
    "todo_keep": ("TODO.md", task_content(TASK_WRITTEN), todo_keep()),
}


def assert_refused(
    result: subprocess.CompletedProcess[str], field: str, what: str
) -> None:
    """Exit 2 through lib.err naming the field, and no traceback."""
    assert result.returncode == 2, result.stderr
    assert "Traceback" not in result.stderr
    assert result.stderr.startswith(f"handoff-checkpoint: {field}"), result.stderr
    assert what in result.stderr.lower(), result.stderr


# --- a symlink at a root name ---


@pytest.mark.parametrize("relative", [True, False], ids=["relative", "absolute"])
@pytest.mark.parametrize("case", list(REACHING))
def test_a_symlinked_root_file_is_refused_and_its_target_is_untouched(
    tmp_path: Path, case: str, *, relative: bool
) -> None:
    """The target's bytes are asserted first, so a run that writes through the
    link reds there, and one that swaps the link for a file reds on the exit
    code.

    Its positive is every write row in test_checkpoint_writes.py, the same calls
    over a regular file or none.
    """
    rel, task, todo = REACHING[case]
    repo = make_repo(tmp_path)
    target = repo / "notes" / "elsewhere.md"
    target.parent.mkdir()
    target.write_text(TARGET_BODY)
    link = repo / rel
    link.symlink_to(os.path.relpath(target, repo) if relative else target)
    result = run_checkpoint(repo, frame_payload(task, todo))
    assert target.read_text() == TARGET_BODY
    assert_refused(result, rel[:4].lower(), "symbolic link")
    assert link.is_symlink()
    assert not (repo / SENTINEL_REL).exists()
    other = "TODO.md" if rel == "TASK.md" else "TASK.md"
    assert not (repo / other).exists()


@pytest.mark.parametrize("rel", ["TASK.md", "TODO.md"])
def test_a_dangling_symlinked_root_file_is_refused_and_creates_nothing(
    tmp_path: Path, rel: str
) -> None:
    """Writing through a dangling link would create its target."""
    repo = make_repo(tmp_path)
    (repo / rel).symlink_to("nowhere.md")
    payload = frame_payload(task_content(TASK_WRITTEN), todo_content(TODO_WRITTEN))
    result = run_checkpoint(repo, payload)
    assert not (repo / "nowhere.md").exists()
    assert_refused(result, rel[:4].lower(), "symbolic link")


# --- a directory at a root name, no legacy file anywhere ---


@pytest.mark.parametrize("case", list(REACHING))
def test_a_directory_at_the_root_name_is_refused_naming_the_field(
    tmp_path: Path, case: str
) -> None:
    """With no legacy file the plan used to reach the write or the unlink, which
    raised on the directory.

    Its positive is the same calls over a regular file.
    """
    rel, task, todo = REACHING[case]
    repo = make_repo(tmp_path)
    (repo / rel).mkdir()
    result = run_checkpoint(repo, frame_payload(task, todo))
    assert_refused(result, rel[:4].lower(), "directory")
    assert (repo / rel).is_dir()
    assert not (repo / SENTINEL_REL).exists()


# --- a root file the edit cannot read ---


def test_a_todo_that_is_not_utf8_is_refused_on_edit_naming_the_field(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    raw = b"## Remaining\n\n- caf\xe9 item\n"
    (repo / "TODO.md").write_bytes(raw)
    payload = frame_payload(task_content(TASK_WRITTEN), todo_edit("item", "x"))
    result = run_checkpoint(repo, payload)
    assert_refused(result, "todo", "utf-8")
    assert (repo / "TODO.md").read_bytes() == raw
    assert not (repo / "TASK.md").exists()


@NOT_ROOT
def test_a_todo_that_cannot_be_read_is_refused_on_edit_naming_the_field(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    (repo / "TODO.md").write_text(TODO_WRITTEN)
    (repo / "TODO.md").chmod(0o000)
    try:
        payload = frame_payload(task_content(TASK_WRITTEN), todo_edit("item", "x"))
        result = run_checkpoint(repo, payload)
        assert_refused(result, "todo", "cannot be read")
        assert not (repo / "TASK.md").exists()
    finally:
        (repo / "TODO.md").chmod(0o644)
    assert (repo / "TODO.md").read_text() == TODO_WRITTEN


# --- the write keeps the file's mode ---


@pytest.mark.parametrize("mode", [0o640, 0o755])
def test_a_write_keeps_an_existing_files_mode(tmp_path: Path, mode: int) -> None:
    """A sibling temporary file is created 0600; the write carries the old mode
    over rather than leaving that one behind."""
    repo = make_repo(tmp_path)
    for rel in ("TASK.md", "TODO.md"):
        (repo / rel).write_text("stale\n")
        (repo / rel).chmod(mode)
    payload = frame_payload(task_content(TASK_WRITTEN), todo_content(TODO_WRITTEN))
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0, result.stderr
    for rel, body in (("TASK.md", TASK_WRITTEN), ("TODO.md", TODO_WRITTEN)):
        assert (repo / rel).read_text() == body
        assert (repo / rel).stat().st_mode & 0o7777 == mode


def test_a_new_file_takes_the_umask_mode_and_no_temporary_is_left(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    umask = os.umask(0o027)
    try:
        payload = frame_payload(task_content(TASK_WRITTEN), todo_content(TODO_WRITTEN))
        result = run_checkpoint(repo, payload)
    finally:
        os.umask(umask)
    assert result.returncode == 0, result.stderr
    for rel in ("TASK.md", "TODO.md"):
        assert (repo / rel).stat().st_mode & 0o7777 == 0o640
    assert sorted(p.name for p in repo.iterdir() if p.name.startswith(".T")) == []
