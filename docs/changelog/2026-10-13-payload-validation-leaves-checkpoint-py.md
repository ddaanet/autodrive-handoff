# Payload validation leaves checkpoint.py (2026-10-13)

`scripts/checkpoint.py` was 629 lines after the plan layer moved to
`scripts/_checkpoint_plan.py`, still over the 400-line soft cap. The next seam
was the payload validation: `read_payload` through `_todo_edit_strings`, every
function that narrows one field of the JSON payload or exits through `lib.err`
naming it, plus `build_transition` and the `Transition` record it returns.

## What moved

The whole range moves to `scripts/_checkpoint_payload.py`, which
`checkpoint.py` imports as `validation` (not `payload`: `main` already has a
local of that name). The contract is the plan split's:

- No re-export and no compat alias. `checkpoint.py` reaches every moved name
  through the module, `validation.read_payload()`, `validation.Transition` in
  the signatures of `hold_decision` and `compose_sentinel`.
- Every caller patched directly. The only caller is `main`; no test imports a
  moved name, since `tests/test_checkpoint_*.py` drive `checkpoint.py` by
  subprocess, so no test changes.
- Entry points before definitions. The new module lists the validators in the
  order `main` calls them, each helper (`_json_type`, `Transition`,
  `require_one_line`, `_reject_unknown_keys`, `_got`, `validate_task_shape`,
  `_LIST_ITEM`, `TASK_BODY_LIMIT`, `_todo_edit_strings`) and the `JSONDict`
  alias after its first user.
- Errors go through `lib.err`, unchanged.

`validate_root` and `require_session_id` read the environment rather than the
payload. They moved with the range because they answer the same way, a value or
an error naming the field, and `checkpoint.py` keeps only the call order, the
sentinel and the directives.

## What it left

`checkpoint.py` is 241 lines. `_checkpoint_payload.py` is 419, itself just over
the cap; moving the two environment readers back would bring it under, and is
left as an open item rather than taken here, since the range was the one
named. Behaviour is unchanged: the same validators run in the same order with
the same messages.
