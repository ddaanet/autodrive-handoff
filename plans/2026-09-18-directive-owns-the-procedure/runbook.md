# Runbook — the directive owns the procedure

Design: `outline.md` (proofed 2026-09-18). Classification: `classification.md`.
Recall: `recall-artifact.md`. The outline carries no requirement IDs; the
table below assigns them, one per outline commitment.

Deviation from a full-code plan: items are contracts. `Interfaces:` lines are
verbatim; everything else is prose, and no test or implementation body is
written here.

Every executor runs `just precommit` before its commit, calls bare `pytest`
(never `uv run`), and places entry points before the definitions they use.

| Requirement | Phase | Items | Notes |
|---|---|---|---|
| R1 commit act printed iff `with-commit` | 1 | 1.1 | names no git verb |
| R2 parts print in the outline's order | 1 | 1.1 | memory, boundary/nudge, commit, arming, closing |
| R3 `with-commit` memory text loses "Nothing further…" | 1 | 1.1 | trigger-file negative untouched |
| R4 arming text refers to everything above it | 1 | 1.1 | |
| R5 clause-file refusal prints with no part 3–5 after it | 1, 3 | 1.1, 3.1 | sentinel state unchanged |
| R6 `held` iff `(K and M) or (T and C)` | 2 | 2.1 | two mutation checks |
| R7 closing line printed by the checkpoint iff not held | 3 | 3.1 | |
| R8 `handoff-approved` prints status fact then closing line, per kind | 3 | 3.2 | same text as R7's producer |
| R9 both skill bodies take the three-step shape | 4 | 4.1, 4.2 | |
| R10 design doc, changelog, index, `CLAUDE.md` | 5 | 5.1–5.3 | |

Out of scope: the sentinel grammar, `handoff_drive_read`, `stop-drive.sh`, the
walker, the loaders, `autoname`/`restart` behaviour, the approval flow's own
text, the two dangling wikilinks.

## Phase 1: Commit act and part ordering (type: tdd)

- Item 1.1: `scripts/_checkpoint_lib.py`, `scripts/checkpoint.py`,
  `tests/test_checkpoint.py` — the checkpoint composes an ordered list of parts
  and prints them blank-line separated. `memory_directive` reports whether its
  text is the clause-file refusal. `compose_sentinel` receives the hold
  decision and appends no text; `hold_decision` carries today's rule unchanged
  (`K and M`, a refusal counting as `M`). Call sites: `checkpoint.py:main`,
  `compose_directives`, `compose_sentinel`, `print_output`;
  `_checkpoint_lib.py:memory_directive`, `arming_directive`.
  Requirements: R1, R2, R3, R4, R5.
  Slices:
  1. External contract, over `handoff_payload`/`precompact_payload` on a clean
     `make_gitlore_repo`, parametrized on both skills:
     `test_with_commit_prints_the_commit_act` — asserts stdout contains
     `lib.commit_directive()` verbatim; `test_without_commit_prints_no_commit_act`
     — same fixture, asserts it is absent. `test_commit_act_names_no_git_verb` —
     asserts `commit_directive()` contains none of `git commit`, `--amend`,
     `git add`.
  2. Ordering: `test_handoff_parts_print_in_order` — dirty memory, `with-commit`,
     untyped: asserts index of `gitlore memory has uncommitted changes` < index
     of `lib.todo_boundary(root)` < index of `lib.commit_directive()`.
     `test_precompact_parts_print_in_order` — same with a live SDD ledger and
     `lib.sdd_directive(root)` in the middle position.
  3. `test_with_commit_memory_text_drops_nothing_further` — dirty memory,
     `with-commit`: asserts `nothing further` absent from lowercased stdout;
     the existing `carries the memory` row stays green.
  4. Arming moved and reworded: `test_arming_instruction_follows_every_other_part`
     — typed clear, `without-commit`, dirty memory: asserts `held sess-checkpoint`
     on line 1, index of `lib.todo_boundary(root)` < index of
     `lib.arming_directive()`, stdout ends with `arming_directive()`, and
     `Once that is done` absent. `test_arming_text_refers_to_everything_above`
     — asserts `arming_directive()` contains `everything above` and
     `handoff-approved`.
  5. Refusal alone: `test_clause_refusal_is_followed_by_no_commit_or_arming` —
     clause key unset, dirty memory, `with-commit`, typed clear: asserts stdout
     contains `gitlore.memoryApprovalClauseFile`, contains neither
     `commit_directive()` nor `arming_directive()`, and line 1 of the sentinel
     is still `held sess-checkpoint`. Mutation check, recorded in the slice
     report: print parts 3–4 regardless of `refusal` ⟹ this row alone reds.
  Interfaces:
  - `class MemoryPart(NamedTuple)` — `text: str`, `refusal: bool`; `text == ""`
    when nothing is owed
  - `memory_directive(root: str, mode: str) -> MemoryPart`
  - `commit_directive() -> str`
  - `arming_directive() -> str`
  - `hold_decision(transition: Transition, *, memory: bool, commit: bool) -> bool`
  - `compose_directives(skill: str, root: Path, commit_mode: str, *, held: bool) -> list[str]`
    — non-empty parts only, in print order
  - `compose_sentinel(root: Path, transition: Transition, continuation: str, *, held: bool) -> None`
  - `print_output(parts: list[str]) -> None`

