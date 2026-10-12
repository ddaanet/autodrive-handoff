# The git line names paths from the top (2026-10-12)

[Legacy paths are read, and the checkpoint moves them](2026-10-11-legacy-paths-are-read-and-moved.md)
made the checkpoint print, under `with-commit`, one line for the legacy files it
moved or removed: ``git rm --cached --ignore-unmatch -q -- :/<path> …``. It
chose `:/` so the line would run from any directory of the repository. Review
found that the choice was only half made.

## What was wrong

`:/` anchors a pathspec at the top of the git repository. The paths after it
were written relative to `HANDOFF_ROOT`, which is the top of the repository only
when the project directory is. Where the project is a subdirectory of a larger
repository, the line named `:/.claude/handoff-todo.md` while the tracked file
was `:/pkg/.claude/handoff-todo.md`. The pathspec matched nothing, git exited 0,
and `--ignore-unmatch -q` kept the miss invisible to everyone: nothing was
staged, and the commit carried `TODO.md` as a new file and left the legacy file
tracked in `HEAD`. It is the failure the bare relative form had, moved from
"working directory below the root" to "root below the top". The tests ran from a
subdirectory of a root that was a repository top, so no row had a root below it.

## Where the prefix comes from

`repo_prefix(root)` runs `git -C <root> rev-parse --show-prefix` and returns what
git prints: the root's path below the top of its repository, ending in `/`. Git
is the authority on where its own top is, which a walk up the filesystem for a
`.git` would only approximate: it would have to reimplement worktrees, gitfiles,
`GIT_DIR` and submodules, each a place for the two answers to part. The
checkpoint already queries git read-only (the memory directive does), so this is
one more query of the same kind and NFR1 is unchanged in substance: no git state
changes.

`git -C <root> rm …` stays rejected. It would put the whole absolute root on
every such line, where `:/` plus the prefix puts nothing on it in the common
case and a short relative path in the other.

The prefix is `""` at the top, outside any repository, and when git fails, which
leaves the paths as the root has them. A root that is a submodule is the top of
its own repository, so its prefix is empty and the line is right for the
submodule's index, which is where that root's files are tracked.

## Only when the line is owed

`compose_directives` calls it when the call is `with-commit` and has a moved or
removed legacy file, and in no other call. Every other checkpoint spawns what it
spawned before. The prefix goes ahead of each path for the git line alone: the
`Legacy … moved/removed/ignored` report lines still name the path relative to
the root, since the agent reads them as files in the project.

## Quoting

A prefix can hold a space, and the line is meant to be run verbatim. Each
pathspec now goes through `shlex.quote`. A pathspec with no prefix,
`:/.claude/handoff-todo.md`, has no character that needs quoting, so the line
for a root that is the top of its repository is byte-identical to the one before
this change. A prefix with a space comes out single-quoted.

**Residual.** A newline in the prefix still splits the printed line, as a
newline in a root did under `git -C`. Quoting keeps it inside one shell word but
the line is printed as one line of a directive, and the docstring says so. It
is a bound stated and not a case handled.

## The test

`test_printed_git_act_reaches_a_root_below_the_top_of_its_repository` has two
rows, `pkg` and `pkg dir`. The root is a subdirectory of a repository, the
legacy todo is tracked, and the printed command, run through a shell exactly as
printed from another directory of the repository, takes the file out of the
index. `run_printed_git_rm` now hands the backticked command to `bash -c` as
printed instead of re-tokenising it, so the quoting is under test and not
bypassed.

Mutation-checked: dropping the prefix reds both rows; dropping the quoting reds
the spaced row alone; a bare pathspec in place of `:/` still reds the earlier
rows.
