# The drift note quotes its paths

2026-10-13.

## The defect

A security review of the drift report in `report-drive-failure.sh` found that
it spelled the hook input's `.cwd` into the `systemMessage` and the
`additionalContext` verbatim. The cwd is any string a directory can be named,
and the session can be moved into a directory it did not create (a clone, an
extracted archive). A name holding a newline put a line of the attacker's
choosing into harness text the agent reads as instructions; an escape sequence
reached the user's terminal through the `systemMessage`; a backtick could close
a code span the text sat in.

## The decision

Render both paths as quoted data, not as prose: bash's `printf %q`, a builtin,
one line whatever the input. A newline, an escape byte or any other control
character comes out in `$'…'` form and a backtick is backslash-escaped, while a
plain path prints unchanged, so the ordinary note reads as before. A
jq-escaped string was weighed and not taken: JSON escaping leaves a backtick as
it is. The project root is quoted too, though it is the launch directory and
not the hook input: the note's two paths share one rendering.

The marker still holds the whole raw cwd (NUL-terminated since
[No root passes through a capture](2026-10-13-no-root-passes-through-a-capture.md)),
so quoting changes what is shown and not what is compared.

## Residual

`%q`'s `$'…'` form for control characters is what this rests on. It is
verified on bash 5.2 here; macOS's bash 3.2 was not available to run, and the
rows would show a regression there as a raw byte in the note.

## Rows

Drift to a cwd holding a newline, an ESC sequence or backticks: both channels
carry the `%q` form and never the raw cwd, with no newline and no escape byte
past the leading style reset. Each was red before the change on the `%q`-form
assertion. A fourth row pins the ESC cwd as reported once.
