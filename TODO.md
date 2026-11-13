## Remaining

- Before the release, run `just hook-test` and `just py-test` on macOS: the directory lock (`flock` on `.claude/`, bash opening fd 9 on a directory) was probed, tested and reviewed on Linux only, and it fails closed, so a macOS that refuses it stops every checkpoint and transition there. Run one checkpoint from a sandboxed Bash call on macOS as well, since the tests do not cover the macOS sandbox.
- Release the directory-lock fix. `dev` has had the per-commit medium review only; the release review of `dev` against `main` has not run, and `just precommit` last passed before two prose-only edits to `docs/design/sentinel-lock.md` and `docs/design/rejected-alternatives.md`.
- Once that release is installed, my human partner deletes the lock files earlier versions left in other repositories: `find /Users/david/code -maxdepth 3 -path '*/.claude/autodrive.lock' -type f -size 0 -print -delete`; a second run printing nothing proves they are gone.
