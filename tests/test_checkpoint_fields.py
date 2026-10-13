"""Tests for scripts/checkpoint.py (handoff-checkpoint) — schema validation of
the `task` and `todo` fields (action vocabulary, null or absent) and of the
closed top-level key set.

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

from pathlib import Path

import pytest
from conftest import (
    make_repo,
    run_checkpoint,
    task_clear,
    todo_keep,
)

pytestmark = pytest.mark.usefixtures("_session_id")


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
