# Phase 3 checkpoint review — Closing line

Scope: `git diff 2073a37..HEAD -- scripts bin tests` (Items 3.1 and 3.2),
judged against runbook lines 174–255 and the outline's "Closing line", "The
refusal prints alone" and Wording note. Fixes applied, nothing committed.
`just precommit` passes: jq ×3, `shellcheck -x`, ruff check, ruff format,
docformatter, mypy, ty, bats (169), pytest (261 passed, 11 deselected).

## Fixes applied

1. **Major — "closing line is last" was untested whenever another part
   precedes it.** Every row that saw the closing line saw it as the *only*
   part (the four `_closing_only` rows and the four-cell content row). A
   mutation printing it *first* (`parts.insert(0, closing)` in
   `compose_directives`) left all 171 rows green. Fixed in
   `test_precompact_parts_print_in_order`: its fixture (untyped precompact,
   dirty memory, `with-commit`) is the one armed cell with parts ahead of the
   closing line, so it now pins `autodrive` line 1 `== "armed"`, extends the
   index chain to `commit < closing`, and asserts stdout ends with the closing
   line plus one newline. Mutation re-run: that row alone reds, on the
   ordering assertion (`1598 < 0`).

2. **Minor — redundant bats rows.** Slice 1's three `status fact then closing
   content` rows and slice 2's three `closing line matches the checkpoint's`
   rows ran the same fixtures; slice 2's own review showed slice 1's content
   substrings caught none of six producer-drift mutations, and slice 1 alone
   pinned the status fact line. Merged into three rows, one per kind, each
   asserting the whole output exactly:
   `"handoff: <kind> armed; it runs at the end of this turn."$'\n\n'"$expected"`,
   with `[ -n "$expected" ]` first. The section comment keeps the
   trailing-newline residual. Mutations: em dash line drift reds `clear` and
   `compact`; a single `\n` after the status fact reds all three; the rename
   arm printing `/compact` reds `rename` alone. `bin/` restored after each
   (`git diff --stat bin` empty).

3. **Minor — typed content row did not discriminate by skill.**
   `test_closing_line_names_what_the_boundary_is_ready_for` asserted only
   `"armed" in out` on the typed cells, so swapping `Clear`/`Compaction` in
   `closing_directive` stayed green on the Python side. Now asserts
   `Clear armed` / `Compaction armed` per skill.

4. **Minor — `assert_stdout_is_closing` docstring** summary wrapped onto a
   second line. Now one line.

5. **Minor — `bin/handoff-approved` comment** said only that restart never
   holds. The `rename → Ready to /clear` mapping rests on autoname never
   holding too (a held rename is always an untyped handoff; a held clear or
   compact always driven). Now stated.

## Checked, no change

- **One producer per path.** Not held: `compose_directives` appends the
  closing line in the `else` of `ending.held`, after every other part; the
  refusal returns `[memory.text]` before that branch. Held: the checkpoint
  prints the arming instruction and no closing line;
  `handoff-approved` prints it keyed on `DRIVE_KIND`. All 16 boundary cells
  were run (skill × typed × commit mode × memory dirty). Every armed cell ends
  on the closing line, and every held cell ends on the arming instruction with
  no `End on one line`. Texts are byte-identical across producers (pinned by
  the bats rows), and all four quote the line the reply ends on.
- **`*)` fallback.** Unreachable through the checkpoint. restart has
  `commit_mode == ""` and an empty memory part, so `hold_decision` is false.
  autoname never holds. An untyped compact types nothing and is never typed.
  A hand-written held `restart` would print the status fact and a trailing
  blank line, which is harmless.
- **NFR1.** `handoff-approved` calls no Python, git or tmux. The literal
  arms are single-quoted under an `SC2016` disable scoped to the `case`.
- **Documentation surfaces.** `compose_sentinel` no longer appends arming text,
  and its docstring says so ("held or armed per `held`"). The docstrings for
  `compose_directives`, `Ending` and `closing_directive` describe current
  behaviour. `Ending` sits above its consumer, which is where `FilePlan` and
  `Transition` sit in this bottom-up file.
- **Remaining rows.** `test_held_sentinel_prints_no_closing_line` and
  `test_refusal_prints_alone_when_not_held` each pin the sentinel state
  before their stdout assertion. The refusal row asserts exact stdout. The
  mutation evidence in `item-3-1-s2-test-review.md` (M3, M6) still holds.

## Observations for the orchestrator (no fix in scope)

- **Closing-line timing in the one armed cell with a memory approval.**
  Untyped precompact with dirty memory is armed, so its output is the memory
  directive (which asks for approval, and so ends a turn), then the commit act
  if any, then `End on one line: …`. The commit act and the arming
  instruction both open "Once everything above is done". The closing line has
  no such anchor, so a fresh agent could append `Ready to /compact` to the
  reply that asks for approval. The runbook interface pins the opening
  (`closing_directive` "opens with `End on one line`"), and `handoff-approved`
  must print the same bytes, so changing it is a spec decision, not a
  correction. Two ways to settle it: Phase 4's "follow what it prints, in
  order", or the dogfood run. UNFIXABLE in scope.
- **Two blank lines between parts.** `print_output` joins parts that each
  end in `\n` with `"\n\n"`. This predates Phase 3 and is cosmetic.
