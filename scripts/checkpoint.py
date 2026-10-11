#!/usr/bin/env python3
"""Handoff-checkpoint: the one write path for the handoff/precompact wrap-up.

Reads a JSON payload on stdin, validates it against the schema (FR2 — a
violation exits 2 naming the offending field on stderr), applies the task/todo
tagged union — content, or an object naming an action (FR5) — to `TASK.md` and
`TODO.md` in the root, composes the sentinel (FR8), and prints the directive
output (FR9). Only `handoff` carries a `task`; `precompact` forbids the key and
removes any task file on disk.

NFR1: nothing here mutates git state — this is the agent's sandboxed Bash, and
both files are plain tracked files whichever commit comes next picks up. At turn
end the sentinel is taken by scripts/drive-take.sh and run by the drive mod.

Port of checkpoint.sh — see docs/changelog/2026-08-10-python-split.md. The
composer reads its own sentinel back through handoff_drive_read, which stays the
single bash implementation of the sentinel grammar (still used by drive-take.sh,
load-compact.sh, load-handoff.sh and report-drive-failure.sh) — so this shells
out to it rather than reimplementing the grammar a second time, which is exactly
the drift the single-parser design exists to prevent.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Literal, NamedTuple, NoReturn, cast

import _checkpoint_lib as lib

# A parsed JSON object. The payload's shape is validated at runtime (FR2),
# not by static typing — every value is Any until a validate_* function
# narrows it.
JSONDict = dict[str, Any]

# Mirrors _lib.sh's HANDOFF_REL_* constants. Changing either side is a
# breaking change (see CLAUDE.md conventions); kept in sync by hand rather
# than sourced, since _lib.sh stays bash.
HANDOFF_REL_TASK = "TASK.md"
HANDOFF_REL_TODO = "TODO.md"
HANDOFF_REL_DRIVE = ".claude/autodrive"

_LIB_SH = Path(__file__).resolve().parent / "_lib.sh"


def main() -> int:
    """Run the checkpoint.

    Validate the payload, apply writes, compose the sentinel and directives,
    print them.
    """
    payload = read_payload()
    root = validate_root()
    skill = validate_skill(payload)
    validate_top_level_keys(payload)

    if skill == "autoname":
        validate_autoname_forbidden_fields(payload)
    commit_mode = validate_commit_mode(payload, skill)
    title = validate_rename(payload, skill)
    transition = build_transition(payload, skill, title)
    continuation = validate_continuation(payload, skill, typed=transition.typed)

    memory = lib.MemoryPart("", refusal=False)
    if skill in ("handoff", "precompact"):
        memory = lib.memory_directive(str(root), commit_mode)
    held = hold_decision(
        transition, memory=bool(memory.text), commit=commit_mode == "with-commit"
    )
    if held:
        # Resolving before anything is written (task/todo/sentinel):
        # a held sentinel's first line names the session, and there is
        # nothing else this run could do with it unset.
        require_session_id(
            "transition", "cannot compose a held sentinel naming the session holding it"
        )

    if skill in ("handoff", "precompact"):
        task_action, task_content = validate_task(payload, skill)
        todo_action, todo_content, todo_old, todo_new = validate_todo(payload)
        task_plan = plan_task(root, task_action, task_content)
        todo_plan = plan_todo(root, todo_action, todo_content, todo_old, todo_new)
        apply_plan(task_plan)
        apply_plan(todo_plan)

    compose_sentinel(root, transition, continuation, held=held)
    ending = Ending(held=held, typed=transition.typed)
    parts = compose_directives(skill, root, commit_mode, memory, ending)
    print_output(parts)
    return 0


class Transition(NamedTuple):
    """The sentinel's kind, its command lines, and whether it is typed."""

    kind: str
    cmds: list[str]
    typed: bool


def err(field: str, message: str) -> NoReturn:
    """Print a schema/write-time error naming field, then exit 2."""
    print(f"handoff-checkpoint: {field}: {message}", file=sys.stderr)
    raise SystemExit(2)


def _json_type(value: object) -> str:
    """Return the jq-style type name of a decoded JSON value."""
    if isinstance(value, bool):
        return "boolean"
    checks: list[tuple[type | tuple[type, ...], str]] = [
        (type(None), "null"),
        ((int, float), "number"),
        (str, "string"),
        (list, "array"),
        (dict, "object"),
    ]
    for types, name in checks:
        if isinstance(value, types):
            return name
    return "unknown"


