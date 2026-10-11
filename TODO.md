## Open decisions

- Memory candidate, not written, needs the approval gate: what is private about a private repository is its content, not its name or existence, so a report in a public repo may name it and must not reproduce or describe what is in it. `memory/MEMORY.md` is at 96% of its budget.
- The step 1 reports alias seven repositories as `private-A` to `private-G`. Their names are not private, so the aliases could be restored; that means rebuilding unpushed commits again, and it has not been asked for.
- `inbox/brief-session-start-skill-checkpoint.md` is untriaged and names the retired `.claude/handoff-*.md` paths, so it is the one hit of the plan's verification grep outside the README's upgrade note.

## Remaining

- Dogfood the skills from a second terminal. Done here, in a scratch repo through a real `claude -p --plugin-dir`: session start with neither file, a hand-written `TODO.md` alone, a headings-only `TASK.md` beside it, and `TASK.md` alone each injected what the loader contract says; through the real shim, an over-cap task with a list was refused with both facts and a `precompact` call removed `TASK.md` and edited the foreign `TODO.md` in place. Not done: `/handoff:handoff` and `/handoff:precompact` run by an agent, and a driven transition. With the installed 0.15.0 enabled, `--plugin-dir` loads this repo's command hooks but not its mod ("another plugin of that name loads first"), so disable the installed plugin for that run.
- Release as 0.16.0 with `just release` when asked; the shape change is breaking. It bumps `handoff` (tag and GitHub release) and `claude-plugins` (marketplace entry), whose description of the plugin still says "a local file".
- After 0.16.0 is installed, other repositories' `.claude/handoff-*.md` are moved by hand with the two `git mv` lines in the README, by whoever works there next.
- `memory/MEMORY.md` is at 96% of its budget; `/gitlore:index-audit` is the curation pass when wanted.
