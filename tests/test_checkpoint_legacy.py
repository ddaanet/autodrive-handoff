"""Tests for scripts/checkpoint.py (handoff-checkpoint) — the legacy path
migration: the frame halves a 0.15 session left under `.claude/handoff-*.md`,
read and moved at the checkpoint. This is the whole block, helpers and harness
strings included, and it goes in one pass when the legacy fallback is retired.

The helpers shared with the other tests/test_checkpoint_*.py files are in
tests/conftest.py.
"""

import errno
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

import _checkpoint_lib as lib
import pytest
from conftest import (
    CHECKPOINT,
    add_sdd_ledger,
    dirty_memory,
    drive_state,
    frame_payload,
    git_free_env,
    handoff_payload,
    make_gitlore_repo,
    make_repo,
    precompact_payload,
    run_checkpoint,
    run_git,
    task_clear,
    todo_clear,
    todo_edit,
    todo_keep,
    unset_clause_file,
)

pytestmark = pytest.mark.usefixtures("_session_id")


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

# The with-commit act that stages a tracked legacy path as deleted:
# `git -C <root> rm --cached --ignore-unmatch -q -- <rel> …`, each argument
# shell-quoted, each rel relative to the root and in the order given, task
# before todo. `-C` makes it run from any directory and keeps the root's name
# out of every pathspec, so a glob or `!x` root is a directory change.
#
# Two constraints on the implementation that these rows make:
# - `lib.commit_directive`'s legacy-paths parameter must be optional: the rows
#   that expect today's text call it with no argument.
# - A legacy path named on any line other than the act's counts as a report
#   (`report_lines`), so an act split over two lines with a path on the second
#   one reads as a duplicate report and fails the one-report rows.
UNSTAGE_MARK = "--ignore-unmatch"


def git_act(root: Path, *rels: str) -> str:
    """Return the printed act for these legacy paths, in the order given."""
    words = ["git", "-C", str(root)]
    words += ["rm", "--cached", "--ignore-unmatch", "-q", "--", *rels]
    return " ".join(shlex.quote(word) for word in words)


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
    "content": (TODO_WRITTEN, TODO_WRITTEN, "moved_or_removed"),
}

