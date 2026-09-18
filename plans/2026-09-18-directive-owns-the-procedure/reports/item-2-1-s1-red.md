# Item 2.1 / slice 1 — RED report

Test added: `test_typed_with_commit_clean_memory_is_held` in
`tests/test_checkpoint.py`, in a new `# Hold rule` section between `# Arming`
and `# Composition` (before `test_handoff_composition_carries_todo_boundary_not_sdd_nudge`).

Parametrized over `(payload_fn, typed_field)`: `(handoff_payload, "clear")`,
`(precompact_payload, "compact")`. Each: `make_gitlore_repo` (clean memory, no
`dirty_memory()` call), `commit_act = lib.commit_directive()` and
`arming = lib.arming_directive()` asserted non-empty, payload built via
`payload_fn("with-commit")` with the typed field forced `True`, checkpoint run,
then: return code 0, sentinel line 1 is `held sess-checkpoint`, and
`out.index(commit_act) < out.index(arming)`.

No stub needed — `hold_decision`, `commit_directive`, `arming_directive` are
all already implemented (post-phase-1 state). The test drives the existing
`hold_decision(transition, *, memory)` two-argument rule, which does not yet
have the `commit` parameter/second disjunct from Item 2.1.

## Command

```
pytest tests/test_checkpoint.py -k test_typed_with_commit_clean_memory_is_held -v
```

## Per-test output

Both parametrizations fail on the same assertion, for the intended reason —
the current rule (`bool(transition.cmds) and memory`) evaluates to `False`
under clean memory regardless of `commit`, so the sentinel is `armed` rather
than `held`:

```
FAILED tests/test_checkpoint.py::test_typed_with_commit_clean_memory_is_held[handoff_payload-clear]
AssertionError: assert 'armed' == 'held sess-checkpoint'

FAILED tests/test_checkpoint.py::test_typed_with_commit_clean_memory_is_held[precompact_payload-compact]
AssertionError: assert 'armed' == 'held sess-checkpoint'
```

Both fail on `assert first_line == "held sess-checkpoint"` — a genuine
assertion failure, not an ImportError/AttributeError — confirming the test
exercises the not-yet-widened predicate rather than a missing symbol.

## Full-file run

```
pytest tests/test_checkpoint.py -q
```

Result: `2 failed, 160 passed` — the two new parametrized rows are the only
failures; every pre-existing row (including the phase-1 commit-act, ordering,
arming and clause-refusal rows this slice sits beside) stays green.

## Scope note

Slices 2.1/2 and 2.1/3, and the `hold_decision` widening itself (adding the
`commit` parameter and the `(transition.typed and commit)` disjunct, plus the
`main()` call-site argument), are out of scope for this slice per the
dispatch — left untouched.
