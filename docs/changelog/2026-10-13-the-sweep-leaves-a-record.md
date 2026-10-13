# The sweep leaves a record

2026-10-13.

## What happened

After a `with-commit` handoff on 2026-10-13 the sentinel the checkpoint had
composed was gone when its turn ended, and the clear it armed did not run. No
failure file existed and nothing reached either channel of the session that
had composed it. The earlier held-sentinel loss (2026-10-12, see `TODO.md`) had
the same look: the file vanished and no one could say who took it.

## Why the report could not answer

`report-drive-failure.sh` runs on `UserPromptSubmit` in every session that
shares the root. The harness starts background sessions in the same root after
a `git commit` (the commit review), each with its own session id, and each runs
this hook. When one of them sweeps the file, the note it prints goes to that
session's own `systemMessage` and `additionalContext`. The session that
composed the file never sees it, and no transcript of the composing session
carries it. The removal is therefore silent to the one reader who needs it.

## The change

Every removal the sweep makes appends one tab-separated line to
`.claude/autodrive.swept` (`HANDOFF_REL_DRIVE_SWEPT`): UTC time,
`sweeper=<session id>`, `state=`, `owner=` (`-` when none), `kind=`,
`age=<seconds>s` by the file's mtime, and `cwd=` `%q`-quoted. It covers the
`armed`, abandoned (held by another session), malformed and stranded `pending`
removals. The file is newest first, trimmed to 50 lines, never consumed, and
created only when something is swept. A failed write never blocks the sweep,
because the record is a diagnostic and the sweep is the behaviour. The existing
`.claude/autodrive*` ignore rule covers it.

## What it answers, and what it does not

It names the remover and the sentinel's age, which tells a background review
session from the owner's own prompt and a stale file from a fresh one. It does
not fix the sweep rule: whether a held file owned by another session is truly
abandoned is still the open item in `TODO.md`, and the `armed` sweep is
suspected, unproven, of sharing the cause. The record is what lets the next
occurrence settle that from evidence.
