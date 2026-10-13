"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the shape of a `task`
content string: the body cap and the no-list rule (FR13).

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

import subprocess
from pathlib import Path

import pytest
from conftest import (
    frame_payload,
    make_repo,
    prose,
    run_checkpoint,
    task_clear,
)

pytestmark = pytest.mark.usefixtures("_session_id")


# ==========================================================================
# Task shape -- the body cap and the no-list rule on a `task` content string
# ==========================================================================

TASK_BODY_LIMIT = 1000


def assert_task_shape_error(
    result: subprocess.CompletedProcess[str], *facts: str
) -> None:
    """One `task` error line: `facts`, then the sentence on where the rest
    goes."""
    assert result.returncode == 2
    lines = result.stderr.splitlines()
    assert len(lines) == 1
    assert lines[0].startswith("handoff-checkpoint: task: ")
    for fact in facts:
        assert fact in lines[0]
    assert '"todo"' in lines[0]
    assert "one sentence" in lines[0]
    assert "memory" in lines[0]


@pytest.mark.parametrize(
    ("count", "accepted"),
    [(TASK_BODY_LIMIT, True), (TASK_BODY_LIMIT + 1, False)],
    ids=["exactly_the_limit_accepted", "one_over_rejected"],
)
def test_task_body_cap_boundary(tmp_path: Path, count: int, *, accepted: bool) -> None:
    repo = make_repo(tmp_path)
    content = f"## Current task\n\n{prose(count)}\n"
    result = run_checkpoint(repo, frame_payload(content))
    task = repo / "TASK.md"
    if accepted:
        assert result.returncode == 0
        assert task.read_text() == content
    else:
        assert_task_shape_error(
            result,
            "task",
            str(count),
            f"body is {count} characters, the limit is 1000 (headings not counted)",
        )
        assert not task.exists()


@pytest.mark.parametrize(
    "content",
    [
        f"## Current task\n\n{prose(TASK_BODY_LIMIT)}\n\n### Detail\n",
        f"# Title\n## Current task\n{prose(500)}\n### Midway\n{prose(499)}\n",
    ],
    ids=["headings_around_the_body", "heading_splits_the_body"],
)
def test_task_body_cap_does_not_count_headings(tmp_path: Path, content: str) -> None:
    """Both fixtures exceed 1000 characters once heading lines are counted."""
    assert len(content) > TASK_BODY_LIMIT + 10
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(content))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


def test_task_body_cap_ignores_blank_lines_and_whitespace_around_the_body(
    tmp_path: Path,
) -> None:
    content = f"\n\n   \n{prose(TASK_BODY_LIMIT)}\n  \n\n"
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(content))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


@pytest.mark.parametrize(
    ("count", "accepted"),
    [(TASK_BODY_LIMIT, True), (TASK_BODY_LIMIT + 1, False)],
    ids=["1000_characters_are_2000_bytes_accepted", "1001_characters_rejected"],
)
def test_task_body_cap_counts_characters_not_bytes(
    tmp_path: Path, count: int, *, accepted: bool
) -> None:
    content = f"## Current task\n\n{prose(count, 'é')}\n"
    assert len(prose(count, "é").encode()) == 2 * count
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(content))
    if accepted:
        assert result.returncode == 0
        assert (repo / "TASK.md").read_text() == content
    else:
        assert_task_shape_error(result, "task", str(count), "the limit is 1000")


def test_task_hash_without_space_is_body_not_a_heading(tmp_path: Path) -> None:
    """`#tag` is content: with it the body is 1005 characters, without it
    1000."""
    content = f"## Current task\n\n{prose(TASK_BODY_LIMIT)}\n#tag\n"
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(content))
    assert_task_shape_error(
        result, "task", "body is 1005 characters, the limit is 1000"
    )
    assert not (repo / "TASK.md").exists()


@pytest.mark.parametrize(
    ("content", "number", "quote"),
    [
        ("## Current task\n\n- item\n", 3, "- item"),
        ("first prose line\nsecond prose line\n* item\n", 3, "* item"),
        ("intro\n+ item\n", 2, "+ item"),
        ("intro\n1. item\n", 2, "1. item"),
        ("intro\n1) item\n", 2, "1) item"),
        ("intro\n  - item\n", 2, "- item"),
        ("intro\n- one\n- two\n", 2, "- one"),
        (
            "## Current task\n\nintro\n- " + "x" * 60 + "\n",
            4,
            "- " + "x" * 38,
        ),
    ],
    ids=[
        "dash_after_heading_and_blank",
        "star_after_two_prose_lines",
        "plus",
        "numbered_dot",
        "numbered_paren",
        "indented_dash_quote_is_stripped",
        "first_of_two_items_is_named",
        "long_line_quote_cut_to_40",
    ],
)
def test_task_list_item_rejected_naming_its_line(
    tmp_path: Path, content: str, number: int, quote: str
) -> None:
    assert len(quote) <= 40
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(content))
    assert_task_shape_error(result, "task", f'line {number} is a list item ("{quote}")')
    assert result.stderr.count("is a list item") == 1
    assert not (repo / "TASK.md").exists()


@pytest.mark.parametrize(
    "line",
    [
        "**bold** text opens the line",
        "a well - known approach",
        "-flag is set",
        "2026 was the year",
        "3.5 times the size",
    ],
    ids=["bold", "mid_line_hyphen", "marker_without_space", "year", "decimal"],
)
def test_task_lines_that_are_not_list_items_accepted(tmp_path: Path, line: str) -> None:
    content = f"## Current task\n\nintro\n{line}\n"
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(content))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


def test_task_over_the_cap_with_a_list_item_is_one_error_with_both_facts(
    tmp_path: Path,
) -> None:
    content = f"intro\n- item\n{prose(TASK_BODY_LIMIT)}\n"
    count = len(content.strip())
    assert count > TASK_BODY_LIMIT
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(content))
    assert_task_shape_error(
        result,
        'line 2 is a list item ("- item")',
        f"body is {count} characters, the limit is 1000 (headings not counted)",
    )


@pytest.mark.parametrize(
    "content",
    [f"## Current task\n\n{prose(TASK_BODY_LIMIT + 1)}\n", "intro\n- item\n"],
    ids=["over_the_cap", "list_item"],
)
def test_task_shape_failure_writes_nothing(tmp_path: Path, content: str) -> None:
    repo = make_repo(tmp_path)
    task_path = repo / "TASK.md"
    task_before = "## Current task\n\nstale\n"
    task_path.write_text(task_before)
    payload = frame_payload(content, "## Remaining\n\nnext step\n")
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "task" in result.stderr
    assert task_path.read_text() == task_before
    assert not (repo / "TODO.md").exists()
    assert not (repo / ".claude" / "autodrive").exists()


def test_task_clear_is_not_subject_to_the_shape_rules(tmp_path: Path) -> None:
    """Green before the change and after it: `clear` carries no content
    string."""
    repo = make_repo(tmp_path)
    (repo / "TASK.md").write_text(f"- long and listy\n{prose(TASK_BODY_LIMIT + 1)}\n")
    result = run_checkpoint(repo, frame_payload(task_clear()))
    assert result.returncode == 0
    assert result.stderr == ""
    assert not (repo / "TASK.md").exists()
