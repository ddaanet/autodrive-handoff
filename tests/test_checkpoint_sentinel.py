"""Tests for scripts/checkpoint.py (handoff-checkpoint) — `continue: true`
needing a task or a todo to point at, and the legal combinations of the
transition fields with the exact bytes of the sentinel `.claude/autodrive` they
compose.

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

from pathlib import Path

import pytest
from checkpoint import CONTINUATION
from conftest import (
    make_repo,
    read_back_drive,
    run_checkpoint,
    task_clear,
    todo_clear,
    todo_keep,
)

pytestmark = pytest.mark.usefixtures("_session_id")


# --- `continue` needs a task or a todo to point at (handoff only) ---

TODO_BODY = "- run the gate\n"

# (task, todo, TASK.md before, TODO.md before): after the call neither half has
# a body, so the continuation would point at nothing.
BODYLESS: dict[str, tuple[object, object, str | None, str | None]] = {
    "both-cleared": (task_clear(), todo_clear(), None, None),
    "todo-kept-no-file": (task_clear(), todo_keep(), None, None),
    "todo-kept-headings-only": (task_clear(), todo_keep(), None, "## Remaining\n"),
    "todo-headings-only-content": (task_clear(), "## Remaining\n", None, None),
    "task-headings-only-content": ("## Task\n", todo_clear(), None, None),
    "cleared-over-files-with-bodies": (
        task_clear(),
        todo_clear(),
        "Resume the parser work.\n",
        TODO_BODY,
    ),
}


def clear_continue_payload(
    task: object, todo: object, *, cont: bool
) -> dict[str, object]:
    return {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "T",
        "clear": True,
        "continue": cont,
        "task": task,
        "todo": todo,
    }


def seed_frame(repo: Path, task_was: str | None, todo_was: str | None) -> None:
    if task_was is not None:
        (repo / "TASK.md").write_text(task_was)
    if todo_was is not None:
        (repo / "TODO.md").write_text(todo_was)


def frame_bytes(repo: Path) -> dict[str, bytes | None]:
    return {
        name: (repo / name).read_bytes() if (repo / name).exists() else None
        for name in ("TASK.md", "TODO.md")
    }


@pytest.mark.parametrize("case", BODYLESS)
def test_continue_true_with_no_task_or_todo_to_point_at_errors(
    tmp_path: Path, case: str
) -> None:
    task, todo, task_was, todo_was = BODYLESS[case]
    repo = make_repo(tmp_path)
    seed_frame(repo, task_was, todo_was)
    before = frame_bytes(repo)
    result = run_checkpoint(repo, clear_continue_payload(task, todo, cont=True))
    assert result.returncode == 2
    assert "continue" in result.stderr
    assert frame_bytes(repo) == before
    assert not (repo / ".claude" / "autodrive").exists()


@pytest.mark.parametrize("case", BODYLESS)
def test_continue_false_is_legal_with_no_task_or_todo(
    tmp_path: Path, case: str
) -> None:
    task, todo, task_was, todo_was = BODYLESS[case]
    repo = make_repo(tmp_path)
    seed_frame(repo, task_was, todo_was)
    result = run_checkpoint(repo, clear_continue_payload(task, todo, cont=False))
    assert result.returncode == 0, result.stderr
    assert read_back_drive(repo / ".claude" / "autodrive")


@pytest.mark.parametrize(
    ("task", "todo", "todo_was"),
    [
        ("Resume the parser work.", todo_clear(), None),
        (task_clear(), TODO_BODY, None),
        (task_clear(), todo_keep(), TODO_BODY),
        (task_clear(), todo_keep(), "## Remaining\n- run the gate\n"),
        ("Resume the parser work.", TODO_BODY, None),
    ],
    ids=[
        "task-body",
        "todo-body",
        "todo-kept-with-body",
        "todo-kept-under-heading",
        "both",
    ],
)
def test_continue_true_is_legal_when_either_half_has_a_body(
    tmp_path: Path, task: object, todo: object, todo_was: str | None
) -> None:
    repo = make_repo(tmp_path)
    seed_frame(repo, None, todo_was)
    result = run_checkpoint(repo, clear_continue_payload(task, todo, cont=True))
    assert result.returncode == 0, result.stderr
    assert (repo / ".claude" / "autodrive").read_text().endswith(f"\n{CONTINUATION}\n")


@pytest.mark.parametrize("todo", [todo_clear(), todo_keep()], ids=["clear", "keep"])
def test_precompact_continue_true_needs_no_file_the_summary_carries_the_task(
    tmp_path: Path, todo: object
) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": True,
        "continue": True,
        "todo": todo,
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0, result.stderr
    assert (repo / ".claude" / "autodrive").read_text().endswith(f"\n{CONTINUATION}\n")


# --- the legal combinations and the sentinel's bytes ---


def test_handoff_clear_true_no_continuation(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (
        repo / ".claude" / "autodrive"
    ).read_text() == "armed sess-checkpoint\nclear\n/rename A Title\n/clear\n"
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_handoff_clear_true_with_continuation(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": True,
        "task": task_clear(),
        "todo": "- run the gate\n",
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == (
        f"armed sess-checkpoint\nclear\n/rename A Title\n/clear\n{CONTINUATION}\n"
    )
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_precompact_compact_false_two_line_marker(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": False,
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (
        repo / ".claude" / "autodrive"
    ).read_text() == "armed sess-checkpoint\ncompact\n"


def test_precompact_compact_true_no_continuation_bare_compact(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": True,
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (
        repo / ".claude" / "autodrive"
    ).read_text() == "armed sess-checkpoint\ncompact\n/compact\n"
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_precompact_compact_true_with_continuation(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": True,
        "continue": True,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == (
        f"armed sess-checkpoint\ncompact\n/compact\n{CONTINUATION}\n"
    )
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_precompact_focus_directive_no_continuation(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": "keep the parser work",
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == (
        "armed sess-checkpoint\ncompact\n/compact keep the parser work\n"
    )
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_precompact_focus_directive_and_continuation_both_carried(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": "keep the parser work",
        "continue": True,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == (
        f"armed sess-checkpoint\ncompact\n/compact keep the parser work\n"
        f"{CONTINUATION}\n"
    )
    assert read_back_drive(repo / ".claude" / "autodrive")
