"""The Vibe checkpoint end to end, and the skill copies' identity.

Each behavioural test runs skills/<skill>/checkpoint.py through python3 as the
skill protocol does — payload on stdin, cwd at a throwaway project root — and
asserts the writes and the directive output. The copy-identity test is the sync
guard: an edit lands in vibe-plugin/scripts/ and reaches the caller skills
through `just sync-vibe`; a drifted copy fails here.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Any

import conftest
import pytest
from conftest import dirty_memory, make_gitlore_repo, make_repo

# The repo top level, as check-size reserves for the toolkit: the tests run
# from anywhere pytest plants them, so resolve against this file's location.
REPO = Path(__file__).resolve().parent.parent
VIBE = REPO / "vibe-plugin"
# Derived from the tree, as the `sync-vibe` recipe derives its targets: the
# skills carrying a checkpoint.py, and the canonical modules they copy.
SKILL_DIRS = tuple(
    sorted(p.parent.name for p in (VIBE / "skills").glob("*/checkpoint.py"))
)
MODULES = tuple(sorted(p.name for p in (VIBE / "scripts").glob("*.py")))

TASK = "## Current task\n\nPort the handoff plugin to Vibe; the tree is written."
TODO = "## Open decisions\n\n- None left.\n\n## Remaining\n\n- Run the gates."


def run_checkpoint(
    repo: Path, payload: dict[str, Any], *, skill: str = "handoff"
) -> subprocess.CompletedProcess[str]:
    """Run the named skill's checkpoint with the payload on stdin."""
    return conftest.run_checkpoint(
        repo,
        payload,
        command=(sys.executable, str(VIBE / "skills" / skill / "checkpoint.py")),
        with_session_id=False,
    )


@pytest.fixture
def project(tmp_path: Path) -> Path:
    """A throwaway project root: git init marks it for the root check."""
    return make_repo(tmp_path)


def test_copies_are_identical_to_the_canonical_scripts() -> None:
    """The sync guard: every skill module copy matches vibe-plugin/scripts."""
    assert SKILL_DIRS
    assert MODULES
    for skill_dir in SKILL_DIRS:
        for module in MODULES:
            copy = VIBE / "skills" / skill_dir / module
            assert copy.is_file(), f"missing copy: skills/{skill_dir}/{module}"
            assert copy.read_bytes() == (VIBE / "scripts" / module).read_bytes(), (
                f"skills/{skill_dir}/{module} drifted from scripts/{module};"
                " run `just sync-vibe`"
            )


def test_handoff_writes_the_frame_and_names_the_clear(
    project: Path,
) -> None:
    """A handoff writes both files and ends on the one /clear line."""
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Port The Handoff Plugin To Vibe",
            "task": TASK,
            "todo": TODO,
        },
    )
    assert result.returncode == 0, result.stderr
    assert (project / "TASK.md").read_text() == TASK
    assert (project / "TODO.md").read_text() == TODO
    assert (
        result.stdout.rstrip("\n").splitlines()[-1]
        == "`Written — /clear when you are ready; the fresh session reads"
        " TASK.md and TODO.md first.`"
    )
    assert "`/rename Port The Handoff Plugin To Vibe`" in result.stdout
    assert "make the commit the request called for" in result.stdout


def test_claude_continue_key_is_unknown(project: Path) -> None:
    """The Claude schema's `continue` is rejected before anything is written."""
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Some Title",
            "continue": True,
            "task": TASK,
            "todo": TODO,
        },
    )
    assert result.returncode == 2
    assert 'unknown key "continue"' in result.stderr
    assert not (project / "TASK.md").exists()


def test_task_over_limit_rejected_and_nothing_written(project: Path) -> None:
    """A 1001-character prose body exits 2; the absent file proves the order."""
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Some Title",
            "task": "## Current task\n\n" + "word " * 300,
            "todo": TODO,
        },
    )
    assert result.returncode == 2
    assert "the limit is 1000" in result.stderr
    assert not (project / "TASK.md").exists()
    assert not (project / "TODO.md").exists()


def test_precompact_writes_the_task_and_names_the_compact(
    project: Path,
) -> None:
    """Precompact writes TASK.md as handoff does, and the output is the
    closing line alone: the /compact line with its direction."""
    (project / "TASK.md").write_text("## Current task\n\nstale\n")
    result = run_checkpoint(
        project,
        {
            "skill": "precompact",
            "commit": "without-commit",
            "task": TASK,
            "todo": {"action": "keep"},
        },
        skill="precompact",
    )
    assert result.returncode == 0, result.stderr
    assert (project / "TASK.md").read_text() == TASK
    assert result.stdout == (
        "Once everything above is done, end on one line, the command the user"
        " pastes to compact:\n"
        "`/compact TASK.md and TODO.md survive this"
        " compaction on disk and are the task frame: do not reproduce them."
        " State the current task and its next action as the conversation now"
        " stands, and say the next turn first reads TASK.md and TODO.md from"
        " disk.`\n"
    )


