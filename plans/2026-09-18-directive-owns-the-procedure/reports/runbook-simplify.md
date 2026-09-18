# Simplification Report

**Runbook:** plans/2026-09-18-directive-owns-the-procedure/runbook.md
**Date:** 2026-09-18

## Summary

- Items before: 9
- Items after: 9
- Lines before: 324
- Lines after: 323
- Consolidated: 1 slice-level pattern (2 slices → 1), 0 item-level merges

Item count is unchanged: every item-level merge candidate is either explicitly
forbidden by the task's hard limits (4.1/4.2, 5.1–5.3, cross-phase 1/2/3) or
blocked by a real dependency chain (1.1 → 2.1 → 3.1 → 3.2, each in its own
phase or gating the next item's fixture). The one consolidation applied is at
the slice level, within a single item, which is where this runbook's
redundancy actually lives — each item is already a "god item" of several
TDD slices rather than the runbook containing many small identical items.

## Consolidations Applied

### 1. Item 3.2 slices 1 and 2 merged into one parametrized slice

- **Type:** identical-pattern (slice-level, same item)
- **Slices merged:**
  - Old slice 1: `handoff-approved: rename prints the status fact then Ready
    to /clear` (single kind, rename).
  - Old slice 2: `handoff-approved: clear and compact print the driven line`
    (two kinds, `clear` and `compact`, already described as "one row per
    kind").
- **Result:** new slice 1, `handoff-approved: status fact then closing
  content, per kind` — one row per kind across all three kinds (`rename`,
  `clear`, `compact`), each with its own sentinel-shape fixture, asserting
  the status fact on line 1 for every row, plus `rename`'s `Ready to /clear`
  containment and `clear`/`compact`'s `End on one line` present / `Ready to`
  absent. Old slice 3 renumbered to slice 2; its one cross-reference in the
  item body ("slice 3 is what holds the two producers together") updated to
  "slice 2".
- **Rationale:** old slice 2 already bundled two kinds as "one row per kind"
  over varying fixture data with varying expected substrings — the same
  shape Item 3.1 slice 2 uses across all four `(skill, typed)` cells in one
  slice, including cells with different assertion polarity (contains vs.
  contains-neither). Old slice 1 tested the third kind (`rename`) with the
  same procedure (`run_approved` helper, status-fact-on-line-1 check) and no
  distinct behavior beyond a different closing-line substring. Extending the
  table to three rows is squarely the "N items each with fixture variation →
  one parametrized item" pattern, mirrors an existing precedent in the same
  runbook, and removes one TDD slice (one fewer red/green dispatch pair)
  without dropping any original assertion: every check from both old slices
  (line-1 status fact per kind, `Ready to /clear` for rename, `End on one
  line` present and `Ready to` absent for clear/compact) is preserved
  verbatim in the merged row table.

## Patterns Not Consolidated

- **Items 1.1, 2.1, 3.1, 3.2** (one per phase, or gated by a hard dependency
  chain) — not mergeable: phases 1–3 are separate red/green review
  boundaries per the task's hard limit, and 3.1 → 3.2 touch different files
  (`_checkpoint_lib.py`/`checkpoint.py` vs. `bin/handoff-approved`) with 3.2
  consuming 3.1's `closing_directive` contract, a genuine dependency.
- **Items 4.1 and 4.2** — excluded by the task's hard limit (different prose
  artifacts, one-artifact-one-item format rule).
- **Items 5.1–5.3** — excluded by the task's hard limit (each edits a
  different prose artifact: changelog, design doc, `CLAUDE.md`).
- **Item 2.1 slices 1 and 2** — not merged despite both varying only fixture
  data (`clear: true`/`with-commit` vs. `clear: false`/`with-commit` over the
  same base fixture): each is independently mutation-checked (the task's
  hard limit states "phase 2's two mutation checks each depend on their row
  standing alone"), and the runbook itself notes each mutation targets a
  different defect (drop the second disjunct vs. widen it to `K and C`).
  Merging them into one parametrized test would make a single mutation
  potentially red only one row of a shared test rather than isolate the
  defect per the report's own mutation-check design.
- **Item 1.1 slices 1–5 and Item 3.1 slices 1–5** — each slice adds a
  distinct behavior (external contract, ordering, memory-text content,
  arming placement, refusal-alone) per the format rule ("each later slice
  adds exactly one behaviour"); several are individually mutation-checked
  (slice 5 of 1.1; slices 3 and 5 of 3.1), so folding them together would
  blur which mutation reds which row.
- **The repeated "asserts `lib.X()` is non-empty" clauses across ~10 rows in
  Items 1.1, 2.1, and 3.1** — these look like a standing-preamble rule
  (lines 21–24) restated per row, but per the review report (Major Issue #3)
  the corrector added both the standing rule *and* an explicit per-row
  non-empty clause as a deliberate belt-and-suspenders fix for a found
  defect (vacuous `lib.*()` comparisons against a function returning `""`).
  The task's hard limit says to keep each clause or keep the standing rule
  that covers it, "never drop both" — since this was a reviewed, intentional
  double-statement of a correctness-critical guard rather than accidental
  duplication, removing the per-row clauses was judged too risky for the
  line count it would save (a handful of words per row) and was left alone.
- **Sequential additions to one function** — none found. No item adds
  several standalone elements to the same loop body, dict constructor, or
  module one-per-item; the closest shape (Item 1.1's `compose_directives`
  parts list) is built by one slice's worth of ordering tests already, not
  spread across several items.

## Requirements Mapping

No changes. All R1–R11 rows still map to the same items (R8 → Item 3.2,
unaffected by the slice renumbering within that item — the mapping table has
no slice-level granularity).
