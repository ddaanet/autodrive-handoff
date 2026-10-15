"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the arming
instruction, the rule that picks the `held` or `armed` state of the sentinel
(and the held state with its owner), and the held path's validation of
CLAUDE_CODE_SESSION_ID before any write.

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

from collections.abc import Callable
from pathlib import Path

import _checkpoint_lib as lib
import pytest
from conftest import (
    add_sdd_ledger,
    dirty_memory,
    drive_state,
    handoff_payload,
    make_gitlore_repo,
    precompact_payload,
    run_checkpoint,
    task_clear,
    todo_keep,
    unset_clause_file,
)

pytestmark = pytest.mark.usefixtures("_session_id")


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
    unset_clause_file(repo)
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
    assert first_line == "armed sess-checkpoint"
    assert "handoff-approved" not in result.stdout
    assert commit_act in result.stdout


def test_untyped_precompact_with_commit_clean_memory_is_armed(tmp_path: Path) -> None:
    """The FR-G marker cell (¬K ∧ ¬T ∧ C) types nothing, so it never holds."""
    repo = make_gitlore_repo(tmp_path)
    assert lib.memory_directive(str(repo), "with-commit").text == ""
    result = run_checkpoint(repo, precompact_payload("with-commit"))
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed sess-checkpoint"


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
    assert first_line == "armed sess-checkpoint"
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


def test_held_via_commit_session_id_unset_errors_before_any_write(
    tmp_path: Path,
) -> None:
    """Held through (T ∧ C): a typed transition owing a commit, clean memory."""
    repo = make_gitlore_repo(tmp_path)
    payload = handoff_payload("with-commit")
    payload["clear"] = True
    result = run_checkpoint(repo, payload, with_session_id=False)
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
    result = run_checkpoint(repo, payload, with_session_id=False)
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


def test_armed_cell_session_id_unset_errors_before_any_write(tmp_path: Path) -> None:
    """An armed sentinel names its owner too, so an armed cell needs the id."""
    repo = make_gitlore_repo(tmp_path)
    payload = handoff_payload("without-commit")
    result = run_checkpoint(repo, payload, with_session_id=False)
    assert result.returncode != 0
    assert "cannot read back" not in result.stderr
    assert "CLAUDE_CODE_SESSION_ID" in result.stderr
    _assert_nothing_written(repo)


def test_armed_cell_session_id_set_names_the_owner(tmp_path: Path) -> None:
    """Paired positive for the armed row: same fixture, variable set."""
    repo = make_gitlore_repo(tmp_path)
    payload = handoff_payload("without-commit")
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed sess-checkpoint"


# --- held versus armed ---


def test_typed_transition_with_memory_gate_pending_held(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": True,
        "continue": True,
        "task": task_clear(),
        "todo": "- run the gate\n",
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
        "continue": False,
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
        "continue": True,
        "task": task_clear(),
        "todo": "- run the gate\n",
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed sess-checkpoint"
    assert "handoff-approved" not in result.stdout


def test_untyped_handoff_still_types_rename_so_it_holds_too(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    payload = {
        "skill": "handoff",
        "commit": "without-commit",
        "rename": "A Title",
        "clear": False,
        "continue": False,
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
        "continue": False,
        "todo": todo_keep(),
    }
    result = run_checkpoint(repo, payload)
    assert result.returncode == 0
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed sess-checkpoint"
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
    assert first_line == "armed sess-checkpoint"
