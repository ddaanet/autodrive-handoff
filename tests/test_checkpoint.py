"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the schema validation,
write semantics, transition/sentinel composition, and directive composition that
live in checkpoint.py + _checkpoint_lib.py. Port of the checkpoint.sh-specific
rows of tests/checkpoint.bats — see docs/changelog/2026-08-10-python-split.md.

inject-checkpoint-root.sh, bin/handoff-approved and the bin/handoff-checkpoint
shim stay bash and stay tested in tests/checkpoint.bats; this file covers only
checkpoint.py's own behavior.
"""

import errno
import json
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

import _checkpoint_lib as lib
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
CHECKPOINT = REPO_ROOT / "scripts" / "checkpoint.py"
LIB = REPO_ROOT / "scripts" / "_lib.sh"

GITLORE_MEMORY_APPROVAL_CLAUSE = (
    "The commit message is a subject line, a blank line, then one paragraph per\n"
    "changed memory file, each opening with a bold prefix naming the file's kind and\n"
    "its tier/slug. Template:\n"
    "\n"
    "    <subject line, no conventional-commit prefix>\n"
    "\n"
    "    **New <tier>/<slug>:** what the fact records, and what prompted writing it\n"
    "    now rather than earlier."
)


@pytest.fixture(autouse=True)
def _session_id(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", "sess-checkpoint")
    monkeypatch.delenv("CLAUDE_PROJECT_DIR", raising=False)


def make_repo(tmp_path: Path, name: str = "repo") -> Path:
    repo = tmp_path / name
    if repo.exists():
        shutil.rmtree(repo)
    (repo / ".claude").mkdir(parents=True)
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    return repo


def make_gitlore_repo(tmp_path: Path, name: str = "glrepo") -> Path:
    repo = tmp_path / name
    if repo.exists():
        shutil.rmtree(repo)
    (repo / "memory").mkdir(parents=True)
    (repo / ".claude").mkdir(parents=True)
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    (repo / ".gitmodules").write_text(
        '[submodule "gitlore-memory"]\n\tpath = memory\n\turl = ./memory\n'
    )
    mem = repo / "memory"
    subprocess.run(["git", "init", "-q"], cwd=mem, check=True)
    (mem / "seed.md").write_text("seed\n")
    subprocess.run(["git", "add", "-A"], cwd=mem, check=True)
    subprocess.run(
        ["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "seed"],
        cwd=mem,
        check=True,
    )
    clause_file = repo / ".gitlore-memory-approval-clause.txt"
    clause_file.write_text(GITLORE_MEMORY_APPROVAL_CLAUSE + "\n")
    subprocess.run(
        ["git", "config", "gitlore.memoryApprovalClauseFile", str(clause_file)],
        cwd=repo,
        check=True,
    )
    return repo


def dirty_memory(repo: Path) -> None:
    (repo / "memory" / "feedback_x.md").write_text("new entry\n")


def add_sdd_ledger(repo: Path, slug: str = "feature-plan") -> None:
    d = repo / ".superpowers" / "sdd" / slug
    d.mkdir(parents=True)
    (repo / ".superpowers" / "sdd" / ".gitignore").write_text("*\n")
    (d / "progress.md").write_text(
        f"# SDD ledger — plan: docs/plans/{slug}.md\n"
        "Task 1: complete (commits abc1234..def5678, review clean)\n"
    )


def add_flat_sdd_ledger(repo: Path) -> None:
    d = repo / ".superpowers" / "sdd"
    d.mkdir(parents=True)
    (d / ".gitignore").write_text("*\n")
    (d / "progress.md").write_text(
        "Task 1: complete (commits abc1234..def5678, review clean)\n"
    )


def add_unidentified_sdd_ledger(repo: Path, slug: str = "ghmem") -> None:
    d = repo / ".superpowers" / "sdd" / slug
    d.mkdir(parents=True)
    (repo / ".superpowers" / "sdd" / ".gitignore").write_text("*\n")
    (d / "progress.md").write_text("# ghmem — progress (C2 COMPLETE)\n")


def task_content(content: str) -> str:
    return content


def task_clear() -> dict[str, str]:
    # Also spelled out in tests/checkpoint.bats' handoff_payload(); the two
    # move together.
    return {"action": "clear"}


def todo_content(content: str) -> str:
    return content


def todo_keep() -> dict[str, str]:
    return {"action": "keep"}


def todo_clear() -> dict[str, str]:
    return {"action": "clear"}


def todo_edit(old: str, new: str) -> dict[str, str]:
    return {"action": "edit", "old_string": old, "new_string": new}


def run_checkpoint(
    repo: Path,
    payload: Mapping[str, object] | str,
    root: Path | None = None,
    *,
    command: Sequence[str] = (sys.executable, str(CHECKPOINT)),
) -> subprocess.CompletedProcess[str]:
    """Run checkpoint.py with cwd=repo, HANDOFF_ROOT=root (default repo).

    `command` replaces the interpreter-and-script argv, for a harness that wraps
    the script.
    """
    env = dict(os.environ)
    env["HANDOFF_ROOT"] = str(root if root is not None else repo)
    env["CLAUDE_CODE_SESSION_ID"] = os.environ.get(
        "CLAUDE_CODE_SESSION_ID", "sess-checkpoint"
    )
    env.pop("CLAUDE_PROJECT_DIR", None)
    text = payload if isinstance(payload, str) else json.dumps(payload)
    return subprocess.run(
        list(command),
        cwd=repo,
        input=text,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def read_back_drive(drive_path: Path) -> bool:
    """Mirror `handoff_drive_read` (bash, unmoved) reading back a sentinel."""
    script = f'source "{LIB}"; handoff_drive_read "{drive_path}"'
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, check=False
    )
    return result.returncode == 0


def drive_state(drive_path: Path) -> tuple[str, str]:
    script = (
        f'source "{LIB}"; handoff_drive_read "{drive_path}" >/dev/null 2>&1; '
        'printf "%s\\n%s\\n" "$DRIVE_STATE" "$DRIVE_OWNER"'
    )
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, check=False
    )
    lines = result.stdout.splitlines()
    return (lines[0] if lines else "", lines[1] if len(lines) > 1 else "")


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


# ==========================================================================
# Write semantics (FR5)
# ==========================================================================


def frame_payload(task: object, todo: object = None) -> dict[str, object]:
    """A `handoff` payload carrying `task` as given and `todo` kept by
    default."""
    return {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "continue": None,
        "task": task,
        "todo": todo_keep() if todo is None else todo,
    }


def test_task_write_creates_file(tmp_path: Path) -> None:
    """Handoff only: precompact forbids `task`, so it never writes one."""
    repo = make_repo(tmp_path)
    content = "## Current task\n\nreal content\n"
    result = run_checkpoint(repo, frame_payload(task_content(content)))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


def test_task_write_replaces_a_pre_existing_file_whole(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    (repo / "TASK.md").write_text("## Current task\n\nstale, and longer\n")
    content = "## Current task\n\nfresh\n"
    result = run_checkpoint(repo, frame_payload(task_content(content)))
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
    result = run_checkpoint(repo, frame_payload(task_clear(), todo_content(todo)))
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
    result = run_checkpoint(repo, frame_payload(task_content(task), todo_clear()))
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
        payload = frame_payload(task_content(body))
    else:
        payload = frame_payload(task_clear(), todo_content(body))
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
        payload = frame_payload(task_clear(), todo_content(content))
    else:
        payload = precompact_payload("with-commit", todo_content(content))
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / "TODO.md").read_text() == content


def test_task_and_todo_both_written(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    task = "## Current task\n\nbody\n"
    todo = "## Remaining\n\n- x\n"
    result = run_checkpoint(repo, frame_payload(task_content(task), todo_content(todo)))
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
        task_content("## Current task\n\nwould have been written\n"),
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
    result = run_checkpoint(repo, frame_payload(task_content(task), todo_keep()))
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
        (["--is-empty-body"], "## Remaining\n", 0),
        (["--is-empty-body"], "## Remaining\n\n- an item\n", 1),
        (["--bogus"], "", 2),
        ([], "", 2),
    ],
    ids=["empty", "has_a_body", "unknown_flag", "no_flag"],
)
def test_is_empty_body_cli_exit_code(argv: list[str], stdin: str, code: int) -> None:
    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "_checkpoint_lib.py"), *argv],
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == code


# ==========================================================================
# Task shape -- the body cap and the no-list rule on a `task` content string
# ==========================================================================

TASK_BODY_LIMIT = 1000


def prose(n: int, char: str = "a") -> str:
    """One prose line of exactly n characters, never a heading or a list
    item."""
    return char * n


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
    result = run_checkpoint(repo, frame_payload(task_content(content)))
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
    result = run_checkpoint(repo, frame_payload(task_content(content)))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


def test_task_body_cap_ignores_blank_lines_and_whitespace_around_the_body(
    tmp_path: Path,
) -> None:
    content = f"\n\n   \n{prose(TASK_BODY_LIMIT)}\n  \n\n"
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(task_content(content)))
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
    result = run_checkpoint(repo, frame_payload(task_content(content)))
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
    result = run_checkpoint(repo, frame_payload(task_content(content)))
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
    result = run_checkpoint(repo, frame_payload(task_content(content)))
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
    result = run_checkpoint(repo, frame_payload(task_content(content)))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == content


def test_task_over_the_cap_with_a_list_item_is_one_error_with_both_facts(
    tmp_path: Path,
) -> None:
    content = f"intro\n- item\n{prose(TASK_BODY_LIMIT)}\n"
    count = len(content.strip())
    assert count > TASK_BODY_LIMIT
    repo = make_repo(tmp_path)
    result = run_checkpoint(repo, frame_payload(task_content(content)))
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
    payload = frame_payload(
        task_content(content), todo_content("## Remaining\n\nnext step\n")
    )
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
    ).read_text() == "armed\nrename\n/rename Two Words Title\n"
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
    result = run_checkpoint(repo, frame_payload(task_content(task), todo_content(todo)))
    assert result.returncode == 0
    assert (repo / "TASK.md").read_text() == task
    assert (repo / "TODO.md").read_text() == todo
    assert read_back_drive(repo / ".claude" / "autodrive")


# ==========================================================================
# The transition and the continuation
# ==========================================================================


def test_clear_missing_under_handoff_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "continue": None,
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
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
        "continue": None,
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


def test_continuation_against_untyped_transition_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": False,
        "continue": "pick up per the task file",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr

    payload = {
        "skill": "precompact",
        "commit": "with-commit",
        "compact": False,
        "continue": "pick up per the task file",
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr


def test_multiline_continuation_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": True,
        "continue": "first line\nsecond line",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr


def test_continuation_beginning_with_slash_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": True,
        "continue": "/resume the work",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr


def test_whitespace_only_continuation_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": True,
        "continue": "   ",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr


def test_continue_neither_null_nor_string_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "with-commit",
        "rename": "T",
        "clear": True,
        "continue": True,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "continue" in result.stderr


# --- the six legal combinations ---


def test_handoff_clear_true_no_continuation(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (
        repo / ".claude" / "autodrive"
    ).read_text() == "armed\nclear\n/rename A Title\n/clear\n"
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_handoff_clear_true_with_continuation(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": "pick up per the task file",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == (
        "armed\nclear\n/rename A Title\n/clear\npick up per the task file\n"
    )
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_precompact_compact_false_two_line_marker(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": False,
        "continue": None,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == "armed\ncompact\n"


def test_precompact_compact_true_no_continuation_bare_compact(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": True,
        "continue": None,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == "armed\ncompact\n/compact\n"
    assert read_back_drive(repo / ".claude" / "autodrive")


def test_precompact_focus_directive_and_continuation_both_carried(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    payload = {
        "skill": "precompact",
        "commit": "without-commit",
        "compact": "keep the parser work",
        "continue": "continue with task 3",
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert (repo / ".claude" / "autodrive").read_text() == (
        "armed\ncompact\n/compact keep the parser work\ncontinue with task 3\n"
    )
    assert read_back_drive(repo / ".claude" / "autodrive")


# --- held versus armed ---


def test_typed_transition_with_memory_gate_pending_held(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": "pick up per the task file",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "held sess-checkpoint"
    assert "handoff-approved" in result.stdout


def test_held_sentinel_names_the_session_that_holds_it(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    state, owner = drive_state(repo / ".claude" / "autodrive")
    assert state == "held"
    assert owner == "sess-checkpoint"


def test_typed_transition_no_memory_gate_armed_no_arming_instruction(
    tmp_path: Path,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": "pick up per the task file",
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"
    assert "handoff-approved" not in result.stdout


def test_untyped_handoff_still_types_rename_so_it_holds_too(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": False,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "held sess-checkpoint"
    assert "handoff-approved" in result.stdout


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
def test_sentinel_typing_nothing_arms_even_with_memory_gate_pending(
    tmp_path: Path,
    commit: str,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {
        "skill": "precompact",
        "commit": commit,
        "compact": False,
        "continue": None,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"
    assert "handoff-approved" not in result.stdout


def test_autoname_arms_against_dirty_memory_having_asked_nothing(
    tmp_path: Path,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {"skill": "autoname", "rename": "A Side Conversation"}
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"


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
    ).read_text() == "armed\nrename\n/rename A Side Conversation\n"
    state, _ = drive_state(repo / ".claude" / "autodrive")
    assert state == "armed"


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
        ("task", task_content("body")),
        ("todo", todo_content("body")),
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


# ==========================================================================
# Memory directive
# ==========================================================================


def handoff_payload(commit: str) -> dict[str, object]:
    return {
        "skill": "handoff",
        "commit": commit,
        "rename": "Session Title",
        "clear": False,
        "continue": None,
        "task": task_clear(),
        "todo": todo_keep(),
    }


def precompact_payload(commit: str, todo: object = None) -> dict[str, object]:
    return {
        "skill": "precompact",
        "commit": commit,
        "compact": False,
        "continue": None,
        "todo": todo_keep() if todo is None else todo,
    }


def assert_stdout_is_closing(
    result: subprocess.CompletedProcess[str], skill: str, *, typed: bool
) -> None:
    """Assert stdout is exactly the closing line.

    First asserts the line itself is non-empty, so this cannot pass against an
    unwritten closing_directive.
    """
    closing = lib.closing_directive(skill, typed=typed)
    assert closing != ""
    assert result.stdout == closing


def test_not_gitlore_managed_closing_only(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, "plain")
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert_stdout_is_closing(result, "handoff", typed=False)


def test_gitlore_clean_memory_closing_only(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert_stdout_is_closing(result, "handoff", typed=False)


def test_submodule_registered_not_materialized_closing_only(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    shutil.rmtree(repo / "memory" / ".git")
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert_stdout_is_closing(result, "handoff", typed=False)


def test_dirty_memory_directive_names_both_ipc_paths(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert "uncommitted changes" in result.stdout
    assert "feedback_x.md" in result.stdout
    assert str(repo / ".claude" / "gitlore-memory-message") in result.stdout
    assert str(repo / ".claude" / "gitlore-commit-memory") in result.stdout


def test_clause_resolved_content_is_its_own_block(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert GITLORE_MEMORY_APPROVAL_CLAUSE in result.stdout
    assert f"\n\n{GITLORE_MEMORY_APPROVAL_CLAUSE}\n\n" in result.stdout
    assert "72 characters" in result.stdout


def test_clause_file_unset_names_key_and_restart(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    subprocess.run(
        ["git", "config", "--unset", "gitlore.memoryApprovalClauseFile"],
        cwd=repo,
        check=True,
    )
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert "gitlore.memoryapprovalclausefile" in result.stdout.lower()
    assert "/restart" in result.stdout
    # The checkpoint has already written the task file, the todo file and the
    # sentinel by the time this prints, so it claims no such thing — only that
    # the memory changes are still pending.
    assert "Nothing has been written" not in result.stdout
    assert "The memory changes are still pending." in result.stdout
    assert str(repo / ".claude" / "gitlore-memory-message") not in result.stdout
    assert str(repo / ".claude" / "gitlore-commit-memory") not in result.stdout


def test_clause_file_missing_same_key_and_restart_report(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    subprocess.run(
        [
            "git",
            "config",
            "gitlore.memoryApprovalClauseFile",
            str(repo / ".gitlore-memory-approval-clause-missing.txt"),
        ],
        cwd=repo,
        check=True,
    )
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert "gitlore.memoryapprovalclausefile" in result.stdout.lower()
    assert "/restart" in result.stdout
    assert "Nothing has been written" not in result.stdout
    assert "The memory changes are still pending." in result.stdout
    assert str(repo / ".claude" / "gitlore-memory-message") not in result.stdout


def test_unset_and_missing_clause_reports_are_the_same(tmp_path: Path) -> None:
    repo_unset = make_gitlore_repo(tmp_path, "glrepo_unset")
    dirty_memory(repo_unset)
    subprocess.run(
        ["git", "config", "--unset", "gitlore.memoryApprovalClauseFile"],
        cwd=repo_unset,
        check=True,
    )
    unset_result = run_checkpoint(repo_unset, handoff_payload("without-commit"))

    repo_missing = make_gitlore_repo(tmp_path, "glrepo_missing")
    dirty_memory(repo_missing)
    subprocess.run(
        [
            "git",
            "config",
            "gitlore.memoryApprovalClauseFile",
            str(repo_missing / "gone.txt"),
        ],
        cwd=repo_missing,
        check=True,
    )
    missing_result = run_checkpoint(repo_missing, handoff_payload("without-commit"))

    assert unset_result.returncode == 0
    assert missing_result.returncode == 0
    assert unset_result.stdout == missing_result.stdout


def test_with_commit_summary_write_only_no_trigger_mention(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    assert result.returncode == 0
    assert str(repo / ".claude" / "gitlore-memory-message") in result.stdout
    assert "gitlore-commit-memory" not in result.stdout
    assert "trigger" not in result.stdout
    assert "two file writes" not in result.stdout


def test_with_commit_states_commit_carries_the_memory(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    assert result.returncode == 0
    assert "carries the memory" in result.stdout.lower()


def test_without_commit_keeps_standalone_two_file_instruction(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert "two file writes" in result.stdout
    assert "Write the trigger file (any content)" in result.stdout
    assert "carries the memory" not in result.stdout


def test_with_commit_memory_text_drops_nothing_further(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    assert result.returncode == 0
    assert "gitlore memory has uncommitted changes" in result.stdout
    assert "nothing further" not in result.stdout.lower()


# ==========================================================================
# Commit act
# ==========================================================================


@pytest.mark.parametrize("payload_fn", [handoff_payload, precompact_payload])
def test_with_commit_prints_the_commit_act(
    tmp_path: Path, payload_fn: Callable[[str], dict[str, object]]
) -> None:
    repo = make_gitlore_repo(tmp_path)
    commit_act = lib.commit_directive()
    assert commit_act
    result = run_checkpoint(repo, payload_fn("with-commit"))
    assert result.returncode == 0
    assert commit_act in result.stdout
    assert "commit" in commit_act.lower()


@pytest.mark.parametrize("payload_fn", [handoff_payload, precompact_payload])
def test_without_commit_prints_no_commit_act(
    tmp_path: Path, payload_fn: Callable[[str], dict[str, object]]
) -> None:
    repo = make_gitlore_repo(tmp_path)
    commit_act = lib.commit_directive()
    assert commit_act
    result = run_checkpoint(repo, payload_fn("without-commit"))
    assert result.returncode == 0
    assert commit_act not in result.stdout


def test_commit_act_is_the_exact_no_git_verb_sentence() -> None:
    """Pin the exact sentence rather than blacklisting verb spellings.

    A reword naming a verb another way ("stage and commit", "`git ci`") passes
    a substring blacklist; the design record quotes this sentence verbatim
    (docs/changelog/2026-09-18-the-directive-owns-the-procedure.md).
    """
    assert lib.commit_directive() == (
        "Once everything above is done, make the commit the request called for, "
        "including any change to `TASK.md` and `TODO.md`.\n"
    )


# ==========================================================================
# Ordering
# ==========================================================================


def test_handoff_parts_print_in_order(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    todo_boundary = lib.todo_boundary(str(repo))
    commit_act = lib.commit_directive()
    assert todo_boundary
    assert commit_act
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    assert result.returncode == 0
    out = result.stdout
    memory_index = out.index("gitlore memory has uncommitted changes")
    todo_index = out.index(todo_boundary)
    commit_index = out.index(commit_act)
    assert memory_index < todo_index < commit_index


def test_parts_are_separated_by_one_blank_line(tmp_path: Path) -> None:
    """Every gap between parts is one blank line, never two.

    Each part ends in a newline of its own, so a join that does not strip it
    prints a second blank line at every seam.
    """
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    result = run_checkpoint(repo, precompact_payload("with-commit"))
    assert result.returncode == 0
    assert "\n\n\n" not in result.stdout
    assert result.stdout.endswith("`Ready to /compact`.\n")


def test_precompact_parts_print_in_order(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    sdd_directive = lib.sdd_directive(str(repo))
    commit_act = lib.commit_directive()
    closing = lib.closing_directive("precompact", typed=False)
    assert sdd_directive
    assert commit_act
    assert closing
    result = run_checkpoint(repo, precompact_payload("with-commit"))
    assert result.returncode == 0
    # Untyped precompact types nothing, so it stays armed with memory dirty:
    # the one cell where the closing line follows every other part.
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"
    out = result.stdout
    memory_index = out.index("gitlore memory has uncommitted changes")
    sdd_index = out.index(sdd_directive)
    commit_index = out.index(commit_act)
    closing_index = out.index(closing)
    assert memory_index < sdd_index < commit_index < closing_index
    assert out.endswith(closing)


# ==========================================================================
# Arming
# ==========================================================================


def test_arming_instruction_follows_every_other_part(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    todo_boundary = lib.todo_boundary(str(repo))
    arming = lib.arming_directive()
    assert todo_boundary
    assert arming
    payload = handoff_payload("without-commit")
    payload["clear"] = True
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "held sess-checkpoint"
    out = result.stdout
    assert out.count(arming) == 1
    todo_index = out.index(todo_boundary)
    arming_index = out.index(arming)
    assert todo_index < arming_index
    assert out.rstrip("\n").endswith(arming.rstrip("\n"))
    assert "Once that is done" not in out


def test_arming_text_refers_to_everything_above() -> None:
    arming = lib.arming_directive()
    assert arming
    assert "everything above" in arming
    assert "handoff-approved" in arming


def test_clause_refusal_is_followed_by_no_commit_or_arming(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    subprocess.run(
        ["git", "config", "--unset", "gitlore.memoryApprovalClauseFile"],
        cwd=repo,
        check=True,
    )
    add_sdd_ledger(repo)
    boundary = lib.todo_boundary(str(repo))
    commit_act = lib.commit_directive()
    arming = lib.arming_directive()
    assert boundary
    assert commit_act
    assert arming
    payload = handoff_payload("with-commit")
    payload["clear"] = True
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    out = result.stdout
    assert "gitlore.memoryapprovalclausefile" in out.lower()
    assert boundary not in out
    assert commit_act not in out
    assert arming not in out
    assert "end on one line" not in out.lower()
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "held sess-checkpoint"


# ==========================================================================
# Hold rule
# ==========================================================================


@pytest.mark.parametrize(
    ("payload_fn", "typed_field"),
    [(handoff_payload, "clear"), (precompact_payload, "compact")],
)
def test_typed_with_commit_clean_memory_is_held(
    tmp_path: Path,
    payload_fn: Callable[[str], dict[str, object]],
    typed_field: str,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    assert lib.memory_directive(str(repo), "with-commit").text == ""
    commit_act = lib.commit_directive()
    arming = lib.arming_directive()
    assert commit_act
    assert arming
    payload = payload_fn("with-commit")
    payload[typed_field] = True
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "held sess-checkpoint"
    out = result.stdout
    commit_index = out.index(commit_act)
    arming_index = out.index(arming)
    assert commit_index < arming_index


def test_untyped_handoff_with_commit_clean_memory_is_armed(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    assert lib.memory_directive(str(repo), "with-commit").text == ""
    commit_act = lib.commit_directive()
    assert commit_act
    payload = handoff_payload("with-commit")
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"
    assert "handoff-approved" not in result.stdout
    assert commit_act in result.stdout


def test_untyped_precompact_with_commit_clean_memory_is_armed(tmp_path: Path) -> None:
    """The FR-G marker cell (¬K ∧ ¬T ∧ C) types nothing, so it never holds."""
    repo = make_gitlore_repo(tmp_path)
    assert lib.memory_directive(str(repo), "with-commit").text == ""
    result = run_checkpoint(repo, precompact_payload("with-commit"))
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"


def test_handoff_commit_precedes_closing_line_when_armed(tmp_path: Path) -> None:
    """On the handoff side, the commit act precedes the closing line."""
    repo = make_gitlore_repo(tmp_path)
    commit_act = lib.commit_directive()
    closing = lib.closing_directive("handoff", typed=False)
    assert commit_act
    assert closing
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"
    out = result.stdout
    commit_index = out.index(commit_act)
    closing_index = out.index(closing)
    assert commit_index < closing_index
    assert out.endswith(closing)


# ==========================================================================
# Held path validates CLAUDE_CODE_SESSION_ID before any write (finding 2)
# ==========================================================================


def _assert_nothing_written(repo: Path) -> None:
    assert not (repo / "TASK.md").exists()
    assert not (repo / "TODO.md").exists()
    assert not (repo / ".claude" / "autodrive").exists()


def _run_checkpoint_no_session_id(
    repo: Path, payload: Mapping[str, object]
) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env["HANDOFF_ROOT"] = str(repo)
    env.pop("CLAUDE_CODE_SESSION_ID", None)
    env.pop("CLAUDE_PROJECT_DIR", None)
    return subprocess.run(
        [sys.executable, str(CHECKPOINT)],
        cwd=repo,
        input=json.dumps(payload),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_held_via_commit_session_id_unset_errors_before_any_write(
    tmp_path: Path,
) -> None:
    """Held through (T ∧ C): a typed transition owing a commit, clean memory."""
    repo = make_gitlore_repo(tmp_path)
    payload = handoff_payload("with-commit")
    payload["clear"] = True
    result = _run_checkpoint_no_session_id(repo, payload)
    assert result.returncode != 0
    # Guard against a vacuous pass: today's message blames the composer
    # ("composed a sentinel this version cannot read back") without naming
    # the variable at all — rule that phrasing out explicitly.
    assert "cannot read back" not in result.stderr
    assert "CLAUDE_CODE_SESSION_ID" in result.stderr
    _assert_nothing_written(repo)


def test_held_via_memory_session_id_unset_errors_before_any_write(
    tmp_path: Path,
) -> None:
    """Held through (K ∧ M): dirty memory behind an untyped handoff."""
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = handoff_payload("without-commit")
    result = _run_checkpoint_no_session_id(repo, payload)
    assert result.returncode != 0
    assert "cannot read back" not in result.stderr
    assert "CLAUDE_CODE_SESSION_ID" in result.stderr
    _assert_nothing_written(repo)


def test_held_session_id_set_still_succeeds_via_commit(tmp_path: Path) -> None:
    """Paired positive for the (T ∧ C) row: same fixture, variable set."""
    repo = make_gitlore_repo(tmp_path)
    payload = handoff_payload("with-commit")
    payload["clear"] = True
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "held sess-checkpoint"


def test_armed_cell_succeeds_with_session_id_unset(tmp_path: Path) -> None:
    """The validation is scoped to the held path — an armed cell needs no id."""
    repo = make_gitlore_repo(tmp_path)
    payload = handoff_payload("without-commit")
    result = _run_checkpoint_no_session_id(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"


# ==========================================================================
# closing_directive raises on an unknown skill (finding 4)
# ==========================================================================


def test_closing_directive_raises_on_unknown_skill() -> None:
    with pytest.raises(ValueError, match="bogus"):
        lib.closing_directive("bogus", typed=False)


# ==========================================================================
# Composition
# ==========================================================================


def test_handoff_composition_carries_todo_boundary_not_sdd_nudge(
    tmp_path: Path,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert ".superpowers/sdd/feature-plan/progress.md" in result.stdout
    assert "TODO.md" in result.stdout
    assert "Minor findings" not in result.stdout
    assert "re-dispatched" not in result.stdout


def test_precompact_composition_carries_sdd_nudge_memory_first(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    result = run_checkpoint(repo, precompact_payload("without-commit"))
    assert result.returncode == 0
    assert str(repo / ".claude" / "gitlore-commit-memory") in result.stdout
    assert ".superpowers/sdd/feature-plan/progress.md" in result.stdout
    out_lines = result.stdout.splitlines()
    mem_line = next(
        i for i, line in enumerate(out_lines) if "gitlore-commit-memory" in line
    )
    sdd_line = next(
        i
        for i, line in enumerate(out_lines)
        if ".superpowers/sdd/feature-plan/progress.md" in line
    )
    assert mem_line < sdd_line


@pytest.mark.parametrize("skill", ["handoff", "precompact"])
def test_each_boundary_composes_own_directive_not_the_others(
    tmp_path: Path, skill: str
) -> None:
    repo = make_gitlore_repo(tmp_path, "bnd")
    dirty_memory(repo)
    add_sdd_ledger(repo)
    if skill == "handoff":
        payload = {
            "skill": skill,
            "commit": "without-commit",
            "rename": "T",
            "clear": False,
            "continue": None,
            "task": task_clear(),
            "todo": todo_keep(),
        }
    else:
        payload = {
            "skill": skill,
            "commit": "without-commit",
            "compact": False,
            "continue": None,
            "todo": todo_keep(),
        }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    if skill == "handoff":
        assert "survives the /clear" in result.stdout
        assert "re-dispatched" not in result.stdout
    else:
        assert "re-dispatched" in result.stdout
        assert "survives the /clear" not in result.stdout
    lines = result.stdout.splitlines()
    mem = next(i for i, line in enumerate(lines) if "gitlore-memory-message" in line)
    led = next(
        i
        for i, line in enumerate(lines)
        if ".superpowers/sdd/feature-plan/progress.md" in line
    )
    assert mem < led


@pytest.mark.parametrize("skill", ["handoff", "precompact"])
def test_live_ledger_scopes_todo_file_rather_than_standing_it_down(
    tmp_path: Path, skill: str
) -> None:
    repo = make_gitlore_repo(tmp_path, "scope")
    add_sdd_ledger(repo)
    payload = (
        handoff_payload("without-commit")
        if skill == "handoff"
        else precompact_payload("without-commit")
    )
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    assert "TODO.md" in result.stdout
    assert "outside the plan" in result.stdout
    assert "must not exist" not in result.stdout


def test_precompact_no_ledger_memory_directive_only(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, precompact_payload("without-commit"))
    assert result.returncode == 0
    assert str(repo / ".claude" / "gitlore-memory-message") in result.stdout
    assert ".superpowers/sdd/feature-plan/progress.md" not in result.stdout


def test_flat_path_stray_does_not_suppress_todo_file(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_flat_sdd_ledger(repo)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert "TODO.md" not in result.stdout


def test_unidentified_workspace_does_not_suppress_todo_file(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_unidentified_sdd_ledger(repo)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert "TODO.md" not in result.stdout


def test_flat_path_ledger_alone_precompact_closing_only(tmp_path: Path) -> None:
    repo = tmp_path / "sddflat"
    (repo / ".claude").mkdir(parents=True)
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    add_flat_sdd_ledger(repo)
    result = run_checkpoint(repo, precompact_payload("without-commit"))
    assert result.returncode == 0
    assert_stdout_is_closing(result, "precompact", typed=False)


def test_several_live_workspaces_most_recently_modified_wins(tmp_path: Path) -> None:
    for i, pair in enumerate((("a-live", "z-stale"), ("z-live", "a-stale")), start=1):
        live, stale = pair
        repo = tmp_path / f"sddmulti{i}"
        (repo / ".claude").mkdir(parents=True)
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        add_sdd_ledger(repo, stale)
        add_sdd_ledger(repo, live)
        old_time = 1735689600  # 2025-01-01
        os.utime(
            repo / ".superpowers" / "sdd" / stale / "progress.md", (old_time, old_time)
        )
        result = run_checkpoint(repo, precompact_payload("without-commit"))
        assert result.returncode == 0
        assert f".superpowers/sdd/{live}/progress.md" in result.stdout
        assert stale not in result.stdout


# ==========================================================================
# Closing line
# ==========================================================================


@pytest.mark.parametrize(
    ("skill", "typed"),
    [
        ("handoff", False),
        ("precompact", False),
        ("handoff", True),
        ("precompact", True),
    ],
)
def test_closing_line_names_what_the_boundary_is_ready_for(
    tmp_path: Path, skill: str, *, typed: bool
) -> None:
    repo = make_gitlore_repo(tmp_path)
    if skill == "handoff":
        payload = handoff_payload("without-commit")
        payload["clear"] = typed
    else:
        payload = precompact_payload("without-commit")
        payload["compact"] = typed
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"
    assert_stdout_is_closing(result, skill, typed=typed)
    out = result.stdout
    assert out.startswith("Once everything above is done, end on one line: `")
    if typed:
        name = "Clear" if skill == "handoff" else "Compaction"
        assert f"{name} armed" in out
        assert "Ready to" not in out
    elif skill == "handoff":
        assert "Ready to /clear" in out
    else:
        assert "Ready to /compact" in out


@pytest.mark.parametrize(
    ("payload_fn", "typed_field"),
    [(handoff_payload, "clear"), (precompact_payload, "compact")],
)
def test_held_sentinel_prints_no_closing_line(
    tmp_path: Path,
    payload_fn: Callable[[str], dict[str, object]],
    typed_field: str,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    assert lib.memory_directive(str(repo), "with-commit").text == ""
    payload = payload_fn("with-commit")
    payload[typed_field] = True
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "held sess-checkpoint"
    assert "end on one line" not in result.stdout.lower()


def test_refusal_prints_alone_when_not_held(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    subprocess.run(
        ["git", "config", "--unset", "gitlore.memoryApprovalClauseFile"],
        cwd=repo,
        check=True,
    )
    refusal = lib.memory_directive(str(repo), "with-commit")
    assert refusal.text != ""
    assert refusal.refusal
    result = run_checkpoint(repo, precompact_payload("with-commit"))
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed"
    assert result.stdout == refusal.text


# ==========================================================================
# Legacy path migration
# ==========================================================================
#
# 0.15.0 kept the frame under `.claude/handoff-task.md` and
# `.claude/handoff-todo.md`; the loader reads those as a fallback and the
# checkpoint moves them to `TASK.md` / `TODO.md`. The plan leaves the wording
# of the checkpoint's stdout free, so this block pins only what a reader of the
# rows needs: a report is ONE line of stdout that names the legacy path
# (relative to the root) and carries one action word, and the git act is the
# literal command below. The word is matched whole and without regard to case
# (`\bmoved\b`), because "removed" contains "moved".

# Mirror HANDOFF_LEGACY_REL_TASK / _TODO in scripts/_lib.sh, by hand.
LEGACY_TASK_REL = ".claude/handoff-task.md"
LEGACY_TODO_REL = ".claude/handoff-todo.md"
SENTINEL_REL = ".claude/autodrive"

# The action words: a rename onto the root name, an unlink of a legacy file,
# and a legacy file left alone because the root file wins.
MOVED = re.compile(r"\bmoved\b", re.IGNORECASE)
REMOVED = re.compile(r"\bremoved\b", re.IGNORECASE)
IGNORED = re.compile(r"\bignored\b", re.IGNORECASE)

# The with-commit act that stages a tracked legacy path as deleted. Paths follow
# it space-separated, each as git's top-level pathspec (`:/<rel>`) so the act
# runs from any directory of the repository, task before todo.
#
# Two constraints on the implementation that these rows make:
# - `lib.commit_directive`'s legacy-paths parameter must be optional: the rows
#   that expect today's text call it with no argument.
# - A legacy path named on any line other than a `git rm` line counts as a
#   report (`report_lines`), so an act split over two lines with a path on the
#   second one reads as a duplicate report and fails the one-report rows.
GIT_RM = "git rm --cached --ignore-unmatch -q --"


def git_act(*rels: str) -> str:
    """Return the printed act for these legacy paths, in the order given."""
    return " ".join([GIT_RM, *(f":/{rel}" for rel in rels)])


TASK_LEGACY_BODY = "## Current task\n\nlegacy task prose\n"
TASK_ROOT_BODY = "## Current task\n\nroot task prose\n"
TASK_WRITTEN = "## Current task\n\nwritten task prose\n"
TODO_LEGACY_BODY = "## Remaining\n\n- legacy item\n- second legacy item\n"
TODO_ROOT_BODY = "## Remaining\n\n- root item\n- second root item\n"
TODO_WRITTEN = "## Remaining\n\n- written item\n"
HEADINGS_ONLY = "## Remaining\n"

# A root file the loader's own predicate (`is_empty_body`) counts as absent.
BODYLESS_ROOTS = {
    "headings_only": HEADINGS_ONLY,
    "whitespace_only": "   \n\n\t\n",
    "empty": "",
}

# A todo action, what TODO.md must hold after it over each starting content,
# and which report the legacy file owes. A content string over a legacy-only
# half is a move or a removal, whichever wording the report picks.
TODO_OVER_LEGACY = {
    "keep": (todo_keep(), TODO_LEGACY_BODY, "moved"),
    "edit": (
        todo_edit("- second legacy item", "- edited item"),
        TODO_LEGACY_BODY.replace("- second legacy item", "- edited item"),
        "moved",
    ),
    "content": (todo_content(TODO_WRITTEN), TODO_WRITTEN, "moved_or_removed"),
}

# The same three actions over a root file that has a body: what it ends as.
TODO_OVER_ROOT = {
    "keep": (todo_keep(), TODO_ROOT_BODY),
    "edit": (
        todo_edit("- second root item", "- edited root item"),
        TODO_ROOT_BODY.replace("- second root item", "- edited root item"),
    ),
    "content": (todo_content(TODO_WRITTEN), TODO_WRITTEN),
}


def read(path: Path) -> str | None:
    """Return the file's text, or None when there is no regular file."""
    return path.read_text() if path.is_file() else None