# The same three actions over a root file that has a body: what it ends as.
TODO_OVER_ROOT = {
    "keep": (todo_keep(), TODO_ROOT_BODY),
    "edit": (
        todo_edit("- second root item", "- edited root item"),
        TODO_ROOT_BODY.replace("- second root item", "- edited root item"),
    ),
    "content": (TODO_WRITTEN, TODO_WRITTEN),
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
    return [ln for ln in out.splitlines() if rel in ln and UNSTAGE_MARK not in ln]


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
    result = run_checkpoint(repo, migration_payload(TASK_WRITTEN, None))
    ok(result)
    assert read(repo / "TASK.md") == TASK_WRITTEN
    assert not (repo / LEGACY_TASK_REL).exists()
    assert_reported(result.stdout, LEGACY_TASK_REL, "moved_or_removed")


def test_both_halves_migrate_in_one_call_each_reported(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(TASK_WRITTEN, todo_keep())
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
    result = run_checkpoint(repo, migration_payload(TASK_WRITTEN, None))
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
    result = run_checkpoint(repo, migration_payload(TASK_WRITTEN, None))
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
    payload = migration_payload(TASK_ROOT_BODY, todo_keep())
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
    payload = migration_payload(task_clear(), HEADINGS_ONLY)
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
    result = run_checkpoint(repo, migration_payload(headings, None))
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
    base = migration_payload(TASK_WRITTEN, todo_keep())
    rejected = run_checkpoint(repo, {**base, **spoiled}, with_session_id=has_session)
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
    unset_clause_file(repo)
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
        act = git_act(repo, LEGACY_TODO_REL)
        assert report_at < out.index(act) < out.index(refusal.text)
    else:
        assert "git -C" not in out
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
        act = git_act(repo, LEGACY_TASK_REL, LEGACY_TODO_REL)
        assert act in out
        assert out.index(act) < out.rindex("Once everything above is done")
    else:
        assert "git -C" not in out


def git_status_lines(repo: Path) -> list[str]:
    """Return `git status --porcelain` as lines."""
    return run_git(
        repo, "status", "--porcelain", capture_output=True
    ).stdout.splitlines()


def printed_git_act(out: str) -> str:
    """Return the command the act line holds between its backticks.

    The wording around it is free. The command is the text after `run `` up to
    the line's last backtick, which a root without a backtick never contains.
    """
    line = next(ln for ln in out.splitlines() if UNSTAGE_MARK in ln)
    command = line[line.index("run `") + len("run `") : line.rindex("`")]
    assert command.startswith("git "), line
    return command


def run_printed_git_rm(
    repo: Path, out: str, cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    """Run the git act stdout prints, from `cwd` (default a subdirectory).

    The agent's Bash cwd persists across calls and is anywhere, so the act must
    work from there: `-C <root>` is what makes it, and a pathspec relative to
    the cwd would match nothing, which `--ignore-unmatch -q` hides. It is run
    through a shell exactly as printed, quoting included, and not checked: the
    caller asserts on the exit status and on the index, so a refusal is a failed
    assertion with git's own message.
    """
    command = printed_git_act(out)
    if cwd is None:
        cwd = repo / "sub"
        cwd.mkdir(exist_ok=True)
    return subprocess.run(
        ["bash", "-c", command],
        cwd=cwd,
        env=git_free_env(),
        capture_output=True,
        text=True,
        check=False,
    )


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
    ident = ["-c", "user.email=t@t", "-c", "user.name=t"]
    run_git(repo, *ident, "add", "-f", LEGACY_TODO_REL)
    run_git(repo, *ident, "commit", "-qm", "seed")
    result = run_checkpoint(repo, migration_payload(task_clear(), todo_keep(), commit))
    ok(result)
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    status = git_status_lines(repo)
    assert f" D {LEGACY_TODO_REL}" in status, status
    assert "?? TODO.md" in status, status
    if commit == "with-commit":
        ran = run_printed_git_rm(repo, result.stdout)
        assert ran.returncode == 0, ran.stderr
        status = git_status_lines(repo)
        assert f"D  {LEGACY_TODO_REL}" in status, status
        run_git(repo, "add", "TODO.md")
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
    ran = run_printed_git_rm(repo, result.stdout)
    assert ran.returncode == 0, ran.stderr
    assert git_status_lines(repo) == before


# A root, the directories beside it whose legacy files must stay tracked, and
# where the root is. Each name is a pathspec hazard for a line that spells the
# root into a pathspec: a glob that reaches a sibling (`a*b` and `a?b` over
# `a b` and `aXb`, which sort on either side of it; `a[1]` over `a1`), or a
# leading `!` or `^` that `:/` would fold into its own magic (over `other` and
# `x`).
UNSTAGE_ROOTS = {
    "top": (".", ["sub", "other"]),
    "plain": ("pkg", ["other"]),
    "spaced": ("pkg dir", ["other"]),
    "bang": ("!x", ["other", "x"]),
    "caret": ("^x", ["other", "x"]),
    "star": ("a*b", ["a b", "aXb"]),
    "question": ("a?b", ["a b", "aXb"]),
    "bracket": ("a[1]", ["a1"]),
}


@pytest.mark.parametrize("cwd", ["inside", "outside"])
@pytest.mark.parametrize("name", UNSTAGE_ROOTS)
def test_printed_git_act_unstages_only_the_roots_own_legacy_file(
    tmp_path: Path, name: str, cwd: str
) -> None:
    """The act stages the root's legacy file as deleted and nothing beside it.

    The root is the top of its repository or a directory below it, named plain,
    with a space or with a character git reads as pathspec magic, and every
    directory beside it holds a tracked legacy file of its own. The printed
    command is run through a shell from a directory of the repository that is
    not the root, and from one outside the repository. `-C` carries the
    location, so the root's name is a directory change and never a pathspec:
    dropping it reds every row, from outside for want of a repository and from
    inside for want of a root. Dropping the quoting reds the spaced root and the
    globs, which the shell would otherwise expand or split. The magic-named roots
    are the proof that git needs no literal-pathspec option: the legacy paths
    are fixed names and the root's name never reaches a pathspec.
    """
    below, siblings = UNSTAGE_ROOTS[name]
    repo = make_repo(tmp_path)
    root = repo if below == "." else repo / below
    tracked = [] if below == "." else [f"{below}/{LEGACY_TODO_REL}"]
    tracked += [f"{sibling}/{LEGACY_TODO_REL}" for sibling in siblings]
    own = LEGACY_TODO_REL if below == "." else f"{below}/{LEGACY_TODO_REL}"
    tracked.append(own)
    for rel in tracked:
        (repo / rel).parent.mkdir(parents=True, exist_ok=True)
        put(repo, rel, TODO_LEGACY_BODY)
    # Setup only: the tracked names hold pathspec magic, which `add` would read.
    opts = ["--literal-pathspecs", "-c", "user.email=t@t", "-c", "user.name=t"]
    run_git(repo, *opts, "add", "-f", "--", *tracked)
    run_git(repo, *opts, "commit", "-qm", "seed")
    payload = migration_payload(task_clear(), todo_keep(), "with-commit")
    result = run_checkpoint(repo, payload, root)
    ok(result)
    assert read(root / "TODO.md") == TODO_LEGACY_BODY
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved")

    def in_index() -> set[str]:
        out = run_git(repo, "ls-files", "-z", capture_output=True).stdout
        return {path for path in out.split("\0") if path}

    assert in_index() == set(tracked)
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    ran = run_printed_git_rm(
        repo, result.stdout, elsewhere if cwd == "outside" else None
    )
    assert ran.returncode == 0, ran.stderr
    assert in_index() == set(tracked) - {own}


# A root whose name would end the code span or split the line the act sits in.
# Each carries INJECTED, the text an agent would read as a further instruction.
UNPRINTABLE_ROOTS = {
    "backtick": "a`INJECTED`b",
    "newline": "a\nINJECTED",
    "carriage_return": "a\rINJECTED",
    "escape": "a\x1bINJECTED",
    "delete": "a\x7fINJECTED",
    "line_separator": "a\u2028INJECTED",
    "next_line": "a\x85INJECTED",
    "bidi_override": "a\u202eINJECTED",
}
UNPRINTABLE_SENTENCE = (
    "The project path holds a character that cannot be printed safely. "
    "From the directory that holds the project's `.claude/` directory, "
    f"run `git rm --cached --ignore-unmatch -q -- {LEGACY_TODO_REL}`."
)


@pytest.mark.parametrize("name", UNPRINTABLE_ROOTS)
def test_a_root_that_cannot_be_printed_is_refused_not_interpolated(
    tmp_path: Path, name: str
) -> None:
    """A backtick or control character in the root never reaches stdout.

    The act is replaced by one plain sentence that echoes nothing of the path,
    and the closing line stays last. Letting the root through unchanged reds
    every row on the marker, which the root's name carries.
    """
    repo = make_repo(tmp_path)
    root = repo / UNPRINTABLE_ROOTS[name]
    (root / LEGACY_TODO_REL).parent.mkdir(parents=True)
    put(root, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    result = run_checkpoint(
        repo, migration_payload(task_clear(), todo_keep(), "with-commit"), root
    )
    ok(result)
    out = result.stdout
    assert read(root / "TODO.md") == TODO_LEGACY_BODY
    assert "INJECTED" not in out, out
    assert str(root) not in out
    assert UNPRINTABLE_SENTENCE in out
    assert "git -C" not in out
    assert "\x1b" not in out
    assert out.count(UNPRINTABLE_SENTENCE) == 1
    assert out.endswith(lib.closing_directive("handoff", typed=False)), out


def test_a_printable_root_keeps_the_act_and_no_refusal(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    root = repo / "pkg dir"
    (root / LEGACY_TODO_REL).parent.mkdir(parents=True)
    put(root, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    result = run_checkpoint(
        repo, migration_payload(task_clear(), todo_keep(), "with-commit"), root
    )
    ok(result)
    assert git_act(root, LEGACY_TODO_REL) in result.stdout
    assert UNPRINTABLE_SENTENCE not in result.stdout


def test_git_rm_act_names_only_the_files_that_moved_or_went(tmp_path: Path) -> None:
    """The task's legacy file is ignored (root wins): it is not a target."""
    repo = make_gitlore_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(TASK_WRITTEN, todo_keep(), "with-commit")
    result = run_checkpoint(repo, payload)
    ok(result)
    assert_reported(result.stdout, LEGACY_TASK_REL, "ignored")
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved")
    lines = [ln for ln in result.stdout.splitlines() if UNSTAGE_MARK in ln]
    assert len(lines) == 1, result.stdout
    assert git_act(repo, LEGACY_TODO_REL) in lines[0]
    assert LEGACY_TASK_REL not in lines[0]


def test_git_rm_act_is_not_owed_to_a_legacy_file_that_is_only_ignored(
    tmp_path: Path,
) -> None:
    repo = make_gitlore_repo(tmp_path)
    put(repo, "TASK.md", TASK_ROOT_BODY)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    payload = migration_payload(TASK_ROOT_BODY, todo_keep(), "with-commit")
    result = run_checkpoint(repo, payload)
    ok(result)
    assert_reported(result.stdout, LEGACY_TASK_REL, "ignored")
    assert_reported(result.stdout, LEGACY_TODO_REL, "ignored")
    assert UNSTAGE_MARK not in result.stdout


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
    payload = migration_payload(TASK_WRITTEN, todo)
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
    result = run_checkpoint(repo, migration_payload(TASK_WRITTEN, todo_keep()))
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
    assert UNSTAGE_MARK not in second.stdout


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
# root file the write cannot replace, and the task and todo that reach it.
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
        TODO_WRITTEN,
    ),
    "task_content": (
        "TASK.md",
        LEGACY_TASK_REL,
        TASK_LEGACY_BODY,
        "## Current task\n",
        TASK_WRITTEN,
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
    the write to the root name fails (the root directory at mode 555, since
    the write replaces the name rather than opening the file, standing in for
    any failure). Taking the legacy file off its path first would leave the
    content nowhere: the loader would say `No todo`. Its positive is the rows
    that move or replace the legacy file when the write succeeds.
    """
    root_rel, legacy_rel, legacy_body, bodyless, task, todo = FAILING_WRITES[case]
    repo = make_repo(tmp_path)
    put(repo, legacy_rel, legacy_body)
    put(repo, root_rel, bodyless)
    before = snapshot(repo)
    repo.chmod(0o555)
    try:
        result = run_checkpoint(repo, migration_payload(task, todo))
    finally:
        repo.chmod(0o755)
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

    `keep` does not read the list, and `clear` only unlinks, so a mode 000 file
    is no reason to fail either. Its positive is the same call over a legacy
    file, where the root file is read to tell whether it has a body.
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
        "content": TODO_WRITTEN,
        "clear": todo_clear(),
    }[action]
    repo = make_repo(tmp_path)
    make_symlinked_legacy(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY, relative=relative)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    before = snapshot(repo)
    result = run_checkpoint(repo, migration_payload(TASK_WRITTEN, todo))
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
    task = TASK_WRITTEN if action == "content" else task_clear()
    repo = make_repo(tmp_path)
    make_symlinked_legacy(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY, relative=relative)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    result = run_checkpoint(repo, migration_payload(task, todo_keep()))
    assert result.returncode != 0
    assert "Traceback" not in result.stderr
    assert LEGACY_TASK_REL in result.stderr
    assert snapshot(repo) == before


@pytest.mark.parametrize("half", ["todo", "task"])
def test_a_symlinked_root_file_beside_a_legacy_file_is_refused(
    tmp_path: Path, half: str
) -> None:
    """The root-name refusal holds where the legacy file would be moved or
    replaced through it.

    The rows with no legacy file are in test_checkpoint_root_files.py.
    """
    root_rel, legacy_rel, legacy_body = {
        "todo": ("TODO.md", LEGACY_TODO_REL, TODO_LEGACY_BODY),
        "task": ("TASK.md", LEGACY_TASK_REL, TASK_LEGACY_BODY),
    }[half]
    repo = make_repo(tmp_path)
    put(repo, legacy_rel, legacy_body)
    target = repo / "notes" / "elsewhere.md"
    target.parent.mkdir()
    target.write_text(HEADINGS_ONLY)
    (repo / root_rel).symlink_to(target)
    before = snapshot(repo)
    result = run_checkpoint(repo, migration_payload(TASK_WRITTEN, todo_keep()))
    assert snapshot(repo) == before
    assert result.returncode == 2
    assert "Traceback" not in result.stderr
    assert result.stderr.startswith(f"handoff-checkpoint: {half}: {root_rel}")


@NOT_ROOT
def test_a_root_todo_that_cannot_be_read_beside_a_legacy_file_is_refused(
    tmp_path: Path,
) -> None:
    """With a legacy file the root file is read to tell whether it has a body; a
    read that fails is refused naming the field, nothing moved.

    Its positive is the same mode-000 root file with no legacy file,
    `test_root_files_that_cannot_be_read_stay_unread_with_no_legacy_file`.
    """
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    put(repo, "TODO.md", TODO_ROOT_BODY)
    (repo / "TODO.md").chmod(0o000)
    try:
        result = run_checkpoint(repo, migration_payload(task_clear(), todo_keep()))
        assert result.returncode == 2
        assert "Traceback" not in result.stderr
        assert result.stderr.startswith("handoff-checkpoint: todo: TODO.md")
        assert read(repo / LEGACY_TODO_REL) == TODO_LEGACY_BODY
    finally:
        (repo / "TODO.md").chmod(0o644)
    assert read(repo / "TODO.md") == TODO_ROOT_BODY


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
