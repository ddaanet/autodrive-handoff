# Item 3.1, slice 1 — GREEN

Mode: GREEN. Repo: /Users/david/code/handoff. Commit:
`111cc33973a2cbcb3105aa90b545f6ff843af762` — "✨ Item 3.1/1 — closing line
printed when not held".

## Implementation

`scripts/_checkpoint_lib.py`: `closing_directive(skill: str, *, typed: bool)
-> str` filled in (was the RED slice's inert stub). Never `""`; opens with
`End on one line`. Typed (driven): "End on one line: the transition is armed
and runs at the end of this turn." Untyped (prepared): "End on one line:
`Ready to /clear`." for `skill == "handoff"`, "End on one line: `Ready to
/compact`." for `skill == "precompact"`.

`scripts/checkpoint.py`: `compose_directives` appends
`lib.closing_directive(skill, typed=transition.typed)` as the last part when
`not held`, mirroring the existing `if held: parts.append(arming_directive())`
branch (now `else: parts.append(closing_directive(...))`). `main()`'s one
caller updated accordingly.

## Deviation from the dispatch's suggested interface

The dispatch suggested threading `typed` into `compose_directives` as a
keyword-only param (`*, held: bool, typed: bool`), i.e. 6 total parameters.
That trips `ruff` `PLR0913` (max 5). Fix: replaced the `held: bool` parameter
with `transition: Transition` (positional, no longer keyword-only) and
recompute `held` inside `compose_directives` via the existing `hold_decision`
formula (`hold_decision(transition, memory=bool(memory.text), commit=commit_mode
== "with-commit")`) — the same call `main()` already makes ahead of
`compose_sentinel`. This keeps `hold_decision` the single source of truth
for `held` (no risk of the two computations drifting) at the cost of calling
it twice per checkpoint run — cheap, pure, no side effects. `main()`'s call
site is now `compose_directives(skill, root, commit_mode, memory,
transition)`. `closing_directive`'s own interface is unchanged from the test
review's fix: `closing_directive(skill: str, *, typed: bool) -> str`.

## Four closing texts, verbatim

- `("handoff", typed=False)`: `` End on one line: `Ready to /clear`. ``
- `("precompact", typed=False)`: `` End on one line: `Ready to /compact`. ``
- `("handoff", typed=True)`: `End on one line: the transition is armed and
  runs at the end of this turn.`
- `("precompact", typed=True)`: `End on one line: the transition is armed and
  runs at the end of this turn.` (same text as handoff/typed — the outline's
  driven content is not skill-specific)

Each function return also carries a trailing `\n` from `_printf_lines`.

## Verification

- `pytest tests/test_checkpoint.py -q` — 164 passed (was 4 failed / 160
  passed at RED).
- `just precommit` — green in full: jq/shellcheck/ruff check/ruff
  format/docformatter/mypy/ty, `bats tests/hook-test.bats
  tests/checkpoint.bats` (166 ok), `pytest` (254 passed, 11 deselected).
- `git status --porcelain scripts tests` — clean after commit; only the
  pre-existing untracked sandbox/report files remain elsewhere in the tree.

## Scope

Touched only `scripts/_checkpoint_lib.py`, `scripts/checkpoint.py`,
`tests/test_checkpoint.py`, all inside slice 3.1/1's boundary. No skill,
docs, or `bin/handoff-approved` changes (Item 3.2, out of scope here). Slice
3.1/1's four boundary rows now go through `assert_stdout_is_closing`
(unchanged from RED); the two non-boundary rows
(`test_restart_never_holds_even_with_dirty_memory`,
`test_autoname_against_dirty_memory_no_directive_at_all`) still assert
`stdout == ""` (R11), untouched by this slice — `compose_directives` returns
`[]` before reaching `closing_directive` for `autoname`/`restart`, since the
skill gate (`if skill not in ("handoff", "precompact"): return []`) is
unchanged.