def put(repo: Path, rel: str, text: str | None) -> None:
    """Write text at rel, or leave the path alone when text is None."""
    if text is not None:
        (repo / rel).write_text(text)


def snapshot(root: Path) -> dict[str, tuple[str, bytes]]:
    """Map every path under root (`.git` aside) to its kind and bytes.

    A symlink is recorded by its target and never followed, so a dangling one
    and a directory are told apart from a file whose bytes happen to match.
    """
    seen: dict[str, tuple[str, bytes]] = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in [*dirnames, *filenames]:
            path = Path(dirpath) / name
            rel = str(path.relative_to(root))
            if path.is_symlink():
                seen[rel] = ("link", str(path.readlink()).encode())
            elif path.is_dir():
                seen[rel] = ("dir", b"")
            else:
                seen[rel] = ("file", path.read_bytes())
    return seen


def migration_payload(
    task: object, todo: object, commit: str = "without-commit"
) -> dict[str, object]:
    """A `handoff` payload, untyped, carrying task and todo as given."""
    payload = frame_payload(task, todo)
    payload["commit"] = commit
    return payload


def report_lines(out: str, rel: str) -> list[str]:
    """Return the stdout lines that name rel, the git act's line aside."""
    return [ln for ln in out.splitlines() if rel in ln and "git rm" not in ln]