def require_one_line(field: str, value: str) -> None:
    """Error unless value is non-blank and holds no embedded newline."""
    if not re.sub(r"\s", "", value):
        err(field, "must not be empty or whitespace only")
    if "\n" in value:
        err(field, "must be a single line")


def read_payload() -> JSONDict:
    """Parse the JSON payload on stdin, or error naming "payload"."""
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        err("payload", "malformed JSON on stdin")
    if not isinstance(payload, dict):
        err("payload", "malformed JSON on stdin")
    return payload


def validate_root() -> Path:
    """Return HANDOFF_ROOT from the environment.

    Injected by inject-checkpoint-root.sh into the very command that invokes
    this.
    """
    root = os.environ.get("HANDOFF_ROOT", "")
    if not root:
        err(
            "root",
            "HANDOFF_ROOT is unset — call via the handoff-checkpoint shim on PATH, "
            "unmodified, so the PreToolUse(Bash) hook recognises and injects it",
        )
    path = Path(root)
    if not path.is_dir():
        err("root", f'HANDOFF_ROOT does not name a directory (got "{root}")')
    return path


def validate_skill(payload: JSONDict) -> str:
    """Return the skill name.

    One of "handoff", "precompact" or "autoname".
    """
    skill = payload.get("skill")
    if "skill" not in payload or skill in (None, ""):
        err(
            "skill",
            'required, one of "handoff", "precompact" or "autoname"',
        )
    if skill not in ("handoff", "precompact", "autoname"):
        err(
            "skill",
            f'must be "handoff", "precompact" or "autoname", got "{skill}"',
        )
    return cast("str", skill)


def validate_top_level_keys(payload: JSONDict) -> None:
    """Error naming the first (sorted) key outside the union any skill takes.

    Flat rather than skill-dependent: each of the four skill-specific
    validators below already rejects a *known* key present under the wrong
    skill, with a message more specific than this one could give (naming the
    skill, or the action it collides with) — a skill-dependent check placed
    this early would shadow those and regress their tests for no gain. What
    none of them is positioned to catch is a key outside the vocabulary
    altogether (a typo like "tasks"), which collides with nothing skill-
    specific to name; this is the one place that closes that gap.
    """
    extra = sorted(k for k in payload if k not in _TOP_LEVEL_KEYS)
    if not extra:
        return
    takes = ", ".join(f'"{k}"' for k in _TOP_LEVEL_KEYS)
    err("payload", f'unknown key "{extra[0]}", takes only {takes}')


_TOP_LEVEL_KEYS = (
    "skill",
    "commit",
    "rename",
    "task",
    "todo",
    "clear",
    "compact",
    "continue",
)


def validate_commit_mode(payload: JSONDict, skill: str) -> str:
    """Return the commit mode.

    "" for autoname (it carries no commit awareness); the commit mode string
    otherwise.
    """
    if skill == "autoname":
        return ""
    commit_mode = payload.get("commit")
    if commit_mode not in ("with-commit", "without-commit"):
        if commit_mode in (None, ""):
            err("commit", 'required, one of "with-commit" or "without-commit"')
        err("commit", f'must be "with-commit" or "without-commit", got "{commit_mode}"')
    return cast("str", commit_mode)


def validate_autoname_forbidden_fields(payload: JSONDict) -> None:
    """Error naming the field if any boundary-only field is present."""
    for forbidden in ("commit", "task", "todo", "clear", "compact", "continue"):
        if forbidden in payload:
            err(forbidden, 'forbidden when skill is "autoname"')


def validate_rename(payload: JSONDict, skill: str) -> str:
    """Return the flattened title.

    Required wherever a title is decided (handoff, autoname) and forbidden under
    precompact by key presence.
    """
    if skill == "precompact":
        if "rename" in payload:
            err("rename", 'forbidden when skill is "precompact"')
        return ""
    if "rename" not in payload or payload.get("rename") is None:
        err("rename", f'required when skill is "{skill}"')
    if _json_type(payload["rename"]) != "string":
        err("rename", f"must be a title string, got {_json_type(payload['rename'])}")
    title = re.sub(r"\s+", " ", payload["rename"]).strip()
    if not title:
        err("rename", "must be a non-empty title")
    return title