## Phase 2: Hold rule (type: tdd)

- Item 2.1: `scripts/checkpoint.py:hold_decision`, `tests/test_checkpoint.py` —
  widen the rule to `(K and M) or (T and C)`. Post-phase-1 state: `main`
  already passes `commit=` and prints the arming instruction from `held`, so
  this item changes one predicate and adds rows beside
  `test_typed_transition_no_memory_gate_armed_no_arming_instruction`, over that
  row's fixture. Requirements: R6. Depends on: Item 1.1
  Slices:
  1. `test_typed_with_commit_clean_memory_is_held` — parametrized: handoff
     `clear: true`, precompact `compact: true`; clean memory, `with-commit`:
     asserts line 1 is `held sess-checkpoint`, and index of `commit_directive()`
     < index of `arming_directive()` in stdout. Mutation check: drop the second
     disjunct ⟹ this row alone reds.
  2. `test_untyped_handoff_with_commit_clean_memory_is_armed` — same fixture,
     `clear: false`: asserts line 1 is `armed`, `handoff-approved` absent from
     stdout, `commit_directive()` present. Mutation check: widen the second
     disjunct to `K and C` ⟹ this row alone reds.
  3. `test_sentinel_typing_nothing_arms_even_with_memory_gate_pending` gains a
     `with-commit` parameter: asserts `armed` under both modes.
  Interfaces:
  - `hold_decision(transition: Transition, *, memory: bool, commit: bool) -> bool`
    — signature unchanged from Item 1.1; true iff
    `(transition.cmds and memory) or (transition.typed and commit)`

## Phase 3: Closing line (type: tdd)

- Item 3.1: `scripts/_checkpoint_lib.py:closing_directive`,
  `scripts/checkpoint.py:compose_directives`, `tests/test_checkpoint.py` — the
  closing line is the last part whenever the sentinel is not held and the
  memory part is not a refusal. Its text is an instruction to end the reply on
  one named line. Requirements: R5, R7. Depends on: Item 2.1
  Slices:
  1. External contract: a helper `assert_stdout_is_closing(result, skill, typed)`
     asserts stdout equals `lib.closing_directive(skill, typed)` plus one
     newline. The four silent boundary rows
     (`test_not_gitlore_managed_silent`, `test_gitlore_clean_memory_silent`,
     `test_submodule_registered_not_materialized_silent`,
     `test_flat_path_ledger_alone_precompact_silent`) move from
     `stdout == ""` to the helper. The `autoname` and `restart` rows keep
     `stdout == ""`.
  2. Content per cell, `test_closing_line_names_what_the_boundary_is_ready_for`,
     parametrized: `("handoff", False)` contains `Ready to /clear`;
     `("precompact", False)` contains `Ready to /compact`; `("handoff", True)`
     and `("precompact", True)` contain `armed` and neither `Ready to` string.
     All four open with `End on one line`.
  3. `test_held_sentinel_prints_no_closing_line` — over phase 2 slice 1's
     fixture: asserts `End on one line` absent. Mutation check: print the
     closing line regardless of `held` ⟹ this row alone reds.
  4. `test_clause_refusal_is_followed_by_no_commit_or_arming` gains the
     assertion that `End on one line` is absent.
  Interfaces:
  - `closing_directive(skill: str, typed: bool) -> str`

