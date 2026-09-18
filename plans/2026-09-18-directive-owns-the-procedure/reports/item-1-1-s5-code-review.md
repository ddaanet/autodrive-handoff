# Item 1.1 / slice 5 — code review

Scope: `scripts/_checkpoint_lib.py`, `scripts/checkpoint.py` as changed by
`78d5256`, plus the whole of Item 1.1's contract (last slice).

## Findings

1. **Fixed (minor, ordering rule)** — `class MemoryPart` sat above
   `memory_directive`, its only user in the module. The module has
   `from __future__ import annotations`, so the return annotation is lazy and
   the body constructs `MemoryPart` only at call time: no evaluation-order
   constraint applies, and the GREEN report says as much while placing it
   first anyway. Moved it to directly after `memory_directive`. No
   behaviour change.

No other findings.

## Checks against the Interface

- `MemoryPart(NamedTuple)` — `text: str`, `refusal: bool`: matches.
- `memory_directive(root: str, mode: str) -> MemoryPart`: matches. Return
  paths: no submodule, no `.git`, and clean status each return
  `("", refusal=False)`. `_resolve_approval_clause` returns `None` for both a
  missing key (returncode ≠ 0 or empty value) and a missing or unreadable file,
  and both go through the one `refusal=True` branch. The normal directive
  returns `refusal=False`. So `refusal` is true only on the clause-file
  refusal, which covers both of its causes.
- Callers: `checkpoint.py:main` is the only caller (grep across `scripts/`,
  `bin/`, `tests/`). The module's `_cli` touches only `is_empty_body`, not
  `memory_directive`. There is no compat shim, and no `str`-returning wrapper
  remains.
- `compose_directives(..., memory: lib.MemoryPart, *, held: bool) -> list[str]`:
  returns `[memory.text]` alone when `memory.refusal`, and `[]` for
  autoname/restart (since the memory default is empty and they have no
  commit mode and are never held).

## Item 1.1 contract, whole

- `main` calls `memory_directive` once, only for handoff/precompact.
- The order in `main` is: memory part → `hold_decision(transition,
  memory=bool(memory.text))` → `compose_sentinel(..., held=held)` →
  `compose_directives(..., memory, held=held)` → `print_output(parts)`.
- `hold_decision` is `bool(transition.cmds) and memory`, which is today's rule.
  A refusal counts as `M` because its text is non-empty. The new row confirms
  this: the sentinel is still `held sess-checkpoint`.
- `compose_sentinel` returns `None` and appends no text, because the arming
  text moved into `compose_directives`.
- `_read_back_drive` is byte-identical to its pre-Item version. It only moved
  below `compose_sentinel`, its user, per the ordering rule. `c723a32..HEAD`
  diff checked.
- `print_output(parts)` writes nothing for `[]`. Otherwise it writes the parts
  joined with `"\n\n"` plus one trailing newline, which is byte-identical to
  the old memory-only, second-only and both cases.

## Mutation check (the slice's own)

The GREEN report's mutation removed the whole short-circuit, which also
brought the todo boundary back. That is not the specified mutation. I ran the
specified one: I kept the refusal branch but appended parts 3–4 regardless of
`refusal`:

```python
if memory.refusal:
    tail = [lib.commit_directive()] if commit_mode == "with-commit" else []
    if held:
        tail.append(lib.arming_directive())
    return [memory.text, *tail]
```

`pytest tests/test_checkpoint.py -q -p no:randomly` gave 1 failed and 159
passed. The only failure was `test_clause_refusal_is_followed_by_no_commit_or_arming`,
at `tests/test_checkpoint.py:2345` (`assert commit_act not in out`). The boundary
assertion one line above still passed, so the red comes from part 3 itself.
I restored `checkpoint.py` from a copy, and `git status` shows it unmodified.

## Gate

`just precommit` after the fix passed: jq manifest/settings lint, shellcheck,
ruff, ruff-format, docformatter, mypy, ty, bats, and pytest (250 passed,
11 deselected `live`).

## Refactor flagged: none

Not committed. The working-tree change is `scripts/_checkpoint_lib.py` (the
`MemoryPart` move).