def build_transition(payload: JSONDict, skill: str, title: str) -> Transition:
    """Return the transition this call types, per the skill's own rules."""
    if skill == "autoname":
        return Transition("rename", [f"/rename {title}"], typed=False)
    if skill == "handoff":
        return _build_handoff_transition(payload, title)
    return _build_precompact_transition(payload)


def require_session_id(field: str, reason: str) -> str:
    """Return CLAUDE_CODE_SESSION_ID, or error naming field with reason."""
    session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not session_id:
        err(field, f"CLAUDE_CODE_SESSION_ID is unset — {reason}")
    return session_id


def _build_handoff_transition(payload: JSONDict, title: str) -> Transition:
    if "compact" in payload:
        err("compact", 'forbidden when skill is "handoff"')
    if "clear" not in payload:
        err("clear", 'required when skill is "handoff"')
    if not isinstance(payload["clear"], bool):
        err("clear", "must be true or false")
    if payload["clear"] is True:
        return Transition("clear", [f"/rename {title}", "/clear"], typed=True)
    return Transition("rename", [f"/rename {title}"], typed=False)


def _build_precompact_transition(payload: JSONDict) -> Transition:
    if "clear" in payload:
        err("clear", 'forbidden when skill is "precompact"')
    if "compact" not in payload:
        err("compact", 'required when skill is "precompact"')
    compact_val = payload["compact"]
    ctype = _json_type(compact_val)
    if ctype == "boolean":
        if compact_val is True:
            return Transition("compact", ["/compact"], typed=True)
        return Transition("compact", [], typed=False)
    if ctype == "string":
        require_one_line("compact", compact_val)
        return Transition("compact", [f"/compact {compact_val}"], typed=True)
    err("compact", "must be true, false, or a focus directive string")
    raise AssertionError("unreachable")  # err() always raises


def validate_continuation(payload: JSONDict, skill: str, *, typed: bool) -> str:
    """Return the continuation prompt, or "" when there is none."""
    if skill == "autoname":
        return ""
    if "continue" not in payload:
        err("continue", "required, either null or one line of prose")
    if payload["continue"] is None:
        return ""
    if not isinstance(payload["continue"], str):
        err("continue", "must be null or one line of prose")
    continuation = payload["continue"]
    require_one_line("continue", continuation)
    if continuation.startswith("/"):
        err("continue", "must not begin with `/`")
    if not typed:
        err("continue", "must be null when the transition is not driven")
    return continuation


def _got(value: object) -> str:
    """Render a rejected `action` value: quoted when a string, else its type.

    A non-string action rendered with `f"{value}"` prints a Python repr —
    `True`, not `true` — so the diagnostic names a spelling no JSON producer
    could have sent. Every other type reads better as its type name anyway,
    which is what the neighbouring diagnostics already say.
    """
    if _json_type(value) == "string":
        return f'"{value}"'
    return _json_type(value)


def _reject_unknown_keys(
    field: str, obj: JSONDict, action: str, allowed: tuple[str, ...]
) -> None:
    """Error unless obj carries only "action" and the action's own keys.

    An action object that silently ignores what it does not recognize is the
    defect class the tagged union was opened to close one level down: an agent
    told `must be "clear", got "write"` that corrects only the action leaves
    its `content` in place, and the frame is removed with nothing said.
    """
    extra = sorted(k for k in obj if k != "action" and k not in allowed)
    if not extra:
        return
    takes = (
        "takes no other key"
        if not allowed
        else "takes only " + " and ".join(f'"{k}"' for k in allowed)
    )
    err(field, f'unknown key "{extra[0]}", {{"action": "{action}"}} {takes}')


