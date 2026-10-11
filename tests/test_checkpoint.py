"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the schema validation,
write semantics, transition/sentinel composition, and directive composition that
live in checkpoint.py + _checkpoint_lib.py. Port of the checkpoint.sh-specific
rows of tests/checkpoint.bats — see docs/changelog/2026-08-10-python-split.md.

inject-checkpoint-root.sh, bin/handoff-approved and the bin/handoff-checkpoint
shim stay bash and stay tested in tests/checkpoint.bats; this file covers only
checkpoint.py's own behavior.
"""

import json
import os
import shutil
import subprocess
import sys
from collections.abc import Callable, Mapping
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
    repo: Path, payload: Mapping[str, object] | str, root: Path | None = None
) -> subprocess.CompletedProcess[str]:
    """Run checkpoint.py with cwd=repo, HANDOFF_ROOT=root (default repo)."""
    env = dict(os.environ)
    env["HANDOFF_ROOT"] = str(root if root is not None else repo)
    env["CLAUDE_CODE_SESSION_ID"] = os.environ.get(
        "CLAUDE_CODE_SESSION_ID", "sess-checkpoint"
    )
    env.pop("CLAUDE_PROJECT_DIR", None)
    text = payload if isinstance(payload, str) else json.dumps(payload)
    return subprocess.run(
        [sys.executable, str(CHECKPOINT)],
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