def assert_reported(out: str, rel: str, kind: str) -> None:
    """Assert stdout carries exactly one report of rel, of the given kind.

    `kind` is "moved", "removed", "moved_or_removed" or "ignored". An ignored
    file's report never says it moved or went, and the others never say it was
    ignored.
    """
    lines = report_lines(out, rel)
    assert len(lines) == 1, f"want one line naming {rel}, got {lines!r} in {out!r}"
    line = lines[0]
    acts = {
        "moved": [MOVED],
        "removed": [REMOVED],
        "moved_or_removed": [MOVED, REMOVED],
    }
    if kind == "ignored":
        assert re.search(IGNORED, line), line
        assert not re.search(MOVED, line), line
        assert not re.search(REMOVED, line), line
    else:
        assert any(re.search(word, line) for word in acts[kind]), line
        assert not re.search(IGNORED, line), line


def assert_not_reported(out: str, rel: str) -> None:
    """Assert no stdout line outside the git act names rel."""
    assert report_lines(out, rel) == [], out


def assert_directive_tail(
    out: str, repo: Path, skill: str, *, typed: bool, held: bool
) -> None:
    """Assert the sentinel's state is the expected one and its tail ends stdout.

    `held` comes from the caller's parametrization, never from the sentinel the
    code under test wrote: a migration that forced `held` (or `armed`) would
    otherwise pick the matching tail and pass. The one closing line, or the
    arming line when held, is that tail.
    """
    state, _owner = drive_state(repo / SENTINEL_REL)
    assert state == ("held" if held else "armed")
    tail = lib.arming_directive() if held else lib.closing_directive(skill, typed=typed)
    assert tail
    assert out.endswith(tail), out
    assert out.count(tail) == 1, out


