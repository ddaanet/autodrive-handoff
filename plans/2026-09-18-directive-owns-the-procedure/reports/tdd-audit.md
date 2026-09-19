# TDD Process Review: 2026-09-18-directive-owns-the-procedure

**Date:** 2026-09-19 13:51 CEST
**Runbook:** plans/2026-09-18-directive-owns-the-procedure/runbook.md
**Commits analyzed:** 581c99f..7389e56 (32 commits; Phases 1–3 are `tdd`)
**Sources used:** slice reports under `reports/`, `phase-{1,2,3}-corrector.md`,
runbook git history, `git show`/`git diff` on every commit a report names. No
report was missing; the transcript fallback was not needed.

## Executive Summary

Phases 1–3 show disciplined per-slice TDD throughout: every full slice has a
genuine RED (assertion failure, never an error/collection failure), a
test-review that hunts wrong-reason passes and frequently strengthens the
row, one GREEN commit carrying tests and implementation together, and a
code-review commit when — and only when — a fix was found. The three
declared batched slices (1.1/2, 2.1/2–3, 3.1/2–5, 3.2/2) are exactly what the
task's deviation note describes: mutation evidence in place of a RED failure,
because the behaviour was already delivered, and each is unusually rigorous
about proving the mutation maps to the claimed row and nothing else. The
Phase 3 anchor fix (`7389e56`) matches deviation #2's description precisely.
No test-id drops, no multi-slice commits, no unrecorded list revisions, and
no regressions were found. The only mechanical finding worth a recommendation
is that two "batched" RED reports (`item-2-1-s2-red.md`, `item-3-1-s2-red.md`)
corrected the runbook's own stated mutation predictions — a discipline win,
but one that shows the runbook's "this row alone reds" claims should be
written more conservatively in future plans.

## Per-Slice Compliance

