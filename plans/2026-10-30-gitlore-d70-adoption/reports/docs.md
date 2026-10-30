# Docs report: gitlore D70 adoption

Nothing committed. `scripts/`, `bin/`, `tests/`, `.claude/settings.json` untouched.

## Files touched

- `CLAUDE.md`: Layout second paragraph rewritten (dirty listing + `gitlore:commit` pointer, same text under both modes, gitlink named in the commit act, needs a gitlore shipping the skill, new changelog cited); `_checkpoint_lib.py` bullet (`memory_directive(root)` plain string, coupling is `.gitmodules` + skill name; `commit_directive(memory: bool)`); `just precommit` line drops the `precommitCommand` claim; `conftest.py` bullet drops `unset_clause_file` and "gitlore's pre-commit hook" becomes "a git hook running the gate"; test bullets for directives (new rows, new mutation checks), composition (memory part located by `gitlore:commit`) and legacy (refusal clause removed); routing line "the gitlore files" becomes "the gitlore seam". The `checkpoint.py` bullet never mentioned the refusal; left as is.
- `README.md`: Memory paragraph (skill, needs gitlore shipping it, gitlink in the commit) and the read-only git paragraph (clause-key read removed).
- `docs/design/the-checkpoint-directive.md`: part 2 and part 4 of "What the checkpoint prints"; the clause-file refusal paragraph deleted; "The gitlore seam" rewritten. Now 150ish lines.
- `docs/design/decisions.md`: "agent supplies one fact" restated; "Ask the question the request can answer" loses the false pre-commit-hook hazard and keeps the uniform-ask and answerable-question reasoning; "Withholding is a mechanism" replaced by "The directive points at the skill and holds no copy of the protocol".
- `docs/design/rejected-alternatives.md`: PreCompact entry: "write the message file" becomes "commit"; "any later commit" becomes "any later turn".
- `docs/design.md`: index line "Withholding is a mechanism." renamed to match.
- `docs/changelog/2026-10-30-memory-commits-go-through-the-skill.md`: new entry (why, the two failures, point-at-skill, listing stays, gitlink named, hold unchanged, no shim, rows).
- `docs/changelog.md`: index line at top, no version (no neighbouring line carries one, and 0.19.0 is not cut).

## Superseded blockquotes added (2026-10-30, each scoped, bodies untouched)

- 2026-06-12-gitlore-aware-handoff (top)
- 2026-07-20-precompact-drives-the-compaction (top; file IPC and mode split)
- 2026-07-25-commit-awareness (top; mechanism, withholding-a-filename)
- 2026-07-28-memory-approval-from-gitlore (top; discovery mechanism)
- 2026-07-29-approval-clause-renders-as-a-block (top)
- 2026-08-05-transitions-become-modes (under "Commit awareness narrows"; the pre-commit-hook hazard)
- 2026-08-10-restart-names-the-stale-clause-remedy (top)
- 2026-09-18-the-directive-owns-the-procedure (under "The refusal prints alone")
- 2026-10-11-legacy-paths-are-read-and-moved (under "No git work, and the act that stands in for it"; "Where it prints")
- 2026-10-13-the-test-harness-sheds-gits-environment (under "The defect"; cause named was gitlore's pre-commit hook)

## Checks run

`just check-refs`: passed (256 references in 28 files). Final grep of CLAUDE.md, README.md, docs/design.md, docs/design/, skills/ for the retired tokens: only the unrelated `PostToolBatch` context-nudge passage in decisions.md remains. No file under `docs/design/` is near 400 lines.

## Unsure

- The changelog's "two failure modes" are taken from gitlore's inbox note (fresh install: refusal with unfixable advice; stale key: files nothing consumes); I did not reproduce them.
- `CLAUDE.md` "a git hook running the gate exports `GIT_DIR`…" is generic, since the specific gitlore hook is gone; a reviewer may prefer to drop the clause.
- The 2026-10-13 and 2026-10-11 blockquotes are slightly beyond the listed candidates; drop them if too eager.
- `.claude/settings.json` has no `precommitCommand` match in my grep (its edit is not mine).
- The new changelog names no handoff-side test file counts; the "Rows" section describes the plan's rows, which the code owner should confirm match.
