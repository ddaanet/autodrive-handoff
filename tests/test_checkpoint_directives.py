"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the directive parts
printed on stdout: the memory directive, the commit act and the order of the
parts.

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

import shutil
from collections.abc import Callable
from pathlib import Path

import _checkpoint_lib as lib
import pytest
from conftest import (
    COMMIT_ACT,
    COMMIT_ACT_WITH_MEMORY,
    MEMORY_DIRECTIVE_CLOSING,
    add_sdd_ledger,
    assert_stdout_is_closing,
    dirty_memory,
    handoff_payload,
    make_gitlore_repo,
    make_repo,
    precompact_payload,
    run_checkpoint,
    run_git,
)

pytestmark = pytest.mark.usefixtures("_session_id")


# ==========================================================================
# Memory directive
# ==========================================================================


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


MEMORY_HEAD = "gitlore memory has uncommitted changes:"
MEMORY_PART = f"{MEMORY_HEAD}\n\n?? feedback_x.md\n\n{MEMORY_DIRECTIVE_CLOSING}\n"


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
def test_dirty_memory_directive_is_the_status_then_the_skill_sentence(
    tmp_path: Path, commit: str
) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload(commit))
    assert result.returncode == 0
    assert MEMORY_PART in result.stdout


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
def test_dirty_memory_directive_names_no_file_handshake(
    tmp_path: Path, commit: str
) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload(commit))
    assert result.returncode == 0
    assert "uncommitted changes" in result.stdout
    out = result.stdout.lower()
    for gone in (
        "gitlore-memory-message",
        "gitlore-commit-memory",
        "memoryapprovalclausefile",
        "trigger",
        "blockquote",
    ):
        assert gone not in out


def _memory_part(stdout: str) -> str:
    """The memory directive: from its head through its closing sentence."""
    start = stdout.find(MEMORY_HEAD)
    assert start != -1, stdout
    end = stdout.find(MEMORY_DIRECTIVE_CLOSING, start)
    assert end != -1, stdout
    return stdout[start : end + len(MEMORY_DIRECTIVE_CLOSING)]


def test_memory_part_is_byte_identical_under_both_commit_modes(
    tmp_path: Path,
) -> None:
    parts = []
    for commit in ("without-commit", "with-commit"):
        repo = make_gitlore_repo(tmp_path, f"glrepo_{commit}")
        dirty_memory(repo)
        result = run_checkpoint(repo, handoff_payload(commit))
        assert result.returncode == 0
        parts.append(_memory_part(result.stdout))
    assert parts[0] == parts[1]
    assert parts[0] == MEMORY_PART.rstrip("\n")


# ==========================================================================
# Commit act
# ==========================================================================


@pytest.mark.parametrize("payload_fn", [handoff_payload, precompact_payload])
def test_with_commit_prints_the_commit_act(
    tmp_path: Path, payload_fn: Callable[[str], dict[str, object]]
) -> None:
    repo = make_gitlore_repo(tmp_path)
    result = run_checkpoint(repo, payload_fn("with-commit"))
    assert result.returncode == 0
    assert COMMIT_ACT in result.stdout
    assert "gitlink" not in result.stdout


@pytest.mark.parametrize("payload_fn", [handoff_payload, precompact_payload])
def test_with_commit_and_dirty_memory_names_the_staged_gitlink(
    tmp_path: Path, payload_fn: Callable[[str], dict[str, object]]
) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, payload_fn("with-commit"))
    assert result.returncode == 0
    assert COMMIT_ACT_WITH_MEMORY in result.stdout
    assert COMMIT_ACT not in result.stdout


