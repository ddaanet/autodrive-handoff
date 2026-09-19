# Runbook — the directive owns the procedure

Design: `outline.md` (proofed 2026-09-18). Classification: `classification.md`.
Recall: `recall-artifact.md`. The outline carries no requirement IDs; the
table below assigns them, one per outline commitment.

Deviation from a full-code plan: items are contracts. `Interfaces:` lines are
verbatim; everything else is prose, and no test or implementation body is
written here.

Every executor runs `just precommit` before its commit, calls bare `pytest`
(never `uv run`), places entry points before the definitions they use, and
keeps no compat alias or back-compat wrapper for a signature this runbook
changes — every in-repo caller is patched in the same item.

Standing rules for the test rows below:

- `import _checkpoint_lib as lib` resolves in `tests/` because `pyproject.toml`
  sets `pythonpath = ["scripts"]`; `tests/test_checkpoint.py` does not import it
  today, so the import is added by Item 1.1.
- **Every assertion that compares stdout against a `lib.*()` return value first
  asserts that value is non-empty.** A function returning `""` satisfies a
  containment check and scores index 0 in an ordering check, so the row would
  pass against an unwritten function.
- Skills load at the point of use: `craft:directive-writing` for every new
  agent-facing string (Items 1.1, 3.1, 3.2, 4.1, 4.2), `craft:test-discipline`
  for every mutation-checked row (phases 1–3), `plugin-craft:skill-authoring`
  for phase 4, `craft:design-doc-writing` for phase 5.

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
| R11 `autoname`/`restart` still print nothing | 3 | 3.1 | two existing rows keep `stdout == ""` |

Out of scope: the sentinel grammar, `handoff_drive_read`, `stop-drive.sh`, the
walker, the loaders, `autoname`/`restart` behaviour, the approval flow's own
text, the two dangling wikilinks.

## Phase 1: Commit act and part ordering (type: tdd)

