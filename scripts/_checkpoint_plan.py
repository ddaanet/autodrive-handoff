"""Plan layer for checkpoint.py (handoff-checkpoint).

Resolves each half of the wrap-up, the task and the todo, to a `FilePlan` (FR5)
before anything is written, so every payload failure surfaces while the plans
are being resolved; `apply_plan` then performs them. The legacy migration is
part of that resolution: a half's legacy file is moved, removed or left ignored
by the same plan, and `legacy_reports` says which. Errors go through
`_checkpoint_lib.err`, which exits 2 naming the offending field.
"""

from __future__ import annotations

import errno
import os
import shutil
import tempfile
from pathlib import Path
from typing import Literal, NamedTuple

import _checkpoint_lib as lib


class Legacy(NamedTuple):
    """What a plan does about the file at its half's legacy path.

    `moved`: its bytes become the root file. `removed`: it goes, its bytes
    carried nowhere. `ignored`: the root file wins and it stays as it is.
    """

    path: Path
    rel: str
    fate: Literal["moved", "removed", "ignored"]


class FilePlan(NamedTuple):
    """What one half will do to its file, resolved before anything is written.

    A NamedTuple, like Transition beside it, so the record itself is frozen.
    `none` leaves the list as it is: with no legacy file it neither reads nor
    stats the root file (FR4). `move` carries the legacy file onto `path` with
    its modification time; a `write` or a `remove` also takes its legacy file
    away unless that one is `ignored`.
    """

    act: Literal["write", "remove", "move", "none"]
    path: Path
    body: str
    legacy: Legacy | None = None


class Half(NamedTuple):
    """One half's root file and legacy path, and whether the root file counts.

    A root file counts when it has a body: the loader's own test, so what the
    checkpoint treats as the frame is what the next session is shown. Only a
    half with a legacy file asks; any other reads `False` and its root file is
    left unread.
    """

    path: Path
    legacy_path: Path
    legacy_rel: str
    has_body: bool


def edited_body(field: str, path: Path, old: str, new: str) -> str:
    """Return path's content with old replaced by new, first occurrence only.

    Errors, naming field, if old is absent or ambiguous. Returns the replacement
    rather than writing it, which is what lets both lib.err() sites run while a
    plan is still being resolved, ahead of any write (FR2).
    """
    content = path.read_text(encoding="utf-8")
    count = content.count(old)
    if count == 0:
        lib.err(f"{field}.old_string", f"not found in {path}")
    if count > 1:
        lib.err(f"{field}.old_string", f"ambiguous, {count} occurrences in {path}")
    return content.replace(old, new, 1)


def read_half(field: str, root: Path, rel: str, legacy_rel: str) -> Half:
    """Return the half's paths, or error when its legacy file cannot be handled.

    Errors when a directory sits on the root file, which leaves the legacy file
    nowhere to go, and when the legacy path is a symlink to a file, whose
    relative target would not resolve from the root. The root file is read only
    when a legacy file exists.
    """
    path = root / rel
    legacy_path = root / legacy_rel
    if not legacy_path.is_file():
        return Half(path, legacy_path, legacy_rel, has_body=False)
    if legacy_path.is_symlink():
        lib.err(field, f"{legacy_rel} is a symbolic link, not a file")
    if path.is_dir():
        lib.err(field, f"{rel} is a directory, not a file")
    counts = path.is_file() and not lib.is_empty_body(
        path.read_text(encoding="utf-8", errors="replace")
    )
    return Half(path, legacy_path, legacy_rel, counts)


def legacy_fate(half: Half, *, after: bool, carried: bool) -> Legacy | None:
    """Return what becomes of the half's legacy file, None when there is none.

    `after` is whether the root file will have a body once the plan is applied;
    `carried` is whether the legacy file's bytes are what it will hold. A root
    file with a body before and after is the frame and the legacy file stays.
    Any other outcome would leave the legacy file as a frame the loader could
    pick up again, so it goes.
    """
    if not half.legacy_path.is_file():
        return None
    if half.has_body and after:
        return Legacy(half.legacy_path, half.legacy_rel, "ignored")
    fate: Literal["moved", "removed"] = "moved" if carried else "removed"
    return Legacy(half.legacy_path, half.legacy_rel, fate)


def plan_task(root: Path, action: str, content: str) -> FilePlan:
    """Resolve the task write or clear to a plan (FR5).

    A content string is written as given; only `clear` removes the root file.
    """
    half = read_half("task", root, HANDOFF_REL_TASK, HANDOFF_LEGACY_REL_TASK)
    if action == "clear":
        legacy = legacy_fate(half, after=False, carried=False)
        return FilePlan("remove", half.path, "", legacy)
    after = not lib.is_empty_body(content)
    legacy = legacy_fate(half, after=after, carried=False)
    return FilePlan("write", half.path, content, legacy)


