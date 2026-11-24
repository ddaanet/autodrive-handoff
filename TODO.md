## Remaining

- Strengthen the compaction prompt's verbatim rule (prompts/compaction.md and the installed ~/.vibe/prompts/handoff-compact.md): the summariser appended its own parenthetical annotation inside the TODO.md frame block during the live compact, where it could be read as file content — say annotations go outside the frame.
- Propose to gitlore (another repo, read-only here): its launcher injects `--settings '{"autoMemoryDirectory":…}'` before the subcommand, and claude 2.1.330 refuses any option before `plugin`, so `claude plugin test` and `claude plugin validate` sit behind "not run from this spelling"; until gitlore accommodates it, gate runs here need `GITLORE_LAUNCHED=1 just precommit` to skip the injection.
