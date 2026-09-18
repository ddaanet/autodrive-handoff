# Item 2.1 / slices 2 and 3 — RED report

Both slices' rows already pass against the unmutated SUT: Item 2.1/1 already
widened `hold_decision` to `(bool(transition.cmds) and memory) or
(transition.typed and commit)` in `scripts/checkpoint.py`. This RED's evidence
is the mutation checks, not a genuine assertion failure.

## Slice 2: `test_untyped_handoff_with_commit_clean_memory_is_armed`

Added in `tests/test_checkpoint.py`, immediately after slice 1's
`test_typed_with_commit_clean_memory_is_held` and before the `# Composition`
section header. Same fixture as slice 1 (clean memory via `make_gitlore_repo`
with no `dirty_memory()` call, `commit_act = lib.commit_directive()` asserted
non-empty), but `handoff_payload("with-commit")` unmodified — `clear` stays at
its default `False` (untyped). Asserts: return code 0, sentinel line 1 is
`armed`, `"handoff-approved"` absent from stdout, and `commit_act` present in
stdout.

## Slice 3: `test_sentinel_typing_nothing_arms_even_with_memory_gate_pending`

Existing test at (pre-edit) `tests/test_checkpoint.py:1820` — precompact,
`compact: False`, dirty memory — gained a
`@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])`
parameter, replacing the payload's hardcoded `"commit": "without-commit"`
with the parametrized value. Both parametrizations assert line 1 is `armed`.

## Command (unmutated SUT)

```
pytest tests/test_checkpoint.py -k "test_untyped_handoff_with_commit_clean_memory_is_armed or test_sentinel_typing_nothing_arms_even_with_memory_gate_pending" -v
```

```
tests/test_checkpoint.py::test_sentinel_typing_nothing_arms_even_with_memory_gate_pending[without-commit] PASSED
tests/test_checkpoint.py::test_sentinel_typing_nothing_arms_even_with_memory_gate_pending[with-commit] PASSED
tests/test_checkpoint.py::test_untyped_handoff_with_commit_clean_memory_is_armed PASSED
```

Full file: `pytest tests/test_checkpoint.py -q` → `164 passed`. No pre-existing
row broke.

## Mutation A — widen the second disjunct to `bool(transition.cmds) and commit`

```python
return (bool(transition.cmds) and memory) or (bool(transition.cmds) and commit)
```

`pytest tests/test_checkpoint.py -q` → `2 failed, 162 passed`:

```
FAILED tests/test_checkpoint.py::test_rename_only_manifest_present_empty_sentinel_written
FAILED tests/test_checkpoint.py::test_untyped_handoff_with_commit_clean_memory_is_armed
```

Slice 2's row reds as expected. A second, pre-existing row also reds:
`test_rename_only_manifest_present_empty_sentinel_written` (line 1310) —
untyped handoff, `with-commit`, plain (non-gitlore) repo, so `memory=False`.
Under the real predicate, `transition.cmds` is non-empty (`/rename` is always
typed) but `transition.typed` is `False`, so the second disjunct never fires
and the sentinel stays `armed`. Mutation A replaces `transition.typed` with
`bool(transition.cmds)` (true here too), so `commit=True` alone flips it to
`held` — the same defect class slice 2 targets, on a fixture slice 2's
dispatch did not anticipate. `test_sentinel_typing_nothing_arms_even_with_memory_gate_pending`
stays green under Mutation A on both parametrizations: that fixture's
`transition.cmds` is empty (untyped precompact types nothing), so
`bool(transition.cmds) and commit` is `False` regardless of `commit`.

Restored; re-ran full file → `164 passed`, confirming the revert.

## Mutation B — narrow the second disjunct to `commit` alone

```python
return (bool(transition.cmds) and memory) or commit
```

`pytest tests/test_checkpoint.py -q` → `3 failed, 161 passed`:

```
FAILED tests/test_checkpoint.py::test_rename_only_manifest_present_empty_sentinel_written
FAILED tests/test_checkpoint.py::test_sentinel_typing_nothing_arms_even_with_memory_gate_pending[with-commit]
FAILED tests/test_checkpoint.py::test_untyped_handoff_with_commit_clean_memory_is_armed
```

Slice 3's `with-commit` parametrization reds as expected (its `without-commit`
sibling stays green — `commit=False` there, so the mutated disjunct is still
`False`). Slice 2's row and the same pre-existing
`test_rename_only_manifest_present_empty_sentinel_written` row also red, for
the same reason as under Mutation A: both are untyped-transition,
`with-commit` fixtures the mutated predicate can no longer distinguish from a
typed one.

Restored; re-ran full file → `164 passed`, confirming the revert.

## Deviation from the dispatch's stated expectations

The dispatch's "expected: slice 2's row alone" (Mutation A) and "expected:
slice 3's with-commit parametrization among them" (Mutation B, which already
hedges with "among them") undercounted by one row each: pre-existing
`test_rename_only_manifest_present_empty_sentinel_written` reds under both
mutations, because it independently occupies the same cell slice 2 targets
(untyped transition, `with-commit`, `memory=False` there vs. clean-but-truthy
`memory` in slice 2's gitlore fixture — both leave the first disjunct `False`
and only `transition.typed` distinguishes the real predicate from either
mutation). This is additional evidence for the same rule, not a
contradiction; recorded here per the "report faithfully" convention rather
than silently matching the dispatch's wording.

## Verification that scripts/ is unmutated

```
git diff scripts/ | wc -l
```
→ `0`, after each mutation was restored. Final full-suite run:
`pytest tests/test_checkpoint.py -q` → `164 passed`.

## Scope

No `scripts/` changes committed (both mutations were temporary, restored
immediately after their run). Only `tests/test_checkpoint.py` changed:
slice 2's new test, and slice 3's parametrization of the existing test.
Nothing committed.