def ok(result: subprocess.CompletedProcess[str]) -> None:
    """Assert a clean exit, showing stderr when it was not."""
    assert result.returncode == 0, result.stderr


# --- 1. effective content: the root file with a body, else the legacy one ---


@pytest.mark.parametrize(
    "repo_name", ["repo", "spaced dir/repo name"], ids=["plain", "spaced"]
)
@pytest.mark.parametrize("action", list(TODO_OVER_LEGACY))
def test_legacy_todo_with_no_root_file_is_moved_to_the_root_name(
    tmp_path: Path, action: str, repo_name: str
) -> None:
    repo = make_repo(tmp_path, repo_name)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    todo, expected, kind = TODO_OVER_LEGACY[action]
    result = run_checkpoint(repo, migration_payload(task_clear(), todo))
    ok(result)
    assert read(repo / "TODO.md") == expected
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, kind)


def test_keep_moves_the_legacy_todo_with_its_modification_time(
    tmp_path: Path,
) -> None:
    """The move is a rename: the loader's "saved … ago" reads this mtime.

    A copy and unlink would stamp the file "now". The legacy file is dated far
    in the past so that a same-second copy cannot match by accident, and the
    bytes are asserted first so the row fails on an assertion, not on a missing
    file.
    """
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    then = 1_700_000_000_000_000_000
    os.utime(repo / LEGACY_TODO_REL, ns=(then, then))
    ok(run_checkpoint(repo, migration_payload(task_clear(), todo_keep())))
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    assert (repo / "TODO.md").stat().st_mtime_ns == then


