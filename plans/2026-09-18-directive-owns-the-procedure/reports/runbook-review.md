# Runbook Review: the directive owns the procedure

**Artifact**: `plans/2026-09-18-directive-owns-the-procedure/runbook.md`
**Design**: `plans/2026-09-18-directive-owns-the-procedure/outline.md` (proofed 2026-09-18)
**Date**: 2026-09-18
**Mode**: review + fix-all

## Summary

The runbook's phase structure, dependency chain and requirement mapping hold up
against the outline: five phases, ten commitments traced, the settled decisions
(the two-disjunct hold rule, refusal-prints-alone, dispatched-opus phases 4–5)
carried without reopening. What it did not carry was executable precision. Four
test rows as written were vacuous or outright false against the real fixtures
and the real output format, one requirement half (R5's closing-line side) had no
discriminating cell, one interface forced `memory_directive` to be called twice
or not at all, and one signature would have failed `just precommit` on ruff
ARG001 at phase 1's own commit. All of it was fixable from the design; every
finding below is FIXED in `runbook.md`.

**Overall Assessment**: Ready

## Requirements Coverage

| Requirement | Phase | Items | Coverage | Notes |
|---|---|---|---|---|
| R1 commit act iff `with-commit` | 1 | 1.1/1 | Complete | vacuity fixed (non-empty + `commit` anchor) |
| R2 part order | 1 | 1.1/2, 1.1/4 | Complete | ledger fixture added — was false/vacuous without it |
| R3 "Nothing further" dropped | 1 | 1.1/3 | Complete | trigger-file negative named explicitly |
| R4 arming refers to everything above | 1 | 1.1/4 | Complete | `endswith` corrected for the trailing newline |
| R5 refusal prints alone | 1, 3 | 1.1/5, 3.1/4, **3.1/5 (new)** | Complete | held cell alone did not discriminate |
| R6 hold rule `(K∧M)∨(T∧C)` | 2 | 2.1/1–3 | Complete | both mutation checks verified sound |
| R7 closing line iff not held | 3 | 3.1/1–3 | Complete | cells now exercised through checkpoint runs |
| R8 `handoff-approved` per kind | 3 | 3.2/1–3 | Complete | producer (literal bash text) pinned |
| R9 three-step skill bodies | 4 | 4.1, 4.2 | Complete | anchors re-derived; two stale claims added |
| R10 records | 5 | 5.1–5.3 | Complete | design.md enumeration widened by two passages |
| R11 `autoname`/`restart` silent | 3 | 3.1/1 | Complete | **row added to the table** — outline commitment had no ID |

Outline commitments with no ID before this review: "`autoname`/`restart` still
print nothing" (now R11) and "the read-back is unchanged" (now stated in Item
1.1's prose). Everything else in the outline's per-file section maps to an item.

## Review Findings

### Critical Issues

1. **Phase 1 slice 2's handoff row asserts an ordering that is false against its
   own fixture**
   - Location: Item 1.1, slice 2, `test_handoff_parts_print_in_order`
   - Problem: the stated fixture was "dirty memory, `with-commit`, untyped" with
     no SDD ledger. `lib.todo_boundary(root)` returns `""` without a live ledger
     (`_checkpoint_lib.py:220`), so `stdout.index(todo_boundary(root))` is 0 and
     the assertion `index("gitlore memory has uncommitted changes") < 0` is
     false — the row fails on correct code. The precompact row named a ledger;
     the handoff row did not.
   - Fix: both rows now specify `make_gitlore_repo` + `dirty_memory` +
     `add_sdd_ledger`, and assert the middle part non-empty first.
   - **Status**: FIXED

2. **Phase 1 slice 4's `endswith` assertion is false against the real output
   format**
   - Location: Item 1.1, slice 4, `test_arming_instruction_follows_every_other_part`
   - Problem: "stdout ends with `arming_directive()`". Every directive built by
     `_printf_lines` already ends in `\n`, and `print_output` adds one more past
     the last part (today: `f"{memory}\n"`). So stdout ends with
     `arming_directive() + "\n"` and a bare `endswith` is false.
   - Fix: the assertion is now stated over both sides with trailing newlines
     stripped, with the reason inline.
   - Checked as asked: **nothing prints after the arming instruction in that
     cell**, in phase 1 or later. That cell is `without-commit` (no commit act,
     which is part 3) and held (no closing line, which is part 5, printed only
     when not held). The runbook now says so where the assertion is made.
   - **Status**: FIXED

### Major Issues

3. **Vacuous `lib.*()` comparisons (the whole class)**
   - Location: Item 1.1 slices 1, 2, 4, 5; Item 2.1 slices 1, 2; Item 3.1 slice
     1; Item 3.2 slice 3
   - Problem: `assert lib.commit_directive() in result.stdout` passes for a
     function returning `""`, and `stdout.index("")` is 0, which silently
     satisfies every ordering assertion. Eight rows were exposed. (The negative
     forms — `not in`, `== ""` — are not vacuous: `"" in x` is always true, so
     they fail loudly instead.)
   - Fix: a standing rule in the preamble ("every assertion comparing stdout
     against a `lib.*()` return value first asserts that value is non-empty"),
     plus an explicit non-empty clause on each affected row, plus content
     anchors where a non-empty stub would still pass — the commit act's
     lowercased text contains `commit`; `closing_directive` opens with `End on
     one line`; `arming_directive` contains `everything above` and
     `handoff-approved`.
   - **Status**: FIXED

4. **R5's closing-line half had no discriminating cell**
   - Location: Item 3.1, slice 4
   - Problem: slice 4 added "`End on one line` absent" to the refusal row — but
     that row's sentinel is *held* (typed clear + dirty memory), and a held
     sentinel suppresses the closing line on its own. The assertion passes even
     if the refusal guard on the closing line is never written.
   - Fix: new slice 3.1/5, `test_refusal_prints_alone_when_not_held` — untyped
     precompact (types nothing ⟹ `armed`), dirty memory, clause key unset,
     `with-commit`; asserts stdout is exactly the refusal plus one newline, with
     its own mutation check (drop the refusal guard ⟹ this row alone reds).
   - **Status**: FIXED

5. **`compose_directives`'s signature makes the memory part unreachable or
   double-computed**
   - Location: Item 1.1, Interfaces
   - Problem: `compose_directives(skill, root, commit_mode, *, held)` takes no
     memory part, but `held` is derived from whether a memory directive was
     emitted. Either `main` calls `memory_directive` and `compose_directives`
     calls it a second time (two extra `git` subprocesses, and the refusal
     detection duplicated), or `held` cannot be computed before the call. Two
     executors resolve this differently.
   - Fix: `compose_directives` now takes `memory: MemoryPart`; Item 1.1's prose
     pins `main`'s order (memory part → `hold_decision` → `compose_sentinel` →
     `compose_directives` → `print_output`) and states `memory_directive` is
     called once, by `main`. The refusal short-circuit is placed in
     `compose_directives`.
   - **Status**: FIXED

6. **`print_output`'s contract was unspecified, and its empty case is
   load-bearing**
   - Location: Item 1.1, Interfaces
   - Problem: `print_output(parts: list[str]) -> None` said nothing about the
     separator or the trailing newline, yet phase 3 slice 1 asserts stdout
     *equals* the closing line "plus one newline" and phase 1 slice 4 asserts a
     suffix. Worse, a naive join emits `"\n"` for an empty list, which reds the
     four silent boundary rows through phases 1–2.
   - Fix: the contract is now stated — nothing for an empty list; otherwise the
     parts joined by two newlines plus one trailing newline, byte-identical to
     today's output in the memory-only, second-only and memory+second cases
     (verified against `checkpoint.py:580`).
   - **Status**: FIXED

7. **Phase 1's `hold_decision` signature fails the gate it must pass**
   - Location: Item 1.1 Interfaces / Item 2.1 prose
   - Problem: phase 1 introduced `hold_decision(transition, *, memory, commit)`
     while keeping today's `K ∧ M` rule, so `commit` is unread until phase 2.
     `pyproject.toml` runs ruff with `select = ["ALL"]` over `scripts/*.py` and
     does not ignore `ARG` there, so phase 1's own `just precommit` fails on
     ARG001. Verified empirically against a throwaway probe file (`ARG001 Unused
     function argument: c`, kwonly).
   - Fix: phase 1 declares `(transition, *, memory)`; phase 2 widens the
     signature and adds the `main` argument, with the ruff reason recorded.
   - **Status**: FIXED

8. **Item 4.2 names the wrong step for the commit-placement paragraph**
   - Location: Item 4.2
   - Problem: "remove … step 4's commit placement". That paragraph is the
     closing paragraph of **step 3** (`skills/precompact/SKILL.md:104–108`);
     step 4 begins at line 110 and carries no commit prose.
   - Fix: corrected, with the quoted opening and the exact range, and a note
     that it sits at the end of step 3.
   - **Status**: FIXED

9. **Two stale "the checkpoint can be silent" claims survive phase 4 unnamed**
   - Location: Items 4.1, 4.2
   - Problem: with the closing line always printed at a boundary,
     `skills/handoff/SKILL.md:103` ("`handoff-checkpoint` prints nothing when
     there is nothing further to do") and
     `skills/precompact/SKILL.md:110` ("Nothing printed → nothing further to
     do") plus `:126–127` ("one silent checkpoint call") become false. Neither
     item named them, and both sit outside the passages marked for removal.
   - Fix: both items now carry an explicit "rewrite, do not keep" clause naming
     each sentence and its line.
   - **Status**: FIXED

10. **Item 5.2's design.md enumeration is incomplete**
    - Location: Item 5.2
    - Problem: it named §"Held…" and "the directive-composition prose". Two
      further passages go stale and are unnamed: **FR9** at
      `docs/design.md:156` ("the memory gate and the SDD ledger nudge … memory
      first" — now five parts), and §"Deciding makes no tool call but the memory
      writes" at line 926, whose "the memory writes … sit inside that step,
      before the checkpoint call … and after the commit answer that sets their
      tense" is exactly the placement this job reverses.
    - Fix: item 5.2 now enumerates four passages with line numbers.
    - **Status**: FIXED

11. **Item 3.2 leaves the closing line's producer undecided**
    - Location: Item 3.2
    - Problem: nothing said whether `bin/handoff-approved` duplicates the text
      in bash or shells out to `_checkpoint_lib`. The outline settles it ("the
      final `printf` keeps its status fact and gains the closing-line
      instruction"), but the runbook is what composes the dispatch prompt.
    - Fix: stated — literal text in the final `printf`, no Python call, NFR1's
      shape preserved; slice 3 is the anti-drift check.
    - **Status**: FIXED

### Minor Issues

12. **Item 5.1 defers the superseded-blockquote scope to the outline**
    - A dispatched subagent's prompt is composed from the runbook, and per
      `memory/ddaanet/subagent-skips-at-import-expansion.md` its context omits
      what it was not handed. Fix: the three scope points and the "what stands"
      clause are now spelled out in the item. **Status**: FIXED

13. **Item 5.1 depended on 4.2 only** — it records both skill rewrites. Fix:
    `Depends on: Items 4.1, 4.2`. **Status**: FIXED

14. **`import _checkpoint_lib as lib` is assumed, never stated** — no existing
    row in `tests/test_checkpoint.py` imports it; it resolves only because
    `pyproject.toml` sets `pythonpath = ["scripts"]` (as `test_watcher_lib.py`
    relies on). Fix: stated in the preamble, with the import assigned to Item
    1.1. **Status**: FIXED

15. **Item 3.1 slice 2 did not say how the four cells are exercised** — a direct
    call on `closing_directive` would pin the text and wire nothing. Fix: each
    cell runs the checkpoint (`without-commit`, clean repo ⟹ armed ⟹ the closing
    line is the only part). **Status**: FIXED

16. **Item 3.2's bats rows named no sentinel shapes and no `PYTHONPATH`** — a
    `rename` sentinel is three lines, `clear` five, `compact` three, and slice
    3's `python3` call needs `$repo_root/scripts` on `PYTHONPATH`. Fix: all
    stated; `run_approved`'s stderr separation named. **Status**: FIXED

17. **Item 4.1's "three deciding questions" was ambiguous** — clarified to the
    three decisions the payload cannot derive (typed transition, continuation,
    commit awareness), and the keep-list gained the do-not-re-derive prohibition
    and the non-zero-exit instruction, which a "rewrite step 2" instruction
    could otherwise delete. **Status**: FIXED

18. **Item 5.3 left the `tests/test_checkpoint.py` count open to arithmetic** —
    `CLAUDE.md:848` says "140 tests"; the instruction now says to re-derive it
    by collecting the suite rather than adding to the stated figure, and names
    the second stale sentence in the same paragraph (`:596`, the arming
    instruction "composed onto the memory directive"). **Status**: FIXED

19. **No compat-alias rule in the preamble** — phase 1 changes three signatures.
    Fix: added to the standing executor rules. **Status**: FIXED

20. **Recall-selected skills were not routed to items** — the recall artifact
    assigns `craft:directive-writing`, `craft:test-discipline`,
    `plugin-craft:skill-authoring` and `craft:design-doc-writing` to phases, but
    `/orchestrate` composes from the runbook. Fix: a preamble line maps each
    skill to its items. **Status**: FIXED

### Verified, no change needed

- **Enumerated names and line references** (re-derived by grep, not trusted):
  all eight named existing tests exist —
  `test_typed_transition_no_memory_gate_armed_no_arming_instruction`:1780,
  `test_sentinel_typing_nothing_arms_even_with_memory_gate_pending`:1819,
  `test_restart_never_holds_even_with_dirty_memory`:1956,
  `test_autoname_against_dirty_memory_no_directive_at_all`:2026,
  `test_not_gitlore_managed_silent`:2063, `test_gitlore_clean_memory_silent`:2070,
  `test_submodule_registered_not_materialized_silent`:2077,
  `test_flat_path_ledger_alone_precompact_silent`:2328. The "carries the memory"
  row is at 2187. `grep 'stdout == ""'` returns exactly the six rows the
  outline's correction claims, four of them boundary rows. The line numbers are
  now recorded in the runbook so the next reader need not re-derive them.
- **Prose-artifact line anchors** re-derived and corrected in place:
  `skills/handoff/SKILL.md` tense clause 53–55 (was "line 55"), commit paragraph
  112–117 (was 112–118), step 3 119–125 ✓, "prints nothing" 103;
  `skills/precompact/SKILL.md` tense 41–44 ✓ and 47 ✓, commit paragraph 104–108,
  step 5 119–124 (was 119–125), "normal case" 126–127;
  `docs/design.md` FR9 156, §Held 593, §Deciding 926; `CLAUDE.md` 109, 596, 667,
  848. `skills/handoff/references/design.md` mentions none of this — correctly
  out of scope.
- **Inter-phase state (phase 1 under the old hold rule)**: every phase-1 cell
  that expects `held` reaches it through the first disjunct alone — slice 4
  (typed clear + dirty memory: K∧M) and slice 5 (refusal counts as M, and
  `memory_directive` returns non-empty text there, as today). Slices 1–3 assert
  nothing about sentinel state. No phase-1 row needs phase 2's rule, and the
  runbook now states it.
- **Mutation checks are sound**: dropping the second disjunct reds 2.1/1 alone
  (2.1/2 and 2.1/3 stay armed); widening it to `K ∧ C` reds 2.1/2 alone (untyped
  handoff types `/rename`, so K holds while T does not; untyped precompact types
  nothing, so 2.1/3 is untouched). 3.1/3 and the new 3.1/5 each red alone.
- **Dependencies**: 1.1 → 2.1 → 3.1 → 3.2 → {4.1, 4.2} → 5.1 → 5.2 → 5.3. No
  cycle, no forward reference, prerequisites satisfied. Phase 4's two prose items
  are one-file-per-item (no split prose edits).
- **Phase balance and growth**: 1/1/2/2/3 items, no phase above eight, no phase
  above 40% of the total. Measured today: `scripts/_checkpoint_lib.py` 251 lines
  (projected ~300 — under the 350 split signal), `scripts/checkpoint.py` 628
  (projected ~660; already past the 400-line convention before this job and not
  made materially worse by it — no split proposed), `tests/test_checkpoint.py`
  2353, `tests/checkpoint.bats` 480, `skills/handoff/SKILL.md` 245 (shrinks),
  `skills/precompact/SKILL.md` 146 (shrinks).
- **Format**: no code block inside any item; `Interfaces:` blocks are one line
  per contract with full signature and return type; every item carries
  `Requirements:`; slice 1 of each tdd item pins the external contract.

## Fixes Applied

- Preamble — compat-alias rule; the `lib.*()` non-empty rule; the
  `pythonpath = ["scripts"]` import note; skill-to-item routing.
- Requirements table — R11 added (`autoname`/`restart` print nothing).
- Item 1.1 — `main`'s call order and the single `memory_directive` call; refusal
  short-circuit located in `compose_directives`; read-back stated unchanged;
  slice 1 non-empty + `commit` anchor; slice 2 ledger fixture on both rows;
  slice 3 trigger-file negative named; slice 4 ledger fixture, stripped-suffix
  assertion, and the "nothing follows it in this cell" note; slice 5 the unset
  mechanism and the "suppresses the parts, not the hold" statement; Interfaces
  rewritten (`hold_decision` without `commit`, `compose_directives` taking
  `MemoryPart`, `print_output`'s full contract, never-`""` annotations).
- Item 2.1 — post-phase-1 state corrected (the `commit` parameter and its
  argument arrive here, with the ruff reason); the phase-1-independence
  statement; fixture line references; non-empty clauses; slice 3's `T`-is-false
  reason.
- Item 3.1 — helper asserts non-empty; the six rows carry line numbers and the
  R11 tag; slice 2 exercised through checkpoint runs in all four cells; new
  slice 5 for the armed refusal; `closing_directive` annotated.
- Item 3.2 — producer decided (literal bash `printf`, no Python call); sentinel
  shapes per kind; `run_approved`'s stderr separation; `PYTHONPATH` for slice 3;
  non-empty clause.
- Item 4.1 — quoted anchors with corrected ranges; the stale "prints nothing"
  sentence; expanded keep-list (three decisions named, do-not-re-derive, the
  non-zero-exit instruction).
- Item 4.2 — step **3** correction for the commit paragraph; quoted anchors with
  corrected ranges; the two stale silence claims; expanded keep-list.
- Item 5.1 — the three superseded-scope points and what stands, spelled out;
  `Depends on: Items 4.1, 4.2`.
- Item 5.2 — four passages enumerated with line numbers (FR9 and §Deciding
  added).
- Item 5.3 — `:109`, `:596`, `:667`, `:848` named; the count re-derived rather
  than incremented; `MemoryPart` return recorded.

## Design Alignment

No settled decision was reopened. The hold rule stays `(K and M) or (T and C)`
with its two mutation checks and the rejected uniform predicate untouched; the
refusal-prints-alone rule is strengthened (a second cell) rather than altered;
phases 4–5 keep `Model: opus` and their dispatched-prose shape; the boundaries
section still excludes the sentinel grammar, the walker, the loaders and
`autoname`/`restart` behaviour. The one place the review went beyond the
outline's letter is Item 5.2's two extra `docs/design.md` passages and Items
4.1/4.2's stale-silence sentences — all of them consequences the outline's own
changes make false, not new decisions.

Unfixable: none. No item contains "choose"/"decide"/"determine" language, and
every code-touching item enumerates its call sites.