| Item/slice | RED evidence | Test review | One slice commit | Tests unmodified | Issues |
|---|---|---|---|---|---|
| 1.1/1 | genuine, 5/5 fail on `assert commit_act` | pass, 2 fixes (case-fold assertion, ruff I001) | `411f2c7` GREEN + `7ebfdc7` review-fix | yes | none |
| 1.1/2 (batched) | mutation evidence only (4 permutations of `compose_directives`'s return tuple) | pass, deviation accepted with a corroborating table | `6f8cdbf` orchestrator ✅ (tests only) | yes | none |
| 1.1/3 | genuine, fails on the "nothing further" absence assertion | pass, no changes | `0a4c0c9` GREEN (no review-fix commit — none needed) | yes | none |
| 1.1/4 | genuine, both rows fail on assertions | pass, 1 fix (uniqueness guard `count(arming)==1`) | `31166d8` GREEN + `71f5a51` review-fix | yes | none |
| 1.1/5 | genuine, fails on `commit_act not in out` | pass, no test changes; runs the mutation check itself since the dispatch deferred it | `78d5256` GREEN + `bd7ac62` review-fix | yes | none |
| 2.1/1 | genuine, both parametrizations fail `armed == held...` | pass, 1 fix (pin clean-memory premise) | `a9a2b6e` GREEN + `bff44f3` review-fix (comments) | yes | none |
| 2.1/2–3 (batched) | mutation evidence (2 mutations, A and B) — corrects the runbook's "this row alone" claim | pass, adds 2 more mutations (C, D) confirming the finding | `e3708e6` orchestrator ✅ (tests only) | yes | see List Revisions |
| 3.1/1 | genuine, 4/4 fail on the helper's non-empty guard | pass, 2 fixes (keyword-only `typed`, renamed 4 tests) | `111cc33` GREEN + `2cc0f29` review-fix | yes, renames disclosed | see List Revisions |
| 3.1/2–5 (batched) | mutation evidence (M2, M3, M4/5 — 3 mutations covering 4 slices) | pass, 1 fix to slice 2 (armed + exact-stdout assertions), corrects a dispatch uncertainty | `a428abc` orchestrator ✅ (tests only) | yes | none |
| 3.2/1 | genuine, rows 13–15 fail on content assertion | pass, 2 fixes (blank-line separator, kind-word assertions) | `fcc6d00` GREEN + `e9e1112` review-fix | yes | none |
| 3.2/2 (batched) | mutation evidence (2 mutations, one per producer) | pass, 1 correction to the RED report's own trailing-newline claim | `a8abf8b` orchestrator ✅ (tests only) | yes | in-report correction, see below |

## Violations

None found. Every GREEN report names exactly one commit; every such commit's
diff (`git show <hash> --stat`) contains only that slice's test rows plus
implementation, confirmed against the test-review's id list for slices 1.1/1,
1.1/4, 1.1/5, 2.1/1, 3.1/1 and 3.2/1's bats rows. Every "Item N.M/k"-marked
commit is accounted for by a report: GREEN commits by the green report,
review-fix commits (`7ebfdc7`, `71f5a51`, `bd7ac62`, `bff44f3`, `2cc0f29`,
`e9e1112`) by the matching code-review report's "Fixes applied" section, and
the phase-level fix commits (`ff79945`, `d046b9c`, `7389e56`) by the
corrector/anchor-fix narrative. No commit's report or message indicates a red
suite at any point; every green/code-review/corrector report ends with `just
precommit` green and a full-suite pytest/bats count.

## List Revisions

- **Item 2.1 slice 2** — runbook blockquote "Corrected at review, 2026-09-18"
  under the slice (`runbook.md:156-164`), added by `phase-2-corrector.md`
  (commit `2073a37`). Traces to `item-2-1-s2-red.md`/`-test-review.md`'s
  finding that the `K and C` mutant also reds the pre-existing
  `test_rename_only_manifest_present_empty_sentinel_written` row, not slice
  2's row alone. Recorded, not a defect.
- **Item 3.1 slice 1** — "List revision after slice 3.1/1" blockquote
  (`runbook.md:219-225`), committed as part of `e3a1d28`. Records
  `closing_directive`'s signature becoming keyword-only (`*, typed: bool`)
  and `compose_directives` taking an `Ending` NamedTuple — both driven by
  `just precommit`'s ruff FBT001/PLR0913 gates, caught at test-review
  (slice 1) and code-review (slice 1) respectively. Recorded.
- **Item 3.1, after the Phase 3 checkpoint** — "Revised after the Phase 3
  checkpoint, 2026-09-19" blockquote (`runbook.md:227-235`), landed in
  `7389e56` together with the anchor-fix code change. Matches deviation #2 in
  the task brief exactly: `phase-3-corrector.md` raised the unanchored
  closing-line risk as an "Observations for the orchestrator (no fix in
  scope)" item; my human partner approved the wording change; the
  orchestrator implemented it directly (tests changed first — the two
  absence assertions loosened to case-insensitive `"end on one line"` and the
  four-cell content row's `startswith` updated — then both producers
  reworded, then a mutation/parity re-check on the bats drift row, which
  needed no edit since both producers changed identically). No subagent RED
  or code-review report exists for this change, consistent with "self-
  reviewed from the diff" being explicitly authorized for this one fix.
- No other divergence between the runbook's slice lists and what actually
  executed was found across Phases 1–3.

## Code Quality Observations

- **In-report corrections are used correctly.** `item-3-2-s2-red.md`
  contains a `> **Corrected at review, 2026-09-19.**` blockquote fixing its
  own wrong claim about trailing-newline drift being unobservable — caught by
  the test-review's own mutation M7. This is the `plans/` convention working
  as designed: the write-time record stays, the correction is scoped and
  dated, and what still stands is stated.
- **Wrong-reason hunting is unusually thorough** throughout — e.g.
  `item-1-1-s4-test-review.md` catches that the ordering assertion alone
  would pass a GREEN that prints the arming text twice, and adds
  `out.count(arming) == 1`; `item-3-2-s2-test-review.md` runs nine distinct
  mutations (M1–M9) to pin each of the six literal arms in
  `bin/handoff-approved` to its own bats row.
  `item-2-1-s2-test-review.md` finds two mutations (C, D) the RED report did
  not try, and uses them to justify keeping a row that no single mutation
  reds alone (slice 2).
