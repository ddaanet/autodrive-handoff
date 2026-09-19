## Remaining

- Fix two dangling wikilinks in the ddaanet memory tier, both introduced on this repo's side before the tier merge: `[[errexit-blind-inside-test]]` in `memory/ddaanet/git-add-untracked-deletion.md` and `[[mutation-check-discipline]]` in `memory/ddaanet/sandbox-effects.md` — likely meant the `shell-scripting:shell-gotchas` and `craft:test-discipline` skills; confirm before swapping.
- Split `docs/design.md` (1248 lines, ~3× the 400-line soft cap) into cohesive nodes; the directive-owns-the-procedure run grew it by ~90 lines.
- Move `main` in `scripts/checkpoint.py` from the bottom of the file to the top (entry points before the definitions they use).
- The memory directive's clause-file refusal (`scripts/_checkpoint_lib.py`, `memory_directive`) says "Nothing has been written", which is false once the checkpoint has written task/todo/manifest/sentinel: drop that clause, keep "The memory changes are still pending.", and update the refusal rows' expected text.
