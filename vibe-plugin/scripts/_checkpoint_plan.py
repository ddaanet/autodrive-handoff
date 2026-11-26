"""Plan layer for the Vibe checkpoint.

Resolves each half of the wrap-up, the task and the todo, to a `FilePlan` before
anything is written, so every payload failure surfaces while the plans are being
resolved; `apply_plan` then performs them. Errors go through
`_checkpoint_lib.err`, which exits 2 naming the offending field.
"""

from __future__ import annotations

import os
import stat
import tempfile
from pathlib import Path
from typing import Literal, NamedTuple

import _checkpoint_lib as lib

HANDOFF_REL_TASK = "TASK.md"
HANDOFF_REL_TODO = "TODO.md"


class FilePlan(NamedTuple):
    """What one half will do to its file, resolved before anything is written.

    A NamedTuple so the record itself is frozen. `none` leaves the list as it
    is: it does not read the file, only looks at what sits at its name.
    """

    act: Literal["write", "remove", "none"]
    path: Path
    body: str


def edited_body(field: str, path: Path, old: str, new: str) -> str:
    """Return path's content with old replaced by new, first occurrence only.

    Errors, naming field, if old is absent or ambiguous. Returns the replacement
    rather than writing it, which is what lets both lib.err() sites run while a
    plan is still being resolved, ahead of any write.
    """
    content = read_strict(field, path)
    count = content.count(old)
    if count == 0:
        lib.err(f"{field}.old_string", f"not found in {path}")
    if count > 1:
        lib.err(f"{field}.old_string", f"ambiguous, {count} occurrences in {path}")
    return content.replace(old, new, 1)


def check_target(field: str, root: Path, rel: str) -> Path:
    """Return the half's path, or error when its name cannot be handled.

    Errors, whatever the action, when the name is a symbolic link, which a write
    would follow to a file the checkpoint does not own, or a directory, which no
    write or removal can land on.
    """
    path = root / rel
    if path.is_symlink():
        lib.err(field, f"{rel} is a symbolic link, not a file")
    if path.is_dir():
        lib.err(field, f"{rel} is a directory, not a file")
    return path


def read_strict(field: str, path: Path) -> str:
    """Return path's text as UTF-8, or error naming field when it cannot."""
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        lib.err(field, f"{path.name} is not valid UTF-8")
    except OSError as exc:
        lib.err(field, f"{path.name} cannot be read: {exc.strerror}")


def plan_task(root: Path, action: str, content: str) -> FilePlan:
    """Resolve the task write or clear to a plan.

    A content string is written as given; only `clear` removes the file.
    """
    path = check_target("task", root, HANDOFF_REL_TASK)
    if action == "clear":
        return FilePlan("remove", path, "")
    return FilePlan("write", path, content)


def plan_todo(root: Path, action: str, content: str, old: str, new: str) -> FilePlan:
    """Resolve the todo write, edit, clear or keep to a plan.

    A content string and an edit's result are written as given, whatever is left
    in them; only `clear` removes the file. `edit` errors here, ahead of any
    write, when the file is absent or `old` does not occur in it exactly once.
    """
    path = check_target("todo", root, HANDOFF_REL_TODO)
    if action == "keep":
        return FilePlan("none", path, "")
    if action == "clear":
        return FilePlan("remove", path, "")
    if action == "edit":
        if not path.is_file():
            lib.err(
                "todo.old_string",
                f"edit requested but {HANDOFF_REL_TODO} does not exist",
            )
        return FilePlan("write", path, edited_body("todo", path, old, new))
    return FilePlan("write", path, content)


def apply_plan(plan: FilePlan) -> None:
    """Perform the write or unlink a plan names.

    A write lands through a sibling temporary file renamed onto the name, and
    the unlink removes the name itself, so neither follows a symlink that
    appeared there after resolution refused one. A filesystem failure surfaces
    as it is, every payload failure having been found while the plans were being
    resolved.
    """
    if plan.act == "write":
        write_replacing(plan.path, plan.body)
    elif plan.act == "remove":
        plan.path.unlink(missing_ok=True)


def write_replacing(path: Path, body: str) -> None:
    """Write body at path through a sibling temporary file and os.replace.

    The rename swaps whatever is at the name, a link included, for the new file
    rather than writing through it. The new file keeps the mode of the regular
    file it replaces, else takes the one the umask gives a new file; the
    temporary file, named `.<name>.*`, is removed when anything fails.
    """
    mode = replaced_mode(path)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            tmp.write(body)
        Path(name).chmod(mode)
        Path(name).replace(path)
    except BaseException:
        Path(name).unlink(missing_ok=True)
        raise


def replaced_mode(path: Path) -> int:
    """Return the regular file's permission bits, else 0o666 under the umask."""
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        st = None
    if st is not None and stat.S_ISREG(st.st_mode):
        return stat.S_IMODE(st.st_mode)
    umask = os.umask(0)
    os.umask(umask)
    return 0o666 & ~umask
