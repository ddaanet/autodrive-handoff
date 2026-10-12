"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the session root
checkpoint.py takes from HANDOFF_ROOT, and the schema validation (FR2) of the
JSON payload on stdin: the closed key set, each required field, each literal and
tagged union.

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


@pytest.mark.parametrize(
    ("field", "value", "reason"),
    [
        ("task", {"action": "emty"}, 'got "emty"'),
        ("todo", {"action": "emty"}, 'got "emty"'),
        ("task", {"action": "keep"}, 'got "keep"'),
        (
            "task",
            {"action": "edit", "old_string": "a", "new_string": "b"},
            'got "edit"',
        ),
        ("task", {}, 'action: required, a content string or {"action": "clear"}'),
        (
            "todo",
            {},
            'action: required, a content string or "clear", "keep" or "edit"',
        ),
        ("task", {"action": None}, 'must be "clear", got null'),
        (
            "todo",
            {"action": None},
            'must be "clear", "keep" or "edit", got null',
        ),
        ("task", {"action": True}, 'must be "clear", got boolean'),
        ("todo", {"action": 5}, "got number"),
        (
            "task",
            {"action": "clear", "content": "IMPORTANT UNSAVED"},
            'unknown key "content"',
        ),
        (
            "todo",
            {"action": "keep", "content": "## Remaining\n\n- x\n"},
            'unknown key "content"',
        ),
        (
            "todo",
            {"action": "clear", "old_string": "a"},
            'unknown key "old_string"',
        ),
        (
            "todo",
            {"action": "edit", "old_string": "a", "new_string": "b", "content": "x"},
            'unknown key "content"',
        ),
        ("task", 42, "got number"),
        ("todo", 42, "got number"),
        (
            "todo",
            {"action": "edit", "new_string": "b"},
            'old_string: required for {"action": "edit"}',
        ),
        (
            "todo",
            {"action": "edit", "old_string": "a"},
            'new_string: required for {"action": "edit"}',
        ),
        (
            "todo",
            {"action": "edit", "old_string": 5, "new_string": "b"},
            "old_string: must be a string, got number",
        ),
        (
            "todo",
            {"action": "edit", "old_string": "a", "new_string": None},
            "new_string: must be a string, got null",
        ),
    ],
    ids=[
        "task_unknown_action",
        "todo_unknown_action",
        "task_keep_rejected",
        "task_edit_rejected",
        "task_no_action_key",
        "todo_no_action_key",
        "task_null_action",
        "todo_null_action",
        "task_boolean_action",
        "todo_number_action",
        "task_clear_with_unknown_key",
        "todo_keep_with_unknown_key",
        "todo_clear_with_edit_key",
        "todo_edit_with_unknown_key",
        "task_not_string_or_object",
        "todo_not_string_or_object",
        "todo_edit_missing_old_string",
        "todo_edit_missing_new_string",
        "todo_edit_old_string_not_a_string",
        "todo_edit_new_string_not_a_string",
    ],
)
def test_task_or_todo_action_vocabulary_errors_naming_field(
    tmp_path: Path, field: str, value: object, reason: str
) -> None:
    """Everything outside the union is a named error.

    Both fields dispatch on an `action` key, and `edit`'s own required keys
    are checked by the same dispatch: an unknown action, a missing `action`
    key, a value that is neither string nor object, `task` receiving a
    `todo`-only action (`keep`, `edit`), and `edit` missing — or mistyping —
    either required key independently: each exits 2 naming the offending field
    and its own reason. The two mistyped rows are what keeps `edit` from being
    the one arm of the union that types nothing: every other arm's content is
    a checked string, and an unchecked one reaches `edited_body`'s
    `content.count(old)` as a TypeError traceback, which exits 1 and names no
    field.

    The `action` key itself is checked by key presence, not by truthiness:
    an absent one is `required` and names the whole vocabulary — that branch
    is what an out-of-date producer sending the retired
    `{"file_path": …, "content": …}` shape hits, so it has to say what to
    write instead — while an explicit `null` is a value like any other and
    reports what it is. Non-string values render as their JSON type, never a
    Python repr (`got boolean`, not `got "True"`).

    An action object carrying any other key is rejected too. Ignoring it is
    the defect class the union closed one level up: an agent told
    `must be "clear", got "write"` that corrects only the action leaves its
    `content` behind, and the frame is removed with nothing said.

    `task_edit_rejected`, `todo_edit_missing_old_string` and
    `todo_edit_missing_new_string` restate, in action vocabulary,
    `test_task_with_old_string_new_string_errors` /
    `test_todo_only_new_string_errors` / `test_todo_only_old_string_errors` —
    the same contract reached through the dispatch instead of through
    key-combination sniffing on a bare object. Each `reason` pins that
    shape's own diagnostic and no other: an `edit` missing a key must say
    `required for`, not the `does not exist` / `not found` / `ambiguous` the
    same `todo.old_string` namespace also carries.
    """
    repo = make_repo(tmp_path)
    payload: dict[str, object] = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    payload[field] = value
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert field in result.stderr
    assert reason in result.stderr


