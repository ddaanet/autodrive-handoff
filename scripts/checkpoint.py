#!/usr/bin/env python3
"""Handoff-checkpoint: the one write path for the handoff/precompact wrap-up.

Reads a JSON payload on stdin, validates it against the schema (FR2 — a
violation exits 2 naming the offending field on stderr), applies the task/todo
tagged union — content, or an object naming an action (FR5) — to `TASK.md` and
`TODO.md` in the root, composes the sentinel (FR8), and prints the directive
output (FR9). Only `handoff` carries a `task`; `precompact` forbids the key and
removes any task file on disk. The sentinel and the directive composition live
here; validating the payload lives in _checkpoint_payload.py, and resolving the
two halves to file plans, the legacy migration included, and applying them in
_checkpoint_plan.py.

NFR1: nothing here mutates git state — this is the agent's sandboxed Bash, and
both files are plain tracked files whichever commit comes next picks up. A file
left at a legacy path is renamed or removed on the filesystem, and what the next
commit owes git for it is printed, not run. At turn end the sentinel is taken by
scripts/drive-take.sh and run by the drive mod.

Port of checkpoint.sh — see docs/changelog/2026-08-10-python-split.md. The
composer reads its own sentinel back through handoff_drive_read, which stays the
single bash implementation of the sentinel grammar (still used by drive-take.sh,
load-compact.sh, load-handoff.sh and report-drive-failure.sh) — so this shells
out to it rather than reimplementing the grammar a second time, which is exactly
the drift the single-parser design exists to prevent.
"""

from __future__ import annotations

import shlex
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

import _checkpoint_lib as lib
import _checkpoint_payload as validation
import _checkpoint_plan as planning

# Mirrors _lib.sh's HANDOFF_REL_DRIVE. Changing either side is a breaking
# change (see CLAUDE.md conventions); kept in sync by hand rather than sourced,
# since _lib.sh stays bash.
HANDOFF_REL_DRIVE = ".claude/autodrive"

_LIB_SH = Path(__file__).resolve().parent / "_lib.sh"


def main() -> int:
    """Run the checkpoint.

    Validate the payload, apply writes, compose the sentinel and directives,
    print them.
    """
    payload = validation.read_payload()
    root = validation.validate_root()
    skill = validation.validate_skill(payload)
    validation.validate_top_level_keys(payload)

    if skill == "autoname":
        validation.validate_autoname_forbidden_fields(payload)
    commit_mode = validation.validate_commit_mode(payload, skill)
    title = validation.validate_rename(payload, skill)
    transition = validation.build_transition(payload, skill, title)
    continuation = validation.validate_continuation(
        payload, skill, typed=transition.typed
    )

    memory = lib.MemoryPart("", refusal=False)
    if skill in ("handoff", "precompact"):
        memory = lib.memory_directive(str(root), commit_mode)
    held = hold_decision(
        transition, memory=bool(memory.text), commit=commit_mode == "with-commit"
    )
    # Resolved before anything is written (task/todo/sentinel): every call
    # composes a sentinel, held or armed, and both name their owner on line 1,
    # so there is nothing this run could do with it unset.
    owner = validation.require_session_id(
        "transition", "cannot compose a sentinel naming the session that owns it"
    )
    check_sentinel_target(root)

    plans: list[planning.FilePlan] = []
    if skill in ("handoff", "precompact"):
        task_action, task_content = validation.validate_task(payload, skill)
        todo_action, todo_content, todo_old, todo_new = validation.validate_todo(
            payload
        )
        plans = [
            planning.plan_task(root, task_action, task_content),
            planning.plan_todo(root, todo_action, todo_content, todo_old, todo_new),
        ]
        # Only under handoff: after a compaction the summary carries the task.
        if skill == "handoff" and continuation:
            require_something_to_continue(plans)
        for plan in plans:
            planning.apply_plan(plan)

    compose_sentinel(
        root, transition, continuation=continuation, owner=owner, held=held
    )
    ending = Ending(held=held, typed=transition.typed)
    boundary = Boundary(skill, root, commit_mode)
    parts = compose_directives(boundary, memory, ending, plans)
    print_output(parts)
    return 0


def require_something_to_continue(plans: list[planning.FilePlan]) -> None:
    """Refuse the continuation when neither half would have a body.

    The fixed continuation points at `TASK.md` and `TODO.md`; with both empty
    after the plans, the next session is told there is no task frame and would
    still be sent a prompt to continue from it. Errors, naming `continue`,
    before anything is written.
    """
    if not any(planning.has_body_after(plan) for plan in plans):
        lib.err(
            "continue",
            "true, but neither TASK.md nor TODO.md would have a body: there is"
            " no task or todo for the continuation to point at",
        )


def hold_decision(
    transition: validation.Transition, *, memory: bool, commit: bool
) -> bool:
    """Return whether the transition is held pending an explicit release.

    Held iff the sentinel names any command and a memory directive is owed, or
    the transition is driven (`typed`) and this turn carries a commit. The
    second disjunct is scoped to `typed` rather than to "names any command":
    what it protects under a commit is work from a transition that would run
    over a failed commit, and an untyped handoff's only command is `/rename`,
    whose misfire costs nothing — holding that case too would add an approval
    call to the common "handoff and commit" invocation for no protected state.
    """
    return (bool(transition.cmds) and memory) or (transition.typed and commit)