- Item 1.1: `scripts/_checkpoint_lib.py`, `scripts/checkpoint.py`,
  `tests/test_checkpoint.py` — the checkpoint composes an ordered list of parts
  and prints them blank-line separated. `memory_directive` reports whether its
  text is the clause-file refusal, and `compose_directives` returns that
  refusal as the whole list when it is. `compose_sentinel` receives the hold
  decision and appends no text; `hold_decision` carries today's rule unchanged
  (`K and M`, a refusal counting as `M`). `main`'s order becomes: resolve the
  memory part, compute `held` from it via `hold_decision`, `compose_sentinel`
  with that decision, `compose_directives` with the memory part and that
  decision, `print_output`. `memory_directive` is called once, by `main`; the
  sentinel read-back through `handoff_drive_read` is unchanged. Call sites:
  `checkpoint.py:main`, `compose_directives`, `compose_sentinel`,
  `print_output`; `_checkpoint_lib.py:memory_directive`, `arming_directive`.
  Requirements: R1, R2, R3, R4, R5.
  Slices:
  1. External contract, over the existing `handoff_payload(commit)` /
     `precompact_payload(commit)` helpers on a clean `make_gitlore_repo`
     (clean memory, no ledger), parametrized on both skills:
     `test_with_commit_prints_the_commit_act` — asserts `lib.commit_directive()`
     is non-empty and appears in stdout verbatim, and that its lowercased text
     contains the word `commit` (the anchor that keeps a stub from passing);
     `test_without_commit_prints_no_commit_act` — same fixture, asserts that
     same non-empty text is absent from stdout.
     `test_commit_act_names_no_git_verb` — asserts `commit_directive()` is
     non-empty and contains none of `git commit`, `--amend`, `git add`.
  2. Ordering, each row over `make_gitlore_repo` + `dirty_memory` +
     `add_sdd_ledger` — the ledger is what makes the middle part non-empty, and
     without it both assertions below are vacuous or false:
     `test_handoff_parts_print_in_order` — `with-commit`, untyped: asserts
     `lib.todo_boundary(root)` and `lib.commit_directive()` are both non-empty,
     then index of `gitlore memory has uncommitted changes` < index of
     `lib.todo_boundary(root)` < index of `lib.commit_directive()`.
     `test_precompact_parts_print_in_order` — same fixture and shape with
     `lib.sdd_directive(root)`, likewise asserted non-empty, in the middle
     position.
  3. `test_with_commit_memory_text_drops_nothing_further` — dirty memory,
     `with-commit`: asserts `nothing further` absent from lowercased stdout;
     the existing `carries the memory` row (`test_checkpoint.py:2187`) stays
     green, and so does the load-bearing negative that `with-commit` output
     never names the trigger file.
  4. Arming moved and reworded: `test_arming_instruction_follows_every_other_part`
     — typed clear, `without-commit`, dirty memory, `add_sdd_ledger`: asserts
     `lib.todo_boundary(root)` and `lib.arming_directive()` are non-empty, line
     1 of the sentinel is `held sess-checkpoint`, index of
     `lib.todo_boundary(root)` < index of `lib.arming_directive()`, stdout with
     trailing newlines stripped ends with `arming_directive()` likewise
     stripped (`print_output` adds one newline past the last part, so a bare
     `endswith` on the unstripped text is false), and `Once that is done` is
     absent. Nothing follows the arming instruction in this cell in any later
     phase either: the closing line of Item 3.1 prints only when the sentinel
     is not held. `test_arming_text_refers_to_everything_above` — asserts
     `arming_directive()` is non-empty and contains `everything above` and
     `handoff-approved`.
  5. Refusal alone: `test_clause_refusal_is_followed_by_no_commit_or_arming` —
     clause key unset (`git config --unset gitlore.memoryApprovalClauseFile`,
     as in `test_clause_file_unset_names_key_and_restart`), dirty memory,
     `with-commit`, typed clear: asserts stdout contains
     `gitlore.memoryApprovalClauseFile`, contains neither the (non-empty)
     `commit_directive()` nor `arming_directive()`, and line 1 of the sentinel
     is still `held sess-checkpoint` — the refusal suppresses the printed parts
     and not the hold. Mutation check, recorded in the slice report: print
     parts 3–4 regardless of `refusal` ⟹ this row alone reds.
  Interfaces:
  - `class MemoryPart(NamedTuple)` — `text: str`, `refusal: bool`; `text == ""`
    when nothing is owed, and `refusal` is true only for the clause-file refusal
  - `memory_directive(root: str, mode: str) -> MemoryPart`
  - `commit_directive() -> str` — never `""`
  - `arming_directive() -> str` — never `""`
  - `hold_decision(transition: Transition, *, memory: bool) -> bool` — today's
    rule, `transition.cmds and memory`; the `commit` parameter arrives in Item
    2.1, where it is first read (ruff runs `select = ["ALL"]` over `scripts/`
    with `ARG` un-ignored, so an unused parameter fails `just precommit`)
  - `compose_directives(skill: str, root: Path, commit_mode: str, memory: MemoryPart, *, held: bool) -> list[str]`
    — non-empty parts only, in print order; `[memory.text]` alone when
    `memory.refusal`; `[]` for `autoname`/`restart`
  - `compose_sentinel(root: Path, transition: Transition, continuation: str, *, held: bool) -> None`
  - `print_output(parts: list[str]) -> None` — writes nothing for an empty list
    (the four silent boundary rows assert `stdout == ""` until Item 3.1);
    otherwise the parts joined by two newlines plus one trailing newline, which
    is byte-identical to today's output in the memory-only, second-only and
    memory+second cases

## Phase 2: Hold rule (type: tdd)

