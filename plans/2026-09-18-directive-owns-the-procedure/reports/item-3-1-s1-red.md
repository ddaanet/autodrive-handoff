# Item 3.1, slice 1 — RED

Mode: RED. Repo: /Users/david/code/handoff.

## SUT stub

`scripts/_checkpoint_lib.py`: added `closing_directive(skill: str, typed: bool)
-> str`, placed after `arming_directive()` (its neighbor in print order —
memory, boundary/nudge, commit, arming, closing) and before `ledger_path()`.
Inert: `del skill, typed; return ""`. Nothing else in `scripts/` touched.

## Test changes

`tests/test_checkpoint.py`:

- Added `assert_stdout_is_closing(result, skill, typed)` right before its
  first use (above `test_not_gitlore_managed_silent`, after
  `precompact_payload`): asserts `lib.closing_directive(skill, typed) != ""`,
  then `result.stdout == closing + "\n"`.
- Moved the four boundary rows from `stdout == ""` to the helper:
  - `test_not_gitlore_managed_silent` → `assert_stdout_is_closing(result, "handoff", False)`
  - `test_gitlore_clean_memory_silent` → `assert_stdout_is_closing(result, "handoff", False)`
  - `test_submodule_registered_not_materialized_silent` → `assert_stdout_is_closing(result, "handoff", False)`
  - `test_flat_path_ledger_alone_precompact_silent` → `assert_stdout_is_closing(result, "precompact", False)`
- Left the two non-boundary rows unchanged (still `stdout == ""`):
  `test_restart_never_holds_even_with_dirty_memory`,
  `test_autoname_against_dirty_memory_no_directive_at_all`.

## Run: `pytest tests/test_checkpoint.py -q`

```
FAILED tests/test_checkpoint.py::test_not_gitlore_managed_silent - AssertionError: assert '' != ''
FAILED tests/test_checkpoint.py::test_gitlore_clean_memory_silent - AssertionError: assert '' != ''
FAILED tests/test_checkpoint.py::test_submodule_registered_not_materialized_silent - AssertionError: assert '' != ''
FAILED tests/test_checkpoint.py::test_flat_path_ledger_alone_precompact_silent - AssertionError: assert '' != ''
4 failed, 160 passed in 18.58s
```

Each failure is the helper's own non-empty guard (`assert closing != ""`)
tripping on the stub's `""` — not a stdout-content mismatch, confirming the
row cannot pass against an unwritten `closing_directive`.

## Per-test detail

- `test_not_gitlore_managed_silent` — FAIL at
  `assert_stdout_is_closing`'s `assert closing != ""` (`AssertionError: assert
  '' != ''`).
- `test_gitlore_clean_memory_silent` — same failure, same line.
- `test_submodule_registered_not_materialized_silent` — same failure, same
  line.
- `test_flat_path_ledger_alone_precompact_silent` — same failure, same line.
- `test_restart_never_holds_even_with_dirty_memory` — PASS (unchanged,
  `stdout == ""`).
- `test_autoname_against_dirty_memory_no_directive_at_all` — PASS (unchanged,
  `stdout == ""`).
- Rest of `tests/test_checkpoint.py` (160 rows) — PASS, unaffected by the stub
  (every other call site either ignores `closing_directive` or doesn't reach
  it yet).

## Scope check

`git status --porcelain scripts/ tests/` shows only `scripts/_checkpoint_lib.py`
and `tests/test_checkpoint.py` modified. No commit made.
