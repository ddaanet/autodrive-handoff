# Step 7 — dogfood

Run on `dist/plugin/` (`just dogfood`), Claude Code 2.1.296.

| # | Check | Result |
|---|-------|--------|
| 1 | `/handoff:autoname` | Pass. The mod ran `/rename` at turn end; no sentinel left. |
| 2 | Driven clear with continuation | Pass. The continuation was the new session's first prompt, the frame was injected, `.claude/autodrive` and `.claude/autodrive.failed` were absent afterwards. |
| 3 | Forced failure | Inconclusive. A well-formed `armed`/`compact`/`/compact` sentinel was not rejected: the mod ran the compact, `.claude/autodrive` was consumed and `.claude/autodrive.failed` never appeared. The `failFile` path is covered only by the stub rig. See below. |
| 4 | Mod-not-loaded sweep note | Pass. Run on a copy of `dist/plugin` with `modules` stripped from `hooks.json` (hooks live, mod absent) rather than `--safe-mode`, which may disable the hook too. The launched session wrote the row; `.claude/autodrive` is absent afterwards. |

Cleanup: `.claude/autodrive.log` (gitignored, untracked, retired walker) deleted.

## Finding for check 3

An unknown command line cannot reach the mod. `handoff_drive_read` pins each
slot to its literal (`/rename <arg>`, `/clear`, `/compact [arg]`), so a sentinel
carrying anything else is swept as malformed (`kind: null`), which exercises the
parser path rather than the mod's `failFile` write. A genuine mod-level
rejection needs a well-formed line the host refuses to run.

The workaround was a well-formed `/compact` armed on a short conversation. The
host accepted it and compacted the session, so no rejection was produced. A
live rejection would need a line the host refuses but the parser accepts;
`/rename <arg>` and `/clear` are the other pinned literals and the host is
unlikely to refuse them either. Treat the `failFile` write and the
`UserPromptSubmit` report as verified by `tests/mod` and `tests/hook-test.bats`
only, not live.

## Remaining

- Release via `just release` is my human partner's call (breaking: the
  `restart` kind and skill are gone).
