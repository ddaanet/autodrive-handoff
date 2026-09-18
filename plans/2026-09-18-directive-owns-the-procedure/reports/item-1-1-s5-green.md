# Item 1.1 / slice 5 — GREEN report

Commit: `78d5256` — "✨ Item 1.1/5 — clause-file refusal prints alone"

## What changed

`scripts/_checkpoint_lib.py`:
- Added `class MemoryPart(NamedTuple)`: `text: str`, `refusal: bool`, placed
  immediately before `memory_directive` (its only user in this file; the
  module's `from __future__ import annotations` makes the forward reference
  in `memory_directive`'s own return annotation safe regardless of
  placement, so no evaluation-order exception was needed).
- `memory_directive` now returns `MemoryPart` on every path: `MemoryPart("",
  refusal=False)` on each of the three silent branches (no submodule, no
  `.git`, clean status), `MemoryPart(<refusal text>, refusal=True)` when the
  clause file cannot be read, `MemoryPart(common + specific, refusal=False)`
  on the normal directive.

`scripts/checkpoint.py`:
- `compose_directives`'s `memory` parameter is now typed `lib.MemoryPart`
  (was `str`). First line of the body: `if memory.refusal: return
  [memory.text]` — the refusal suppresses the todo boundary/SDD nudge, the
  commit act, and the arming instruction. The non-refusal path reads
  `memory.text` where it used to read the bare `memory` string; otherwise
  unchanged.
- `main`'s default is now `memory = lib.MemoryPart("", refusal=False)`
  (was `""`); `hold_decision(transition, memory=bool(memory.text))` reads
  the tuple's `text` field, preserving today's rule (a refusal still counts
  as `M`, since its `text` is non-empty).

All `MemoryPart(...)` constructions pass `refusal` as a keyword — ruff's
`FBT003` (boolean positional value) flagged the first pass with 6
violations; fixed by keyword-ifying every call site, matching the existing
style of `Transition(..., typed=...)`.

No other caller of `memory_directive` exists in `scripts/`, `tests/`, or
`bin/` (grepped before editing) — `checkpoint.py:main` is its sole caller,
per the runbook.

## Verification

- `pytest tests/test_checkpoint.py -q` — 160 passed (the slice's RED test,
  `test_clause_refusal_is_followed_by_no_commit_or_arming`, now passes;
  every prior-slice test, including `test_arming_instruction_follows_every_other_part`
  and `test_with_commit_memory_text_drops_nothing_further`, stays green).
- Mutation check (slice's own, run here since the dispatch deferred it to
  GREEN/code-review): reverted `compose_directives`'s refusal short-circuit
  (`if memory.refusal: return [memory.text]`) back to falling through to the
  normal composition. Re-ran the full file: exactly one test failed —
  `test_clause_refusal_is_followed_by_no_commit_or_arming`, on `assert
  boundary not in out` (the todo-boundary text now appears after the
  refusal, as the mutation predicts) — all 159 others stayed green. Restored
  the guard; confirmed 160/160 green again.
- `just precommit` — jq/shellcheck/ruff/ruff-format/docformatter/mypy/ty all
  green (docformatter required an in-place rewrap of `MemoryPart`'s
  docstring, applied), `bats tests/*.bats` (166 rows) and `pytest` (250
  passed, 11 deselected `live`-marker rows) both green.

## Notes

- Left `plans/2026-09-18-directive-owns-the-procedure/reports/item-1-1-s5-red.md`
  and `item-1-1-s5-test-review.md` uncommitted, per the dispatch.
- No skill/docs/CLAUDE.md files touched — out of scope for this slice.
