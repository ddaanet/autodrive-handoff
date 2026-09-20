## Remaining

- Run `/deliverable-review plans/2026-09-18-directive-owns-the-procedure` on opus in a fresh session.
- Investigate why the driven restart's continuation line did not land: the walker reported `re-check whether the masking bind mounts are gone…` never reached the composer, which is the exact failure `wait_for_composer` (2026-08-15) was added to close. `tests/test_drive_when_idle.py` has a row for it, so the gate works against the stub — the live path is what to look at.
- Split `memory/ddaanet/sandbox-effects.md`: it is 33.6KB against a 4KB recall limit, so every section past the symptom table is invisible to recall. One fact per file, with index lines; this session added a phantom-removal paragraph and a symptom row to a file that was already far over.
- Fix two dangling wikilinks in the ddaanet memory tier, both introduced on this repo's side before the tier merge: `[[errexit-blind-inside-test]]` in `memory/ddaanet/git-add-untracked-deletion.md` and `[[mutation-check-discipline]]` in `memory/ddaanet/sandbox-effects.md` — likely meant the `shell-scripting:shell-gotchas` and `craft:test-discipline` skills; confirm before swapping.
- Split `docs/design.md` (1248 lines, ~3x the 400-line soft cap) into cohesive nodes; the directive-owns-the-procedure run grew it by ~90 lines.
- Move `main` in `scripts/checkpoint.py` from the bottom of the file to the top (entry points before the definitions they use).
- The memory directive's clause-file refusal (`scripts/_checkpoint_lib.py`, `memory_directive`) says "Nothing has been written", which is false once the checkpoint has written task/todo/manifest/sentinel: drop that clause, keep "The memory changes are still pending.", and update the refusal rows' expected text.
