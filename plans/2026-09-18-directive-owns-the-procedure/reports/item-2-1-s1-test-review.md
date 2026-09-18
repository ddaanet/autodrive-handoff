# Item 2.1 / slice 1 — test review

Row under review: `test_typed_with_commit_clean_memory_is_held`
(`tests/test_checkpoint.py`, new `# Hold rule` section). Verdict: **red for the
stated reason; one fix applied.**

## 1. Mechanical

`pytest tests/test_checkpoint.py -q` → `2 failed, 160 passed`. Both
parametrizations (`handoff_payload-clear`, `precompact_payload-compact`) FAIL
on `assert first_line == "held sess-checkpoint"` (`'armed'`), line 2376 after
the fix. No PASSED, no ERROR. The ruff check and the format check are both
clean.

## 2. Wrong-reason hunting

- **Is memory clean?** Yes. The row calls `make_gitlore_repo` and never calls
  `dirty_memory`. `make_gitlore_repo` commits `seed.md` in the submodule, so
  `git status --porcelain` there is empty. `test_gitlore_clean_memory_silent`
  already shows the same fixture yielding empty stdout. The row did not pin
  that premise itself, though. **Fix applied:** it now asserts
  `lib.memory_directive(str(repo), "with-commit").text == ""` before the
  run. The first disjunct (`K and M`) therefore cannot be what holds it, and a
  future fixture change that dirties memory fails there, loudly, rather than
  letting the row go green through the wrong disjunct. It is re-run and still
  red on the sentinel assertion.
- **Same fixture as `test_typed_transition_no_memory_gate_armed_no_arming_instruction`
  with `commit` flipped?** The fixture is the same: `make_gitlore_repo`, clean
  memory, `task_clear()`, `todo_keep()`. The payload is not a byte-for-byte
  copy, because the row goes through the shared `handoff_payload` /
  `precompact_payload` helpers and forces the typed field `True`. For the
  handoff case this gives `rename: "Session Title"` and `continue: None`, where
  the sibling has `"A Title"` and a prose continuation. None of those fields
  enters `hold_decision`, which reads `transition.cmds`, `transition.typed`,
  memory and commit. The helpers are what let the precompact parametrization
  exist, so I left this alone.
- **Ordering check.** It uses `str.index` for both strings, so a missing
  commit act or arming line raises `ValueError` rather than scoring `-1`. Both
  lib values are asserted non-empty first, per the runbook's standing rule, so
  an empty string cannot score index 0.
- **Wrong widenings.** `C` alone and `K and C` would both pass this row, which
  is expected. They are separated by the later slices:
  - Slice 2 (untyped handoff, `with-commit`, clean memory ⟹ `armed`) reds on
    both `K and C` and `C` alone, since an untyped handoff has `K` (the
    `/rename`) but not `T`.
  - Slice 3 (precompact `compact: false`, dirty memory, `with-commit` ⟹
    `armed`) reds on `C` alone, since that sentinel types nothing.
  - Among the widenings, only `(K and M) or (T and C)` is green on all three
    slices.
- **Mutation check.** The planned mutation is "drop the second disjunct ⟹ this
  row alone reds". The current SUT is exactly that mutant: it has the
  first disjunct only. Against it, the full-file run reds these two rows and
  nothing else. That is the mutation evidence for this row, observed before the
  implementation exists. The GREEN/code-review step should still re-run the
  mutation once the disjunct is added.

## Change made

`tests/test_checkpoint.py`, in the new row after `make_gitlore_repo`:

```python
assert lib.memory_directive(str(repo), "with-commit").text == ""
```

SUT untouched; nothing committed.
