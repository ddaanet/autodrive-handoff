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
    task_content,
    todo_content,
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
        "task": task_content("## Current task\n\nbody\n"),
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
        "todo": todo_keep(),
    }
    assert run_checkpoint(repo, payload).returncode == 0
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "T",
        "clear": False,
        "continue": None,
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
            "continue": None,
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
        "continue": None,
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
        "continue": None,
        "todo": todo_keep(),
        "rename": value,
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "rename" in result.stderr
    assert "precompact" in result.stderr


@pytest.mark.parametrize(
    "value",
    [task_content("## Current task\n\nreplacement\n"), task_clear(), None],
    ids=["content", "clear", "null"],
)
def test_task_present_under_precompact_errors(tmp_path: Path, value: object) -> None:
    """`task` is forbidden under precompact by key presence, whatever its value.

    The pre-existing frame and the absent sentinel pin where the check runs: a
    payload rejected after the task half was applied would pass the message
    assertions and still replace or remove the file.
    """
    repo = make_repo(tmp_path)
    stale = "## Current task\n\nIMPORTANT UNSAVED\n"
    (repo / "TASK.md").write_text(stale)
    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": False,
        "continue": None,
        "todo": todo_keep(),
        "task": value,
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "task" in result.stderr
    assert 'forbidden when skill is "precompact"' in result.stderr
    assert (repo / "TASK.md").read_text() == stale
    assert not (repo / ".claude" / "autodrive").exists()


@pytest.mark.parametrize(
    "existed", [True, False], ids=["pre_existing", "never_existed"]
)
def test_precompact_without_task_leaves_no_task_file(
    tmp_path: Path, *, existed: bool
) -> None:
    """The removal runs whether or not there is a file, and is no error without
    one.

    The todo half writes in the same call, so a pass is not a run that stopped
    before the task half.
    """
    repo = make_repo(tmp_path)
    if existed:
        (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    todo = "## Remaining\n\n- an item\n"
    result = run_checkpoint(repo, precompact_payload("with-commit", todo_content(todo)))
    assert result.returncode == 0
    assert result.stderr == ""
    assert not (repo / "TASK.md").exists()
    assert (repo / "TODO.md").read_text() == todo


def test_precompact_task_removal_leaves_kept_todo_byte_identical(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    todo = "## Remaining\n\n- keep me\n"
    (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    (repo / "TODO.md").write_text(todo)
    result = run_checkpoint(repo, precompact_payload("with-commit", todo_keep()))
    assert result.returncode == 0
    assert not (repo / "TASK.md").exists()
    assert (repo / "TODO.md").read_text() == todo


def test_precompact_task_removal_with_todo_content_writes_the_todo(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    todo = "## Remaining\n\n- fresh item\n"
    (repo / "TASK.md").write_text("## Current task\n\nstale\n")
    (repo / "TODO.md").write_text("## Remaining\n\n- old\n")
    result = run_checkpoint(repo, precompact_payload("with-commit", todo_content(todo)))
    assert result.returncode == 0
    assert not (repo / "TASK.md").exists()
    assert (repo / "TODO.md").read_text() == todo


@pytest.mark.parametrize("value", [{"title": "Fix parser"}, 42, ["A Title"], True])
def test_rename_not_a_string_errors(tmp_path: Path, value: object) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "clear": False,
        "continue": None,
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
        "continue": None,
        "todo": todo_keep(),
    }
    assert run_checkpoint(repo, payload).returncode == 0