def plan_todo(root: Path, action: str, content: str, old: str, new: str) -> FilePlan:
    """Resolve the todo write, edit, clear or keep to a plan (FR5).

    A content string and an edit's result are written as given, whatever is left
    in them; only `clear` removes the root file. `edit` errors here, ahead of
    any write, when the file is absent or `old` does not occur in it exactly
    once. The file is the root one when it has a body, else the legacy one.
    """
    half = read_half("todo", root, HANDOFF_REL_TODO, HANDOFF_LEGACY_REL_TODO)
    if action == "keep":
        legacy = legacy_fate(half, after=half.has_body, carried=True)
        if legacy is not None and legacy.fate == "moved":
            return FilePlan("move", half.path, "", legacy)
        return FilePlan("none", half.path, "", legacy)
    if action == "clear":
        legacy = legacy_fate(half, after=False, carried=False)
        return FilePlan("remove", half.path, "", legacy)
    if action == "edit":
        use_legacy = not half.has_body and half.legacy_path.is_file()
        source = half.legacy_path if use_legacy else half.path
        if not source.is_file():
            lib.err(
                "todo.old_string",
                f"edit requested but {HANDOFF_REL_TODO} does not exist",
            )
        body = edited_body("todo", source, old, new)
        legacy = legacy_fate(
            half, after=not lib.is_empty_body(body), carried=use_legacy
        )
        return FilePlan("write", half.path, body, legacy)
    legacy = legacy_fate(half, after=not lib.is_empty_body(content), carried=False)
    return FilePlan("write", half.path, content, legacy)


def apply_plan(plan: FilePlan) -> None:
    """Perform the write, unlink or move a plan names.

    Then take the legacy file off its path unless it is ignored, so the root
    file is current before the legacy one goes. A failed move errors; the other
    arms leave a filesystem failure to surface as it is, every payload failure
    having been found while the plans were being resolved.
    """
    legacy = plan.legacy
    if plan.act == "write":
        plan.path.write_text(plan.body, encoding="utf-8")
    elif plan.act == "remove":
        plan.path.unlink(missing_ok=True)
    elif plan.act == "move" and legacy is not None:
        move_legacy(legacy, plan.path)
    if legacy is not None and legacy.fate != "ignored":
        legacy.path.unlink(missing_ok=True)


def move_legacy(legacy: Legacy, path: Path) -> None:
    """Put the legacy file's bytes and modification time at `path`.

    A rename when the two share a device. Across devices, a copy lands beside
    `path` and is renamed onto it, so the root file is whole or untouched; the
    caller removes the legacy file after. Any other failure errors naming it.
    """
    try:
        legacy.path.replace(path)
    except OSError as exc:
        if exc.errno != errno.EXDEV:
            lib.err(legacy.rel, f"cannot be moved to {path.name}: {exc.strerror}")
        copy_across_devices(legacy, path)


def copy_across_devices(legacy: Legacy, path: Path) -> None:
    """Copy the legacy file onto `path` through a sibling temporary file."""
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    os.close(fd)
    try:
        shutil.copy2(legacy.path, name)
        Path(name).replace(path)
    except OSError as exc:
        Path(name).unlink(missing_ok=True)
        lib.err(legacy.rel, f"cannot be moved to {path.name}: {exc.strerror}")


def legacy_reports(plans: list[FilePlan]) -> str:
    """Return one line per legacy file the plans found, or "" for none."""
    lines = []
    for plan in plans:
        legacy = plan.legacy
        if legacy is None:
            continue
        if legacy.fate == "moved":
            lines.append(f"Legacy {legacy.rel} moved to {plan.path.name}.")
        elif legacy.fate == "removed":
            lines.append(f"Legacy {legacy.rel} removed.")
        else:
            lines.append(
                f"Legacy {legacy.rel} is ignored: {plan.path.name} has a body."
            )
    return "".join(f"{line}\n" for line in lines)


# Mirrors _lib.sh's HANDOFF_REL_* constants. Changing either side is a
# breaking change (see CLAUDE.md conventions); kept in sync by hand rather
# than sourced, since _lib.sh stays bash.
HANDOFF_REL_TASK = "TASK.md"
HANDOFF_REL_TODO = "TODO.md"

# Mirrors _lib.sh's HANDOFF_LEGACY_REL_*: where the task and todo files lived
# before they moved to the root. The checkpoint moves a file off them; the
# fallback goes once no sibling repository still has a `.claude/handoff-*.md`.
# `grep -rni legacy scripts/ tests/` lists all of it.
HANDOFF_LEGACY_REL_TASK = ".claude/handoff-task.md"
HANDOFF_LEGACY_REL_TODO = ".claude/handoff-todo.md"
