#!/usr/bin/env python3
"""Shared helpers for checkpoint.py and _checkpoint_plan.py.

Port of _checkpoint-lib.sh — see docs/changelog/2026-08-10-python-split.md. Each
directive function returns its directive text, or "" when silent
(`memory_directive` wraps its text in a `MemoryPart`); the caller decides
whether to print it. `err` is the one exit for a schema or write-time error,
shared by both callers. The emptiness rule is also reachable from bash through
the --is-empty-body CLI.
"""

from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import NamedTuple, NoReturn


def _printf_lines(*args: str) -> str:
    r"""Mirror bash's `printf '%s\n' arg...`: each arg followed by a newline."""
    return "\n".join(args) + "\n"


def err(field: str, message: str) -> NoReturn:
    """Print a schema/write-time error naming field, then exit 2."""
    print(f"handoff-checkpoint: {field}: {message}", file=sys.stderr)
    raise SystemExit(2)


def is_empty_body(content: str) -> bool:
    """Report whether content is empty once ATX headings/blanks are removed.

    A `## Remaining` with no items, a task file with headings and no content:
    both are empty.

    "Blank" is the line with no trailing whitespace left, so a line of spaces
    alone is blank rather than content. "Heading" is an ATX heading and not
    merely a leading `#` (`ATX_HEADING`): `#!/bin/sh`, `#tag` and a run of seven
    `#` are all content, the `#` run in each being followed by something other
    than whitespace or the line's end. The leading-space bound is markdown's
    own: up to three indents a heading, and a fourth opens a code block, whose
    `# comment` line is content like any other. Testing the stripped line
    instead would put that line back in the class this function exists to keep
    out of it.
    """
    for raw in content.split("\n"):
        line = raw.rstrip()
        if line == "" or ATX_HEADING.fullmatch(line):
            continue
        return False
    return True


# Markdown's own ATX rule: up to three leading spaces, 1-6 `#`, then the line
# ends or whitespace separates the text. Read by is_empty_body, above, and by
# checkpoint.py's task-shape check; matched against a right-stripped line.
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


def _resolve_approval_clause(root: str) -> str | None:
    """Return the clause text, or None when it cannot be read.

    The caller reports the key-and-restart fallback on None.
    """
    clause_result = subprocess.run(
        ["git", "-C", root, "config", "--get", "gitlore.memoryApprovalClauseFile"],
        capture_output=True,
        text=True,
        check=False,
    )
    clause_file = clause_result.stdout.strip() if clause_result.returncode == 0 else ""
    path = Path(clause_file) if clause_file else None
    if path is None or not path.is_file() or not os.access(path, os.R_OK):
        return None
    return path.read_text(encoding="utf-8").rstrip("\n")