def test_legacy_task_with_no_root_file_is_replaced_by_the_written_task(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    result = run_checkpoint(repo, migration_payload(task_content(TASK_WRITTEN), None))
    ok(result)
    assert read(repo / "TASK.md") == TASK_WRITTEN
    assert not (repo / LEGACY_TASK_REL).exists()
    assert_reported(result.stdout, LEGACY_TASK_REL, "moved_or_removed")


def test_both_halves_migrate_in_one_call_each_reported(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(task_content(TASK_WRITTEN), todo_keep())
    result = run_checkpoint(repo, payload)
    ok(result)
    assert read(repo / "TASK.md") == TASK_WRITTEN
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    assert not (repo / LEGACY_TASK_REL).exists()
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TASK_REL, "moved_or_removed")
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved")


def test_legacy_todo_with_no_body_and_no_root_file_is_still_moved(
    tmp_path: Path,
) -> None:
    """A headings-only legacy file is the effective content when root is absent.

    The loader says nothing about it, so the checkpoint's report is the only
    notice the agent gets.
    """
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, HEADINGS_ONLY)
    result = run_checkpoint(repo, migration_payload(task_clear(), todo_keep()))
    ok(result)
    assert read(repo / "TODO.md") == HEADINGS_ONLY
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved")


# --- 2. a root file with no body is absent, whatever sits at its path ---


@pytest.mark.parametrize(
    "root_before", list(BODYLESS_ROOTS.values()), ids=list(BODYLESS_ROOTS)
)
@pytest.mark.parametrize("action", list(TODO_OVER_LEGACY))
def test_bodyless_root_todo_is_replaced_by_the_move(
    tmp_path: Path, action: str, root_before: str
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", root_before)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    todo, expected, kind = TODO_OVER_LEGACY[action]
    result = run_checkpoint(repo, migration_payload(task_clear(), todo))
    ok(result)
    assert read(repo / "TODO.md") == expected
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, kind)