- Item 2.1: `scripts/checkpoint.py:hold_decision`, `tests/test_checkpoint.py` —
  widen the rule to `(K and M) or (T and C)`. Post-phase-1 state: `main`
  already computes `held` through `hold_decision` and the composition already
  prints the arming instruction from it, so this item adds the `commit`
  parameter and its `main` call-site argument, changes one predicate, and adds
  rows beside `test_typed_transition_no_memory_gate_armed_no_arming_instruction`
  (`test_checkpoint.py:1780` — handoff, `without-commit`, `clear: true`, clean
  memory), over that row's fixture with `commit` flipped. No phase-1 row
  depends on the widened rule: every phase-1 cell that holds holds through the
  first disjunct. Requirements: R6. Depends on: Item 1.1
  Slices:
  1. `test_typed_with_commit_clean_memory_is_held` — parametrized: handoff
     `clear: true`, precompact `compact: true`; clean memory, `with-commit`:
     asserts `lib.commit_directive()` and `lib.arming_directive()` are
     non-empty, line 1 of the sentinel is `held sess-checkpoint`, and index of
     `commit_directive()` < index of `arming_directive()` in stdout. Mutation
     check: drop the second disjunct ⟹ this row alone reds.
  2. `test_untyped_handoff_with_commit_clean_memory_is_armed` — same fixture,
     `clear: false`: asserts line 1 is `armed`, `handoff-approved` absent from
     stdout, and the non-empty `commit_directive()` present. Mutation check:
     widen the second disjunct to `K and C` ⟹ this row alone reds.

     > **Corrected at review, 2026-09-18.** "this row alone reds" is wrong:
     > the `K and C` mutant also reds the pre-existing
     > `test_rename_only_manifest_present_empty_sentinel_written` (untyped
     > handoff, `with-commit`, non-gitlore repo, so `M` false), which pins the
     > sentinel bytes `armed\nrename\n…` and so occupies the same cell. Evidence:
     > `reports/item-2-1-s2-red.md` and `item-2-1-s2-test-review.md`, both
     > `2 failed, 162 passed` naming those two rows. What stands: the mutation
     > reds this row, and this row is still the only one that names the cell
     > and asserts both stdout facts (commit act present, arming absent).
  3. `test_sentinel_typing_nothing_arms_even_with_memory_gate_pending`
     (`test_checkpoint.py:1819` — precompact, `compact: false`, dirty memory)
     gains a `with-commit` parameter: asserts `armed` under both modes. `T` is
     false there, so the second disjunct must not fire on the FR-G marker.
  Interfaces:
  - `hold_decision(transition: Transition, *, memory: bool, commit: bool) -> bool`
    — widened from Item 1.1's `(transition, *, memory)`; true iff
    `(transition.cmds and memory) or (transition.typed and commit)`

## Phase 3: Closing line (type: tdd)

- Item 3.1: `scripts/_checkpoint_lib.py:closing_directive`,
  `scripts/checkpoint.py:compose_directives`, `tests/test_checkpoint.py` — the
  closing line is the last part whenever the sentinel is not held and the
  memory part is not a refusal. Its text is an instruction to end the reply on
  one named line. Requirements: R5, R7. Depends on: Item 2.1
  Slices:
  1. External contract: a helper `assert_stdout_is_closing(result, skill, typed)`
     asserts `lib.closing_directive(skill, typed)` is non-empty and that stdout
     equals it plus one newline. The four silent boundary rows
     (`test_not_gitlore_managed_silent`:2063,
     `test_gitlore_clean_memory_silent`:2070,
     `test_submodule_registered_not_materialized_silent`:2077,
     `test_flat_path_ledger_alone_precompact_silent`:2328 — all
     `without-commit`, clean memory, untyped, so all armed) move from
     `stdout == ""` to the helper. The two non-boundary rows
     (`test_restart_never_holds_even_with_dirty_memory`:1956,
     `test_autoname_against_dirty_memory_no_directive_at_all`:2026) keep
     `stdout == ""` — R11.
  2. Content per cell, `test_closing_line_names_what_the_boundary_is_ready_for`,
     parametrized over the four `(skill, typed)` cells and exercised through a
     checkpoint run in each (not a direct call on the function), all
     `without-commit` on a clean `make_gitlore_repo` so the sentinel is armed
     and the closing line is the only part: `("handoff", False)` contains
     `Ready to /clear`; `("precompact", False)` contains `Ready to /compact`;
     `("handoff", True)` and `("precompact", True)` contain `armed` and neither
     `Ready to` string. All four open with `End on one line`.
  3. `test_held_sentinel_prints_no_closing_line` — over phase 2 slice 1's
     fixture: asserts `End on one line` absent. Mutation check: print the
     closing line regardless of `held` ⟹ this row alone reds.
  4. `test_clause_refusal_is_followed_by_no_commit_or_arming` gains the
     assertion that `End on one line` is absent.
  5. The refusal against an *armed* sentinel — the cell where slice 4's held
     fixture proves nothing, since a held sentinel suppresses the closing line
     on its own: `test_refusal_prints_alone_when_not_held` — untyped precompact
     (`compact: false`, so the sentinel types nothing and is `armed`), dirty
     memory, clause key unset, `with-commit`: asserts stdout is exactly the
     refusal text plus one newline — no commit act, no closing line. Mutation
     check: drop the `refusal` guard from the closing-line branch ⟹ this row
     alone reds.
  Interfaces:
  - `closing_directive(skill: str, typed: bool) -> str` — never `""`; opens
    with `End on one line`

  > **List revision after slice 3.1/1.** `typed` is keyword-only —
  > `closing_directive(skill: str, *, typed: bool)` — since the positional
  > form fails ruff FBT001/FBT003. `compose_directives` takes
  > `ending: Ending` (a `NamedTuple` of `held` and `typed`, in
  > `checkpoint.py`) in place of `*, held`, keeping one hold decision under
  > ruff's five-parameter cap. Item 3.2 slice 2's one-liner calls
  > `closing_directive("<skill>", typed=<bool>)`.

  > **Revised after the Phase 3 checkpoint, 2026-09-19.** The closing line
  > opens `Once everything above is done, end on one line:` rather than
  > `End on one line`, in both producers. Untyped precompact with dirty memory
  > is armed, so its closing line follows a memory directive that asks for
  > approval. Unanchored, it could end the reply that asks the question, while
  > the commit act and the arming instruction both already wait for
  > everything above them. Raised in `reports/phase-3-corrector.md`, taken by
  > my human partner. The absence rows now match `end on one line`
  > case-insensitively.

