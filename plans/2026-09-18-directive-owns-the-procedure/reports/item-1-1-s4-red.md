# Item 1.1 — slice 4 RED report

Tests added to `tests/test_checkpoint.py`, in a new `# Arming` section
inserted between the `# Ordering` and `# Composition` sections (after
`test_precompact_parts_print_in_order`, before
`test_handoff_composition_carries_todo_boundary_not_sdd_nudge`).

No SUT files touched (`scripts/_checkpoint_lib.py`, `scripts/checkpoint.py`
unmodified).

## test_arming_instruction_follows_every_other_part

Fixture: `make_gitlore_repo` + `dirty_memory` + `add_sdd_ledger`,
`handoff_payload("without-commit")` with `clear` overridden to `True`
(typed clear).

Asserts (in order): `lib.todo_boundary(root)` and `lib.arming_directive()`
non-empty; sentinel line 1 is `held sess-checkpoint`; index of
`todo_boundary` < index of `arming_directive()` in stdout; stdout
(trailing newlines stripped) ends with `arming_directive()` (also
stripped); `"Once that is done"` absent from stdout.

Result: **FAILED** on a genuine assertion —

```
    todo_index = out.index(todo_boundary)
    arming_index = out.index(arming)
>   assert todo_index < arming_index
E   assert 1131 < 1065
```

The sentinel-state assertion (`held sess-checkpoint`) and the two
non-empty asserts passed first; the failure is on ordering, exactly as
anticipated in the dispatch — today `compose_sentinel` appends
`arming_directive()` onto the memory part, so it prints before the todo
boundary rather than after it. Never reached the `endswith`/`"Once that is
done"` assertions below the ordering check.

## test_arming_text_refers_to_everything_above

Asserts `lib.arming_directive()` is non-empty and contains both
`"everything above"` and `"handoff-approved"`.

Result: **FAILED** on a genuine assertion —

```
    assert arming
>   assert "everything above" in arming
E   AssertionError: assert 'everything above' in 'Once that is done, run `handoff-approved` (Bash, no arguments).\n'
```

`arming_directive()`'s current text contains `handoff-approved` but not
`"everything above"` — matches expectation (today's wording is "Once that
is done", unreworded).

## Full-file run

```
pytest tests/test_checkpoint.py
```

157 passed, 2 failed — the two new tests above. No other row regressed.