def test_precompact_without_task_errors_and_keeps_the_task_file(
    project: Path,
) -> None:
    """An absent `task` is a named error under precompact, not a removal."""
    (project / "TASK.md").write_text(TASK)
    result = run_checkpoint(
        project,
        {
            "skill": "precompact",
            "commit": "without-commit",
            "todo": {"action": "keep"},
        },
        skill="precompact",
    )
    assert result.returncode == 2
    assert "task: required" in result.stderr
    assert (project / "TASK.md").read_text() == TASK


@pytest.mark.parametrize(
    ("skill", "key", "value"),
    [
        ("precompact", "compact", True),
        ("precompact", "compact", "keep the parser work"),
        ("precompact", "clear", True),
        ("handoff", "clear", True),
        ("handoff", "compact", False),
    ],
)
def test_transition_keys_are_unknown(
    project: Path, skill: str, key: str, value: object
) -> None:
    """No transition flag exists: `clear` and `compact` are unknown keys."""
    payload: dict[str, Any] = {
        "skill": skill,
        "commit": "without-commit",
        "task": {"action": "clear"},
        "todo": {"action": "keep"},
        key: value,
    }
    if skill == "handoff":
        payload["rename"] = "Some Title"
    result = run_checkpoint(project, payload, skill=skill)
    assert result.returncode == 2
    assert f'unknown key "{key}"' in result.stderr
    assert not (project / "TASK.md").exists()


def test_todo_edit_replaces_one_occurrence(project: Path) -> None:
    """An edit drops one item without carrying the whole list."""
    existing = "## Remaining\n\n- Old item.\n- Second item.\n"
    (project / "TODO.md").write_text(existing)
    result = run_checkpoint(
        project,
        {
            "skill": "precompact",
            "commit": "with-commit",
            "task": {"action": "clear"},
            "todo": {"action": "edit", "old_string": "- Old item.", "new_string": ""},
        },
        skill="precompact",
    )
    assert result.returncode == 0, result.stderr
    assert (project / "TODO.md").read_text() == "## Remaining\n\n\n- Second item.\n"
    assert result.stdout.rstrip("\n").splitlines()[-1].startswith("`/compact ")


def test_autoname_prints_the_rename_line_and_writes_nothing(
    project: Path,
) -> None:
    """Autoname's only output is the title and the user-run /rename."""
    result = run_checkpoint(
        project, {"skill": "autoname", "rename": "Try Guard"}, skill="autoname"
    )
    assert result.returncode == 0, result.stderr
    assert "/rename Try Guard" in result.stdout
    assert not (project / "TASK.md").exists()


def test_autoname_succeeds_outside_a_project(tmp_path: Path) -> None:
    """Autoname writes nothing, so a cwd with no project marker is fine."""
    result = run_checkpoint(
        tmp_path, {"skill": "autoname", "rename": "Try Guard"}, skill="autoname"
    )
    assert result.returncode == 0, result.stderr
    assert "/rename Try Guard" in result.stdout


def test_autoname_refuses_boundary_fields(project: Path) -> None:
    """A boundary field under autoname names the field, exit 2."""
    result = run_checkpoint(
        project,
        {"skill": "autoname", "rename": "Try Guard", "commit": "with-commit"},
        skill="autoname",
    )
    assert result.returncode == 2
    assert 'commit: forbidden when skill is "autoname"' in result.stderr


def test_memory_directive_names_the_dirty_submodule(tmp_path: Path) -> None:
    """A dirty gitlore-memory submodule turns the memory directive on."""
    project = make_gitlore_repo(tmp_path)
    dirty_memory(project)
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Some Title",
            "task": TASK,
            "todo": TODO,
        },
    )
    assert result.returncode == 0, result.stderr
    assert "gitlore memory has uncommitted changes:" in result.stdout
    assert "Vibe has no gitlore:commit skill" in result.stdout
    assert "leave the memory pointer out of it" in result.stdout
    assert "staged" not in result.stdout


def test_root_check_refuses_a_non_project_cwd(tmp_path: Path) -> None:
    """A cwd with no project marker errors naming root, before any write."""
    result = run_checkpoint(
        tmp_path,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Some Title",
            "task": TASK,
            "todo": TODO,
        },
    )
    assert result.returncode == 2
    assert "root: the cwd is not a project root" in result.stderr
    assert not (tmp_path / "TASK.md").exists()
