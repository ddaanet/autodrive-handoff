#!/usr/bin/env python3
"""Shared helpers for the Vibe checkpoint.

The checkpoint.py and _checkpoint_plan.py of the Vibe port: the gitlore
directives and the error helper unchanged from the Claude plugin's
scripts/_checkpoint_lib.py, the frame-fitting half and the
--has-body/--fit-frame CLI dropped (the loaders that consumed them do not
exist under Vibe), the closing directive rewritten for a boundary the *user*
carries out — nothing under Vibe can type `/clear` — and a rename directive
where the drive's `/rename` used to run. New: the compaction-prompt guard,
which is the Vibe compact seam's only liveness check.

Each directive function returns its directive text, or "" when silent; the
caller decides whether to print it. `err` is the one exit for a schema or
write-time error, shared by both callers.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tomllib
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
    """Return the rename act for autoname and handoff.

    Vibe has no drive to submit `/rename` at turn end, so the title crosses only
    as a line the user acts on.
    """
    return _printf_lines(
        f'Session title decided: "{title}".',
        "Nothing here can type /rename; the user runs it:",
        f"`/rename {title}`",
    )


def closing_directive(skill: str, *, ready: bool) -> str:
    """Return the instruction to end the reply on one named line.

    `ready` says the user asked for the transition to run at once (`clear: true`
    under handoff, `compact: true` under precompact); false, they are preparing
    one they will run themselves. Quoted either way, so the agent relays the
    line rather than paraphrasing it. Anchored like the commit act and the
    rename directive, so it is not appended to a reply still asking for the
    memory directive's approval.
    """
    if skill not in ("handoff", "precompact"):
        raise ValueError(skill)
    lead = "Once everything above is done, end on one line:"
    if ready:
        line = (
            "`Ready to /clear — the fresh session reads TASK.md and TODO.md first.`"
            if skill == "handoff"
            else "`Ready to /compact — everything durable is on disk or in the todo.`"
        )
    elif skill == "handoff":
        line = "`Written — /clear when you are ready.`"
    else:
        line = "`Written — /compact when you are ready.`"
    return _printf_lines(lead, line)


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


def compaction_prompt_guard(root: str) -> str:
    """Return the compact-seam warning, or "" when the seam is in place.

    The custom compaction prompt is the only carrier of the task across a Vibe
    /compact: this checkpoint removes `TASK.md`, and without the prompt the
    summary paraphrases what the removal just took to disk. The check mirrors
    Vibe 3.0.1's load_prompt resolution: `compaction_prompt_id` read from the
    project layer, then the user layer (VIBE_HOME, else ~/.vibe) of config.toml,
    and the named prompt looked up in the project prompts dir, then the user's —
    the builtin id is the seam's absence, not its presence. Residual bound: an
    env override (VIBE_COMPACTION_PROMPT_ID) or a config file changed between
    the read and the /compact escapes the check; presence is checked, not
    content, so a custom prompt that is not the plugin's passes; and the project
    layer is read even where Vibe skips an untrusted folder.
    """
    prompt_id = _compaction_prompt_id(root)
    if prompt_id != "compact":
        for prompts_dir in (
            Path(root) / ".vibe" / "prompts",
            _vibe_home() / "prompts",
        ):
            if (prompts_dir / f"{prompt_id}.md").is_file():
                return ""
    return _printf_lines(
        "Tell the user: TASK.md is removed at this boundary, and every compaction "
        "after it paraphrases its context: the task reaches the compacted "
        "session only through the custom compaction prompt, and none is "
        "installed.",
        "",
        "To install it before running /compact, copy the plugin's prompts/"
        "compaction.md to .vibe/prompts/handoff-compact.md and set "
        'compaction_prompt_id = "handoff-compact" — the plugin README has '
        "the whole setup.",
    )


def _vibe_home() -> Path:
    """Return Vibe's user layer: VIBE_HOME when set, else ~/.vibe."""
    if vibe_home := os.environ.get("VIBE_HOME"):
        return Path(vibe_home).expanduser().resolve()
    return Path.home() / ".vibe"


def _compaction_prompt_id(root: str) -> str:
    """Return the effective compaction_prompt_id, "compact" when unreadable."""
    for cfg in (
        Path(root) / ".vibe" / "config.toml",
        _vibe_home() / "config.toml",
    ):
        try:
            with cfg.open("rb") as f:
                data = tomllib.load(f)
        except (OSError, tomllib.TOMLDecodeError):
            continue
        value = data.get("compaction_prompt_id")
        if isinstance(value, str) and value:
            return value
    return "compact"
