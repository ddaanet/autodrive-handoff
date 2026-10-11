## Open decisions

- The plan's six defaults were spelled out to my human partner and await a ruling; steps 4 and 5 hold until then: (1) keep the `autodrive` guard in `write-guard.sh`; (2) drop checkpoint staging (manifest, `bash-post.sh`); (3) no deletion on an empty body; (4) no protection for a foreign `TODO.md`; (5) no migration code; (6) empty-frame report from `load-handoff.sh` only.
- The step 2 error sentence was shown to my human partner with an offer to reword it; no answer yet. It ends: `The task is prose within the limit: keep the task in hand and where it stands, move remaining steps and open decisions to "todo", cut finished work to one sentence, and write standing rules and conventions to memory.`
- Memory candidate, not written: a report committed to a public repo aliases private repositories and drops what they are about (the step 1 survey named them and had to be rewritten out of three unpushed commits). Needs the approval gate; `memory/MEMORY.md` is at 96% of its budget.
- `inbox/brief-session-start-skill-checkpoint.md`, already pushed, names a private repository and says what it is about. Reported to my human partner, untouched.

## Remaining

- Step 2: review the green phase (eight mutations requested, each with its expected red rows), `just precommit`, commit.
- Step 4, the move and the cut, inline, after the defaults are ruled on; load `craft:removing-cleanly` first.
- Step 5, the loaders report: red then green Sonnet dispatches, reviewed here; then `just mod-smoke`.
- Step 6, records; load `craft:design-doc-writing` first. Includes the docs, `CLAUDE.md` and `README.md` that still say precompact carries `task`, and the handoff skill's task template, which should name the four destinations (task in hand stays; plan and open decisions to the todo; standing rules and conventions to memory through its approval gate; finished work cut to one sentence) and the cap and no-list rule.
- Plan verification: the grep for retired names returns nothing outside `docs/changelog/`, `plans/` and `memory/`; dogfood from a second terminal the same day.
- The anonymised reports alias seven private or remote-less repositories as `private-A` to `private-G`; the pre-rewrite commits survive only in the local reflog and must not be pushed.
- Release as 0.16.0 with `just release` when asked; the shape change is breaking.
- `memory/MEMORY.md` is at 96% of its budget; `/gitlore:index-audit` is the curation pass when wanted.
