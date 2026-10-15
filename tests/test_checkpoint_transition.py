"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the transition fields
(`clear`, `compact`, `continue`) and the sentinel `.claude/autodrive` they
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


# ==========================================================================
# The transition and the continuation
# ==========================================================================


def test_clear_missing_under_handoff_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "clear" in result.stderr


def test_clear_not_boolean_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": "yes",
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "clear" in result.stderr


def test_clear_present_under_precompact_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "clear": True,
        "compact": False,
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "clear" in result.stderr


def test_compact_missing_under_precompact_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "compact" in result.stderr


def test_compact_present_under_handoff_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "compact": True,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "compact" in result.stderr


def test_compact_neither_boolean_nor_string_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": ["focus"],
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "compact" in result.stderr


def test_empty_compact_directive_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": "",
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "compact" in result.stderr


def test_multiline_compact_directive_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": "keep the parser\nand the tests",
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "compact" in result.stderr


def test_continue_missing_errors_at_either_boundary(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": True,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr

    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": True,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr


def test_the_continuation_is_one_line_the_drive_will_not_run_as_a_command() -> None:
    assert CONTINUATION
    assert CONTINUATION.strip() == CONTINUATION
    assert len(CONTINUATION.splitlines()) == 1
    assert not CONTINUATION.startswith("/")


# --- `continue` is a boolean; `true` needs a carried-out transition ---

# Every boundary the checkpoint knows, driven or not.
BOUNDARIES: dict[str, dict[str, object]] = {
    "clear": {"skill": "handoff", "rename": "T", "clear": True},
    "no-clear": {"skill": "handoff", "rename": "T", "clear": False},
    "compact": {"skill": "precompact", "compact": True},
    "compact-focus": {"skill": "precompact", "compact": "keep the parser work"},
    "no-compact": {"skill": "precompact", "compact": False},
}
DRIVEN = ["clear", "compact", "compact-focus"]
NOT_DRIVEN = ["no-clear", "no-compact"]


def boundary_payload(boundary: str, cont: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "commit": "without-commit",
        "continue": cont,
        "todo": todo_keep(),
        **BOUNDARIES[boundary],
    }
    if payload["skill"] == "handoff":
        payload["task"] = task_clear()
    return payload


@pytest.mark.parametrize("boundary", BOUNDARIES)
@pytest.mark.parametrize(
    "value",
    [None, CONTINUATION, "", "pick up per the task file", 0, 1, 1.5, [], {}],
    ids=["null", "string", "empty", "prose", "zero", "one", "float", "list", "object"],
)
def test_continue_that_is_not_a_boolean_errors(
    tmp_path: Path, boundary: str, value: object
) -> None:
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, boundary_payload(boundary, value))
    assert result.returncode == 2
    assert "continue" in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()


@pytest.mark.parametrize("boundary", NOT_DRIVEN)
def test_continue_true_against_a_transition_not_carried_out_errors(
    tmp_path: Path, boundary: str
) -> None:
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, boundary_payload(boundary, cont=True))
    assert result.returncode == 2
    assert "continue" in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()


@pytest.mark.parametrize("boundary", [*DRIVEN, *NOT_DRIVEN])
def test_continue_false_is_legal_at_every_boundary(
    tmp_path: Path, boundary: str
) -> None:
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, boundary_payload(boundary, cont=False))
    assert result.returncode == 0, result.stderr
    assert read_back_drive(repo / ".claude" / "autodrive")


@pytest.mark.parametrize("boundary", DRIVEN)
def test_continue_true_is_legal_when_the_transition_is_carried_out(
    tmp_path: Path, boundary: str
) -> None:
    repo = make_repo(tmp_path)
    (repo / "TODO.md").write_text("- run the gate\n")
    result = run_checkpoint(repo, boundary_payload(boundary, cont=True))
    assert result.returncode == 0, result.stderr
    assert read_back_drive(repo / ".claude" / "autodrive")


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


# Every character Python's `str.splitlines` breaks on: what the TUI or the
# sentinel's line-wise read could take for the end of a line, submitting the
# rest early or shifting the lines below it. `\n` alone was rejected before.
LINE_BREAKS = {
    "lf": "\n",
    "cr": "\r",
    "vt": "\x0b",
    "ff": "\x0c",
    "fs": "\x1c",
    "gs": "\x1d",
    "rs": "\x1e",
    "nel": "\x85",
    "ls": " ",
    "ps": " ",
}


@pytest.mark.parametrize("brk", LINE_BREAKS.values(), ids=LINE_BREAKS.keys())
def test_compact_directive_with_any_line_break_errors(tmp_path: Path, brk: str) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": f"keep the parser{brk}and the tests",
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "compact" in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()
