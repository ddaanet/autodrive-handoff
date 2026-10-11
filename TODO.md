## Remaining

- Once 0.16.0 is installed, delete the untracked `.claude/handoff-task.md` and `.claude/handoff-todo.md` that the 0.15.0 handoff of 2026-10-11 left here; they must not be committed.
- After 0.16.0 is installed, other repositories' `.claude/handoff-*.md` are moved by hand with the two `git mv` lines in the README, by whoever works there next.
- The marketplace entry's description of the plugin in `claude-plugins` still says "a local file".
- `memory/MEMORY.md` is past the size at which the loader truncates its tail; `/gitlore:index-audit` is the curation pass when wanted.
