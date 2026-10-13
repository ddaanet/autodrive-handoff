# A root path that cannot be printed

The unstage act (`git -C <root> rm --cached --ignore-unmatch -q -- <path> …`)
spells the root into a backtick code span on one line. `shlex.quote` protects
the shell, not the directive: a directory name holding a backtick ends the span
early, and one holding a newline, carriage return, escape or DEL splits or
rewrites the line, leaving the text after it for the agent to read as a further
instruction. The old docstring noted the newline case and left it.

## Decision

When the root matches a backtick or any control character (`\x00`-`\x1f`,
`\x7f`), `legacy_unstage_directive` prints one sentence instead of the act:
the project path holds a character that cannot be printed safely, and the
legacy files are to be unstaged by hand with `git rm --cached` from the project
root. It echoes nothing of the path.

Weighed and rejected: an act that drops `-C` and relies on the working
directory. The agent's cwd is not the root's, which is what `-C` was introduced
to settle (see `2026-10-13-the-unstage-line-runs-from-the-root.md`). Escaping the
characters inside the span has no form a code span can carry.

Output for every other root, spaced and glob-named ones included, is
unchanged. The rows are in `tests/test_checkpoint_legacy.py`: one root per
character class asserting the path text is absent, the sentence present once
and the closing line last, and a spaced root keeping the act.
