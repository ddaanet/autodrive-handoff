"""Payload validation for handoff-checkpoint (FR2).

Each validate_* function narrows one field of the JSON payload read on stdin, or
exits 2 through lib.err naming the offending field. build_transition turns the
boundary fields into the Transition the sentinel is composed from; validate_task
and validate_todo return the task/todo tagged union as plain tuples that
_checkpoint_plan.py resolves into file plans. validate_root and
require_session_id read the environment rather than the payload, but answer the
same way: a value, or an error naming the field.

checkpoint.py imports this module as `validation`; nothing here writes a file.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any, NamedTuple, cast

import _checkpoint_lib as lib


def read_payload() -> JSONDict:
    """Parse the JSON payload on stdin, or error naming "payload"."""
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        lib.err("payload", "malformed JSON on stdin")
    if not isinstance(payload, dict):
        lib.err("payload", "malformed JSON on stdin")
    return payload


# A parsed JSON object. The payload's shape is validated at runtime (FR2),
# not by static typing — every value is Any until a validate_* function
# narrows it.
JSONDict = dict[str, Any]


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


def validate_skill(payload: JSONDict) -> str:
    """Return the skill name.

    One of "handoff", "precompact" or "autoname".
    """
    skill = payload.get("skill")
    if "skill" not in payload or skill in (None, ""):
        lib.err(
            "skill",
            'required, one of "handoff", "precompact" or "autoname"',
        )
    if skill not in ("handoff", "precompact", "autoname"):
        lib.err(
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
    lib.err("payload", f'unknown key "{extra[0]}", takes only {takes}')


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


def validate_autoname_forbidden_fields(payload: JSONDict) -> None:
    """Error naming the field if any boundary-only field is present."""
    for forbidden in ("commit", "task", "todo", "clear", "compact", "continue"):
        if forbidden in payload:
            lib.err(forbidden, 'forbidden when skill is "autoname"')


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
            lib.err("commit", 'required, one of "with-commit" or "without-commit"')
        lib.err(
            "commit", f'must be "with-commit" or "without-commit", got "{commit_mode}"'
        )
    return cast("str", commit_mode)


def validate_rename(payload: JSONDict, skill: str) -> str:
    """Return the flattened title.

    Required wherever a title is decided (handoff, autoname) and forbidden under
    precompact by key presence.
    """
    if skill == "precompact":
        if "rename" in payload:
            lib.err("rename", 'forbidden when skill is "precompact"')
        return ""
    if "rename" not in payload or payload.get("rename") is None:
        lib.err("rename", f'required when skill is "{skill}"')
    if _json_type(payload["rename"]) != "string":
        lib.err(
            "rename", f"must be a title string, got {_json_type(payload['rename'])}"
        )
    title = re.sub(r"\s+", " ", payload["rename"]).strip()
    if not title:
        lib.err("rename", "must be a non-empty title")
    return title


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


def build_transition(payload: JSONDict, skill: str, title: str) -> Transition:
    """Return the transition this call types, per the skill's own rules."""
    if skill == "autoname":
        return Transition("rename", [f"/rename {title}"], typed=False)
    if skill == "handoff":
        return _build_handoff_transition(payload, title)
    return _build_precompact_transition(payload)


class Transition(NamedTuple):
    """The sentinel's kind, its command lines, and whether it is typed."""

    kind: str
    cmds: list[str]
    typed: bool


def _build_handoff_transition(payload: JSONDict, title: str) -> Transition:
    if "compact" in payload:
        lib.err("compact", 'forbidden when skill is "handoff"')
    if "clear" not in payload:
        lib.err("clear", 'required when skill is "handoff"')
    if not isinstance(payload["clear"], bool):
        lib.err("clear", "must be true or false")
    if payload["clear"] is True:
        return Transition("clear", [f"/rename {title}", "/clear"], typed=True)
    return Transition("rename", [f"/rename {title}"], typed=False)


