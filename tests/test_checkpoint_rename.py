"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the `rename` field
(FR8) and the `autoname` skill.

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

from pathlib import Path

import pytest
from conftest import (
    dirty_memory,
    drive_state,
    frame_payload,
    make_gitlore_repo,
    make_repo,
    read_back_drive,
    run_checkpoint,
    task_clear,
    todo_keep,
)

pytestmark = pytest.mark.usefixtures("_session_id")


# ==========================================================================
# Rename -- FR8
# ==========================================================================


def test_rename_only_sentinel_written_neither_file_created(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "Two Words Title",
        "clear": False,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (
        repo / ".claude" / "autodrive"
    ).read_text() == "armed sess-checkpoint\nrename\n/rename Two Words Title\n"
    assert read_back_drive(repo / ".claude" / "autodrive")
    assert not (repo / "TASK.md").exists()
    assert not (repo / "TODO.md").exists()


def test_multiline_title_flattened_to_one_line(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "Two  Words\nAnd More",
        "clear": False,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    content = (repo / ".claude" / "autodrive").read_text()
    assert len(content.splitlines()) == 3
    assert "/rename Two Words And More" in content.splitlines()


def test_whitespace_only_title_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "   ",
        "clear": False,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "rename" in result.stderr


def test_root_without_a_claude_directory_gets_one_for_the_sentinel(
    tmp_path: Path,
) -> None:
    """The frame lives in the root, so the sentinel is the one thing that needs
    `.claude/`: a root that has none still takes both files and the sentinel."""
    repo = make_repo(tmp_path)
    (repo / ".claude").rmdir()
    task = "## Current task\n\nbody\n"
    todo = "## Remaining\n\n- x\n"
    result = run_checkpoint(repo, frame_payload(task, todo))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == task
    assert (repo / "TODO.md").read_text() == todo
    assert read_back_drive(repo / ".claude" / "autodrive")


@pytest.mark.parametrize("blocked", ["claude-is-a-file", "sentinel-is-a-directory"])
def test_a_sentinel_path_that_cannot_take_a_file_is_refused_before_any_write(
    tmp_path: Path, blocked: str
) -> None:
    """`.claude` a file, or `.claude/autodrive` a directory: the sentinel cannot
    be written there.

    The call exits 2 naming the field and the path, with no traceback, and is
    refused before either frame file is touched.
    """
    repo = make_repo(tmp_path)
    if blocked == "claude-is-a-file":
        (repo / ".claude").rmdir()
        (repo / ".claude").write_text("not a directory\n")
        rel = ".claude"
    else:
        (repo / ".claude" / "autodrive").mkdir()
        rel = ".claude/autodrive"
    (repo / "TASK.md").write_text("## Current task\n\nold\n")
    (repo / "TODO.md").write_text("## Remaining\n\n- old\n")
    result = run_checkpoint(
        repo, frame_payload("## Current task\n\nnew\n", "## Remaining\n\n- new\n")
    )
    assert result.returncode == 2, result.stderr
    assert "Traceback" not in result.stderr
    assert "transition" in result.stderr
    assert rel in result.stderr
    assert (repo / "TASK.md").read_text() == "## Current task\n\nold\n"
    assert (repo / "TODO.md").read_text() == "## Remaining\n\n- old\n"


# ==========================================================================
# the autoname skill
# ==========================================================================


def test_autoname_rename_sentinel_armed_nothing_else(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {"skill": "autoname", "rename": "A Side Conversation"}
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (
        repo / ".claude" / "autodrive"
    ).read_text() == "armed sess-checkpoint\nrename\n/rename A Side Conversation\n"
    state, owner = drive_state(repo / ".claude" / "autodrive")
    assert (state, owner) == ("armed", "sess-checkpoint")


def test_autoname_without_a_session_id_errors_and_composes_nothing(
    tmp_path: Path,
) -> None:
    """The rename sentinel is armed, and an armed sentinel names its owner."""
    repo = make_repo(tmp_path)
    payload = {"skill": "autoname", "rename": "A Side Conversation"}
    result = run_checkpoint(repo, payload, with_session_id=False)
    assert result.returncode != 0
    assert "cannot read back" not in result.stderr
    assert "CLAUDE_CODE_SESSION_ID" in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()


def test_autoname_leaves_both_frame_files_byte_identical(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    task = "## Current task\n\nlive\n"
    todo = "## Remaining\n\n- an item\n"
    (repo / "TASK.md").write_text(task)
    (repo / "TODO.md").write_text(todo)
    payload = {"skill": "autoname", "rename": "A Side Conversation"}
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == task
    assert (repo / "TODO.md").read_text() == todo


def test_rename_missing_under_autoname_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {"skill": "autoname"}
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "rename" in result.stderr


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("commit", "with-commit"),
        ("task", "body"),
        ("todo", "body"),
        ("clear", True),
        ("compact", True),
        ("continue", "pick up per the task file"),
    ],
)
def test_every_boundary_field_is_schema_error_under_autoname(
    tmp_path: Path, field: str, value: object
) -> None:
    repo = make_repo(tmp_path)
    payload = {"skill": "autoname", "rename": "A Side Conversation", field: value}
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert field in result.stderr
    assert "autoname" in result.stderr


def test_autoname_against_dirty_memory_no_directive_at_all(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {"skill": "autoname", "rename": "A Side Conversation"}
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert result.stdout == ""
