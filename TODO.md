## Remaining

- Release the directory-lock fix. `dev` has had the per-commit medium review only; the release review of `dev` against `main` has not run, and `just precommit` last passed before two prose-only edits to `docs/design/sentinel-lock.md` and `docs/design/rejected-alternatives.md`.
- Once that release is installed, my human partner deletes the lock files earlier versions left in other repositories: `find /Users/david/code -maxdepth 3 -path '*/.claude/autodrive.lock' -type f -size 0 -print -delete`; a second run printing nothing proves they are gone.