def _build_precompact_transition(payload: JSONDict) -> Transition:
    if "clear" in payload:
        lib.err("clear", 'forbidden when skill is "precompact"')
    if "compact" not in payload:
        lib.err("compact", 'required when skill is "precompact"')
    compact_val = payload["compact"]
    ctype = _json_type(compact_val)
    if ctype == "boolean":
        if compact_val is True:
            return Transition("compact", ["/compact"], typed=True)
        return Transition("compact", [], typed=False)
    if ctype == "string":
        require_one_line("compact", compact_val)
        return Transition("compact", [f"/compact {compact_val}"], typed=True)
    lib.err("compact", "must be true, false, or a focus directive string")
    raise AssertionError("unreachable")  # lib.err() always raises


def validate_continuation(payload: JSONDict, skill: str, *, typed: bool) -> str:
    """Return the continuation prompt, or "" when there is none."""
    if skill == "autoname":
        return ""
    if "continue" not in payload:
        lib.err("continue", "required, either null or one line of prose")
    if payload["continue"] is None:
        return ""
    if not isinstance(payload["continue"], str):
        lib.err("continue", "must be null or one line of prose")
    continuation = payload["continue"]
    require_one_line("continue", continuation)
    if continuation.startswith("/"):
        lib.err("continue", "must not begin with `/`")
    if not typed:
        lib.err("continue", "must be null when the transition is not driven")
    return continuation


def require_one_line(field: str, value: str) -> None:
    """Error unless value is non-blank and holds no line break.

    A line break is any character `str.splitlines` breaks on (LF, CR, VT, FF,
    FS, GS, RS, NEL, LS, PS), not LF alone: each line of the sentinel is
    submitted with one Enter, and a CR or a Unicode separator is a break to the
    TUI or to a line-wise read of the file as much as LF is.
    """
    if not re.sub(r"\s", "", value):
        lib.err(field, "must not be empty or whitespace only")
    if value.splitlines() != [value]:
        lib.err(
            field,
            "must be a single line, with no line break (LF, CR, VT, FF, FS, GS, "
            "RS, NEL, LS or PS)",
        )


def require_session_id(field: str, reason: str) -> str:
    """Return CLAUDE_CODE_SESSION_ID, or error naming field with reason."""
    session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not session_id:
        lib.err(field, f"CLAUDE_CODE_SESSION_ID is unset — {reason}")
    return session_id


def validate_task(payload: JSONDict, skill: str) -> tuple[str, str]:
    """("write", content) or ("clear", "").

    Required under handoff. Forbidden under precompact by key presence, whatever
    the value, and the absent key resolves to ("clear", ""): the removal runs
    through the same plan as an explicit clear.
    """
    if skill == "precompact":
        if "task" in payload:
            lib.err("task", 'forbidden when skill is "precompact"')
        return "clear", ""
    if "task" not in payload:
        lib.err("task", 'required, a content string or {"action": "clear"}')
    task = payload["task"]
    ttype = _json_type(task)
    if ttype == "string":
        validate_task_shape(cast("str", task))
        return "write", cast("str", task)
    if ttype == "object":
        if "action" not in task:
            lib.err("task.action", 'required, a content string or {"action": "clear"}')
        action = task["action"]
        if action == "clear":
            _reject_unknown_keys("task", task, "clear", ())
            return "clear", ""
        lib.err("task.action", f'must be "clear", got {_got(action)}')
    lib.err(
        "task",
        f'must be a content string or {{"action": "clear"}}, got {ttype}',
    )
    raise AssertionError("unreachable")  # lib.err() always raises


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
    lib.err(field, f'unknown key "{extra[0]}", {{"action": "{action}"}} {takes}')


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
    lib.err(
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
        lib.err("todo", "required, a content string or an object naming an action")
    todo = payload["todo"]
    ttype = _json_type(todo)
    if ttype == "string":
        return "write", cast("str", todo), "", ""
    if ttype == "object":
        if "action" not in todo:
            lib.err(
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
        lib.err(
            "todo.action",
            f'must be "clear", "keep" or "edit", got {_got(action)}',
        )
    lib.err(
        "todo",
        f"must be a content string or an object naming an action, got {ttype}",
    )
    raise AssertionError("unreachable")  # lib.err() always raises


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
            lib.err(f"todo.{key}", 'required for {"action": "edit"}')
        ktype = _json_type(todo[key])
        if ktype != "string":
            lib.err(f"todo.{key}", f"must be a string, got {ktype}")
        strings.append(cast("str", todo[key]))
    return strings[0], strings[1]
