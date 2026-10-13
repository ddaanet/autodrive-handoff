# A root symlink is not read

2026-10-13.

## The defect

[A legacy symlink is not read](2026-10-13-a-legacy-symlink-is-not-read.md)
stopped the loaders following a symlink at the legacy paths, and left the
sibling paths open: `handoff_frame` still tested and read the root `TASK.md`
and `TODO.md` through `-f`, `_handoff_has_body` and `cat`, all of which follow
a link. A repository can commit `TASK.md -> /some/readable/file`, and that file
was then injected as the task frame at `SessionStart(startup|clear)` and at the
compact boundary. The checkpoint already refused a root symlink on write
([Root files are not followed through symlinks](2026-10-13-root-files-are-not-followed-through-symlinks.md)),
so here too the loader and the checkpoint disagreed about the same path. Found
by the commit security review of the legacy change.

## The decision

A root path that is a symlink, dangling or not, is a root file with no body,
the same refusal as at the legacy paths, in the same place in `handoff_frame`.

Shadowing: a symlinked root file does not shadow the legacy file beside it, so
a legacy body loads, noted as loaded from the legacy path, and no "ignored"
note is given. The alternative was to treat the link as a root file that
exists and so keep the legacy file out. That was not taken because shadowing
is the root file's body winning, and a refused file has no body to win with:
the loader's rule is per half "the root file when it has a body, else the
legacy file", and a link changes nothing about the else. It also matches the
next checkpoint, which refuses the root link naming the field before it
resolves either half, so no checkpoint ever acts on "a link shadows a legacy
file". As at the legacy paths, no loader note names the link; the checkpoint's
refusal is where it is reported.

## The change

`handoff_frame` drops a root argument that is a symlink before anything looks
at it, beside the legacy arguments, so both loaders are covered.

## Rows

Through `load-handoff.sh`: `TASK.md` and `TODO.md` each a symlink to a body
(red before: the linked body was the frame), both dangling (green before,
pinned), and a symlinked `TODO.md` beside a legacy todo body (red before: the
link's body won and the legacy file was reported ignored). Through
`load-compact.sh`: `TODO.md` and `TASK.md` each a symlink to a body (red before:
re-injected), both dangling (green before, pinned). Mutations: dropping the
task refusal reds the two `TASK.md` rows; dropping the todo refusal reds the
three `TODO.md` rows.

## Audit of the sibling reads

Reads and writes in `scripts/` and `bin/` that still follow a symlink, found by
grep and not changed here:

- `.claude/autodrive` is tested with `-f` and read by `handoff_drive_read`
  (`< "$file"`) in both loaders, `drive-take.sh`, `report-drive-failure.sh` and
  `bin/handoff-approved`. A link there (made through Bash, or force-added past
  the `.claude/autodrive*` ignore) is parsed through; a target that does not
  parse is reported with `DRIVE_ERR`, which quotes line 1 verbatim, so the
  first line of the linked file reaches the `systemMessage`. `rm -f` then
  removes the link, not the target. `checkpoint.py` writes the sentinel with
  `Path.write_text`, which writes through a link there.
- `.claude/autodrive.failed`: `head -n1` follows a link, and that line goes to
  both channels of `report-drive-failure.sh` as the failure reason.
- The drift marker, `$HANDOFF_POINTER_DIR/handoff-drift-<session id>` under
  the shared `/tmp/claude`, is read and written with redirections that follow a
  link another local user could plant.
- `handoff_drive_arm` writes `"$1.arming.$$"`, a predictable name, with `>`,
  which follows a link planted at it.
- `handoff_owner_live` `stat`s through a link; it reads an mtime only.