- Item 3.2: `bin/handoff-approved`, `tests/checkpoint.bats` — after arming, print
  the existing status fact, a blank line, then the closing line for the kind:
  `rename` → the prepared-handoff line; `clear` → the driven-handoff line;
  `compact` → the driven-precompact line. Requirements: R8.
  Depends on: Item 3.1
  Slices:
  1. `handoff-approved: rename prints the status fact then Ready to /clear` —
     held `rename` sentinel: asserts output line 1 is
     `handoff: rename armed; it runs at the end of this turn.` and the output
     contains `Ready to /clear`.
  2. `handoff-approved: clear and compact print the driven line` — one row per
     kind: asserts the status fact on line 1, `End on one line` present,
     `Ready to` absent.
  3. `handoff-approved: closing line matches the checkpoint's, per kind` — for
     each of the three kinds, asserts everything after the blank line equals
     what `python3` prints for `closing_directive` with the matching
     `(skill, typed)`: `rename` → `("handoff", False)`, `clear` →
     `("handoff", True)`, `compact` → `("precompact", True)`. This row is what
     keeps the two producers from drifting.
  Interfaces:
  - `bin/handoff-approved` stdout on success: the status fact
    `handoff: <kind> armed; it runs at the end of this turn.`, one blank line,
    then the closing line for `<kind>`

## Phase 4: Skill bodies (type: general)

- Item 4.1: `skills/handoff/SKILL.md` — rewrite the protocol to three steps:
  write durable learnings to memory; decide the payload and run
  `handoff-checkpoint` with no other tool call between; follow what it prints,
  in order. Remove the tense clause (line 55), step 2's commit-placement
  paragraphs, step 3 and its matrix. Keep the three deciding questions, the
  templates, the seam section, and every anti-pattern. Body stays under 2000
  words. Requirements: R9. Depends on: Item 3.2
  Model: opus
- Item 4.2: `skills/precompact/SKILL.md` — the same three-step shape; remove the
  tense clause (lines 41 and 47), step 4's commit placement, step 5. Keep its
  deferral to `handoff/SKILL.md` for templates and the seam, and its
  anti-patterns. Requirements: R9. Depends on: Item 3.2
  Model: opus

## Phase 5: Records (type: general)

- Item 5.1: `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md`,
  `docs/changelog.md`,
  `docs/changelog/2026-09-17-memory-moves-inside-the-deciding-step.md` — new
  entry with its index line: the three defects, the hold rule with the
  rejected uniform predicate and the one cell where they differ, the
  refusal-alone rule, why memory leaves the deciding step one commit after
  entering it. The 2026-09-17 entry takes a `> **Superseded 2026-09-18**`
  blockquote scoped as the outline's per-file section states, naming what
  stands. Requirements: R10. Depends on: Item 4.2
  Model: opus
- Item 5.2: `docs/design.md` — rewrite §"Held: a transition an approval has not
  released" for the two-disjunct rule, and the directive-composition prose for
  the five-part order and the two closing-line producers. Present tense, no
  dated entry. Requirements: R10. Depends on: Item 5.1
  Model: opus
- Item 5.3: `CLAUDE.md` — the `handoff` and `precompact` skill bullets (three
  steps), the `checkpoint.py` paragraph stating the old `held` condition, the
  `_checkpoint_lib.py` bullet (new functions; "Couples only to the two IPC
  filenames" gains `gitlore.memoryApprovalClauseFile`), the `handoff-approved`
  bullet, the `tests/test_checkpoint.py` count and the new mutation-checked
  rows, the changelog pointers. Requirements: R10. Depends on: Item 5.2
  Model: opus

## After the last item

Dogfood: a fresh session in this tree, which runs the plugin via
`--plugin-dir`. One handoff typed + `with-commit` + clean memory, one prepared
+ `with-commit`. Surprises patch this runbook.
