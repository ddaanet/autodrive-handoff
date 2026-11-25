"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the session root the
checkpoint takes from HANDOFF_ROOT, and the schema validation (FR2) of the
envelope: each required field, each literal, the `skill` enum and `rename`.

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import (
    CHECKPOINT,
    make_repo,
    precompact_payload,
    run_checkpoint,
    task_clear,
    todo_keep,
)

pytestmark = pytest.mark.usefixtures("_session_id")


# ==========================================================================
# The session root
# ==========================================================================


def test_handoff_root_unset_refuses(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    env = dict(os.environ)
    env.pop("HANDOFF_ROOT", None)
    env.pop("CLAUDE_PROJECT_DIR", None)
    result = subprocess.run(
        [sys.executable, str(CHECKPOINT)],
        cwd=repo,
        input=json.dumps(payload),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 2
    assert "HANDOFF_ROOT" in result.stderr


def test_handoff_root_names_non_directory_refuses(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload, root=repo / "does-not-exist")
    assert result.returncode == 2
    assert "HANDOFF_ROOT" in result.stderr


def test_drifted_cwd_writes_injected_root_never_cwd(tmp_path: Path) -> None:
    root = make_repo(tmp_path, "launch")
    elsewhere = make_repo(tmp_path, "elsewhere")
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "continue": False,
        "task": "## Current task\n\nbody\n",
        "todo": todo_keep(),
    }
    result = run_checkpoint(elsewhere, payload, root=root)
    assert result.returncode == 0
    assert (root / "TASK.md").is_file()
    assert (root / ".claude" / "autodrive").is_file()
    assert not (elsewhere / "TASK.md").exists()
    assert not (elsewhere / ".claude" / "autodrive").exists()


# ==========================================================================
# Schema validation (FR2)
# ==========================================================================


def test_skill_missing_errors_naming_skill(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "commit": "with-commit",
        "rename": "T",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "skill" in result.stderr


def test_skill_unknown_value_errors_naming_skill(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "bogus",
        "commit": "with-commit",
        "rename": "T",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "skill" in result.stderr


def test_commit_missing_errors_naming_commit(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "rename": "T",
        "clear": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "commit" in result.stderr


def test_commit_unknown_value_errors_naming_commit(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "maybe",
        "rename": "T",
        "clear": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "commit" in result.stderr


def test_rename_missing_under_handoff_errors_naming_rename(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "clear": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "rename" in result.stderr


def test_each_of_two_skill_values_accepted(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    assert run_checkpoint(repo, payload).returncode == 0
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "T",
        "clear": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    assert run_checkpoint(repo, payload).returncode == 0


def test_retired_driven_skill_names_rejected(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    for s in ("handoff-continue", "compact-continue"):
        payload = {
            "skill": s,
            "commit": "without-commit",
            "clear": False,
            "continue": False,
            "task": task_clear(),
            "todo": todo_keep(),
        }
        result = run_checkpoint(repo, payload)
        assert result.returncode == 2
        assert "skill" in result.stderr
        assert s in result.stderr


def test_rename_present_under_precompact_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "rename": "Not Allowed",
        "compact": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "rename" in result.stderr
    assert "precompact" in result.stderr


@pytest.mark.parametrize("value", ["", None])
def test_empty_or_null_rename_under_precompact_errors(
    tmp_path: Path, value: object
) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
        "rename": value,
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "rename" in result.stderr
    assert "precompact" in result.stderr


def test_precompact_task_content_writes_the_task_file(tmp_path: Path) -> None:
    """`task` is taken at the compact boundary as at the clear one: a content
    string replaces the file whole."""
    repo = make_repo(tmp_path)
    (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    task = "## Current task\n\nrewire the parser; next, run its tests\n"
    result = run_checkpoint(repo, precompact_payload("with-commit", task=task))
    assert result.returncode == 0, result.stderr
    assert (repo / "TASK.md").read_text() == task


def test_precompact_task_over_the_cap_errors_and_writes_nothing(
    tmp_path: Path,
) -> None:
    """FR13's shape holds at the compact boundary too, checked before any
    write."""
    repo = make_repo(tmp_path)
    stale = "## Current task\n\nstale\n"
    (repo / "TASK.md").write_text(stale)
    task = "## Current task\n\n" + "a" * 1001 + "\n"
    result = run_checkpoint(repo, precompact_payload("with-commit", task=task))
    assert result.returncode == 2
    assert "the limit is 1000" in result.stderr
    assert (repo / "TASK.md").read_text() == stale
    assert not (repo / ".claude" / "autodrive").exists()


@pytest.mark.parametrize(
    "existed", [True, False], ids=["pre_existing", "never_existed"]
)
def test_precompact_task_clear_leaves_no_task_file(
    tmp_path: Path, *, existed: bool
) -> None:
    """`{"action": "clear"}` removes the file whether or not there is one, and
    is no error without one.

    The todo half writes in the same call, so a pass is not a run that stopped
    before the task half.
    """
    repo = make_repo(tmp_path)
    if existed:
        (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    todo = "## Remaining\n\n- an item\n"
    result = run_checkpoint(
        repo, precompact_payload("with-commit", todo, task=task_clear())
    )
    assert result.returncode == 0
    assert result.stderr == ""
    assert not (repo / "TASK.md").exists()
    assert (repo / "TODO.md").read_text() == todo


def test_precompact_without_task_errors_and_keeps_the_task_file(
    tmp_path: Path,
) -> None:
    """An absent `task` is a named error, not a removal: the file and the todo
    stay as they were and no sentinel is composed."""
    repo = make_repo(tmp_path)
    task = "## Current task\n\nIMPORTANT UNSAVED\n"
    todo = "## Remaining\n\n- keep me\n"
    (repo / "TASK.md").write_text(task)
    (repo / "TODO.md").write_text(todo)
    payload = precompact_payload("with-commit", "## Remaining\n\n- new\n")
    del payload["task"]
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "task: required" in result.stderr
    assert (repo / "TASK.md").read_text() == task
    assert (repo / "TODO.md").read_text() == todo
    assert not (repo / ".claude" / "autodrive").exists()


@pytest.mark.parametrize(
    "task", [task_clear(), "## Current task\n\nfresh task\n"], ids=["clear", "content"]
)
def test_precompact_task_write_leaves_kept_todo_byte_identical(
    tmp_path: Path, task: object
) -> None:
    """`todo: keep` leaves an existing TODO.md byte-identical while the task
    half of the same call writes or removes TASK.md."""
    repo = make_repo(tmp_path)
    todo = "## Remaining\n\n- keep me\n\n  trailing  \n"
    (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    (repo / "TODO.md").write_text(todo)
    result = run_checkpoint(
        repo, precompact_payload("with-commit", todo_keep(), task=task)
    )
    assert result.returncode == 0, result.stderr
    assert (repo / "TODO.md").read_bytes() == todo.encode()
    if isinstance(task, str):
        assert (repo / "TASK.md").read_text() == task
    else:
        assert not (repo / "TASK.md").exists()


def test_precompact_task_and_todo_content_both_written(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    task = "## Current task\n\nfresh task\n"
    todo = "## Remaining\n\n- fresh item\n"
    (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    (repo / "TODO.md").write_text("## Remaining\n\n- old\n")
    result = run_checkpoint(repo, precompact_payload("with-commit", todo, task=task))
    assert result.returncode == 0, result.stderr
    assert (repo / "TASK.md").read_text() == task
    assert (repo / "TODO.md").read_text() == todo


@pytest.mark.parametrize("value", [{"title": "Fix parser"}, 42, ["A Title"], True])
def test_rename_not_a_string_errors(tmp_path: Path, value: object) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "clear": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
        "rename": value,
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "rename" in result.stderr
    assert not (repo / ".claude" / "autodrive").exists()


def test_precompact_with_rename_omitted_accepted(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": False,
        "continue": False,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    assert run_checkpoint(repo, payload).returncode == 0
