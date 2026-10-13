# A crashed body check is no body

2026-10-13.

## The defect

`_handoff_has_body` in `_lib.sh` asked `_checkpoint_lib.py --is-empty-body`
whether a file had a body, and read exit 1 as "it has one". Exit 1 is also what
Python itself returns for an uncaught exception, at import or anywhere after,
so a library that crashed — a syntax error left by an edit, a missing stdlib
module, a bug in `is_empty_body` — answered "has a body" for every file it was
asked about. The loader then injected the file, legacy fallback included,
because a check had failed to run. The bash side's own comment said anything
other than exit 1 was not evidence of a body, and it already treated 2 (an
unknown invocation, or a library `python3` cannot open) that way; it could not
tell a crash's 1 from the CLI's.

## The decision

Give the body the one status no failure produces: exit 0. A crash, wherever it
happens, exits 1; a library that cannot be opened exits 2; only a run that got
to the end and found a body exits 0. Catching exceptions inside `_cli` and
exiting 2 was weighed and not taken: it does not cover a crash at import, which
is exactly the case an edit to the library produces.

Inverting the status inverts the flag's sense, so the flag is renamed:
`--is-empty-body` exiting 0 for a body would read backwards. `--has-body` exits
0 for a body, 1 when empty and 2 on an unknown invocation, `--is-empty-body`
included.

## The change

- `_checkpoint_lib.py`: `_cli` answers `--has-body` with 0 for a body and 1 for
  an empty file.
- `_lib.sh`: `_handoff_has_body` is the CLI's status, with no translation.
- Rows: a stub library that raises at import is no body
  (`tests/hook-test.bats`), red before the change on `rc` being 0; the stub rows
  that pinned exit 1 as the body status now pin 0, and exit 1 as empty; the
  "library missing" row stubs the body status before removing the library, so
  the removal is what it measures; the CLI's exit codes in
  `tests/test_checkpoint_writes.py`, the retired flag among the unknown ones.
- Mutation: reading exit 1 as a body again (`|| (( $? == 1 ))`) reds the crash
  row and the exits-1 row.
