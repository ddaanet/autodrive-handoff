"""The Vibe checkpoint end to end, and the skill copies' identity.

Each behavioural test runs skills/<skill>/checkpoint.py through python3 as the
skill protocol does — payload on stdin, cwd at a throwaway project root — and
asserts the writes and the directive output. The copy-identity test is the sync
guard: an edit lands in vibe-plugin/scripts/ and reaches the caller skills
through `just sync-vibe`; a drifted copy fails here.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

# The repo top level, as check-size reserves for the toolkit: the tests run
# from anywhere pytest plants them, so resolve against this file's location.
REPO = Path(__file__).resolve().parent.parent
VIBE = REPO / "vibe-plugin"
SKILL_DIRS = ("handoff", "precompact", "autoname")
MODULES = (
    "checkpoint.py",
    "_checkpoint_payload.py",
    "_checkpoint_plan.py",
    "_checkpoint_lib.py",
)

TASK = "## Current task\n\nPort the handoff plugin to Vibe; the tree is written."
TODO = "## Open decisions\n\n- None left.\n\n## Remaining\n\n- Run the gates."


def run_checkpoint(
    tmp_path: Path, payload: dict[str, Any], *, skill: str = "handoff"
) -> subprocess.CompletedProcess[str]:
    """Run the named skill's checkpoint with the payload on stdin.

    HOME is pinned to the project dir: the guard resolves the user's installed
    compaction prompt through Path.home(), and a runner that has one must not
    silence the warning the tests assert.
    """
    return subprocess.run(
        [
            sys.executable,
            str(VIBE / "skills" / skill / "checkpoint.py"),
        ],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        cwd=tmp_path,
        env={**os.environ, "HOME": str(tmp_path)},
        check=False,
    )


@pytest.fixture
def project(tmp_path: Path) -> Path:
    """A throwaway project root: .git marks it for the root check."""
    (tmp_path / ".git").mkdir()
    return tmp_path


def test_copies_are_identical_to_the_canonical_scripts() -> None:
    """The sync guard: every skill module copy matches vibe-plugin/scripts."""
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
    """A driven handoff writes both files and ends on the /clear line."""
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Port The Handoff Plugin To Vibe",
            "clear": True,
            "task": TASK,
            "todo": TODO,
        },
    )
    assert result.returncode == 0, result.stderr
    assert (project / "TASK.md").read_text() == TASK
    assert (project / "TODO.md").read_text() == TODO
    assert "Ready to /clear" in result.stdout
    assert "`/rename Port The Handoff Plugin To Vibe`" in result.stdout
    assert "make the commit the request called for" in result.stdout


def test_handoff_prepared_wording_when_not_clear(project: Path) -> None:
    """Clear: false closes on the prepared line, not the ready one."""
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "without-commit",
            "rename": "Some Title",
            "clear": False,
            "task": TASK,
            "todo": {"action": "keep"},
        },
    )
    assert result.returncode == 0, result.stderr
    assert "Written — /clear when you are ready." in result.stdout
    assert "Ready to /clear" not in result.stdout
    assert "`/rename Some Title`" in result.stdout


def test_claude_continue_key_is_unknown(project: Path) -> None:
    """The Claude schema's `continue` is rejected before anything is written."""
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Some Title",
            "clear": True,
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
            "clear": True,
            "task": "## Current task\n\n" + "word " * 300,
            "todo": TODO,
        },
    )
    assert result.returncode == 2
    assert "the limit is 1000" in result.stderr
    assert not (project / "TASK.md").exists()
    assert not (project / "TODO.md").exists()


def test_precompact_removes_task_and_warns_when_no_prompt(
    project: Path,
) -> None:
    """Compact: true removes TASK.md; the guard warns the seam is absent."""
    (project / "TASK.md").write_text(TASK)
    result = run_checkpoint(
        project,
        {
            "skill": "precompact",
            "commit": "without-commit",
            "compact": True,
            "todo": {"action": "keep"},
        },
        skill="precompact",
    )
    assert result.returncode == 0, result.stderr
    assert not (project / "TASK.md").exists()
    assert "the custom compaction prompt, and none is installed" in result.stdout