@pytest.mark.parametrize(
    "root_before", list(BODYLESS_ROOTS.values()), ids=list(BODYLESS_ROOTS)
)
def test_bodyless_root_task_is_replaced_by_the_written_task(
    tmp_path: Path, root_before: str
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", root_before)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    result = run_checkpoint(repo, migration_payload(task_content(TASK_WRITTEN), None))
    ok(result)
    assert read(repo / "TASK.md") == TASK_WRITTEN
    assert not (repo / LEGACY_TASK_REL).exists()
    assert_reported(result.stdout, LEGACY_TASK_REL, "moved_or_removed")


# --- 3. a root file with a body wins; the legacy file is left and reported ---


@pytest.mark.parametrize(
    "legacy_before",
    [TODO_LEGACY_BODY, HEADINGS_ONLY],
    ids=["legacy_body", "legacy_bodyless"],
)
@pytest.mark.parametrize("action", list(TODO_OVER_ROOT))
def test_root_todo_with_a_body_wins_and_the_legacy_file_is_reported_ignored(
    tmp_path: Path, action: str, legacy_before: str
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    put(repo, LEGACY_TODO_REL, legacy_before)
    todo, expected = TODO_OVER_ROOT[action]
    result = run_checkpoint(repo, migration_payload(task_clear(), todo))
    ok(result)
    assert read(repo / "TODO.md") == expected
    assert read(repo / LEGACY_TODO_REL) == legacy_before
    assert_reported(result.stdout, LEGACY_TODO_REL, "ignored")


@pytest.mark.parametrize(
    "legacy_before",
    [TASK_LEGACY_BODY, HEADINGS_ONLY],
    ids=["legacy_body", "legacy_bodyless"],
)
def test_root_task_with_a_body_wins_and_the_legacy_file_is_reported_ignored(
    tmp_path: Path, legacy_before: str
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, LEGACY_TASK_REL, legacy_before)
    result = run_checkpoint(repo, migration_payload(task_content(TASK_WRITTEN), None))
    ok(result)
    assert read(repo / "TASK.md") == TASK_WRITTEN
    assert read(repo / LEGACY_TASK_REL) == legacy_before
    assert_reported(result.stdout, LEGACY_TASK_REL, "ignored")


def test_edit_applies_to_the_root_file_never_to_the_ignored_legacy_one(
    tmp_path: Path,
) -> None:
    """`old_string` lives only in the legacy file: the root file is the frame.

    The refusal is the root-wins rule from the other side, and it leaves both
    files as they were.
    """
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    payload = migration_payload(task_clear(), todo_edit("- second legacy item", "- x"))
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "todo.old_string" in result.stderr
    assert "not found" in result.stderr
    assert snapshot(repo) == before


def test_each_ignored_legacy_file_is_reported_once(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    payload = migration_payload(task_content(TASK_ROOT_BODY), todo_keep())
    result = run_checkpoint(repo, payload)
    ok(result)
    after = snapshot(repo)
    after.pop(SENTINEL_REL)
    assert after == before
    assert_reported(result.stdout, LEGACY_TASK_REL, "ignored")
    assert_reported(result.stdout, LEGACY_TODO_REL, "ignored")


# --- 4. a write that leaves the root file without a body removes the legacy ---


@pytest.mark.parametrize(
    ("root_before", "kind"),
    [(None, "moved_or_removed"), (TODO_ROOT_BODY, "removed")],
    ids=["root_absent", "root_with_body"],
)
def test_bodyless_todo_content_removes_the_legacy_file_and_says_so(
    tmp_path: Path, root_before: str | None, kind: str
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", root_before)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(task_clear(), todo_content(HEADINGS_ONLY))
    result = run_checkpoint(repo, payload)
    ok(result)
    assert read(repo / "TODO.md") == HEADINGS_ONLY
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, kind)


def test_edit_that_strikes_the_last_item_removes_the_legacy_file_and_says_so(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", "## Remaining\n\n- only item\n")
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(task_clear(), todo_edit("- only item\n", ""))
    result = run_checkpoint(repo, payload)
    ok(result)
    assert read(repo / "TODO.md") == "## Remaining\n\n"
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, "removed")


def test_edit_that_strikes_the_last_item_of_a_legacy_only_todo_leaves_no_legacy_file(
    tmp_path: Path,
) -> None:
    """The edit applies to the legacy file, then the post-write rule sees a root
    file without a body: either way the legacy file must be gone."""
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, "## Remaining\n\n- only item\n")
    payload = migration_payload(task_clear(), todo_edit("- only item\n", ""))
    result = run_checkpoint(repo, payload)
    ok(result)
    assert read(repo / "TODO.md") == "## Remaining\n\n"
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved_or_removed")


@pytest.mark.parametrize(
    ("root_before", "kind"),
    [(None, "moved_or_removed"), (TASK_ROOT_BODY, "removed")],
    ids=["root_absent", "root_with_body"],
)
def test_bodyless_task_content_removes_the_legacy_file_and_says_so(
    tmp_path: Path, root_before: str | None, kind: str
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", root_before)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    headings = "## Current task\n"
    result = run_checkpoint(repo, migration_payload(task_content(headings), None))
    ok(result)
    assert read(repo / "TASK.md") == headings
    assert not (repo / LEGACY_TASK_REL).exists()
    assert_reported(result.stdout, LEGACY_TASK_REL, kind)


# --- 5. clear, and precompact's task removal, take the legacy file too ---


@pytest.mark.parametrize(
    "root_before", [None, TODO_ROOT_BODY], ids=["root_absent", "root_with_body"]
)
def test_todo_clear_removes_the_legacy_file_too_and_says_so(
    tmp_path: Path, root_before: str | None
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", root_before)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    result = run_checkpoint(repo, migration_payload(task_clear(), todo_clear()))
    ok(result)
    assert not (repo / "TODO.md").exists()
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, "removed")


@pytest.mark.parametrize(
    "root_before", [None, TASK_ROOT_BODY], ids=["root_absent", "root_with_body"]
)
def test_task_clear_removes_the_legacy_file_too_and_says_so(
    tmp_path: Path, root_before: str | None
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", root_before)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    result = run_checkpoint(repo, migration_payload(task_clear(), todo_keep()))
    ok(result)
    assert not (repo / "TASK.md").exists()
    assert not (repo / LEGACY_TASK_REL).exists()
    assert_reported(result.stdout, LEGACY_TASK_REL, "removed")


def test_clear_with_no_legacy_file_says_nothing_about_one(tmp_path: Path) -> None:
    """The clear rows' negative: the root file goes, no legacy line appears.

    Its positive is the pair of rows above, over the same root fixture.
    """
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    result = run_checkpoint(repo, migration_payload(task_clear(), todo_clear()))
    ok(result)
    assert not (repo / "TASK.md").exists()
    assert not (repo / "TODO.md").exists()
    assert_not_reported(result.stdout, LEGACY_TASK_REL)
    assert_not_reported(result.stdout, LEGACY_TODO_REL)


@pytest.mark.parametrize(
    "root_before", [None, TASK_ROOT_BODY], ids=["root_absent", "root_with_body"]
)
def test_precompact_task_removal_takes_the_legacy_task_file_too(
    tmp_path: Path, root_before: str | None
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", root_before)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    result = run_checkpoint(repo, precompact_payload("without-commit"))
    ok(result)
    assert not (repo / "TASK.md").exists()
    assert not (repo / LEGACY_TASK_REL).exists()
    assert_reported(result.stdout, LEGACY_TASK_REL, "removed")


@pytest.mark.parametrize("action", ["keep", "content"])
def test_precompact_carries_a_legacy_todo_by_the_todo_rules(
    tmp_path: Path, action: str
) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    todo, expected, kind = TODO_OVER_LEGACY[action]
    result = run_checkpoint(repo, precompact_payload("without-commit", todo))
    ok(result)
    assert read(repo / "TODO.md") == expected
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, kind)


# --- 6. a rejected payload leaves every file as it was, and moves nothing ---

# A prose task and a keep: both legacy files would go (the task is rewritten,
# the todo moves) if the call succeeded. Each case spoils one thing, names
# what stderr must say (so the refusal is for that reason and not another),
# and says whether the bad run has a session id. The fixed run then proves the
# same fixture migrates once the spoiled thing is right.
REJECTIONS = [
    pytest.param({"bogus": 1}, {}, "bogus", True, id="schema_error"),
    pytest.param(
        {"task": "## Current task\n\n- a list item\n"},
        {},
        "list item",
        True,
        id="task_shape_error",
    ),
    pytest.param(
        {"todo": todo_edit("- missing item", "- x")},
        {"todo": todo_edit("- second legacy item", "- x")},
        "not found",
        True,
        id="edit_old_string_absent",
    ),
    pytest.param(
        {"todo": todo_edit("legacy item", "- x")},
        {"todo": todo_edit("- second legacy item", "- x")},
        "ambiguous",
        True,
        id="edit_old_string_ambiguous",
    ),
    pytest.param(
        {"clear": True, "commit": "with-commit"},
        {"clear": True, "commit": "with-commit"},
        "CLAUDE_CODE_SESSION_ID",
        False,
        id="held_without_a_session_id",
    ),
]


@pytest.mark.parametrize(("spoiled", "fixed", "stderr_says", "has_session"), REJECTIONS)
def test_a_rejected_payload_moves_nothing_and_the_fixed_one_migrates(
    tmp_path: Path,
    spoiled: dict[str, object],
    fixed: dict[str, object],
    stderr_says: str,
    *,
    has_session: bool,
) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    base = migration_payload(task_content(TASK_WRITTEN), todo_keep())
    run = run_checkpoint if has_session else _run_checkpoint_no_session_id
    rejected = run(repo, {**base, **spoiled})
    assert rejected.returncode != 0
    assert stderr_says in rejected.stderr
    assert snapshot(repo) == before
    accepted = run_checkpoint(repo, {**base, **fixed})
    ok(accepted)
    assert read(repo / "TASK.md") == TASK_WRITTEN
    assert read(repo / "TODO.md") is not None
    assert not (repo / LEGACY_TASK_REL).exists()
    assert not (repo / LEGACY_TODO_REL).exists()


def test_a_failing_todo_edit_does_not_remove_a_legacy_task_the_task_half_would(
    tmp_path: Path,
) -> None:
    """The task half resolves first and would remove its legacy file.

    Nothing moves unless BOTH halves resolve: the todo half's refusal, which
    comes second, leaves the legacy task in place.
    """
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    before = snapshot(repo)
    payload = migration_payload(task_clear(), todo_edit("- missing item", "- x"))
    result = run_checkpoint(repo, payload)
    assert result.returncode == 2
    assert "not found" in result.stderr
    assert snapshot(repo) == before
    payload["todo"] = todo_keep()
    ok(run_checkpoint(repo, payload))
    assert not (repo / "TASK.md").exists()
    assert not (repo / LEGACY_TASK_REL).exists()


# --- 7. stdout: the reports, then the directive parts, the closing line last ---


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
@pytest.mark.parametrize("typed", [False, True], ids=["untyped", "typed"])
@pytest.mark.parametrize("skill", ["handoff", "precompact"])
def test_reports_come_first_and_the_tail_stays_last(
    tmp_path: Path, skill: str, *, typed: bool, commit: str
) -> None:
    repo = make_gitlore_repo(tmp_path)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    if skill == "handoff":
        payload = handoff_payload(commit)
        payload["clear"] = typed
    else:
        payload = precompact_payload(commit)
        payload["compact"] = typed
    result = run_checkpoint(repo, payload)
    ok(result)
    out = result.stdout
    assert_reported(out, LEGACY_TASK_REL, "removed")
    assert_reported(out, LEGACY_TODO_REL, "moved")
    # Held iff the transition is carried out and the commit is owed (the
    # memory submodule is clean, so no memory directive holds it).
    held = typed and commit == "with-commit"
    assert_directive_tail(out, repo, skill, typed=typed, held=held)
    reports = [
        ln
        for rel in (LEGACY_TASK_REL, LEGACY_TODO_REL)
        for ln in report_lines(out, rel)
    ]
    last_report = max(out.index(ln) for ln in reports)
    assert last_report < out.rindex("Once everything above is done")


def test_reports_precede_every_directive_part(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    ok(result)
    out = result.stdout
    assert_reported(out, LEGACY_TASK_REL, "removed")
    assert_reported(out, LEGACY_TODO_REL, "moved")
    boundary = lib.todo_boundary(str(repo))
    assert boundary
    parts = [
        "gitlore memory has uncommitted changes",
        boundary.rstrip("\n"),
        "make the commit the request called for",
    ]
    reports = [
        ln
        for rel in (LEGACY_TASK_REL, LEGACY_TODO_REL)
        for ln in report_lines(out, rel)
    ]
    assert max(out.index(ln) for ln in reports) < min(out.index(p) for p in parts)
    # Untyped, but the sentinel names `/rename` and the memory directive is
    # emitted: held, whatever the migration did.
    assert_directive_tail(out, repo, "handoff", typed=False, held=True)


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
def test_reports_and_the_git_rm_act_print_ahead_of_the_clause_file_refusal(
    tmp_path: Path, commit: str
) -> None:
    """The refusal still prints last; the migration it follows is not dropped.

    The files are written before the refusal prints, so on a retry there is
    nothing legacy left and the agent would never be told of the move. The
    reports, and the git act under with-commit, therefore precede the refusal.
    """
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    subprocess.run(
        ["git", "config", "--unset", "gitlore.memoryApprovalClauseFile"],
        cwd=repo,
        check=True,
    )
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    refusal = lib.memory_directive(str(repo), commit)
    assert refusal.refusal
    result = run_checkpoint(repo, handoff_payload(commit))
    ok(result)
    out = result.stdout
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(out, LEGACY_TODO_REL, "moved")
    assert out.endswith(refusal.text)
    assert out.count(refusal.text) == 1
    report_at = out.index(report_lines(out, LEGACY_TODO_REL)[0])
    if commit == "with-commit":
        act = git_act(LEGACY_TODO_REL)
        assert report_at < out.index(act) < out.index(refusal.text)
    else:
        assert "git rm" not in out
        assert report_at < out.index(refusal.text)


@pytest.mark.parametrize("skill", ["handoff", "precompact"])
@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
@pytest.mark.parametrize("typed", [False, True], ids=["untyped", "typed"])
def test_stdout_with_no_legacy_file_anywhere_is_what_it_was(
    tmp_path: Path, skill: str, commit: str, *, typed: bool
) -> None:
    """The commit act, when owed, then the one tail line; nothing else.

    Its positive is every migrating row above: the same call over a legacy file
    adds the reports.
    """
    repo = make_gitlore_repo(tmp_path)
    if skill == "handoff":
        payload = handoff_payload(commit)
        payload["clear"] = typed
    else:
        payload = precompact_payload(commit)
        payload["compact"] = typed
    result = run_checkpoint(repo, payload)
    ok(result)
    held = typed and commit == "with-commit"
    state, _owner = drive_state(repo / SENTINEL_REL)
    assert state == ("held" if held else "armed")
    tail = lib.arming_directive() if held else lib.closing_directive(skill, typed=typed)
    commit_act = lib.commit_directive().rstrip("\n") + "\n\n"
    expected = (commit_act if commit == "with-commit" else "") + tail
    assert result.stdout == expected


# --- 8. the with-commit act that stages a tracked legacy path as deleted ---


@pytest.mark.parametrize("skill", ["handoff", "precompact"])
@pytest.mark.parametrize("with_legacy", [True, False], ids=["legacy", "no_legacy"])
@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
def test_git_rm_act_is_owed_only_to_with_commit_over_a_legacy_file(
    tmp_path: Path, commit: str, *, with_legacy: bool, skill: str
) -> None:
    repo = make_gitlore_repo(tmp_path)
    if with_legacy:
        put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
        put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = (
        handoff_payload(commit) if skill == "handoff" else precompact_payload(commit)
    )
    result = run_checkpoint(repo, payload)
    ok(result)
    out = result.stdout
    if with_legacy and commit == "with-commit":
        act = git_act(LEGACY_TASK_REL, LEGACY_TODO_REL)
        assert act in out
        assert out.index(act) < out.rindex("Once everything above is done")
    else:
        assert "git rm" not in out
        assert "--ignore-unmatch" not in out


def git_status_lines(repo: Path) -> list[str]:
    """Return `git status --porcelain` as lines."""
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


def run_printed_git_rm(repo: Path, out: str) -> None:
    """Run the git act stdout prints, from a subdirectory of the repository.

    The agent's Bash cwd persists across calls and is anywhere under the root,
    so the act must work from there: a pathspec relative to the cwd matches
    nothing and `--ignore-unmatch -q` hides it. The wording around the act is
    free; the command is what the line holds between backticks, and it is run
    through a shell exactly as printed, quoting included.
    """
    line = next(ln for ln in out.splitlines() if GIT_RM in ln)
    command = line[line.index(GIT_RM) :]
    command = command[: command.index("`")]
    assert command.removeprefix(GIT_RM).strip(), line
    sub = repo / "sub"
    sub.mkdir(exist_ok=True)
    subprocess.run(["bash", "-c", command], cwd=sub, check=True)


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
def test_checkpoint_leaves_a_tracked_legacy_file_to_the_printed_git_act(
    tmp_path: Path, commit: str
) -> None:
    """NFR1: the checkpoint renames on the filesystem and stages nothing.

    The legacy file is tracked, as it is in most repositories: the index is
    untouched (` D`, not `D `) whatever the commit mode, so git work cannot hide
    behind an untracked fixture. Under with-commit, running the printed act and
    adding the root file is what makes git record a rename.
    """
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    git = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run([*git, "add", "-f", LEGACY_TODO_REL], cwd=repo, check=True)
    subprocess.run([*git, "commit", "-qm", "seed"], cwd=repo, check=True)
    result = run_checkpoint(repo, migration_payload(task_clear(), todo_keep(), commit))
    ok(result)
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    status = git_status_lines(repo)
    assert f" D {LEGACY_TODO_REL}" in status, status
    assert "?? TODO.md" in status, status
    if commit == "with-commit":
        run_printed_git_rm(repo, result.stdout)
        status = git_status_lines(repo)
        assert f"D  {LEGACY_TODO_REL}" in status, status
        subprocess.run(["git", "add", "TODO.md"], cwd=repo, check=True)
        status = git_status_lines(repo)
        assert f"R  {LEGACY_TODO_REL} -> TODO.md" in status, status


def test_printed_git_act_over_an_untracked_legacy_file_is_a_silent_no_op(
    tmp_path: Path,
) -> None:
    """The act does not ask which legacy files are tracked: untracked is rc 0.

    Its positive is the tracked row above, the same call over a tracked file,
    where the act stages the deletion from the same subdirectory.
    """
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    result = run_checkpoint(
        repo, migration_payload(task_clear(), todo_keep(), "with-commit")
    )
    ok(result)
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    before = git_status_lines(repo)
    run_printed_git_rm(repo, result.stdout)
    assert git_status_lines(repo) == before


@pytest.mark.parametrize("below", ["pkg", "pkg dir"], ids=["plain", "spaced"])
def test_printed_git_act_reaches_a_root_below_the_top_of_its_repository(
    tmp_path: Path, below: str
) -> None:
    """The root is a subdirectory of a larger repository, not its toplevel.

    `:/` anchors at the top of the repository, so each pathspec carries the
    root's own prefix: without it the act names a path beside the root's, which
    `--ignore-unmatch -q` passes over in silence, and the legacy file stays in
    the index. The spaced row is the prefix reaching the line quoted.
    """
    repo = make_repo(tmp_path)
    root = repo / below
    (root / ".claude").mkdir(parents=True)
    put(root, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    tracked = f"{below}/{LEGACY_TODO_REL}"
    git = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run([*git, "add", "-f", tracked], cwd=repo, check=True)
    subprocess.run([*git, "commit", "-qm", "seed"], cwd=repo, check=True)
    payload = migration_payload(task_clear(), todo_keep(), "with-commit")
    result = run_checkpoint(repo, payload, root)
    ok(result)
    assert read(root / "TODO.md") == TODO_LEGACY_BODY
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved")

    def in_index() -> str:
        listing = ["git", "ls-files", "-z", "--", tracked]
        return subprocess.run(
            listing, cwd=repo, capture_output=True, text=True, check=True
        ).stdout

    assert in_index() == f"{tracked}\0"
    run_printed_git_rm(repo, result.stdout)
    assert in_index() == ""


def test_git_rm_act_names_only_the_files_that_moved_or_went(tmp_path: Path) -> None:
    """The task's legacy file is ignored (root wins): it is not a target."""
    repo = make_gitlore_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(task_content(TASK_WRITTEN), todo_keep(), "with-commit")
    result = run_checkpoint(repo, payload)
    ok(result)
    assert_reported(result.stdout, LEGACY_TASK_REL, "ignored")
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved")
    lines = [ln for ln in result.stdout.splitlines() if "git rm" in ln]
    assert len(lines) == 1, result.stdout
    assert git_act(LEGACY_TODO_REL) in lines[0]
    assert LEGACY_TASK_REL not in lines[0]


def test_git_rm_act_is_not_owed_to_a_legacy_file_that_is_only_ignored(
    tmp_path: Path,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(
        task_content(TASK_ROOT_BODY), todo_keep(), "with-commit"
    )
    result = run_checkpoint(repo, payload)
    ok(result)
    assert_reported(result.stdout, LEGACY_TASK_REL, "ignored")
    assert_reported(result.stdout, LEGACY_TODO_REL, "ignored")
    assert "git rm" not in result.stdout


# --- 9. what is not a legacy file, and what cannot be written to ---


def make_legacy_of_kind(repo: Path, rel: str, kind: str) -> None:
    """Put a regular file, a directory or a dangling symlink at rel."""
    path = repo / rel
    if kind == "file":
        path.write_text(TODO_LEGACY_BODY)
    elif kind == "dir":
        path.mkdir()
    else:
        path.symlink_to("nowhere.md")


@pytest.mark.parametrize(
    "root_before", [None, TODO_ROOT_BODY], ids=["root_absent", "root_with_body"]
)
@pytest.mark.parametrize("kind", ["file", "dir", "dangling_symlink"])
def test_only_a_regular_file_at_the_legacy_path_counts(
    tmp_path: Path, kind: str, root_before: str | None
) -> None:
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", root_before)
    make_legacy_of_kind(repo, LEGACY_TODO_REL, kind)
    before = snapshot(repo)
    result = run_checkpoint(repo, migration_payload(task_clear(), todo_keep()))
    ok(result)
    after = snapshot(repo)
    after.pop(SENTINEL_REL)
    if kind == "file":
        assert read(repo / "TODO.md") == (root_before or TODO_LEGACY_BODY)
        assert_reported(
            result.stdout, LEGACY_TODO_REL, "ignored" if root_before else "moved"
        )
        assert (LEGACY_TODO_REL in after) == bool(root_before)
    else:
        assert after == before
        assert result.stdout == lib.closing_directive("handoff", typed=False)


@pytest.mark.parametrize("action", ["keep", "edit", "content"])
def test_todo_directory_with_a_legacy_body_is_refused_not_a_traceback(
    tmp_path: Path, action: str
) -> None:
    repo = make_repo(tmp_path)
    (repo / "TODO.md").mkdir()
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    before = snapshot(repo)
    todo, _expected, _kind = TODO_OVER_LEGACY[action]
    payload = migration_payload(task_content(TASK_WRITTEN), todo)
    result = run_checkpoint(repo, payload)
    assert result.returncode != 0
    assert "Traceback" not in result.stderr
    assert "TODO.md" in result.stderr
    assert "directory" in result.stderr.lower()
    assert snapshot(repo) == before


def test_task_directory_with_a_legacy_body_is_refused_not_a_traceback(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    (repo / "TASK.md").mkdir()
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    result = run_checkpoint(
        repo, migration_payload(task_content(TASK_WRITTEN), todo_keep())
    )
    assert result.returncode != 0
    assert "Traceback" not in result.stderr
    assert "TASK.md" in result.stderr
    assert "directory" in result.stderr.lower()
    assert snapshot(repo) == before


@pytest.mark.parametrize("half", ["todo", "task"])
def test_clear_over_a_directory_with_a_legacy_file_is_refused_naming_it(
    tmp_path: Path, half: str
) -> None:
    """The refusal holds when the action removes rather than moves.

    The message names the path and says it is a directory; it does not claim a
    move, which a `clear` is not. Its positive is the rows above, the same
    fixture under the actions that move or write.
    """
    repo = make_repo(tmp_path)
    root_rel, legacy_rel, legacy_body = {
        "todo": ("TODO.md", LEGACY_TODO_REL, TODO_LEGACY_BODY),
        "task": ("TASK.md", LEGACY_TASK_REL, TASK_LEGACY_BODY),
    }[half]
    (repo / root_rel).mkdir()
    put(repo, legacy_rel, legacy_body)
    before = snapshot(repo)
    payload = migration_payload(
        task_clear(), todo_clear() if half == "todo" else todo_keep()
    )
    result = run_checkpoint(repo, payload)
    assert result.returncode != 0
    assert "Traceback" not in result.stderr
    assert root_rel in result.stderr
    assert "directory" in result.stderr.lower()
    assert snapshot(repo) == before


# --- 10. a second call finds nothing left to move ---


def test_a_second_identical_call_changes_and_reports_nothing(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(task_clear(), todo_keep(), "with-commit")
    first = run_checkpoint(repo, payload)
    ok(first)
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    assert not (repo / LEGACY_TODO_REL).exists()
    settled = snapshot(repo)
    second = run_checkpoint(repo, payload)
    ok(second)
    assert snapshot(repo) == settled
    assert_not_reported(second.stdout, LEGACY_TODO_REL)
    assert "git rm" not in second.stdout


# --- 11. autoname is a rename only: it never touches the frame files ---


@pytest.mark.parametrize(
    "root_before", [None, TODO_ROOT_BODY], ids=["root_absent", "root_with_body"]
)
def test_autoname_leaves_legacy_files_alone_and_reports_nothing(
    tmp_path: Path, root_before: str | None
) -> None:
    """Its positive is the same legacy fixture under `handoff`: moved there when
    no root file counts, reported ignored when one does."""
    repo = make_repo(tmp_path)
    put(repo, "TODO.md", root_before)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    result = run_checkpoint(repo, {"skill": "autoname", "rename": "T"})
    ok(result)
    after = snapshot(repo)
    after.pop(SENTINEL_REL)
    assert after == before
    assert_not_reported(result.stdout, LEGACY_TASK_REL)
    assert_not_reported(result.stdout, LEGACY_TODO_REL)


# --- 12. a failed root write leaves the legacy file where it was ---

NOT_ROOT = pytest.mark.skipif(
    os.geteuid() == 0, reason="root ignores file modes, so no write fails"
)

# Each case: the root file's name, its legacy rel and body, a headings-only
# root file the write cannot open, and the task and todo that reach it.
FAILING_WRITES = {
    "todo_edit": (
        "TODO.md",
        LEGACY_TODO_REL,
        TODO_LEGACY_BODY,
        HEADINGS_ONLY,
        task_clear(),
        todo_edit("- second legacy item", "- c"),
    ),
    "todo_content": (
        "TODO.md",
        LEGACY_TODO_REL,
        TODO_LEGACY_BODY,
        HEADINGS_ONLY,
        task_clear(),
        todo_content(TODO_WRITTEN),
    ),
    "task_content": (
        "TASK.md",
        LEGACY_TASK_REL,
        TASK_LEGACY_BODY,
        "## Current task\n",
        task_content(TASK_WRITTEN),
        todo_keep(),
    ),
}


@NOT_ROOT
@pytest.mark.parametrize("case", list(FAILING_WRITES))
def test_a_root_write_that_fails_leaves_the_legacy_file_as_it_was(
    tmp_path: Path, case: str
) -> None:
    """The legacy file goes only once the root file holds its bytes.

    The root file has no body, so the legacy file is the half's content, and
    the write to the root name fails (mode 444, standing in for any failure).
    Taking the legacy file off its path first would leave the content nowhere:
    the loader would say `No todo`. Its positive is the rows that move or
    replace the legacy file when the write succeeds.
    """
    root_rel, legacy_rel, legacy_body, bodyless, task, todo = FAILING_WRITES[case]
    repo = make_repo(tmp_path)
    put(repo, legacy_rel, legacy_body)
    put(repo, root_rel, bodyless)
    (repo / root_rel).chmod(0o444)
    before = snapshot(repo)
    result = run_checkpoint(repo, migration_payload(task, todo))
    assert result.returncode != 0
    assert read(repo / legacy_rel) == legacy_body
    assert snapshot(repo) == before


# --- 13. a root file the call does not touch is not read either ---


@NOT_ROOT
@pytest.mark.parametrize("todo_action", ["keep", "clear"])
def test_root_files_that_cannot_be_read_stay_unread_with_no_legacy_file(
    tmp_path: Path, todo_action: str
) -> None:
    """No legacy file anywhere: the call behaves as it did before migration.

    `keep` neither reads nor stats the list, and `clear` only unlinks, so a mode
    000 file is no reason to fail either. Its positive is the same call over a
    legacy file, where the root file is read to tell whether it has a body.
    """
    repo = make_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    then = 1_700_000_000_000_000_000
    os.utime(repo / "TODO.md", ns=(then, then))
    (repo / "TASK.md").chmod(0o000)
    (repo / "TODO.md").chmod(0o000)
    todo = todo_keep() if todo_action == "keep" else todo_clear()
    result = run_checkpoint(repo, migration_payload(task_clear(), todo))
    ok(result)
    assert not (repo / "TASK.md").exists()
    if todo_action == "clear":
        assert not (repo / "TODO.md").exists()
    else:
        assert (repo / "TODO.md").stat().st_mode & 0o777 == 0
        assert (repo / "TODO.md").stat().st_mtime_ns == then
        (repo / "TODO.md").chmod(0o644)
        assert read(repo / "TODO.md") == TODO_ROOT_BODY


# --- 14. a legacy path that is a symlink to a file is refused ---

# A symlink at the legacy path resolves from its own directory, so renaming it
# onto the root name leaves a link that points nowhere (a relative target) or
# reads through to a file the checkpoint does not own. It is refused like a
# directory at the root path. A dangling one holds no file and is no legacy
# file at all (`test_only_a_regular_file_at_the_legacy_path_counts`).


def make_symlinked_legacy(repo: Path, rel: str, body: str, *, relative: bool) -> None:
    """Link rel to a file under `notes/`, by a relative or an absolute path."""
    target = repo / "notes" / "elsewhere.md"
    target.parent.mkdir()
    target.write_text(body)
    link = repo / rel
    link.symlink_to(os.path.relpath(target, link.parent) if relative else target)


@pytest.mark.parametrize("relative", [True, False], ids=["relative", "absolute"])
@pytest.mark.parametrize("action", ["keep", "edit", "content", "clear"])
def test_todo_symlinked_at_the_legacy_path_is_refused_and_nothing_moves(
    tmp_path: Path, action: str, *, relative: bool
) -> None:
    """Refused whole: the task half's legacy file stays too.

    Its positive is `test_legacy_todo_with_no_root_file_is_moved_to_the_root_name`,
    the same call over a regular file at the same path.
    """
    todo = {
        "keep": todo_keep(),
        "edit": todo_edit("- second legacy item", "- c"),
        "content": todo_content(TODO_WRITTEN),
        "clear": todo_clear(),
    }[action]
    repo = make_repo(tmp_path)
    make_symlinked_legacy(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY, relative=relative)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    before = snapshot(repo)
    result = run_checkpoint(repo, migration_payload(task_content(TASK_WRITTEN), todo))
    assert result.returncode != 0
    assert "Traceback" not in result.stderr
    assert LEGACY_TODO_REL in result.stderr
    assert snapshot(repo) == before


@pytest.mark.parametrize("relative", [True, False], ids=["relative", "absolute"])
@pytest.mark.parametrize("action", ["content", "clear"])
def test_task_symlinked_at_the_legacy_path_is_refused_and_nothing_moves(
    tmp_path: Path, action: str, *, relative: bool
) -> None:
    """Its positive: the written task replacing a regular legacy task file."""
    task = task_content(TASK_WRITTEN) if action == "content" else task_clear()
    repo = make_repo(tmp_path)
    make_symlinked_legacy(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY, relative=relative)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    result = run_checkpoint(repo, migration_payload(task, todo_keep()))
    assert result.returncode != 0
    assert "Traceback" not in result.stderr
    assert LEGACY_TASK_REL in result.stderr
    assert snapshot(repo) == before


# --- 15. a move survives a rename across devices ---

# A cross-device rename cannot be provoked portably, so the harness makes every
# rename or replace of a path under `.claude/handoff-` raise EXDEV, as the
# kernel does when `.claude` is another mount, and runs checkpoint.py under it.
CROSS_DEVICE_HARNESS = """\
import errno
import os
import runpy
import sys

real = {"rename": os.rename, "replace": os.replace}


def across_devices(name):
    def move(src, dst, *args, **kwargs):
        if ".claude/handoff-" in os.fspath(src):
            raise OSError(errno.EXDEV, os.strerror(errno.EXDEV), src, None, dst)
        return real[name](src, dst, *args, **kwargs)

    return move


os.rename = across_devices("rename")
os.replace = across_devices("replace")
script = sys.argv[1]
sys.path.insert(0, os.path.dirname(script))
runpy.run_path(script, run_name="__main__")
"""

# Reports which errno each rename of a legacy path raises under the harness.
CROSS_DEVICE_PROBE = """\
import os

for name in ("rename", "replace"):
    try:
        getattr(os, name)(".claude/handoff-todo.md", "TODO.md")
    except OSError as exc:
        print(name, exc.errno)
"""


def cross_device_command(tmp_path: Path, script: Path = CHECKPOINT) -> list[str]:
    """Return the argv that runs script under the cross-device harness."""
    harness = tmp_path / "cross_device_harness.py"
    harness.write_text(CROSS_DEVICE_HARNESS)
    return [sys.executable, str(harness), str(script)]


def test_the_cross_device_harness_fails_a_rename_of_a_legacy_file(
    tmp_path: Path,
) -> None:
    """The control for the row below, which would pass if the patch missed."""
    probe = tmp_path / "probe.py"
    probe.write_text(CROSS_DEVICE_PROBE)
    result = subprocess.run(
        cross_device_command(tmp_path, probe),
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.stdout.split() == [
        "rename",
        str(errno.EXDEV),
        "replace",
        str(errno.EXDEV),
    ], result.stderr


def test_keep_moves_a_legacy_todo_across_devices_with_its_modification_time(
    tmp_path: Path,
) -> None:
    """The move falls back to a copy that keeps the time, then unlinks.

    Its positive is `test_keep_moves_the_legacy_todo_with_its_modification_time`,
    the same fixture where the rename works, and the control above shows the
    harness makes the rename fail.
    """
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    then = 1_700_000_000_000_000_000
    os.utime(repo / LEGACY_TODO_REL, ns=(then, then))
    command = cross_device_command(tmp_path)
    result = run_checkpoint(
        repo, migration_payload(task_clear(), todo_keep()), command=command
    )
    ok(result)
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    assert (repo / "TODO.md").stat().st_mtime_ns == then
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved")
