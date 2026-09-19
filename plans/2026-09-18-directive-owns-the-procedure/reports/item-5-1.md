# Item 5.1 — changelog entry for the directive owning the procedure

## Files

- `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md` (new).
  Sections: the three defects (lead), the change (three-step shape and the
  five-part print order), the hold rule (`(K ∧ M) ∨ (T ∧ C)`, the rejected
  uniform `K ∧ (M ∨ C)`, the one cell where they differ, the silent-forget
  cost, the two mutation-checked rows), one producer for the closing line
  (checkpoint vs `handoff-approved`, `DRIVE_KIND` sufficiency, the bats tie,
  the "Once everything above is done" anchor and the untyped-precompact-with-
  dirty-memory case behind it, approved by my human partner), the refusal
  prints alone (with the dropped "Nothing further" sentence and the dropped
  skill-body mechanism sentence), and memory leaving the deciding step one
  commit after entering it.
- `docs/changelog.md` — index line at the top, in the file's one-sentence,
  semicolon-joined style.
- `docs/changelog/2026-09-17-memory-moves-inside-the-deciding-step.md` —
  `> **Superseded 2026-09-18**` blockquote under the title, scoped to the three
  named things (ordering reason, precompact tense clause, commit placement's
  home in skill prose) and naming what stands: memory before the checkpoint,
  and the commit after the checkpoint and before arming, same rule with a new
  carrier. The entry has no sections, so the blockquote heads the whole file,
  as in `2026-07-27-content-null-is-a-no-op.md`.

## Sources checked

Texts quoted from `scripts/_checkpoint_lib.py` (`commit_directive`,
`arming_directive`, `closing_directive`, `MemoryPart`), `scripts/checkpoint.py`
(`hold_decision`, `compose_directives`, `Ending`, `memory=bool(memory.text)`,
so the refusal still counts as `M`), `bin/handoff-approved`'s per-kind
`case`. The "older rename-only row" in the hold section is from the runbook's
Corrected-at-review blockquote on Item 2.1 slice 2. The commit-awareness claim
("the tense half needs no mode") is at line 123 of
`docs/changelog/2026-07-25-commit-awareness.md`.

## Not touched

`docs/design.md` (Item 5.2), `CLAUDE.md` (Item 5.3), skills, code, tests,
other changelog entries.
