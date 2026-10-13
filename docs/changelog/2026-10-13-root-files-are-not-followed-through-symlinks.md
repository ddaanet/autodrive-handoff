# Root files are not followed through symlinks

2026-10-13.

## The defect

`read_half` in `_checkpoint_plan.py` refused a symlink at the legacy path only.
A symlink at the root `TASK.md` or `TODO.md` was let through, and `apply_plan`
wrote with `Path.write_text`, which follows the link: the agent's content landed
in whatever file the link named, inside the project or outside it. A dangling
link had its target created. The checks that did exist ran during resolution
and the write came later, so even a refusal could not cover a link put at the
name between the two.

Three neighbouring paths broke FR2's contract, which is a non-zero exit naming
the field. With no legacy file, `read_half` returned before its directory test,
so a directory at a root name reached `write_text` or `unlink` and raised
`IsADirectoryError` as a traceback, exit 1. `edited_body` read the todo as
strict UTF-8, so a non-UTF-8 `TODO.md` under `edit` raised
`UnicodeDecodeError`, and an unreadable one `PermissionError`, both tracebacks.
`read_half` read the root file leniently when a legacy file existed, so a
non-UTF-8 file passed there, but an unreadable one raised as well.

## The decision

A symlink at a root name is not a legitimate setup. The two files are plain
tracked files of the project (FR4), and a link there would mean the checkpoint
writes somewhere it does not own.

## The change

- `read_half` checks the root name first, under every action and with or
  without a legacy file: a symlink, dangling or not, and a directory are each
  refused through `lib.err` naming the field, exit 2, before anything is
  written. `keep` is refused too, although it writes nothing, so the rule has
  one statement; it now looks at the name, but still does not read the file.
- Reads go through `read_strict` (the edit) and `read_lenient` (the body test
  beside a legacy file), which turn a decode failure or an `OSError` into
  `lib.err` naming the field. The body test stays lenient: a stray byte does not
  change whether a file has a body.
- A write goes through `write_replacing`: a sibling temporary file from
  `tempfile.mkstemp` in the same directory, given the mode of the regular file
  it replaces (else `0o666` under the umask, as a plain write had), then renamed
  onto the name with `os.replace`. The rename replaces a link at the name
  rather than following it, which closes the window between resolution and the
  write for the last component. `unlink` already removed the name itself.

## What it does not cover

The last component only. A root reached through a symlinked directory is
written where that directory lies, and the legacy paths are read and removed
through a symlinked `.claude/`. A write over a read-only root file now succeeds,
since the rename needs only the directory to be writable; the legacy test that
stood a mode-444 file in for a failing write now uses a mode-555 root directory.

## Tests

`tests/test_checkpoint_root_files.py` holds the rows with no legacy file: a
symlinked root file under each action, by a relative and an absolute link, with
the target's bytes asserted before the exit code; a dangling link; a directory
under each action; a non-UTF-8 and an unreadable todo under `edit`; the mode
kept by a write and the umask mode of a new file. `tests/test_checkpoint_legacy.py`
adds a symlinked root file beside a legacy file and an unreadable root todo
beside one. Every refusal row was red against the unchanged code. Mutation:
dropping the refusal reds the symlink rows on the exit code with the target
unchanged; dropping it and restoring `write_text` reds them on the target's
bytes; dropping the mode copy reds the mode rows.
