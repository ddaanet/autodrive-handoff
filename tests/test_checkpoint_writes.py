"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the write semantics
(FR5) of `task` and `todo`: content written as given, `clear`, `keep` and `edit`
on the two root files, and the emptiness rule (`is_empty_body` and its CLI, read
by the bash side).

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

import subprocess
import sys
from pathlib import Path

import _checkpoint_lib as lib
import pytest
from conftest import (
    REPO_ROOT,
    frame_payload,
    make_repo,
    precompact_payload,
    run_checkpoint,
    task_clear,
    todo_clear,
    todo_edit,
    todo_keep,
)

pytestmark = pytest.mark.usefixtures("_session_id")


# ==========================================================================
# Write semantics (FR5)
# ==========================================================================


def test_task_write_creates_file(tmp_path: Path) -> None:
    """Handoff only: precompact forbids `task`, so it never writes one."""
    repo = make_repo(tmp_path)
    content = "## Current task\n\nreal content\n"
    result = run_checkpoint(repo, frame_payload(content))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


def test_task_write_replaces_a_pre_existing_file_whole(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    (repo / "TASK.md").write_text("## Current task\n\nstale, and longer\n")
    content = "## Current task\n\nfresh\n"
    result = run_checkpoint(repo, frame_payload(content))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


@pytest.mark.parametrize(
    "existed", [True, False], ids=["pre_existing", "never_existed"]
)
def test_task_clear_leaves_no_file(tmp_path: Path, *, existed: bool) -> None:
    """`clear` removes the file, and is no error when there is none.

    The todo half writes in the same call, so a pass is not a run that stopped
    before the task half.
    """
    repo = make_repo(tmp_path)
    if existed:
        (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    todo = "## Remaining\n\n- an item\n"
    result = run_checkpoint(repo, frame_payload(task_clear(), todo))
    assert result.returncode == 0
    assert result.stderr == ""
    assert not (repo / "TASK.md").exists()
    assert (repo / "TODO.md").read_text() == todo


@pytest.mark.parametrize(
    "existed", [True, False], ids=["pre_existing", "never_existed"]
)
def test_todo_clear_leaves_no_file(tmp_path: Path, *, existed: bool) -> None:
    """Mirror of the task row, and the only cover of `todo`'s destructive arm.

    The task half writes in the same call, so a pass is not a run that stopped
    before the todo half.
    """
    repo = make_repo(tmp_path)
    if existed:
        (repo / "TODO.md").write_text("## Remaining\n\n- stale\n")
    task = "## Current task\n\nlive\n"
    result = run_checkpoint(repo, frame_payload(task, todo_clear()))
    assert result.returncode == 0
    assert result.stderr == ""
    assert not (repo / "TODO.md").exists()
    assert (repo / "TASK.md").read_text() == task


@pytest.mark.parametrize("field", ["task", "todo"])
@pytest.mark.parametrize(
    "body",
    ["## Current task\n\n## Open decisions\n", "   ", ""],
    ids=["headings_only", "whitespace_only", "empty_string"],
)
def test_content_with_no_body_is_written_as_given(
    tmp_path: Path, field: str, body: str
) -> None:
    """A content string is a write whatever it holds: only `clear` removes.

    Each body is one the emptiness rule reads as empty (test_is_empty_body),
    written over a pre-existing file so that a removal and a skipped write would
    both show.
    """
    repo = make_repo(tmp_path)
    target = repo / ("TASK.md" if field == "task" else "TODO.md")
    target.write_text("## Remaining\n\nstale body\n")
    if field == "task":
        payload = frame_payload(body)
    else:
        payload = frame_payload(task_clear(), body)
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert target.read_text() == body


@pytest.mark.parametrize("skill", ["handoff", "precompact"])
def test_todo_write_creates_file(tmp_path: Path, skill: str) -> None:
    """Run at both boundaries: the `precompact` half proves `main` applies the
    payload it validates, not merely validates it.

    A gate narrowed to `handoff` alone would still validate a precompact payload
    correctly and then skip the write.
    """
    repo = make_repo(tmp_path)
    content = "## Remaining\n\n- an item\n"
    if skill == "handoff":
        payload = frame_payload(task_clear(), content)
    else:
        payload = precompact_payload("with-commit", content)
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / "TODO.md").read_text() == content


def test_task_and_todo_both_written(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    task = "## Current task\n\nbody\n"
    todo = "## Remaining\n\n- x\n"
    result = run_checkpoint(repo, frame_payload(task, todo))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == task
    assert (repo / "TODO.md").read_text() == todo


def test_todo_edit_and_task_clear_both_apply(tmp_path: Path) -> None:
    """Positive twin of the three surviving-task-file negatives below, over the
    same pre-existing-task-file fixture: only the todo `old_string`'s match
    count moves, and both halves apply."""
    repo = make_repo(tmp_path)
    task_path = repo / "TASK.md"
    task_path.write_text("## Current task\n\nrecognisable\n")
    (repo / "TODO.md").write_text("## Remaining\n\n- finish A\n- finish B\n")
    result = run_checkpoint(
        repo, frame_payload(task_clear(), todo_edit("- finish A\n", ""))
    )
    assert result.returncode == 0
    assert not task_path.exists()
    assert (repo / "TODO.md").read_text() == "## Remaining\n\n- finish B\n"


def test_todo_edit_striking_the_last_item_leaves_the_headings(
    tmp_path: Path,
) -> None:
    """An `edit` writes what the replacement leaves, a list with no item
    included: the file stays, and standing it down is `clear`'s to say."""
    repo = make_repo(tmp_path)
    (repo / "TODO.md").write_text("## Remaining\n\n- only item\n")
    result = run_checkpoint(
        repo, frame_payload(task_clear(), todo_edit("- only item\n", ""))
    )
    assert result.returncode == 0
    assert (repo / "TODO.md").read_text() == "## Remaining\n\n"


def test_todo_edit_old_string_absent_errors_task_file_survives(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    task_path = repo / "TASK.md"
    task_before = "## Current task\n\nrecognisable\n"
    task_path.write_text(task_before)
    todo_before = "## Remaining\n\n- keep this\n"
    (repo / "TODO.md").write_text(todo_before)
    result = run_checkpoint(
        repo, frame_payload(task_clear(), todo_edit("- not present", "- x"))
    )
    assert result.returncode == 2
    assert "todo.old_string" in result.stderr
    assert "not found" in result.stderr
    assert (repo / "TODO.md").read_text() == todo_before
    assert task_path.read_text() == task_before
    assert not (repo / ".claude" / "autodrive").exists()


def test_todo_edit_old_string_ambiguous_errors_task_file_survives(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    task_path = repo / "TASK.md"
    task_before = "## Current task\n\nrecognisable\n"
    task_path.write_text(task_before)
    todo_before = "## Remaining\n\n- dup\n- dup\n"
    (repo / "TODO.md").write_text(todo_before)
    result = run_checkpoint(
        repo, frame_payload(task_clear(), todo_edit("- dup", "- single"))
    )
    assert result.returncode == 2
    assert "todo.old_string" in result.stderr
    assert "ambiguous" in result.stderr
    assert (repo / "TODO.md").read_text() == todo_before
    assert task_path.read_text() == task_before
    assert not (repo / ".claude" / "autodrive").exists()


def test_todo_edit_requested_file_missing_errors_task_file_survives(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    task_path = repo / "TASK.md"
    task_before = "## Current task\n\nrecognisable\n"
    task_path.write_text(task_before)
    result = run_checkpoint(repo, frame_payload(task_clear(), todo_edit("a", "b")))
    assert result.returncode == 2
    assert "todo.old_string" in result.stderr
    assert "TODO.md does not exist" in result.stderr
    assert task_path.read_text() == task_before
    assert not (repo / "TODO.md").exists()
    assert not (repo / ".claude" / "autodrive").exists()


def test_todo_edit_old_string_absent_errors_task_file_not_created(
    tmp_path: Path,
) -> None:
    """The mirror of the three rows above: a task half that would write.

    Each of those carries task_clear(), so together they pin that a failing todo
    half does not delete the task file. None of them reaches the opposite sign:
    a task half with content, which must not reach disk either.
    """
    repo = make_repo(tmp_path)
    task_path = repo / "TASK.md"
    todo_before = "## Remaining\n\n- keep this\n"
    (repo / "TODO.md").write_text(todo_before)
    payload = frame_payload(
        "## Current task\n\nwould have been written\n",
        todo_edit("- not present", "- x"),
    )
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "todo.old_string" in result.stderr
    assert "not found" in result.stderr
    assert not task_path.exists()
    assert (repo / "TODO.md").read_text() == todo_before
    assert not (repo / ".claude" / "autodrive").exists()


@pytest.mark.parametrize(
    "before",
    ["## Remaining\n\n- untouched\n", "## Remaining\n", None],
    ids=["a_list", "headings_only", "no_file"],
)
def test_todo_keep_leaves_the_list_as_it_is(tmp_path: Path, before: str | None) -> None:
    """`keep` neither rewrites, removes nor creates, whatever is there.

    The task half writes in the same call, so a pass is not a run that stopped
    before the todo half.
    """
    repo = make_repo(tmp_path)
    todo = repo / "TODO.md"
    if before is not None:
        todo.write_text(before)
    task = "## Current task\n\nreal content\n"
    result = run_checkpoint(repo, frame_payload(task, todo_keep()))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == task
    if before is None:
        assert not todo.exists()
    else:
        assert todo.read_text() == before


# ==========================================================================
# The emptiness rule (`is_empty_body`, and its CLI for the bash side)
# ==========================================================================


@pytest.mark.parametrize(
    ("content", "empty"),
    [
        ("", True),
        ("\n\n", True),
        ("   ", True),
        ("  \n\t\n", True),
        ("## Current task\n\n## Open decisions\n", True),
        ("## Remaining\n", True),
        ("#\n", True),
        ("   ## Current task\n", True),
        ("## Remaining\n\n- an item\n", False),
        ("#!/bin/sh\n", False),
        ("#tag\n", False),
        ("####### seven\n", False),
        ("    # run the migration first\n", False),
    ],
    ids=[
        "empty_string",
        "blank_lines",
        "spaces_alone",
        "whitespace_lines",
        "headings_only",
        "one_heading",
        "bare_hash",
        "three_spaces_indent_a_heading",
        "a_list",
        "shebang",
        "hash_without_space",
        "seven_hashes",
        "four_spaces_open_a_code_block",
    ],
)
def test_is_empty_body(content: str, *, empty: bool) -> None:
    """Empty is no line left once blank lines and ATX headings are set aside.

    Blank is judged on the line without its trailing whitespace, so spaces alone
    are blank. A heading is markdown's own: 1-6 `#` then whitespace or the
    line's end, indented by at most three spaces. `#!/bin/sh`, `#tag` and seven
    `#` are content, and so is a `# comment` at four spaces, which is a code
    block's line.
    """
    assert lib.is_empty_body(content) is empty


@pytest.mark.parametrize(
    ("argv", "stdin", "code"),
    [
        (["--has-body"], "## Remaining\n", 1),
        (["--has-body"], "## Remaining\n\n- an item\n", 0),
        (["--is-empty-body"], "## Remaining\n\n- an item\n", 2),
        (["--bogus"], "", 2),
        ([], "", 2),
    ],
    ids=["empty", "has_a_body", "retired_flag", "unknown_flag", "no_flag"],
)
def test_has_body_cli_exit_code(argv: list[str], stdin: str, code: int) -> None:
    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "_checkpoint_lib.py"), *argv],
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == code
