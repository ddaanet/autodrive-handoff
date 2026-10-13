# The sweep record follows no link

2026-10-13.

## The defect

`record_sweep` in `report-drive-failure.sh` read the old record with
`cat "$swept"` and built the new one in `"$swept.tmp"`, both under `.claude/`,
a directory the agent writes freely. A symlink at `.claude/autodrive.swept`
was read through, copying whatever it named into the record (and into the top
50 lines the agent may later read), and then replaced by the rename. A symlink
at `.claude/autodrive.swept.tmp` was written through: the record's bytes landed
in whatever file it named.

## The change

- A record that is a symlink, or exists and is not a regular file, is left
  alone and nothing is recorded. The sweep goes on; the record is a
  diagnostic, and a failure to keep it was already never the sweep's failure.
- The new record is built in a file `mktemp` creates beside the record,
  `autodrive.swept.XXXXXX`, so no fixed name exists for a link to sit at, and
  the `autodrive.` prefix keeps an orphan under the `.claude/autodrive*`
  ignore. A failed `mktemp` records nothing; a failed rename removes the
  temporary file.
- Every step stays guarded, since the function runs under `set -e`.

A link planted between the `-L` test and the read is a race this does not
close; the window is one shell builtin wide, and the record is a diagnostic.

## Rows

Red before the change on an assertion: a symlinked record (the link was
replaced by a regular file), a symlink at the old `.tmp` name (the decoy it
named was overwritten). Added green and pinned by mutation: `mktemp` failing
(dropping its `|| return 0` exits the hook before the sweep reports), no
temporary file left behind, and the directory-at-the-record row now asserting
nothing was moved into it. Mutations: dropping the `-L` test reds the symlinked
record row; going back to the fixed `.tmp` name reds the planted-link row.