- Item 3.2: `bin/handoff-approved`, `tests/checkpoint.bats` — after arming, print
  the existing status fact, a blank line, then the closing line for the kind:
  `rename` → the prepared-handoff line; `clear` → the driven-handoff line;
  `compact` → the driven-precompact line. The text is literal in the script's
  final `printf`, per kind — `handoff-approved` calls no Python and keeps NFR1's
  shape (one file rewritten, no git, no tmux); slice 2 is what holds the two
  producers together. Requirements: R8. Depends on: Item 3.1
  Slices:
  1. `handoff-approved: status fact then closing content, per kind` — one row
     per kind, each over that kind's sentinel shape (`rename`: `held
     $CLAUDE_CODE_SESSION_ID`, `rename`, `/rename A Title`; `clear`: state,
     kind, `/rename A Title`, `/clear`; `compact`: state, kind, `/compact`),
     run through the existing `run_approved` helper, which separates stderr:
     every row asserts output line 1 is `handoff: <kind> armed; it runs at
     the end of this turn.`; `rename`'s row additionally asserts the output
     contains `Ready to /clear`; `clear` and `compact` assert `End on one
     line` present and `Ready to` absent.
  2. `handoff-approved: closing line matches the checkpoint's, per kind` — for
     each of the three kinds, asserts everything after the blank line equals
     what a `python3 -c` one-liner prints for `closing_directive` with the
     matching `(skill, typed)`, run with `PYTHONPATH="$repo_root/scripts"`:
     `rename` → `("handoff", False)`, `clear` → `("handoff", True)`, `compact`
     → `("precompact", True)`. Assert that printed text is non-empty first.
     This row is what keeps the two producers from drifting.
  Interfaces:
  - `bin/handoff-approved` stdout on success: the status fact
    `handoff: <kind> armed; it runs at the end of this turn.`, one blank line,
    then the closing line for `<kind>`

## Phase 4: Skill bodies (type: general)