def memory_directive(root: str, mode: str) -> MemoryPart:
    """Return the gitlore memory-commit directive, or an empty part.

    When memory is dirty but the approval clause cannot be read, the part is the
    clause-file refusal instead, flagged `refusal=True`.

    `mode` ("with-commit"/"without-commit") selects which of gitlore's two
    commit paths the agent is told to take. The with-commit text never mentions
    the trigger file — its reader has no other source for that filename, so
    saying nothing is what makes the standalone commit unreachable.
    """
    mempath = _resolve_submodule_path(root)
    if not mempath:
        return MemoryPart("", refusal=False)
    mem = Path(root) / mempath
    if not (mem / ".git").exists():
        return MemoryPart("", refusal=False)

    status = subprocess.run(
        ["git", "-C", str(mem), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.rstrip("\n")
    if not status.strip():
        return MemoryPart("", refusal=False)

    clause = _resolve_approval_clause(root)
    if clause is None:
        return MemoryPart(
            _printf_lines(
                "gitlore memory has uncommitted changes, but this session cannot "
                "read the memory-approval wording: git config "
                "gitlore.memoryApprovalClauseFile is unset or its file is missing. "
                "gitlore pins that key at SessionStart — run /restart (or "
                "exit and relaunch with --resume, by hand), then retry. The "
                "memory changes are still pending."
            ),
            refusal=True,
        )

    msgfile = Path(root) / ".claude" / "gitlore-memory-message"
    trigger = Path(root) / ".claude" / "gitlore-commit-memory"
    approve_files = "the file below" if mode == "with-commit" else "either file below"

    common = _printf_lines(
        "gitlore memory has uncommitted changes:",
        "",
        status,
        "",
        "Summarize these changes as a commit message, its title line at most "
        "72 characters.",
        "",
        clause,
        "",
        "Present it to the user as a markdown blockquote (lines prefixed with "
        f"'> ', not a code fence) and get their approval — they may edit it. Do "
        f"not write {approve_files} before the user approves.",
        "",
    )
    if mode == "with-commit":
        specific = _printf_lines(
            "Once approved, write the approved summary to:",
            "",
            f"     {msgfile}",
            "",
            "The commit that lands these changes carries the memory.",
        )
    else:
        specific = _printf_lines(
            "Once approved, commit the memory with two file writes (no Bash):",
            "",
            "  1. Write the approved summary to:",
            f"     {msgfile}",
            "  2. Write the trigger file (any content) to:",
            f"     {trigger}",
        )
    return MemoryPart(common + specific, refusal=False)


class MemoryPart(NamedTuple):
    """The memory directive's text, and whether it is the clause-file refusal.

    `text == ""` when nothing is owed. `refusal` is true only for the clause-
    file refusal, the one memory text that suppresses every part after it — the
    checkpoint prints it alone.
    """

    text: str
    refusal: bool


def commit_directive(root: str = "", legacy_paths: Sequence[str] = ()) -> str:
    """Return the commit act, printed under "with-commit".

    Names no git verb for the commit itself: the request may call for an amend
    or a fresh commit, and the checkpoint does not know which. Names the two
    files because nothing has staged what this call did to them. Legacy paths
    this call moved or removed lead it, as `legacy_unstage_directive`, which
    needs the root they are relative to.
    """
    commit = _printf_lines(
        "Once everything above is done, make the commit the request called for, "
        "including any change to `TASK.md` and `TODO.md`."
    )
    unstage = legacy_unstage_directive(root, legacy_paths)
    return f"{unstage}\n{commit}" if unstage else commit


def legacy_unstage_directive(root: str, paths: Sequence[str]) -> str:
    """Return the act that stages legacy paths as deleted, or "" for none.

    One line, the paths on it: the legacy files this call moved or removed,
    never one it left in place. The line does not ask which are tracked. Each
    path is relative to the root, which `-C` names, so the line runs from any
    directory, and the root's own name, whatever characters it holds, is a
    directory change and never a pathspec. The paths are the fixed names
    `.claude/handoff-task.md` and `.claude/handoff-todo.md`, which hold no glob
    or magic character, so nothing needs git told to read them literally. Every
    argument is shell-quoted. A root holding a backtick or a character that is
    not printable (a control character, a Unicode line or paragraph separator,
    a bidirectional override) cannot sit in a code span on one line, so the act
    is replaced by one sentence that carries no part of the root and names the
    same command with the fixed relative paths, to run where they resolve.
    """
    if not paths:
        return ""
    if "`" in root or not root.isprintable():
        relative = " ".join(shlex.quote(path) for path in paths)
        return _printf_lines(
            "The project path holds a character that cannot be printed safely. "
            "From the directory that holds the project's `.claude/` directory, "
            f"run `git rm --cached --ignore-unmatch -q -- {relative}`."
        )
    words = ["git", "-C", root]
    words += ["rm", "--cached", "--ignore-unmatch", "-q", "--", *paths]
    command = " ".join(shlex.quote(word) for word in words)
    return _printf_lines(f"Before committing, run `{command}`.")


def arming_directive() -> str:
    """Return the instruction that releases a held transition."""
    return _printf_lines(
        "Once everything above is done, run `handoff-approved` (Bash, no arguments)."
    )


def closing_directive(skill: str, *, typed: bool) -> str:
    """Return the instruction to end the reply on one named line.

    Prepared (untyped): the line names what the boundary is ready for. Driven
    (typed): the line says the transition is armed and runs when the turn ends.
    Quoted either way, so the agent relays the line rather than paraphrasing it.
    Anchored like the commit act and the arming instruction, so it is not
    appended to a reply still asking for the memory directive's approval.
    `bin/handoff-approved` prints the same text after its own status fact.
    """
    if skill not in ("handoff", "precompact"):
        raise ValueError(skill)
    lead = "Once everything above is done, end on one line:"
    if typed:
        name = "Clear" if skill == "handoff" else "Compaction"
        return _printf_lines(f"{lead} `{name} armed — it runs when this turn ends.`")
    boundary = "/clear" if skill == "handoff" else "/compact"
    return _printf_lines(f"{lead} `Ready to {boundary}`.")


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
        except OSError:
            continue
        if not first.startswith("# SDD ledger — plan: "):
            continue
        mtime = f.stat().st_mtime
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


def _cli(argv: list[str]) -> int:
    """Run `checkpoint_lib.py --is-empty-body`.

    Reads content on stdin, exits 0 if empty, 1 otherwise.
    """
    if len(argv) == 2 and argv[1] == "--is-empty-body":
        content = sys.stdin.read()
        return 0 if is_empty_body(content) else 1
    print("checkpoint_lib.py: unknown invocation", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_cli(sys.argv))
