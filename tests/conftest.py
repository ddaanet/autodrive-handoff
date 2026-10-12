"""Helpers shared by the tests/test_checkpoint_*.py files.

Those files test scripts/checkpoint.py (handoff-checkpoint), whose logic lives
in checkpoint.py, _checkpoint_plan.py and _checkpoint_lib.py. They are the port
of the checkpoint.sh-specific rows of tests/checkpoint.bats — see
docs/changelog/2026-08-10-python-split.md. inject-checkpoint-root.sh,
bin/handoff-approved and the bin/handoff-checkpoint shim stay bash and stay
tested in tests/checkpoint.bats; the Python files cover only checkpoint.py's own
behavior.

What is here is what two or more of those files use: the repository builders,
the payload builders, the `run_checkpoint` runner. A helper only one file uses
lives in that file. The test files import from here by name (pytest's
`pythonpath` carries tests/), since a fixture would change every call site.

`_session_id` is not `autouse`: this conftest also reaches the other test files,
which must not inherit it. Each tests/test_checkpoint_*.py applies it with a
module-level `pytestmark`.
"""

import json
import os
import shutil
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

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


@pytest.fixture
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


def prose(n: int, char: str = "a") -> str:
    """One prose line of exactly n characters, never a heading or a list
    item."""
    return char * n


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
