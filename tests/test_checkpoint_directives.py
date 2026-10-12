"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the directive parts
printed on stdout: the memory directive, the commit act, the order of the parts,
their composition per skill, and the closing line (`closing_directive`).

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

import os
import shutil
import subprocess
from collections.abc import Callable
from pathlib import Path

import _checkpoint_lib as lib
import pytest
from conftest import (
    GITLORE_MEMORY_APPROVAL_CLAUSE,
    add_flat_sdd_ledger,
    add_sdd_ledger,
    add_unidentified_sdd_ledger,
    dirty_memory,
    handoff_payload,
    make_gitlore_repo,
    make_repo,
    precompact_payload,
    run_checkpoint,
    task_clear,
    todo_keep,
)

pytestmark = pytest.mark.usefixtures("_session_id")


# ==========================================================================
# Memory directive
# ==========================================================================


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
