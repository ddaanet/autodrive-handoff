# Item 2.1 / slice 1 — GREEN report

Commit: `a9a2b6ed79989c9488752bc779532028fa01d79f` — "✨ Item 2.1/1 — typed
with-commit transition is held"

## Implementation

`scripts/checkpoint.py:hold_decision` widened from `(transition, *, memory)`
to `(transition, *, memory: bool, commit: bool)`, predicate widened from
`bool(transition.cmds) and memory` to
`(bool(transition.cmds) and memory) or (transition.typed and commit)` — the
exact interface and rule the dispatch specified, not `K and C` or `C` alone.
Docstring restates the rule and the outline's rationale for scoping the
second disjunct to `typed`: an untyped handoff's only keystroke is `/rename`,
whose misfire costs nothing, so holding that case too would add an approval
call to the common "handoff and commit" invocation for no protected state.

`main()`'s call site now passes `commit=commit_mode == "with-commit"`
alongside the existing `memory=bool(memory.text)`. No other in-repo caller of
`hold_decision` exists (`grep -rn hold_decision --include=*.py .` finds only
the definition and this one call site), so no compat shim was needed.

## Test

`tests/test_checkpoint.py::test_typed_with_commit_clean_memory_is_held` —
already written by RED and fixed by test-review (the
`lib.memory_directive(...).text == ""` premise-pin) — required no further
changes. Both parametrizations (`handoff_payload-clear`,
`precompact_payload-compact`) now pass.

## Verification

- `pytest tests/test_checkpoint.py -k test_typed_with_commit_clean_memory_is_held -v`
  → 2 passed.
- `pytest tests/test_checkpoint.py -q` → 162 passed (0 failed) — no
  pre-existing row broke; none needed fixing.
- Mutation check (per the dispatch and the RED report's plan): temporarily
  reverted the predicate to `bool(transition.cmds) and memory` (dropping the
  second disjunct) and re-ran the full file → `2 failed, 160 passed`, the
  same two parametrizations of this row and nothing else. Confirms the row is
  load-bearing for the widened disjunct alone. Restored the real predicate
  immediately after (verified by re-reading the file).
- `just precommit` → green in full: jq/shellcheck/ruff/ruff-format/
  docformatter/mypy/ty clean, `bats tests/*.bats` 166/166 ok, `pytest`
  252 passed, 11 deselected (the `live` marker). docformatter required one
  re-wrap of the new docstring to its 88-column rule, applied before commit.

## Scope

Slices 2.1/2–3 (the untyped-handoff and dirty-memory-precompact rows that
separate this rule from `K and C` / `C` alone) are untouched, per the
dispatch. Nothing outside `scripts/checkpoint.py` and
`tests/test_checkpoint.py` changed.