def test_malformed_json_errors_naming_payload(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, "{not valid json")
    assert result.returncode == 2
    assert "payload" in result.stderr


def test_top_level_unknown_key_errors_under_handoff(tmp_path: Path) -> None:
    """A superfluous top-level key is a named error, not a silent no-op.

    M3's residual: `_reject_unknown_keys` closes this one level down, inside
    each action object, but nothing compared the payload's own key set — a typo
    like "bogus" (never "tasks"/"todos", which read as a plausible intentional
    key and would not guard against a vacuous pass) sailed through untouched.
    `"bogus"` cannot appear in any other message this otherwise-well-formed
    handoff payload could produce, so a pass here is not an accident of some
    unrelated diagnostic.

    The payload's task half is `clear` over a pre-existing frame, so the row
    also pins where the check runs: rejected before anything is applied, the
    frame survives byte-identical and no sentinel is composed. Moved below the
    two halves, the same payload would remove the file and report an error
    naming only the key.
    """
    repo = make_repo(tmp_path)
    stale = "## Current task\n\nIMPORTANT UNSAVED\n"
    (repo / "TASK.md").write_text(stale)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
        "bogus": "x",
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "bogus" in result.stderr
    assert (repo / "TASK.md").is_file()
    assert (repo / "TASK.md").read_text() == stale
    assert not (repo / ".claude" / "autodrive").exists()


def test_top_level_unknown_key_errors_under_precompact(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": False,
        "continue": None,
        "todo": todo_keep(),
        "bogus": "x",
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "bogus" in result.stderr


def test_top_level_unknown_key_errors_under_autoname(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {"skill": "autoname", "rename": "A Side Conversation", "bogus": "x"}
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "bogus" in result.stderr


@pytest.mark.parametrize(
    ("skill", "field", "shape", "reason"),
    [
        pytest.param(skill, field, shape, reason, id=f"{field}_{shape}-{skill}")
        for skill in ("handoff", "precompact")
        for field, shape, reason in (
            ("task", "null", "got null"),
            ("task", "absent", "required"),
            ("todo", "null", "got null"),
            ("todo", "absent", "required"),
        )
        # `task` is required only under handoff; precompact forbids it, and
        # test_task_present_under_precompact_errors owns that side.
        if not (skill == "precompact" and field == "task")
    ],
)
def test_task_or_todo_null_or_absent_errors_naming_field(
    tmp_path: Path, skill: str, field: str, shape: str, reason: str
) -> None:
    """`todo` is required at both boundaries and `task` under handoff, by key
    presence, with no default.

    `null` and an absent key are distinct, named errors on each field — the
    defect being fixed is an agent choosing a spelling that silently did the
    wrong thing, so both wrong spellings must fail loudly with their own
    reason, and neither may write its target file before failing. Run at both
    boundaries: the rule is main's `skill in ("handoff", "precompact")` gate,
    and a gate naming only one of them is the way it breaks.
    """
    repo = make_repo(tmp_path)
    payload: dict[str, object] = {
        "skill": skill,
        "commit": "with-commit",
        "continue": None,
        "todo": todo_keep(),
    }
    if skill == "handoff":
        payload["task"] = task_clear()
    if skill == "handoff":
        payload["rename"] = "T"
        payload["clear"] = False
    else:
        payload["compact"] = False
    if shape == "null":
        payload[field] = None
    else:
        del payload[field]
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert field in result.stderr
    assert reason in result.stderr
    target = "TASK.md" if field == "task" else "TODO.md"
    assert not (repo / target).exists()
