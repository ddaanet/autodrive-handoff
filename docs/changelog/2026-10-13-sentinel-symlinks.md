# The sentinel and its siblings follow no link

2026-10-13.

## The defect

[A root symlink is not read](2026-10-13-a-root-symlink-is-not-read.md) closed
the frame files and listed what was still open around `.claude/autodrive`:

- every reader of the sentinel (both loaders, `drive-take.sh`, the
  `UserPromptSubmit` sweep, `handoff-approved`) tested it with `-f` and read
  it with `<`, both of which follow a link, so a repository could commit
  `.claude/autodrive -> /any/readable/file` and have that file parsed, its
  first line quoted into a malformed report, its lines offered to the user to
  type, or rewritten on arming;
- `checkpoint.py` wrote the sentinel with `write_text`, through a link;
- `report-drive-failure.sh` read `.claude/autodrive.failed` with `head -n1`,
  through a link, onto both channels;
- the drift marker, `handoff-drift-<session>` in the shared `/tmp/claude`, was
  read and written through whatever another local user put at that name, and
  in a directory that user might own;
- `handoff_drive_arm` wrote a temporary file at `<sentinel>.arming.$$`, a name a
  repository can commit links at, and renamed it with `mv`, which moves a file
  *into* a directory a link at the destination names.

Three background security reviews of the commits that fixed those added three
more: a test-then-read on the failure record, the sweep record and the
sentinel left a window where a link put at the name between the two steps
was followed; the marker directory was created with the umask's mode and used
whoever could write it; and `python3 -c` puts the working directory first on
`sys.path` in a hook that runs inside a repository.

## The decision

One rule for every name under `.claude/autodrive*` and the marker: **the check
and the use are one system call**.

- Reading is `handoff_read_regular` in `_lib.sh`: one `open(2)` with
  `O_NOFOLLOW | O_NONBLOCK`, then `fstat` for a regular file (and, for the
  marker, this user's), printing a status line and then the bytes on one
  stream. No link put at the name at any moment is read, and a FIFO does not
  hang the hook. `handoff_drive_read` reads through it, so all five readers
  and the checkpoint's read-back refuse a link with one `DRIVE_ERR` and take
  their malformed path, whose `rm -f` removes the link and not its target.
  Callers gate on `-L || -f`, so a dangling link is refused and removed too,
  rather than read as no file and left for ever. The sweep records it as its
  own `link` state and offers no lines.
- Writing is a `mktemp` file beside the name, renamed over it with
  `os.replace` (`handoff_replace`, or `write_replacing` in the checkpoint):
  rename(2) replaces a link rather than following it. `mv` is not used,
  because it stats its destination.
- A link at `.claude/autodrive.failed` is no rejection the mod observed: it is
  removed unread and named on both channels, and a `pending` sentinel is not
  cleared on its account.
- The marker directory is created `0700` and used only when it is no link, is
  this user's and is writable by no one else; otherwise there is no marker and
  drift is reported every turn rather than once. Noisy, never silent.
- Every `python3 -c` in a hook or `bin/` runs `-I`. No planted module was
  loaded by the current one-liners on Python 3.14 (every module they import
  is built in or already imported at startup), so this is hardening, pinned
  by a row that fails on any `python3 -c` without it.

## What is not covered

The check is on the last component only, as it is for the root and legacy
files: a symlinked `.claude/` is read and written where it points. Refusing it
would break every user who links `.claude/` from a dotfiles tree, and is left
as an open decision. A `session_id` holding `/` would still place the marker
outside the pointer directory; session ids are harness-generated UUIDs.

The race rows plant the link from a stub of the command a hook runs between
its look and its use (`date` in the sweep record, `head` for the failure
record, `tail` in the arm). The sentinel reader had no such command between
its `-L` test and its read, so its race has no row of its own: the
`handoff_read_regular` rows pin the no-follow open, and the link rows pin each
caller.
