#!/usr/bin/env python3
"""Shared helpers for checkpoint.py and _checkpoint_plan.py.

Port of _checkpoint-lib.sh. Each directive function returns its directive text,
or "" when silent; the caller decides whether to print it. `err` is the one exit
for a schema or write-time error, shared by both callers. The emptiness rule is
also reachable from bash through the --has-body CLI, and the frame's size cut
through --fit-frame.
"""

from __future__ import annotations

import re
import subprocess
import sys
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


def memory_directive(root: str) -> str:
    """Return the gitlore memory directive, or "" when nothing is owed.

    Owed when the `gitlore-memory` submodule is materialized and its worktree is
    dirty. The text names the dirty paths and points at the `gitlore:commit`
    skill, which owns the commit; it is the same under both commit modes.
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
        "Commit them through the gitlore:commit skill: invoke it before drafting a "
        "summary, and follow it.",
    )


def commit_directive(*, memory: bool = False) -> str:
    """Return the commit act, printed under "with-commit".

    Names no git verb for the commit itself: the request may call for an amend
    or a fresh commit, and the checkpoint does not know which. Names the two
    files because nothing has staged what this call did to them. With `memory`
    owed, the act also names the memory gitlink that `gitlore:commit` staged.
    """
    if memory:
        sentence = (
            "Once everything above is done, make the commit the request called for, "
            "including any change to `TASK.md` and `TODO.md` and the memory gitlink "
            "`gitlore:commit` staged."
        )
    else:
        sentence = (
            "Once everything above is done, make the commit the request called for, "
            "including any change to `TASK.md` and `TODO.md`."
        )
    return _printf_lines(sentence)


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


def fit_frame(head: str, todo: str, tail: str) -> str:
    """Return the frame, with whole TODO.md items cut when it would not fit.

    `head` is the header and the task, `todo` the TODO.md text, `tail` what the
    loader appends after the frame; the whole context is the frame, the tail and
    one newline, at most FRAME_LIMIT UTF-16 code units. A frame that fits comes
    back byte for byte. Otherwise items go from the end, the open decisions
    last, and a line closes the frame saying how many TODO.md holds beyond those
    shown. The task and header are never cut: with every item gone the minimal
    form is returned even if it is still over. A TODO.md with no item to cut is
    returned whole.
    """
    budget = FRAME_LIMIT - _units(tail) - 1
    whole = head + "\n\n" + todo
    if _units(whole) <= budget:
        return whole
    lines = todo.split("\n")
    items = _todo_items(lines)
    # Open decisions are cut last; within a tier, the end of the file first.
    order = [i for i in reversed(items) if not i.decision] + [
        i for i in reversed(items) if i.decision
    ]
    if not order:
        return whole
    # The smallest prefix of `order` that fits. The kept text shrinks as the
    # prefix grows and the pointer only lengthens, so no prefix whose kept text
    # is over the budget beside the shortest pointer can fit: binary-search the
    # first one that might, then render forward from it until one does. Each
    # render walks the whole file, so one per dropped item is quadratic.
    shortest = _pointer(order[:1])
    lo, hi = 1, len(order)
    while lo < hi:
        mid = (lo + hi) // 2
        if _units(_render(head, _kept(lines, order[:mid]), shortest)) <= budget:
            hi = mid
        else:
            lo = mid + 1
    for k in range(lo, len(order) + 1):
        out = _render(head, _kept(lines, order[:k]), _pointer(order[:k]))
        if _units(out) <= budget:
            break
    return out


def _units(text: str) -> int:
    """Return the length of `text` in UTF-16 code units, the host's count.

    Never below the code-point count, so it is safe whichever the host uses. A
    lone surrogate (an undecodable byte, through surrogateescape) counts one.
    """
    return len(text.encode("utf-16-le", errors="surrogatepass")) // 2


# The most UTF-16 code units of one hook's additionalContext that Claude Code
# injects whole. Measured on Claude Code 2.1.327: from 10001 the output is
# persisted to a file and the model gets a 2000-character preview. The host is
# JavaScript, whose string length counts UTF-16 units, so an astral character
# (an emoji) costs two.
FRAME_LIMIT = 10000


class _Item(NamedTuple):
    """A top-level item of TODO.md: its line range and its section kind."""

    start: int
    end: int
    decision: bool


def _todo_items(lines: list[str]) -> list[_Item]:
    """Return the items of TODO.md, in file order.

    An item starts at a list marker at column 0 (`- `, `* `, `+ `, `1. `,
    `1) `) outside a code fence, and runs to its last non-blank line before the
    next such line or the next `##` heading. A fence's lines never start an item
    or a section: they extend the item they sit in.
    """
    items: list[_Item] = []
    decision = False
    current = False
    fence = ""
    for n, line in enumerate(lines):
        if fence:
            if _closes(line, fence):
                fence = ""
        elif m := _FENCE.match(line):
            fence = m.group(1)
        elif _SECTION_HEADING.match(line):
            heading = line[2:].strip().rstrip(":").strip().lower()
            decision = heading == "open decisions"
            current = False
            continue
        elif _ITEM_MARKER.match(line):
            items.append(_Item(n, n + 1, decision))
            current = True
            continue
        if current and line.strip():
            items[-1] = items[-1]._replace(end=n + 1)
    return items


# A code fence's opening line: its run of backticks or tildes.
_FENCE = re.compile(r"\s*(`{3,}|~{3,})")


def _closes(line: str, fence: str) -> bool:
    """Tell whether `line` closes the fence opened by `fence`."""
    m = _FENCE.match(line)
    return bool(
        m
        and m.group(1)[0] == fence[0]
        and len(m.group(1)) >= len(fence)
        and not line[m.end() :].strip()
    )


# A `##` heading line that is not a deeper one.
_SECTION_HEADING = re.compile(r"##(?!#)(\s|$)")

# A list item's marker at column 0: bullet or ordered.
_ITEM_MARKER = re.compile(r"([-*+]|\d+[.)]) ")


def _render(head: str, kept: str, pointer: str) -> str:
    return head + ("\n\n" + kept if kept else "") + "\n\n" + pointer


def _kept(lines: list[str], dropped: list[_Item]) -> str:
    gone = {n for i in dropped for n in range(i.start, i.end)}
    return "\n".join(_kept_lines(lines, gone)).rstrip()


def _pointer(dropped: list[_Item]) -> str:
    decisions = sum(1 for i in dropped if i.decision)
    remaining = len(dropped) - decisions
    counts = []
    if remaining:
        counts.append(f"{remaining} more remaining item{'s' * (remaining != 1)}")
    if decisions:
        counts.append(f"{decisions} more open decision{'s' * (decisions != 1)}")
    return (
        f"TODO.md holds {' and '.join(counts)} than shown here: "
        "read it before acting on either list."
    )


def _kept_lines(lines: list[str], gone: set[int]) -> list[str]:
    """Return the lines not in `gone`, with no blank line doubled across a cut.

    An item's range stops at its last non-blank line, so the blank lines that
    separated it from what follows stay; where a cut leaves one blank run
    against another, the second goes.
    """
    kept: list[str] = []
    cut = False
    for n, line in enumerate(lines):
        if n in gone:
            cut = True
            continue
        if cut and not line.strip() and kept and not kept[-1].strip():
            continue
        if line.strip():
            cut = False
        kept.append(line)
    return kept


def _cli(argv: list[str]) -> int:
    """Run `checkpoint_lib.py --has-body` or `--fit-frame`.

    `--has-body` reads content on stdin, exits 0 if it has a body, 1 if it is
    empty, 2 on an unknown invocation. Success is the body because 0 is the one
    status no crash can produce: an uncaught exception, at import as much as
    here, exits 1, and a library python3 cannot open exits 2, so a broken check
    reads as "no body" and the loader injects nothing on its account.

    `--fit-frame` reads head, todo and tail on stdin, each NUL-terminated, and
    prints the fitted frame without a trailing newline. Bytes, not the locale's
    text: the count is of UTF-16 units whatever the hook's locale.
    """
    if len(argv) == 2 and argv[1] == "--has-body":
        content = sys.stdin.read()
        return 1 if is_empty_body(content) else 0
    if len(argv) == 2 and argv[1] == "--fit-frame":
        raw = sys.stdin.buffer.read().decode("utf-8", errors="surrogateescape")
        parts = raw.split("\0")
        if len(parts) != 4 or parts[3]:
            print("checkpoint_lib.py: --fit-frame: head, todo, tail", file=sys.stderr)
            return 2
        out = fit_frame(parts[0], parts[1], parts[2])
        sys.stdout.buffer.write(out.encode("utf-8", errors="surrogateescape"))
        return 0
    print("checkpoint_lib.py: unknown invocation", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_cli(sys.argv))