def validate_task(payload: JSONDict, skill: str) -> tuple[str, str]:
    """("write", content) or ("clear", "").

    Required under handoff. Forbidden under precompact by key presence, whatever
    the value, and the absent key resolves to ("clear", ""): the removal runs
    through the same plan as an explicit clear.
    """
    if skill == "precompact":
        if "task" in payload:
            err("task", 'forbidden when skill is "precompact"')
        return "clear", ""
    if "task" not in payload:
        err("task", 'required, a content string or {"action": "clear"}')
    task = payload["task"]
    ttype = _json_type(task)
    if ttype == "string":
        validate_task_shape(cast("str", task))
        return "write", cast("str", task)
    if ttype == "object":
        if "action" not in task:
            err("task.action", 'required, a content string or {"action": "clear"}')
        action = task["action"]
        if action == "clear":
            _reject_unknown_keys("task", task, "clear", ())
            return "clear", ""
        err("task.action", f'must be "clear", got {_got(action)}')
    err(
        "task",
        f'must be a content string or {{"action": "clear"}}, got {ttype}',
    )
    raise AssertionError("unreachable")  # err() always raises


def validate_task_shape(content: str) -> None:
    """Reject a task body over the character cap or holding a list item.

    The body is the content without its ATX heading lines, stripped; the cap
    counts its characters. A list item is a line opening with a bullet or a
    numbered marker followed by whitespace; the first is named by its 1-based
    line number. Both facts, when both hold, go in one error.
    """
    lines = content.split("\n")
    prose = [ln for ln in lines if not lib.ATX_HEADING.fullmatch(ln.rstrip())]
    body = "\n".join(prose).strip()
    facts: list[str] = []
    for number, line in enumerate(lines, start=1):
        if _LIST_ITEM.match(line):
            facts.append(f'line {number} is a list item ("{line.strip()[:40]}")')
            break
    if len(body) > TASK_BODY_LIMIT:
        facts.append(
            f"body is {len(body)} characters, the limit is {TASK_BODY_LIMIT} "
            "(headings not counted)"
        )
    if not facts:
        return
    err(
        "task",
        "; ".join(facts) + ". The task is prose within the limit: keep the task in "
        'hand and where it stands, move remaining steps and open decisions to "todo", '
        "cut finished work to one sentence, and write standing rules and conventions "
        "to memory.",
    )


# A bullet (`-`, `*`, `+`) or a numbered marker (`1.`, `1)`), then whitespace.
_LIST_ITEM = re.compile(r"^\s*([-*+]|\d+[.)])\s")

# Characters in a task's body, headings not counted.
TASK_BODY_LIMIT = 1000


def validate_todo(payload: JSONDict) -> tuple[str, str, str, str]:
    """Return the todo action and its content or old/new strings.

    ("write", content, "", ""), ("edit", "", old_string, new_string), ("clear",
    "", "", "") or ("keep", "", "", "").
    """
    if "todo" not in payload:
        err("todo", "required, a content string or an object naming an action")
    todo = payload["todo"]
    ttype = _json_type(todo)
    if ttype == "string":
        return "write", cast("str", todo), "", ""
    if ttype == "object":
        if "action" not in todo:
            err(
                "todo.action",
                'required, a content string or "clear", "keep" or "edit"',
            )
        action = todo["action"]
        if action in ("clear", "keep"):
            _reject_unknown_keys("todo", todo, cast("str", action), ())
            return cast("str", action), "", "", ""
        if action == "edit":
            _reject_unknown_keys("todo", todo, "edit", ("old_string", "new_string"))
            old_string, new_string = _todo_edit_strings(todo)
            return "edit", "", old_string, new_string
        err(
            "todo.action",
            f'must be "clear", "keep" or "edit", got {_got(action)}',
        )
    err(
        "todo",
        f"must be a content string or an object naming an action, got {ttype}",
    )
    raise AssertionError("unreachable")  # err() always raises


def _todo_edit_strings(todo: JSONDict) -> tuple[str, str]:
    """Return the edit action's (old_string, new_string), both required strings.

    Typing them here is what keeps `edit` from being the one arm of the union
    that types nothing: every other arm's payload is a checked string, and an
    unchecked one reaches edited_body's `content.count(old)` as a TypeError,
    which exits 1 and names no field (FR2).
    """
    strings: list[str] = []
    for key in ("old_string", "new_string"):
        if key not in todo:
            err(f"todo.{key}", 'required for {"action": "edit"}')
        ktype = _json_type(todo[key])
        if ktype != "string":
            err(f"todo.{key}", f"must be a string, got {ktype}")
        strings.append(cast("str", todo[key]))
    return strings[0], strings[1]


