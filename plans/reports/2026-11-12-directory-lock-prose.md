# Directory lock: prose report (2026-11-12)

## Files changed

- docs/design/sentinel-lock.md: the lock's object is the `.claude/` directory (read-only fd 9, one helper spawn, a link to a directory followed, checkpoint creates `.claude/` first); unavailable causes reworded; the 0600/O_NOFOLLOW/link-residual/never-deleted paragraph replaced by "nothing is left on disk", the untracked-file reason, why the directory is safe to lock, and `wait`'s device/inode check; `check_sentinel_target` clause no longer mentions the lock's mkdir; test-row sentence now names `fail_lock_helper` and the refused `flock`. "Only thing a refused call may leave is an empty `.claude/`" kept. 9650 bytes.
- docs/design/driving-the-transition.md: line ~226 now "(on `.claude/` itself)".
- README.md: file-table row removed; one sentence after the table that the lock is on `.claude/` and leaves no file, and that an earlier version's `autodrive.lock` is unused and safe to delete. The README has no upgrade or version-notes section, so that sentence sits there (the only place that names the file).
- docs/design/rejected-alternatives.md: one new entry (deleting the lock file; a lock outside the tree). 15534 bytes.
- docs/design.md: hub index line for it. 19247 bytes (close to the cap).

Not changed: .claude/rules/tests.md (its lock bullet stays true), CLAUDE.md, decisions.md.

## Remaining grep hits (autodrive.lock, lock file, 0600, O_NOFOLLOW, never deleted)

- docs/: only `O_NOFOLLOW` in scoping.md, driving-the-transition.md:182, sessions-sharing-a-root.md, the-sentinel.md. All are about reading regular files (`handoff_read_regular`), true and unrelated to the lock.
- README.md: none.
- scripts/_drive_lock.py (docstring lines 1-30, `create` at 104, `_open` O_NOFOLLOW at 141), scripts/checkpoint.py (242, 272 `HANDOFF_REL_DRIVE_LOCK = ".claude/autodrive.lock"`), scripts/_lib.sh (37, 97-99): owned by the other agent, untouched. Others in scripts/ (_lib_files.sh, _lib_drive.sh, report-drive-failure.sh) are the read_regular O_NOFOLLOW, unrelated.
- sentinel-lock.md's tail still cites the archived titles "The sentinel takes a lock" and "The lock fails closed"; they are not cited as the argument for the file.

## Unsure / notes

- docs/design/decisions.md:167 says the lock has "a bounded wait that fails open", which contradicts sentinel-lock.md (fails closed). Pre-existing and unrelated to the file, so left; worth a one-word fix ("closed") by whoever owns it.
- `just check-refs` passes. `just check-size` fails only on the untracked `.bats-review.out` (32170 bytes), not on any file I touched.
- The new rejected entry wording on the file-deletion costs follows the plan's Decision section; the node states the "untracked file in every root" reason in sentinel-lock.md.
