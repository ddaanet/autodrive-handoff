# Item 1.1, slice 2/2 — RED report

Mode: RED. k>1: no touch to `scripts/*` beyond a restored mutation probe (see
below). Tests added to `tests/test_checkpoint.py` only.

## Tests added

New `# Ordering` section in `tests/test_checkpoint.py`, between `# Commit act`
and `# Composition`:

- `test_handoff_parts_print_in_order` — `make_gitlore_repo` + `dirty_memory` +
  `add_sdd_ledger`, `handoff_payload("with-commit")` (untyped: `clear: False`,
  `continue: None`). Asserts `lib.todo_boundary(str(repo))` and
  `lib.commit_directive()` are both non-empty, then
  `memory_index < todo_index < commit_index` over `result.stdout`, where
  `memory_index` is the index of the literal `"gitlore memory has uncommitted
  changes"`.
- `test_precompact_parts_print_in_order` — same fixture and shape, with
  `lib.sdd_directive(str(repo))` in the middle position and
  `precompact_payload("with-commit")`.

## Deviation encountered (per dispatch instructions)

Both tests **pass against the unmutated SUT** — slice 1.1/1's GREEN
(`411f2c7`) already prints parts in memory → second → commit order. Per the
dispatch's known-deviation instructions, did not bend the tests; instead
proved each would catch a misordering by mutation.

### Run 1 — unmutated

```
pytest tests/test_checkpoint.py -k "parts_print_in_order" -v
tests/test_checkpoint.py::test_handoff_parts_print_in_order PASSED       [ 50%]
tests/test_checkpoint.py::test_precompact_parts_print_in_order PASSED    [100%]
2 passed, 154 deselected in 0.64s
```

### Mutation

`scripts/checkpoint.py`, `compose_directives`'s return statement — swapped
`second` and `commit` (the two parts after memory) so `main`'s
`memory, second, commit = compose_directives(...)` unpacking crosses them and
`print_output` prints commit before the todo-boundary/SDD-nudge part:

```diff
-    return memory, second, commit
+    return memory, commit, second
```

### Run 2 — mutated

```
pytest tests/test_checkpoint.py -k "parts_print_in_order" -v
tests/test_checkpoint.py::test_handoff_parts_print_in_order FAILED       [ 50%]
tests/test_checkpoint.py::test_precompact_parts_print_in_order FAILED    [100%]
```

`test_handoff_parts_print_in_order`:
```
>       assert memory_index < todo_index < commit_index
E       assert 1048 < 1002
tests/test_checkpoint.py:2259: AssertionError
```
(fails on the second inequality, `todo_index < commit_index` — commit now
prints ahead of the todo boundary)

`test_precompact_parts_print_in_order`:
```
>       assert memory_index < sdd_index < commit_index
E       assert 982 < 936
tests/test_checkpoint.py:2276: AssertionError
```
(same shape — commit now prints ahead of the SDD nudge)

Both red on the ordering assertion, neither on the preceding non-empty
asserts — confirms each test discriminates on the print order, not on
whether the parts exist.

### Restore

Reverted the swap exactly (`return memory, commit, second` →
`return memory, second, commit`). `git diff scripts/` is empty.

### Run 3 — unmutated, post-restore

```
pytest tests/test_checkpoint.py -k "parts_print_in_order" -v
2 passed, 154 deselected in 0.35s
```

## Full-file run: `pytest tests/test_checkpoint.py -q`

`156 passed in 21.53s` — the two new tests plus all 154 pre-existing rows
(includes slice 1's 5 commit-act tests), no regressions.

## Scope confirmation

`git status --short` shows only `M tests/test_checkpoint.py`. No changes to
`scripts/checkpoint.py`, `scripts/_checkpoint_lib.py`, `bin/handoff-approved`,
`tests/checkpoint.bats`, or any skill body. Nothing committed this run.
