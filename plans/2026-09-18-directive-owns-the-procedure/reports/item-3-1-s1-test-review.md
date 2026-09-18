# Item 3.1, slice 1 — test review

Verdict: **red is genuine; two fixes applied.** Still red after the fixes. Nothing committed.

## 1. Mechanical

Ran `pytest tests/test_checkpoint.py -q` after the fixes: `4 failed, 160 passed`. All four
boundary rows FAIL on an assertion (`tests/test_checkpoint.py:2075`, the helper's
`assert closing != ""`). None ERROR and none PASS. The two R11 rows
(`test_restart_never_holds_even_with_dirty_memory`,
`test_autoname_against_dirty_memory_no_directive_at_all`) still pass with `stdout == ""`.

## 2. Wrong-reason hunt

- **`(skill, typed)` per row.** Correct. `handoff_payload` carries `clear: False`,
  `continue: None`, which makes it untyped. `precompact_payload` carries `compact: False`,
  `continue: None`, also untyped. Three rows go through `handoff_payload`, and
  `test_flat_path_ledger_alone_precompact_…` goes through `precompact_payload`. Each row's
  helper call matches its payload.
- **Armed, closing line the only part.** Confirmed from two sources. The first is
  `hold_decision`: all four rows are `without-commit`, so the second disjunct is false. They
  also have no dirty memory, so `memory_directive` returns `MemoryPart("", refusal=False)`
  and the first disjunct is false. The second source is these same fixtures, which passed
  `stdout == ""` before this slice. That shows `todo_boundary`/`sdd_directive` and the
  memory part are all empty here: the flat-path ledger never counts, and there is no todo
  file. So after GREEN the closing line is the only part.
- **Exact equality vs `print_output`.** Consistent. For a one-part list,
  `"\n\n".join([c]) + "\n"` is `c + "\n"`, and that holds whether or not `c` itself ends in
  `\n`. The helper compares against the same `lib.closing_directive` value the checkpoint
  prints, so any trailing newline in the lib string cancels out.
- **Discrimination.** The precompact row reds any GREEN that prints the handoff line for
  every skill, as long as the two cells' texts differ. These rows do not discriminate
  `typed`, because all four are untyped. Slice 2's content-per-cell row owns that axis, so
  nothing needs to change here.
- **Names misled. Fixed.** The four `…_silent` rows now assert a printed line, so I renamed
  them to `…_closing_only` and kept each stem so a search on the old name's prefix still
  finds them:
  - `test_not_gitlore_managed_closing_only`
  - `test_gitlore_clean_memory_closing_only`
  - `test_submodule_registered_not_materialized_closing_only`
  - `test_flat_path_ledger_alone_precompact_closing_only`

  `_closing_line_only` would have put one def over 88 columns (E501). The runbook and
  outline cite the old names. Those are write-time records, so I left them unedited.

## 3. Stub completeness — interface deviation

`ruff check` failed with **FBT001** on the verbatim interface
`closing_directive(skill: str, typed: bool)` and on the helper. It also raised FBT003 at all
four call sites. `del skill, typed` already covered ARG. The repo's precedent is
keyword-only bools: `hold_decision(transition, *, memory, commit)` and
`validate_continuation(payload, skill, *, typed)`. Applied:

```python
def closing_directive(skill: str, *, typed: bool) -> str:
def assert_stdout_is_closing(result, skill: str, *, typed: bool) -> None:
```

Call sites now pass `typed=False` and `typed=typed`. **The runbook's `Interfaces:` line for
Item 3.1 (`closing_directive(skill: str, typed: bool) -> str`) is out of date.** Slice 2's
and Item 3.2's dispatches should cite the keyword-only form. `ruff check scripts tests` and
`ruff format --check` now pass.

## Files touched

- `/Users/david/code/handoff/scripts/_checkpoint_lib.py`: `typed` is now keyword-only; the
  body is still inert.
- `/Users/david/code/handoff/tests/test_checkpoint.py`: `typed` is keyword-only in the
  helper, and the four rows are renamed.
