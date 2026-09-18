# Phase 2 (Hold rule) — checkpoint review

Scope: `git diff ee48524..HEAD -- scripts bin tests`, covering
`scripts/checkpoint.py`, `scripts/_lib.sh` (comment), `bin/handoff-approved`
(comment) and `tests/test_checkpoint.py`. Verdict: **R6 holds and the matrix is
complete. No code defects. One runbook claim was corrected in place.**

## R6

`hold_decision` returns `(bool(transition.cmds) and memory) or
(transition.typed and commit)`. The call site passes
`commit=commit_mode == "with-commit"`. `validate_commit_mode` returns `""` for
`autoname` and `restart`, so neither can hold through the second disjunct. The
docstring states both disjuncts and says why the second is scoped to `typed`.

## Hold matrix

| Cell | Expected | Row |
|---|---|---|
| typed + C + clean, handoff | held | `test_typed_with_commit_clean_memory_is_held[handoff…]` |
| typed + C + clean, precompact | held | `…[precompact…]` |
| untyped handoff + C + clean | armed | `test_untyped_handoff_with_commit_clean_memory_is_armed` (also `test_rename_only_manifest_present_empty_sentinel_written`) |
| FR-G marker + C (dirty memory) | armed | `test_sentinel_typing_nothing_arms_even_with_memory_gate_pending[with-commit]` |
| typed + M | held | `test_typed_transition_with_memory_gate_pending_held` (unchanged) |
| untyped + M | held | `test_untyped_handoff_still_types_rename_so_it_holds_too` (unchanged) |
| typed + ¬M + ¬C | armed | `test_typed_transition_no_memory_gate_armed_no_arming_instruction` (unchanged) |
| FR-G + M + ¬C | armed | `…typing_nothing…[without-commit]` |

The reports' mutation evidence maps each disjunct to a row:

- Dropping the second disjunct reds slice 1 alone.
- `K and C` reds slice 2 and the rename-only row.
- `C` alone also reds slice 3 `[with-commit]`.

I also checked the call-site mutants by reasoning about which rows they would
red:

- `commit=True` would hold the typed `without-commit` clean row, so that row
  reds.
- `commit=False` reds slice 1.

## "This row alone" for slice 2

The runbook's claim is wrong. The `K and C` mutant also reds the older
rename-only row, which pins the same cell through its exact sentinel bytes.
The coverage consequence is harmless: that row makes the cell doubly guarded.
But `plans/` convention requires a wrong claim to be corrected in place, so I
added a `> **Corrected at review, 2026-09-18.**` blockquote under slice 2 in
`runbook.md`. It quotes the claim, cites the s2 reports' evidence, and says
what still stands. Slice 2 is worth keeping. It is the only row that names the
outline's decided cell, and the only one that asserts both stdout facts in it:
commit act present, arming absent.

## Stale hold-condition wording

I grepped `scripts/`, `bin/` and `tests/` for the old condition. The
`hold_decision` docstring, the `_lib.sh` sentinel grammar and the
`bin/handoff-approved` header were already updated by the s1 code review. The
remaining uses of "approval" (in `_lib.sh` around line 284, the owner check in
`handoff-approved`, and `report-watcher-failure.sh`) explain ownership and the
sweep exemption. Both still hold for a commit hold, so none of them is false.
`compose_directives`' docstring says arming is "present only when held", which
is condition-agnostic and correct. No edits were needed. `CLAUDE.md`'s
`compose_sentinel` paragraph still states the old rule. That paragraph is out
of scope and belongs to Phase 5, as the outline says.

## Held without memory: stdout coherence

Observed output for typed + `with-commit` + clean memory, on both skills:

```
Once everything above is done, make the commit the request called for.


Once everything above is done, run `handoff-approved` (Bash, no arguments).
```

The sequence is coherent. The arming line's "everything above" includes the
commit act, so a fresh agent commits first and releases second. A commit that
fails is not "done", so the release is withheld, which is exactly the state the
second disjunct protects. Two observations, both outside Phase 2 and not fixed
here:

- When no memory or todo part precedes it, the commit act's own "Once
  everything above is done" has no printed antecedent. It reads as "the
  skill's prior steps", which is harmless. Worth a look when Phase 3 revisits
  the wording.
- Each part already ends in `\n` (`_printf_lines`), and `print_output` joins
  the parts with `\n\n`. That gives two blank lines between parts and a
  trailing blank line. The runbook says this output is byte-identical to the
  pre-phase-1 output. It is Phase 1's `print_output` shape, and Phase 3 owns
  the exact-stdout helper, so it will surface there if it matters.

## Gate

`just precommit` passed: jq, shellcheck -x, ruff, docformatter, mypy, ty, bats,
and pytest (`254 passed, 11 deselected`).

## Changes made (uncommitted)

- `plans/2026-09-18-directive-owns-the-procedure/runbook.md`: added a
  Corrected-at-review blockquote under Item 2.1 slice 2.
- This report.

UNFIXABLE: none.
