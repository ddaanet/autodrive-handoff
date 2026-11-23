"""Payload validation for the Vibe checkpoint.

Vibe port of the Claude plugin's scripts/_checkpoint_payload.py, minus
`build_transition`, `Transition` and `validate_continuation` (the sentinel
and the driven continuation do not exist under Vibe) and with
`validate_boundary` in their place: it narrows the `clear` (handoff) and
`compact` (precompact) boolean, which decide the closing line's readiness
wording. The `compact` focus string does not port — Vibe's `/compact` takes
no argument, so the focus belongs in the todo.

Each validate_* function narrows one field of the JSON payload read on
stdin, or exits 2 through lib.err naming the offending field. validate_task
and validate_todo return the tagged union as plain tuples that
_checkpoint_plan.py resolves into file plans.

checkpoint.py imports this module as `validation`; nothing here writes a file.
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any, cast

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


# A parsed JSON object. The payload's shape is validated at runtime, not by
# static typing — every value is Any until a validate_* function narrows it.
JSONDict = dict[str, Any]


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

    Flat rather than skill-dependent: each of the skill-specific validators
    below already rejects a *known* key present under the wrong skill, with a
    message more specific than this one could give. What none of them is
    positioned to catch is a key outside the vocabulary altogether (a typo
    like "tasks", or the Claude payload's "continue", which this schema does
    not take), which collides with nothing skill-specific to name; this is
    the one place that closes that gap.
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
)


def validate_autoname_forbidden_fields(payload: JSONDict) -> None:
    """Error naming the field if any boundary-only field is present."""
    for forbidden in ("commit", "task", "todo", "clear", "compact"):
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


def validate_boundary(payload: JSONDict, skill: str) -> bool:
    """Return whether the transition runs at once (the closing line's wording).

    Under handoff the boolean is `clear`: true when the user asked for the
    reset to be carried out, false when they are preparing one they will run
    themselves. Under precompact it is `compact`; the focus string of the
    Claude schema does not port, because Vibe's /compact takes no argument —
    the error says so and points the focus at the todo. autoname returns
    False: its forbidden-fields check has already refused both flags.
    """
    if skill == "autoname":
        return False
    if skill == "handoff":
        if "compact" in payload:
            lib.err("compact", 'forbidden when skill is "handoff"')
        if "clear" not in payload:
            lib.err("clear", 'required when skill is "handoff"')
        return _require_bool("clear", payload["clear"])
    if "clear" in payload:
        lib.err("clear", 'forbidden when skill is "precompact"')
    if "compact" not in payload:
        lib.err("compact", 'required when skill is "precompact"')
    return _require_bool("compact", payload["compact"])


def _require_bool(field: str, value: object) -> bool:
    """Return value as a bool, or error naming field describing both flags."""
    if isinstance(value, bool):
        return value
    if _json_type(value) == "string":
        lib.err(
            field,
            "must be true or false; Vibe's /compact takes no argument, so a"
            " focus goes in the todo, not here",
        )
    lib.err(field, "must be true or false")
    raise AssertionError("unreachable")  # lib.err() always raises


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
    which exits 1 and names no field.
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
