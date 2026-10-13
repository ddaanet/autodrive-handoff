# The unstage line runs from the root (2026-10-13)

[The git line names paths from the top](2026-10-12-the-git-line-names-paths-from-the-top.md)
made the `git rm --cached` line that the checkpoint prints under `with-commit`
read ``:/<prefix><path>``, the root's path below the top of its repository
ahead of each legacy path, from `repo_prefix(root)`. A security review of that
commit found the form unsafe, and a probe found the prefix query unsafe too.

## What was wrong

`shlex.quote` protects the line from the shell and from nothing else. Git still
parses every argument as a pathspec, and the prefix is the name of the root's
own directory, which the user chose.

- A root named with `*`, `?` or `[` is a glob. Under a root `a*b`, the pathspec
  `:/a*b/.claude/handoff-todo.md` also matches `a b/.claude/handoff-todo.md`
  and `aXb/.claude/handoff-todo.md`, so the line unstaged a sibling directory's
  legacy file along with the root's.
- A root named with a leading `!` or `^` extends the `:/` short form into
  top-plus-exclude magic. `:/!x/.claude/handoff-todo.md` is not a path under
  `!x` and git died with `fatal: not removing '.' recursively without -r`.
- `--ignore-unmatch -q` hides both: a pathspec that matches nothing, or too
  much, exits quietly, and the commit the directive asks for next carries the
  wrong deletions.

A separate defect: `repo_prefix` swallowed its own failures. A missing `git`
raised, and exit 128 returned an empty prefix and so a wrong pathspec, silently.
The query existed only to find where the root lies below the top of its
repository.

## The probe

Run with git 2.47.3 in throwaway repositories, first with `--literal-pathspecs`
ahead of `-C` (see below for why it was dropped). The line

    git -C <root> rm --cached --ignore-unmatch -q -- <path> …

with `<root>` the absolute root and each `<path>` relative to it, unstaged
exactly the root's own legacy file and left every sibling's tracked, for a root
at the top of its repository, a subdirectory (`pkg`, `pkg dir`), a submodule
root, roots named `!x`, `^x`, `a*b`, `a?b` and `a[1]` (siblings `other`, `a b`,
`aXb`, `zzb`, `a1`), a root holding a newline, and run from `/`. Outside a
repository it exits 128 with `not a git repository`, loudly. The `:/` form on
`a*b` also unstaged the sibling `a b`, and on `!x` died as above.

## The choice

`git -C <root>` puts the root in a directory change, which is a path, not a
pathspec, so no character of its name is magic. The legacy paths are then
relative to it, which is the form the reports already use, so the line needs no
top-of-repository rewriting, no `repo_prefix` and no query at all: it runs from
any directory, the agent's own working directory included.

The first form of this line also carried `--literal-pathspecs`, a global option
that goes ahead of `-C`, to have git read each remaining path as a name. Writing
the tests showed it changes nothing observable: the paths are the two fixed
names `.claude/handoff-task.md` and `.claude/handoff-todo.md`, neither holds a
character git reads as magic, and with the root moved into `-C` no root name
reaches a pathspec. The rows over magic-named roots passed with it dropped, and
only the rows that pinned the printed text went red. It was probed and found
inert, and dropped.

Every argument is `shlex.quote`d. A newline in the root still splits the printed
line, as it did before this change under `git -C` and under a newline in the
prefix. That is a bound stated and not handled, and a separate item covers the
root path reaching a markdown code span.

## What was removed

`repo_prefix`, the prefix plumbing through `compose_directives`, and the rewrite
of the legacy paths that prefixed them. `legacy_unstage_directive` and
`commit_directive` now take the root. The reports keep naming the paths relative
to the root, and so does the git act: nothing names a path from the top of the
repository any more.

The `:(top,literal)<prefix><path>` variant was weighed and rejected: it closes
the pathspec hazard but still needs the prefix query, whose failure modes are
silent.

## The tests

`test_printed_git_act_unstages_only_the_roots_own_legacy_file` replaces the
two-row `pkg` test. Over a real repository with a tracked legacy todo in the
root and in every sibling, it runs the printed command exactly as printed
through a shell from a directory of the repository and from one outside it, for
roots at the top, below it, with a space, and named `!x`, `^x`, `a*b`, `a?b` and
`a[1]` (siblings sorting on both sides of `a*b`). It asserts the root's own file
left the index and no sibling's did. Against the previous source the magic rows
failed by assertion, a sibling unstaged or the root's file left in place.

Mutation-checked: dropping `-C` reds every row; dropping the quoting reds the
spaced and the glob roots. The magic-named roots stay as the proof that the line
needs no literal-pathspec option.