- **`phase-3-corrector.md` finding 1 is a genuine gap the checkpoint review
  process was built to catch**: no row before the Phase-3 checkpoint pinned
  "closing line prints last" against a fixture where another part precedes
  it and the sentinel is armed (every prior row saw the closing line as
  sole output or checked ordering only against `held`). The corrector fixed
  it in `test_precompact_parts_print_in_order`, mutation-confirmed. This is
  the review-loop working as intended, not a slice defect — it landed before
  any commit shipped the gap unfixed.
- **`bin/handoff-approved` and `_checkpoint_lib.py:closing_directive` are
  kept from drifting** by `tests/checkpoint.bats`'s slice 3.2/2 rows, which
  compute the expected text through a live `python3 -c` call rather than a
  hardcoded literal — the right shape for a two-producer text contract, and
  the Phase-3 anchor fix (`7389e56`) is direct evidence it works: both
  producers were edited in the same commit and the parity rows needed no
  change.
- **Definition-order and docstring hygiene fixes recur at code review**
  (`item-1-1-s4-code-review.md`'s call-order reordering,
  `item-1-1-s5-code-review.md`'s `MemoryPart` placement,
  `phase-1-corrector.md`'s stale-docstring sweep) — small, consistently
  caught, consistently fixed same-commit or same-phase. No accumulation
  into later phases was observed.

## Recommendations

### Minor

1. **State a mutation's expected reds as a lower bound, not an exact set, in
   future runbooks.** Two batched-slice RED reports
   (`item-2-1-s2-red.md`, and implicitly the slice-2 "this row alone reds"
   language in the Item 1.1/2.1 runbook text) had to correct the runbook's
   own claim that a given mutation reds "this row alone" when it also reds
   an unrelated pre-existing row occupying the same predicate cell. The
   executors handled this correctly and recorded it in place
   (`runbook.md:156-164`), so no process gap resulted — but writing the
   runbook's mutation-check clauses as "at least this row" rather than
   "this row alone" would remove a predictable review-time correction.
2. **Consider a standing convention for self-reviewed anchor fixes** (as
   used for `7389e56`): the task brief's deviation #2 authorized it ad hoc.
   The pattern — tests changed and proven red first, both producers changed
   together, a targeted parity re-check, human approval before landing — is
   sound and reusable; naming it (e.g. "in-flight one-commit fix") in the
   execution-skill vocabulary would make its absence-of-a-subagent-review
   self-documenting rather than something an auditor has to reconstruct from
   the runbook blockquote and the diff.

No Important or Critical findings.

## Process Metrics

- Slices executed: 11 (5 in Item 1.1, 3 in Item 2.1 [1 full + 1 batched
  covering 2 runbook slices], 2 in Item 3.1 [1 full + 1 batched covering 4
  runbook slices], 2 in Item 3.2 [1 full + 1 batched]); counting runbook
  slice numbers individually: 16 slices, all compliant.
- Fully compliant: 16/16 (11 dispatch units; 0 violations).
- Wrong-reason tests caught at test review: 1.1/1 (2 fixes), 1.1/4 (1),
  1.1/5 (0, mutation only), 2.1/1 (1), 2.1/2–3 (0, deviation-review only),
  3.1/1 (2), 3.1/2–5 (1), 3.2/1 (2), 3.2/2 (1, a report-text correction) —
  10 test-level fixes total across the phase, plus 2 in-report corrections
  of the RED/runbook narrative (2.1/2–3's "this row alone", 3.2/2's
  trailing-newline claim).
- Dispatches per item: Item 1.1 — 5 slices × (red, test-review, green,
  code-review) except slice 2 (red, test-review only) = 18 dispatches, plus
  1 phase corrector. Item 2.1 — slice 1 full (4) + slice 2–3 batched (2) = 6
  dispatches, plus 1 phase corrector. Item 3.1 — slice 1 full (4) + slices
  2–5 batched (2) = 6 dispatches, plus 1 phase corrector (shared with 3.2).
  Item 3.2 — slice 1 full (4) + slice 2 batched (2) = 6 dispatches. Phase
  3's corrector and the anchor fix are one dispatch/one orchestrator commit
  respectively.
