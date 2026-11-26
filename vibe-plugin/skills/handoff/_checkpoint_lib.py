#!/usr/bin/env python3
"""Shared helpers for the Vibe checkpoint.

The gitlore memory directives, the commit act, the rename directive and the
closing directive, the last two written for a boundary the *user* carries out:
nothing under Vibe can type `/clear` or `/rename`.

Each directive function returns its directive text, or "" when silent; the
caller decides whether to print it. `err` is the one exit for a schema or write-
time error, shared by both callers.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn


def _printf_lines(*args: str) -> str:
    r"""Mirror bash's `printf '%s\n' arg...`: each arg followed by a newline."""
    return "\n".join(args) + "\n"


def err(field: str, message: str) -> NoReturn:
    """Print a schema/write-time error naming field, then exit 2."""
    print(f"handoff-checkpoint: {field}: {message}", file=sys.stderr)
    raise SystemExit(2)


# Markdown's own ATX rule: up to three leading spaces, 1-6 `#`, then the line
# ends or whitespace separates the text. Read by validate_task_shape; matched
# against a right-stripped line.
ATX_HEADING = re.compile(r" {0,3}#{1,6}(\s.*)?")


def _resolve_submodule_path(root: str) -> str:
    gitmodules = Path(root) / ".gitmodules"
    result = subprocess.run(
        ["git", "config", "--file", str(gitmodules), "submodule.gitlore-memory.path"],
        capture_output=True,
        text=True,
        check=False,
    )
    mempath = result.stdout.strip()
    return mempath if result.returncode == 0 else ""


def memory_directive(root: str) -> str:
    """Return the gitlore memory directive, or "" when nothing is owed.

    Owed when the `gitlore-memory` submodule is materialized and its worktree is
    dirty. The text names the dirty paths and says they stay uncommitted:
    gitlore has no Vibe install, so the commit is left to a session that has it.
    It is the same under both commit modes.
    """
    mempath = _resolve_submodule_path(root)
    if not mempath:
        return ""
    mem = Path(root) / mempath
    if not (mem / ".git").exists():
        return ""

    status = subprocess.run(
        ["git", "-C", str(mem), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.rstrip("\n")
    if not status.strip():
        return ""

    return _printf_lines(
        "gitlore memory has uncommitted changes:",
        "",
        status,
        "",
        "Vibe has no gitlore:commit skill, so these stay uncommitted. Report to the "
        "user that the memory changes above are left for a session that has "
        "gitlore (a Claude Code session) to commit, then go on with the parts "
        "below.",
    )


def commit_directive(*, memory: bool = False) -> str:
    """Return the commit act, printed under "with-commit".

    Names no git verb for the commit itself: the request may call for an amend
    or a fresh commit, and the checkpoint does not know which. Names the two
    files because nothing has staged what this call did to them. With `memory`
    owed, the act leaves the memory pointer out of the commit and names it as
    left out: nothing staged it.
    """
    if memory:
        sentence = (
            "Once everything above is done, make the commit the request called for, "
            "including any change to `TASK.md` and `TODO.md`, but leave the memory "
            "pointer out of it and say in your reply that it is left out."
        )
    else:
        sentence = (
            "Once everything above is done, make the commit the request called for, "
            "including any change to `TASK.md` and `TODO.md`."
        )
    return _printf_lines(sentence)


def rename_directive(title: str) -> str:
    """Return the rename act for autoname.

    Vibe has no drive to submit `/rename` at turn end, so the title crosses only
    as a line the user acts on. Under handoff the title rides the closing line
    instead, after its `/clear`, so the order the user types in is the order
    printed.
    """
    return _printf_lines(
        f'Session title decided: "{title}".',
        "Nothing here can type /rename; the user runs it:",
        f"`/rename {title}`",
    )


def closing_directive(skill: str, title: str = "") -> str:
    """Return the instruction to end the reply on one named line.

    One line per skill, quoted so the agent relays it rather than paraphrasing
    it. Under precompact the line carries the `/compact` command, with its
    direction, for the user to paste: the code span holds the command alone, so
    it is copied paste-ready. Under handoff the line also carries the session
    title as `/rename`, after the `/clear`: that order titles the fresh session
    (Vibe's `/clear` starts a new conversation, and `/rename` titles whichever
    is current). Anchored like the commit act and the rename directive, so it is
    not appended to a reply still asking for the memory directive's approval.
    """
    if skill not in ("handoff", "precompact"):
        raise ValueError(skill)
    if skill == "handoff":
        lead = "Once everything above is done, end on one line:"
        line = (
            "Written — type `/clear`, then `/rename "
            + title
            + "`, when you are ready; the fresh session reads"
            " TASK.md and TODO.md first."
        )
    else:
        lead = (
            "Once everything above is done, end on one line, the command the"
            " user pastes to compact:"
        )
        line = f"`/compact {COMPACT_DIRECTION}`"
    return _printf_lines(lead, line)


# The argument of the pasted /compact: Vibe appends it to its builtin summary
# request. One line, no backticks.
COMPACT_DIRECTION = (
    "TASK.md and TODO.md survive this compaction on disk and are the task"
    " frame: do not reproduce them. State the current task and its next action"
    " as the conversation now stands, and say the next turn first reads TASK.md"
    " and TODO.md from disk."
)


def ledger_path(root: str) -> str | None:
    """Return the live workflow-owned progress ledger under root, or None.

    Project-relative. Liveness, not presence: only a workspace whose first line
    is SDD's identity line counts; several live workspaces resolve by mtime,
    ties keeping the lexically-first (glob order).
    """
    root_path = Path(root)
    best: Path | None = None
    best_mtime = float("-inf")
    for f in sorted((root_path / ".superpowers" / "sdd").glob("*/progress.md")):
        if not f.is_file():
            continue
        try:
            first = f.read_text(encoding="utf-8").split("\n", 1)[0]
            mtime = f.stat().st_mtime
        except (OSError, UnicodeDecodeError):
            continue
        if not first.startswith("# SDD ledger — plan: "):
            continue
        if mtime > best_mtime:
            best, best_mtime = f, mtime
    if best is None:
        return None
    return str(best.relative_to(root_path))


def sdd_directive(root: str) -> str:
    """Return the durable-progress nudge (precompact only), or "".

    Silent when there is no live ledger.
    """
    ledger = ledger_path(root)
    if ledger is None:
        return ""
    return _printf_lines(
        "You are running superpowers SDD. Before compacting, bring the ledger "
        f"current at {ledger} — after compaction the SDD skill trusts the "
        "ledger over recollection. Ensure:",
        "",
        "  - every task whose review came back clean has its `Task N: complete "
        "(commits <base>..<head>, review clean)` line",
        "  - any Minor findings seen so far are recorded for the final "
        "whole-branch review",
        "",
        "A task that completed but is missing from the ledger can be "
        "re-dispatched after compaction — the most expensive SDD failure.",
        "",
        "That ledger holds this plan's tasks. Keep them out of TODO.md, which "
        "holds only work outstanding outside the plan.",
    )


def todo_boundary(root: str) -> str:
    """Return the ledger/todo-file boundary (handoff only), or "".

    Silent when there is no live ledger.
    """
    ledger = ledger_path(root)
    if ledger is None:
        return ""
    return _printf_lines(
        f"A workflow-owned progress ledger at {ledger} holds this plan's tasks, "
        "and it survives the /clear. Keep those tasks out of TODO.md, removing "
        "them if they are already there; that file holds only work outstanding "
        "outside the plan. Bring the ledger current if it has drifted."
    )