def test_precompact_guard_silent_when_prompt_installed(
    project: Path,
) -> None:
    """The installed prompt and its config line resolve, and the guard is
    quiet."""
    prompts = project / ".vibe" / "prompts"
    prompts.mkdir(parents=True)
    (prompts / "handoff-compact.md").write_text("preserve the files\n")
    (project / ".vibe" / "config.toml").write_text(
        'compaction_prompt_id = "handoff-compact"\n'
    )
    (project / "TASK.md").write_text(TASK)
    result = run_checkpoint(
        project,
        {
            "skill": "precompact",
            "commit": "without-commit",
            "compact": True,
            "todo": {"action": "keep"},
        },
        skill="precompact",
    )
    assert result.returncode == 0, result.stderr
    assert not (project / "TASK.md").exists()
    assert "compaction prompt" not in result.stdout


def test_precompact_focus_string_refused(project: Path) -> None:
    """The Claude schema's focus string says where the focus belongs instead."""
    result = run_checkpoint(
        project,
        {
            "skill": "precompact",
            "commit": "without-commit",
            "compact": "keep the parser work",
            "todo": {"action": "keep"},
        },
        skill="precompact",
    )
    assert result.returncode == 2
    assert "takes no argument" in result.stderr


def test_todo_edit_replaces_one_occurrence(project: Path) -> None:
    """An edit drops one item without carrying the whole list."""
    existing = "## Remaining\n\n- Old item.\n- Second item.\n"
    (project / "TODO.md").write_text(existing)
    result = run_checkpoint(
        project,
        {
            "skill": "precompact",
            "commit": "with-commit",
            "compact": False,
            "todo": {"action": "edit", "old_string": "- Old item.", "new_string": ""},
        },
        skill="precompact",
    )
    assert result.returncode == 0, result.stderr
    assert (project / "TODO.md").read_text() == "## Remaining\n\n\n- Second item.\n"


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


def test_autoname_refuses_boundary_fields(project: Path) -> None:
    """A boundary field under autoname names the field, exit 2."""
    result = run_checkpoint(
        project,
        {"skill": "autoname", "rename": "Try Guard", "commit": "with-commit"},
        skill="autoname",
    )
    assert result.returncode == 2
    assert 'commit: forbidden when skill is "autoname"' in result.stderr


def test_memory_directive_names_the_dirty_submodule(
    project: Path,
) -> None:
    """A dirty gitlore-memory submodule turns the memory directive on."""
    mem = project / "memory"
    subprocess.run(["git", "init", "-q", str(mem)], check=True)
    (mem / "note.md").write_text("durable\n")
    subprocess.run(
        ["git", "-C", str(mem), "add", "note.md"],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        [
            "git",
            "config",
            "--file",
            str(project / ".gitmodules"),
            "submodule.gitlore-memory.path",
            "memory",
        ],
        check=True,
        capture_output=True,
    )
    result = run_checkpoint(
        project,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Some Title",
            "clear": True,
            "task": TASK,
            "todo": TODO,
        },
    )
    assert result.returncode == 0, result.stderr
    assert "gitlore memory has uncommitted changes:" in result.stdout
    assert "gitlore:commit" in result.stdout
    assert "the memory gitlink `gitlore:commit` staged" in result.stdout


def test_root_check_refuses_a_non_project_cwd(tmp_path: Path) -> None:
    """A cwd with no project marker errors naming root, before any write."""
    result = run_checkpoint(
        tmp_path,
        {
            "skill": "handoff",
            "commit": "with-commit",
            "rename": "Some Title",
            "clear": True,
            "task": TASK,
            "todo": TODO,
        },
    )
    assert result.returncode == 2
    assert "root: the cwd is not a project root" in result.stderr
    assert not (tmp_path / "TASK.md").exists()
