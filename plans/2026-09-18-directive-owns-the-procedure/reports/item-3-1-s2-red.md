# Item 3.1, slices 2–5 — RED

Mode: RED. Repo: /Users/david/code/handoff.

## SUT state

Unchanged. `scripts/_checkpoint_lib.py:closing_directive` and
`scripts/checkpoint.py:compose_directives`/`Ending` are already implemented
(slice 3.1/1's GREEN + code-review fixes, commits `111cc33` / `2cc0f29`). Per
the dispatch, slices 2–5 add tests only; the unmutated SUT is expected to pass
all of them, and the evidence is the four mutation checks below.

## Test changes (`tests/test_checkpoint.py`, no `scripts/` edits)

1. **Slice 2** — `test_closing_line_names_what_the_boundary_is_ready_for`,
   parametrized over `(skill, typed)` ∈ `{("handoff", False), ("precompact",
   False), ("handoff", True), ("precompact", True)}`. Each: `make_gitlore_repo`
   (clean memory), `without-commit`, `clear`/`compact` set to `typed`. Asserts
   stdout starts with `End on one line`; untyped cells assert containment of
   `Ready to /clear` / `Ready to /compact`; typed cells assert `armed` present
   and `Ready to` absent. New section `# Closing line` at the end of the file.
2. **Slice 3** — `test_held_sentinel_prints_no_closing_line`, parametrized
   `(payload_fn, typed_field)` ∈ `{(handoff_payload, "clear"),
   (precompact_payload, "compact")}` — phase 2 slice 1's exact fixture
   (`make_gitlore_repo`, clean memory, `with-commit`, typed field forced
   `True`, which the hold rule's second disjunct makes `held`). Asserts
   sentinel line 1 is `held sess-checkpoint`, then `"End on one line" not in
   result.stdout`.
3. **Slice 4** — `test_clause_refusal_is_followed_by_no_commit_or_arming`
   (pre-existing, unrenamed) gains `assert "End on one line" not in out`
   alongside its existing `boundary`/`commit_act`/`arming` absence checks.
4. **Slice 5** — `test_refusal_prints_alone_when_not_held`: `precompact_payload`
   (untyped, `compact: False` ⟹ `transition.cmds == []` ⟹ `K` false ⟹ armed
   regardless of memory), `make_gitlore_repo` + `dirty_memory` +
   `gitlore.memoryApprovalClauseFile` unset (refusal), `with-commit`. Asserts
   `refusal.text != ""` and `refusal.refusal` first (via
   `lib.memory_directive(str(repo), "with-commit")`), then sentinel line 1 is
   `armed`, then `result.stdout == refusal.text + "\n"` exactly.

## Run 1 — unmutated

```
pytest tests/test_checkpoint.py -q
```

```
171 passed in 29.20s
```

(164 baseline + 4 slice-2 rows + 2 slice-3 rows + 1 slice-5 row = 171; slice
4's row is a pre-existing test gaining one assertion, no new row.) Targeted
rerun of the four new/changed rows individually: `8 passed, 163 deselected`
(the parametrized slice-2 and slice-3 tests expand to 4 + 2, plus slice 4 and
slice 5, = 8).

All pass unmutated, as expected — this slice's evidence is the mutation
checks below, not the first run.

## Mutation checks

Each mutation applied to `scripts/checkpoint.py` in place, full
`tests/test_checkpoint.py` run, then reverted via `cp` from a saved original
before the next mutation. `git diff --stat scripts/checkpoint.py` was empty
before, between and after every mutation (confirmed after each restore).

### M2 — force `typed=False` into the closing line

```python
    else:
        parts.append(lib.closing_directive(skill, typed=False))  # was typed=ending.typed
```

Result: `2 failed, 169 passed`.

```
FAILED tests/test_checkpoint.py::test_closing_line_names_what_the_boundary_is_ready_for[handoff-True]
FAILED tests/test_checkpoint.py::test_closing_line_names_what_the_boundary_is_ready_for[precompact-True]
```

Exactly slice 2's two typed-cell rows red (`assert "armed" in out` fails
because the untyped `Ready to /compact` text is printed instead). The two
untyped-cell rows and every other test stay green.

### M3 — print the closing line regardless of `held`

```python
    parts.append(lib.closing_directive(skill, typed=ending.typed))
    if ending.held:
        parts.append(lib.arming_directive())
    # (dropped the `else:` — closing line now appended unconditionally)
```

Result: `2 failed, 169 passed`.

```
FAILED tests/test_checkpoint.py::test_held_sentinel_prints_no_closing_line[handoff_payload-clear]
FAILED tests/test_checkpoint.py::test_held_sentinel_prints_no_closing_line[precompact_payload-compact]
```

Exactly slice 3's row (both parametrizations) reds — stdout now contains
`End on one line: \`Compaction armed — it runs when this turn ends.\`` ahead
of the arming instruction. `test_arming_instruction_follows_every_other_part`
and `test_typed_with_commit_clean_memory_is_held` stay green: neither asserts
the closing line's absence, and the arming instruction is still last.

### M4/M5 — refusal path also appends the closing line

Dispatch describes these as one code change inspected from two angles (slice
4's added assertion, and slice 5's own row), so both are reported from the
single mutation:

```python
    if memory.refusal:
        return [memory.text, lib.closing_directive(skill, typed=ending.typed)]
```

Result: `2 failed, 169 passed`.

```
FAILED tests/test_checkpoint.py::test_clause_refusal_is_followed_by_no_commit_or_arming
FAILED tests/test_checkpoint.py::test_refusal_prints_alone_when_not_held
```

**Slice 4's row does red** — the dispatch flagged this as uncertain ("it may
not if the sentinel is held"), but the refusal branch returns before
`ending.held` is ever consulted, so the mutation appends the closing line
unconditionally whenever `memory.refusal` is true, independent of hold state.
Slice 4's fixture is held and still shows the closing line appended, so its
new `"End on one line" not in out` assertion catches it. Slice 5's row reds on
the exact-equality assertion (`refusal.text + "\n"` no longer equals stdout,
which now also carries the `Ready to /compact` closing line). No other test
is affected by this mutation — every other refusal-related row
(`test_clause_file_unset_names_key_and_restart`,
`test_clause_file_missing_same_key_and_restart_report`,
`test_unset_and_missing_clause_reports_are_the_same`) asserts substrings
present/absent that this mutation does not disturb.

## Scope check

```
git status --porcelain scripts/ tests/
 M tests/test_checkpoint.py
git diff --stat scripts/
(empty)
git diff --stat tests/
 tests/test_checkpoint.py | 76 ++++++++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 76 insertions(+)
```

No commit made. `scripts/` is byte-identical to its pre-mutation state after
every restore (verified via `git diff` after each of the three mutation
runs).
