#!/usr/bin/env python3
"""Vibe handoff-checkpoint: the one write path at the clear/compact boundary.

Reads a JSON payload on stdin, validates it against the schema (a violation
exits 2 naming the offending field on stderr), applies the task/todo tagged
union — content, or an object naming an action — to `TASK.md` and `TODO.md` in
the cwd, and prints the directive output. `handoff` and `precompact` carry
`task` and `todo` alike.

The Vibe port of the Claude plugin's scripts/checkpoint.py: the sentinel, its
lock, the hold predicate and the session-owner identity all drop, because the
mod that read the sentinel cannot run under Vibe and nothing drives a
continuation. So the payload schema loses `continue`, and where the Claude
checkpoint armed a transition this one only writes the frame and ends with the
instruction naming what the user types (`/clear`, `/compact`, `/rename`). The
root is the cwd — Vibe has no PreToolUse hook to inject HANDOFF_ROOT — guarded
by a run-from-the-project-root check, which autoname skips: it writes nothing.
The memory directive is the only seam left to other machinery.

Validating the payload lives in _checkpoint_payload.py, resolving the two halves
to file plans and applying them in _checkpoint_plan.py, and the directive texts
in _checkpoint_lib.py. The same four files ship inside each caller skill
directory (handoff, precompact, autoname); `just sync-vibe` copies them from
here, and tests/test_vibe_checkpoint.py asserts the copies identical, so this
directory is the one that gets edited.
"""

from __future__ import annotations

import sys
from pathlib import Path

import _checkpoint_lib as lib
import _checkpoint_payload as validation
import _checkpoint_plan as planning


def main() -> int:
    """Run the checkpoint.

    Validate the payload, apply the writes, print the directives. Anything
    that fails does so before the first write: the schema is validated ahead
    of the plans, and the plans and the directives (which run git and read the
    SDD ledger) are resolved ahead of `apply_plan`, so an
    errored call leaves `TASK.md` and `TODO.md` as they were.
    """
    payload = validation.read_payload()
    skill = validation.validate_skill(payload)
    if skill == "autoname":
        # A rename only: no root check, nothing written, the rename line alone.
        validation.validate_top_level_keys(payload)
        validation.validate_autoname_forbidden_fields(payload)
        title = validation.validate_rename(payload, skill)
        print_output([lib.rename_directive(title)])
        return 0

    root = validate_root()
    validation.validate_top_level_keys(payload)
    commit_mode = validation.validate_commit_mode(payload)
    title = validation.validate_rename(payload, skill)
    task_fields = validation.validate_task(payload)
    todo_fields = validation.validate_todo(payload)
    plans = [
        planning.plan_task(root, *task_fields),
        planning.plan_todo(root, *todo_fields),
    ]
    parts = compose_directives(
        skill,
        root,
        title,
        commit_mode=commit_mode,
    )
    for plan in plans:
        planning.apply_plan(plan)
    print_output(parts)
    return 0


def validate_root() -> Path:
    """Return the cwd as the root, or error when it cannot be one.

    The boundary skill runs with the session working directory current and the
    project root in context, so the cwd is the root by construction when the
    skill protocol is followed. The check keeps a call that strays — a `cd` the
    turn made, a subagent's narrower cwd — from writing frame files somewhere
    that is not a project.
    """
    root = Path.cwd()
    if not (
        (root / ".git").exists()
        or (root / "TASK.md").is_file()
        or (root / "TODO.md").is_file()
    ):
        lib.err(
            "root",
            "the cwd is not a project root (no .git, TASK.md or TODO.md) —"
            " run the checkpoint with the project root current",
        )
    return root


def compose_directives(
    skill: str,
    root: Path,
    title: str,
    *,
    commit_mode: str,
) -> list[str]:
    """Return a handoff's or precompact's ordered, non-empty directive parts.

    Print order: the memory directive ("" when the gitlore store is absent
    or clean, and omitted), then the todo boundary/SDD nudge ("" with no live
    ledger, and omitted), then the commit act (present only under
    "with-commit", leaving the memory gitlink out when memory is owed), then
    the rename directive (handoff only), then the closing line — always last.
    """
    memory = lib.memory_directive(str(root))
    nudge = (
        lib.todo_boundary(str(root))
        if skill == "handoff"
        else lib.sdd_directive(str(root))
    )
    parts = [part for part in (memory, nudge) if part]
    if commit_mode == "with-commit":
        parts.append(lib.commit_directive(memory=bool(memory)))
    if skill == "handoff":
        parts.append(lib.rename_directive(title))
    parts.append(lib.closing_directive(skill))
    return parts


def print_output(parts: list[str]) -> None:
    """Print the directive output: the parts, blank-line separated.

    Each part already ends in a newline of its own, so the trailing one is
    stripped before joining: otherwise the separator lands on top of it and
    every gap is two blank lines rather than one.
    """
    sys.stdout.write("\n\n".join(part.rstrip("\n") for part in parts) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