class FilePlan(NamedTuple):
    """What one half will do to its file, resolved before anything is written.

    A NamedTuple, like Transition beside it, so the record itself is frozen.
    `none` is `keep`'s plan alone: the list is left as it is, without a stat
    (FR4).
    """

    act: Literal["write", "remove", "none"]
    path: Path
    body: str


def edited_body(field: str, path: Path, old: str, new: str) -> str:
    """Return path's content with old replaced by new, first occurrence only.

    Errors, naming field, if old is absent or ambiguous. Returns the replacement
    rather than writing it, which is what lets both err() sites run while a plan
    is still being resolved, ahead of any write (FR2).
    """
    content = path.read_text(encoding="utf-8")
    count = content.count(old)
    if count == 0:
        err(f"{field}.old_string", f"not found in {path}")
    if count > 1:
        err(f"{field}.old_string", f"ambiguous, {count} occurrences in {path}")
    return content.replace(old, new, 1)


def plan_task(root: Path, action: str, content: str) -> FilePlan:
    """Resolve the task write or clear to a plan (FR5).

    A content string is written as given; only `clear` removes.
    """
    path = root / HANDOFF_REL_TASK
    if action == "clear":
        return FilePlan("remove", path, "")
    return FilePlan("write", path, content)


def plan_todo(root: Path, action: str, content: str, old: str, new: str) -> FilePlan:
    """Resolve the todo write, edit, clear or keep to a plan (FR5).

    A content string and an edit's result are written as given, whatever is left
    in them; only `clear` removes. `edit` errors here, ahead of any write, when
    the file is absent or `old` does not occur in it exactly once.
    """
    path = root / HANDOFF_REL_TODO
    if action == "keep":
        return FilePlan("none", path, "")
    if action == "clear":
        return FilePlan("remove", path, "")
    if action == "edit":
        if not path.is_file():
            err(
                "todo.old_string",
                f"edit requested but {HANDOFF_REL_TODO} does not exist",
            )
        return FilePlan("write", path, edited_body("todo", path, old, new))
    return FilePlan("write", path, content)


def apply_plan(plan: FilePlan) -> None:
    """Perform the write or the unlink a plan names.

    Neither arm calls err(): a removal of a file that is not there is no error,
    so nothing can fail between the two halves.
    """
    if plan.act == "write":
        plan.path.write_text(plan.body, encoding="utf-8")
    elif plan.act == "remove":
        plan.path.unlink(missing_ok=True)


def hold_decision(transition: Transition, *, memory: bool, commit: bool) -> bool:
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
    root: Path, transition: Transition, continuation: str, *, held: bool
) -> None:
    """Write the sentinel, held or armed per `held`, and read it back.

    The read-back goes through the bash parser; a sentinel it rejects is removed
    and reported as a transition error.
    """
    state = "armed"
    if held:
        session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
        state = f"held {session_id}"

    drive_path = root / HANDOFF_REL_DRIVE
    drive_path.parent.mkdir(exist_ok=True)
    sentinel_lines = [state, transition.kind, *transition.cmds]
    if continuation:
        sentinel_lines.append(continuation)
    drive_path.write_text("\n".join(sentinel_lines) + "\n", encoding="utf-8")

    ok, drive_err = _read_back_drive(drive_path)
    if not ok:
        drive_path.unlink()
        err(
            "transition",
            f"composed a sentinel this version cannot read back — {drive_err}",
        )


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


def compose_directives(
    skill: str, root: Path, commit_mode: str, memory: lib.MemoryPart, ending: Ending
) -> list[str]:
    """Return the ordered, non-empty directive parts for this boundary.

    Print order: memory, then the todo boundary/SDD nudge, then the commit act
    (present only under "with-commit"), then either the arming instruction
    (held) or the closing line (not held) — always last, and mutually
    exclusive. [] under autoname. The clause-file refusal
    (`memory.refusal`) suppresses every other part — the checkpoint prints it
    alone.
    """
    if skill not in ("handoff", "precompact"):
        return []
    if memory.refusal:
        return [memory.text]
    root_s = str(root)
    if skill == "handoff":
        second = lib.todo_boundary(root_s)
    else:
        second = lib.sdd_directive(root_s)
    commit = lib.commit_directive() if commit_mode == "with-commit" else ""
    parts = [part for part in (memory.text, second, commit) if part]
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
