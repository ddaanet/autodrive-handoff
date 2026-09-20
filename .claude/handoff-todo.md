## Remaining

- Add subheadings to `docs/design/driving-the-tui.md` (200 lines, none) at existing paragraph boundaries, no prose change — a follow-up commit, kept out of the split so that one stays a pure move.
- Confirm whether the directive-owns-the-procedure dogfood covered the typed + `with-commit` + clean-memory cell (the one the `T ∧ C` disjunct changed); no plan report records it.
- Investigate why the driven restart's continuation line did not land: the walker reported `re-check whether the masking bind mounts are gone…` never reached the composer, which is the exact failure `wait_for_composer` (2026-08-15) was added to close. `tests/test_drive_when_idle.py` has a row for it, so the gate works against the stub — the live path is what to look at.
- Fix the dangling wikilink `[[green-is-not-evidence]]` in `memory/project_pane-fixtures-are-captures.md` (found by the 2026-09-20 sweep; likely meant the `craft:test-discipline` skill — confirm before swapping).
