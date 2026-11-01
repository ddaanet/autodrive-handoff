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

Port of checkpoint.sh — see the changelog-archive tag's 2026-08-10 record,
"checkpoint.sh and the watcher move to Python". The composer reads its own
sentinel back through handoff_drive_read, which stays the single bash
implementation of the sentinel grammar, which four other scripts still use:
drive-take.sh, load-compact.sh, load-handoff.sh and report-drive-failure.sh. So
this shells out to it rather than reimplementing the grammar a second time,
which is exactly the drift the single-parser design exists to prevent.
"""

from __future__ import annotations

import contextlib
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple, NoReturn

import _checkpoint_lib as lib
import _checkpoint_payload as validation
import _checkpoint_plan as planning
import _drive_lock as drive_lock

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
    root = validate_root()
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

    memory = ""
    if skill in ("handoff", "precompact"):
        memory = lib.memory_directive(str(root))
    held = hold_decision(
        transition, memory=bool(memory), commit=commit_mode == "with-commit"
    )
    # Resolved before anything is written (task/todo/sentinel): every call
    # composes a sentinel, held or armed, and both name their owner on line 1,
    # so there is nothing this run could do with it unset.
    owner = require_session_id(
        "transition", "cannot compose a sentinel naming the session that owns it"
    )
    check_sentinel_target(root)

    plans: list[planning.FilePlan] = []
    task_fields: tuple[str, str] | None = None
    todo_fields: tuple[str, str, str, str] | None = None
    if skill in ("handoff", "precompact"):
        task_fields = validation.validate_task(payload, skill)
        todo_fields = validation.validate_todo(payload)

    # One locked scope covers reading TASK.md/TODO.md to plan, applying the
    # plans and writing the sentinel, so an `edit` resolved against a body is
    # applied to that body, never to one a waiting actor has since replaced.
    # Taken before the first read of either file; a call that cannot take it
    # exits 2 having written nothing, so the same call can be made again (an
    # `edit` could not be, once applied).
    with contextlib.ExitStack() as stack:
        hold_sentinel_lock(stack, root)
        if task_fields and todo_fields:
            plans = [
                planning.plan_task(root, *task_fields),
                planning.plan_todo(root, *todo_fields),
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


def validate_root() -> Path:
    """Return HANDOFF_ROOT from the environment.

    Injected by inject-checkpoint-root.sh into the very command that invokes
    this.
    """
    root = os.environ.get("HANDOFF_ROOT", "")
    if not root:
        lib.err(
            "root",
            "HANDOFF_ROOT is unset — call via the handoff-checkpoint shim on PATH, "
            "unmodified, so the PreToolUse(Bash) hook recognises and injects it",
        )
    path = Path(root)
    if not path.is_dir():
        lib.err("root", f'HANDOFF_ROOT does not name a directory (got "{root}")')
    return path


def require_session_id(field: str, reason: str) -> str:
    """Return CLAUDE_CODE_SESSION_ID, or error naming field with reason."""
    session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not session_id:
        lib.err(field, f"CLAUDE_CODE_SESSION_ID is unset — {reason}")
    return session_id


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
    #
    # The write and the read-back are one step under the sentinel's lock, which
    # the caller holds (`hold_sentinel_lock`), so a take or a sweep acting on the
    # file runs before or after both and never between them.
    try:
        planning.write_replacing(
            drive_path,
            "\n".join(sentinel_lines) + "\n",
            prefix=f"{drive_path.name}.",
        )
    except OSError as e:
        _cannot_write(e)
    try:
        ok, drive_err = _read_back_drive(drive_path)
    except BaseException:
        # Whatever the read-back raised, the file is unverified: gone
        # before the error propagates.
        drive_path.unlink(missing_ok=True)
        raise
    if not ok:
        # Unverified and `armed` is a transition the mod would drive.
        try:
            drive_path.unlink()
        except OSError as e:
            drive_err += f"; it could not be removed: {e.strerror or e}"
    if not ok:
        lib.err(
            "transition",
            f"composed a sentinel this version cannot read back — {drive_err}",
        )


def hold_sentinel_lock(stack: contextlib.ExitStack, root: Path) -> None:
    """Take the sentinel's lock for `stack`'s body, or exit 2 naming the lock.

    Fails closed: a lock busy past the wait (HANDOFF_LOCK_WAIT_SECS) and one that
    could not be set up (a link at its name, no flock) both end the call before
    anything is written, in their own words. `.claude/` is created first, as the
    lock file lives in it.
    """
    try:
        (root / HANDOFF_REL_DRIVE).parent.mkdir(exist_ok=True)
    except OSError as e:
        _cannot_write(e)
    try:
        stack.enter_context(drive_lock.locked(root / HANDOFF_REL_DRIVE_LOCK))
    except drive_lock.LockBusyError:
        lib.err(
            "lock",
            f"the sentinel's lock ({HANDOFF_REL_DRIVE_LOCK}) was busy past the wait"
            " (HANDOFF_LOCK_WAIT_SECS), so nothing was written; run the call again",
        )
    except drive_lock.LockUnavailableError as e:
        lib.err(
            "lock",
            f"the sentinel's lock ({HANDOFF_REL_DRIVE_LOCK}) could not be set up"
            f" ({e}), so nothing was written",
        )


def _cannot_write(error: OSError) -> NoReturn:
    lib.err(
        "transition", f"cannot write {HANDOFF_REL_DRIVE}: {error.strerror or error}"
    )


# Mirrors _lib.sh's HANDOFF_REL_DRIVE_LOCK, the lock every actor holds across
# its own read-decide-write of the sentinel (_drive_lock.py).
HANDOFF_REL_DRIVE_LOCK = ".claude/autodrive.lock"

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
    try:
        result = subprocess.run(
            ["bash", "-c", script], capture_output=True, check=False
        )
    except OSError as e:
        return False, f"the read-back could not run: {e.strerror or e}"
    # Bytes, decoded here: a reader's stderr is a message, never a reason for the
    # read-back to raise.
    reason = result.stderr.decode("utf-8", errors="replace")
    if result.returncode == 0:
        return True, reason
    return False, reason or f"the reader exited {result.returncode} with no reason"


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
    memory: str,
    ending: Ending,
    plans: list[planning.FilePlan],
) -> list[str]:
    """Return the ordered, non-empty directive parts for this boundary.

    Print order: the legacy reports, then the memory directive (`memory`, "" when
    nothing is owed), then the todo boundary/SDD nudge, then the commit act
    (present only under "with-commit", naming the memory gitlink when memory is
    owed), then either the arming instruction (held) or the closing line (not
    held) — always last, and mutually exclusive. [] under autoname. The act that
    stages the legacy paths and the reports both name them relative to the root.
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
    if skill == "handoff":
        second = lib.todo_boundary(root_s)
    else:
        second = lib.sdd_directive(root_s)
    commit = (
        lib.commit_directive(root_s, gone, memory=bool(memory)) if with_commit else ""
    )
    parts = [part for part in (reports, memory, second, commit) if part]
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