def compose_sentinel(
    root: Path,
    transition: validation.Transition,
    *,
    continuation: bool,
    owner: str,
    held: bool,
) -> None:
    """Write the sentinel, held or armed per `held`, and read it back.

    Line 1 names `owner` in either state: the prompt-time sweep tells the
    owner's file from another live session's by it. The read-back goes through
    the bash parser; a sentinel it rejects is removed and reported as a
    transition error.
    """
    state = f"held {owner}" if held else f"armed {owner}"

    drive_path = root / HANDOFF_REL_DRIVE
    sentinel_lines = [state, transition.kind, *transition.cmds]
    if continuation:
        sentinel_lines.append(CONTINUATION)
    # Renamed into place rather than written through the name: a link at the
    # sentinel is swapped for the new file, never followed onto what it names.
    # The temporary file takes the `autodrive.` prefix, which the
    # `.claude/autodrive*` ignore covers, so one orphaned by a kill is never
    # committed.
    try:
        drive_path.parent.mkdir(exist_ok=True)
        planning.write_replacing(
            drive_path,
            "\n".join(sentinel_lines) + "\n",
            prefix=f"{drive_path.name}.",
        )
    except OSError as e:
        lib.err("transition", f"cannot write {HANDOFF_REL_DRIVE}: {e.strerror or e}")

    ok, drive_err = _read_back_drive(drive_path)
    if not ok:
        drive_path.unlink()
        lib.err(
            "transition",
            f"composed a sentinel this version cannot read back — {drive_err}",
        )


# The fixed prompt submitted after a driven transition when `continue` is true.
CONTINUATION = "Continue where the previous context stopped."


def check_sentinel_target(root: Path) -> None:
    """Refuse a sentinel path that cannot take a file, before any write.

    `.claude` must be a directory (a link to one is written where it points) or
    absent, and `.claude/autodrive` must not be a directory. Checked ahead of
    the frame files, so a call that could not compose its sentinel leaves
    TASK.md and TODO.md as they were. compose_sentinel still routes any other
    write failure through `lib.err`.
    """
    drive_path = root / HANDOFF_REL_DRIVE
    parent = drive_path.parent
    if (parent.exists() or parent.is_symlink()) and not parent.is_dir():
        lib.err(
            "transition",
            f"cannot write {HANDOFF_REL_DRIVE}: {parent.name} is not a directory",
        )
    if drive_path.is_dir() and not drive_path.is_symlink():
        lib.err("transition", f"cannot write {HANDOFF_REL_DRIVE}: it is a directory")


def _read_back_drive(drive_path: Path) -> tuple[bool, str]:
    """Read the just-composed sentinel back through handoff_drive_read.

    handoff_drive_read stays bash (unmoved) — the single implementation of the
    sentinel grammar.
    """
    script = (
        f"source {shlex.quote(str(_LIB_SH))}; "
        f"handoff_drive_read {shlex.quote(str(drive_path))} && exit 0; "
        'printf "%s" "$DRIVE_ERR" >&2; exit 1'
    )
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, check=False
    )
    return result.returncode == 0, result.stderr


class Ending(NamedTuple):
    """What ends the directive output: the arming instruction or closing line.

    `held` is the one hold decision, shared with the sentinel; `typed` picks the
    closing line when not held.
    """

    held: bool
    typed: bool


class Boundary(NamedTuple):
    """The boundary this call serves: its skill, root and commit mode."""

    skill: str
    root: Path
    commit_mode: str


def compose_directives(
    boundary: Boundary,
    memory: lib.MemoryPart,
    ending: Ending,
    plans: list[planning.FilePlan],
) -> list[str]:
    """Return the ordered, non-empty directive parts for this boundary.

    Print order: the legacy reports, then memory, then the todo boundary/SDD
    nudge, then the commit act (present only under "with-commit"), then either
    the arming instruction (held) or the closing line (not held) — always last,
    and mutually exclusive. [] under autoname. The act that stages the legacy
    paths and the reports both name them relative to the root. The clause-file
    refusal (`memory.refusal`) suppresses every other part but the legacy
    reports and the act that stages the legacy paths: it prints last.
    """
    skill, root, commit_mode = boundary
    if skill not in ("handoff", "precompact"):
        return []
    reports = planning.legacy_reports(plans)
    gone = [
        plan.legacy.rel
        for plan in plans
        if plan.legacy is not None and plan.legacy.fate != "ignored"
    ]
    with_commit = commit_mode == "with-commit"
    root_s = str(root)
    if memory.refusal:
        unstage = lib.legacy_unstage_directive(root_s, gone) if with_commit else ""
        return [part for part in (reports, unstage, memory.text) if part]
    if skill == "handoff":
        second = lib.todo_boundary(root_s)
    else:
        second = lib.sdd_directive(root_s)
    commit = lib.commit_directive(root_s, gone) if with_commit else ""
    parts = [part for part in (reports, memory.text, second, commit) if part]
    if ending.held:
        parts.append(lib.arming_directive())
    else:
        parts.append(lib.closing_directive(skill, typed=ending.typed))
    return parts


def print_output(parts: list[str]) -> None:
    """Print the directive output (FR9).

    The non-empty parts, in order, blank-line separated. Writes nothing for an
    empty list. Each part already ends in a newline of its own, so the trailing
    one is stripped before joining: otherwise the separator lands on top of it
    and every gap is two blank lines rather than one.
    """
    if parts:
        sys.stdout.write("\n\n".join(part.rstrip("\n") for part in parts) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