- Item 4.1: `skills/handoff/SKILL.md` — rewrite the protocol to three steps:
  write durable learnings to memory; decide the payload and run
  `handoff-checkpoint` with no other tool call between; follow what it prints,
  in order. Remove: the tense clause inside **Capture memory** ("Under
  `with-commit`, memory bodies state present-tense truth — the change described
  as made rather than proposed", lines 53–55); step 2's commit-placement
  paragraph ("When the ask includes a commit, make it **after** the
  checkpoint…", lines 112–117); step 3 "Say what the boundary is ready for" and
  its prepared/driven matrix (lines 119–125). Rewrite, do not keep, step 2's
  opening claim that "`handoff-checkpoint` prints nothing when there is nothing
  further to do" (line 103): at a boundary it now always prints at least the
  closing line. Keep: the three decisions step 1
  owns that the payload cannot derive (typed transition, continuation, commit
  awareness), the "checkpoint owns the decision — do not re-derive or verify
  it" prohibition, the non-zero-exit instruction (it names the offending field
  on stderr; fix the payload and retry), the file templates, the seam section,
  and every anti-pattern. Body stays under 2000 words. Requirements: R9.
  Depends on: Item 3.2
  Model: opus
- Item 4.2: `skills/precompact/SKILL.md` — the same three-step shape. Remove:
  the tense paragraph in step 1 ("Under `with-commit`, memory bodies state
  present-tense truth…", lines 41–44) and the tense clause in step 2 ("in the
  tense the commit answer sets", line 47); step **3**'s closing
  commit-placement paragraph ("When the ask includes a commit, make it
  **after** this call…", lines 104–108 — it sits at the end of step 3, not
  step 4); step 5 and its matrix (lines 119–124). Rewrite, do not keep, the two
  claims that the checkpoint can be silent at a boundary — "Nothing printed →
  nothing further to do" (line 110) and "The normal case … is one silent
  checkpoint call and one line of reply" (lines 126–127): the closing line is
  now always printed, and the normal case is one checkpoint call whose output
  is that one line. Keep: step 4's
  do-not-re-derive prohibition and non-zero-exit instruction, the deferral to
  `handoff/SKILL.md` for templates and the seam, and every anti-pattern —
  including the one about padding the closing line into a summary, which now
  guards text the checkpoint supplies. Requirements: R9. Depends on: Item 3.2
  Model: opus

## Phase 5: Records (type: general)

- Item 5.1: `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md`,
  `docs/changelog.md`,
  `docs/changelog/2026-09-17-memory-moves-inside-the-deciding-step.md` — new
  entry with its index line: the three defects, the hold rule with the
  rejected uniform predicate and the one cell where they differ, the
  refusal-alone rule, why memory leaves the deciding step one commit after
  entering it. The 2026-09-17 entry takes a `> **Superseded 2026-09-18**`
  blockquote scoped to exactly three things: the ordering reason ("after the
  commit answer because that answer sets the tense"), the tense clause restored
  to precompact, and the commit placement's home in skill prose ("It now sits
  in Step 2"). It names what still stands — memory before the checkpoint, and
  the commit after the checkpoint and before arming, same rule with a new
  carrier. Requirements: R10. Depends on: Items 4.1, 4.2
  Model: opus
- Item 5.2: `docs/design.md` — four passages, all present tense, no dated
  entry: **FR9** (line 156, "the memory gate and the SDD ledger nudge … memory
  first") for the five-part order; §"Held: a transition an approval has not
  released" (line 593) for the two-disjunct rule and for the arming
  instruction no longer being composed onto the memory directive; the
  closing line's two producers (checkpoint when not held, `handoff-approved`
  when held) and the refusal-alone rule, stated where the directive
  composition is described; and §"Deciding makes no tool call but the memory
  writes" (line 926), whose "after the commit answer that sets their tense"
  and its surrounding placement argument the tense clause's removal reverses.
  Requirements: R10. Depends on: Item 5.1
  Model: opus
- Item 5.3: `CLAUDE.md` — the `handoff` and `precompact` skill bullets (three
  steps), the `precompact` bullet's directive list (line 109), the
  `checkpoint.py` paragraph stating the old `held` condition **and** its
  sentence "with the arming instruction composed onto the memory directive when
  the sentinel is held" (line 596), the `_checkpoint_lib.py` bullet (new
  functions `commit_directive`/`closing_directive`, `memory_directive`'s
  `MemoryPart` return, the dropped "Nothing further" sentence; "Couples only to
  the two IPC filenames" (line 667) gains `gitlore.memoryApprovalClauseFile`),
  the `handoff-approved` bullet, the `tests/test_checkpoint.py` count (line
  848, currently "140 tests" — re-derive it by collecting the suite, do not
  add to the stated figure) and the new mutation-checked rows, the changelog
  pointers. Requirements: R10. Depends on: Item 5.2
  Model: opus

## After the last item

Dogfood: a fresh session in this tree, which runs the plugin via
`--plugin-dir`. One handoff typed + `with-commit` + clean memory, one prepared
+ `with-commit`. Surprises patch this runbook.
