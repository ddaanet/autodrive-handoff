## Open decisions

- What to do with the modified `.gitlore/bin/claude` (109 changed lines, tracked): it changed on 2026-11-14 before any session work on macOS, apparently gitlore regenerating its shim, and no session here edited or read its diff. Commit it, or restore it.

## Remaining

- Release the directory-lock fix with `/release-ritual`. `dev` has had per-commit medium reviews only (the plan records and the two docs-only commits had none); the release review of `dev` against `main` has not run. `just precommit` passes at the `run_bounded` fix on Linux (uncached) and on macOS, where a sandboxed `bin/handoff-checkpoint` also took the lock on `.claude/` and left no lock file.
- Once that release is installed, my human partner deletes the lock files earlier versions left in other repositories: `find /Users/david/code -maxdepth 3 -path '*/.claude/autodrive.lock' -type f -size 0 -print -delete`; a second run printing nothing proves they are gone.
- Triage the two briefs in `inbox/`: `2026-11-13-brief-pending-truncated-frame.md` and `brief-plugin-dev-0.16.1.md`. Neither has been read.