@pytest.mark.parametrize("payload_fn", [handoff_payload, precompact_payload])
@pytest.mark.parametrize("dirty", [False, True], ids=["clean", "dirty"])
def test_without_commit_prints_no_commit_act(
    tmp_path: Path,
    payload_fn: Callable[[str], dict[str, object]],
    *,
    dirty: bool,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    if dirty:
        dirty_memory(repo)
    result = run_checkpoint(repo, payload_fn("without-commit"))
    assert result.returncode == 0
    assert COMMIT_ACT not in result.stdout
    assert COMMIT_ACT_WITH_MEMORY not in result.stdout
    assert "make the commit the request called for" not in result.stdout


def test_commit_act_is_the_exact_no_git_verb_sentence(tmp_path: Path) -> None:
    """Pin the exact sentence rather than blacklisting verb spellings.

    A reword naming a verb another way ("stage and commit", "`git ci`") passes a
    substring blacklist. Memory clean, no legacy file, nothing to continue: the
    act and the closing line are all there is, so the whole stdout is pinned.
    """
    repo = make_gitlore_repo(tmp_path)
    result = run_checkpoint(repo, precompact_payload("with-commit"))
    assert result.returncode == 0
    closing = lib.closing_directive("precompact", typed=False)
    assert result.stdout == COMMIT_ACT + "\n" + closing


# Unit rows on the new `commit_directive(root, legacy_paths, *, memory)`
# signature: the checkpoint rows above are the behavioural pins.
@pytest.mark.parametrize(
    ("memory", "expected"),
    [(False, COMMIT_ACT), (True, COMMIT_ACT_WITH_MEMORY)],
    ids=["memory_clean", "memory_owed"],
)
def test_commit_directive_unit_follows_memory(*, memory: bool, expected: str) -> None:
    assert lib.commit_directive("", (), memory=memory) == expected


# ==========================================================================
# Ordering
# ==========================================================================


def test_handoff_parts_print_in_order(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    add_sdd_ledger(repo)
    todo_boundary = lib.todo_boundary(str(repo))
    assert todo_boundary
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    assert result.returncode == 0
    out = result.stdout
    assert MEMORY_DIRECTIVE_CLOSING in out
    assert COMMIT_ACT_WITH_MEMORY in out
    memory_index = out.index("gitlore:commit")
    todo_index = out.index(todo_boundary)
    commit_index = out.index(COMMIT_ACT_WITH_MEMORY)
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
    closing = lib.closing_directive("precompact", typed=False)
    assert sdd_directive
    assert closing
    result = run_checkpoint(repo, precompact_payload("with-commit"))
    assert result.returncode == 0
    # Untyped precompact types nothing, so it stays armed with memory dirty:
    # the one cell where the closing line follows every other part.
    first_line = (repo / ".claude" / "autodrive").read_text().splitlines()[0]
    assert first_line == "armed sess-checkpoint"
    out = result.stdout
    assert MEMORY_DIRECTIVE_CLOSING in out
    assert COMMIT_ACT_WITH_MEMORY in out
    memory_index = out.index("gitlore:commit")
    sdd_index = out.index(sdd_directive)
    commit_index = out.index(COMMIT_ACT_WITH_MEMORY)
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
# The harness acts on the repository it built, whatever git's environment
# ==========================================================================
#
# gitlore's pre-commit hook runs `just precommit` with GIT_DIR, GIT_INDEX_FILE
# and GIT_WORK_TREE exported for the outer repository. A builder or a runner
# that passes them on aims every git call at that repository instead of the one
# under tmp_path. A decoy repository stands in for the outer one.


def _decoy_git_env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    decoy = tmp_path / "decoy"
    decoy.mkdir()
    run_git(decoy, "init", "-q")
    (decoy / "tracked.txt").write_text("decoy\n")
    run_git(decoy, "add", "tracked.txt")
    monkeypatch.setenv("GIT_DIR", str(decoy / ".git"))
    monkeypatch.setenv("GIT_WORK_TREE", str(decoy))
    monkeypatch.setenv("GIT_INDEX_FILE", str(decoy / ".git" / "index"))
    return decoy


def _git_bytes(decoy: Path) -> dict[str, bytes]:
    git = decoy / ".git"
    return {
        str(p.relative_to(git)): p.read_bytes()
        for p in sorted(git.rglob("*"))
        if p.is_file()
    }


def test_make_repo_ignores_an_inherited_git_environment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    decoy = _decoy_git_env(tmp_path, monkeypatch)
    before = _git_bytes(decoy)
    repo = make_repo(tmp_path, "built")
    assert (repo / ".git").is_dir()
    assert _git_bytes(decoy) == before


def test_run_checkpoint_ignores_an_inherited_git_environment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    decoy = _decoy_git_env(tmp_path, monkeypatch)
    before = _git_bytes(decoy)
    result = run_checkpoint(repo, handoff_payload("without-commit"))
    assert result.returncode == 0
    assert "feedback_x.md" in result.stdout
    assert _git_bytes(decoy) == before
