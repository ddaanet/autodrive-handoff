# A legacy symlink is not read

2026-10-13.

## The defect

`handoff_frame` tested and read the legacy `.claude/handoff-task.md` and
`.claude/handoff-todo.md` through `-f`, `_handoff_has_body` and `cat`, all of
which follow a symlink. A link at either legacy path made both loaders inject
whatever file it named as the task or the todo, and a link beside a root file
with a body was reported as an ignored legacy file. The checkpoint already
refused a legacy symlink to a file, naming the field, so the loader and the
checkpoint disagreed about the same path.

## The decision

A legacy path that is a symlink, dangling or not, is treated by both loaders as
a path that does not exist: it is neither tested for a body, nor read, nor
counted as shadowed, and no note names it.

The silent treatment was weighed against a note of its own. A note was not
taken because the loaders' channels say what the frame holds and where it came
from, and nothing came from the link; the one actor that can act on the link is
the checkpoint, which refuses a legacy symlink to a file naming the field, so
the user hears of it at the next checkpoint, the moment the bridge would
otherwise move it. A dangling link holds nothing to lose, and the checkpoint
already reads it as no legacy file. So every link is reported by exactly one
writer, as before, and no loader invents a second wording for it.

## The change

`handoff_frame` drops a legacy argument that is a symlink before anything looks
at it, so the refusal covers `handoff_frame`, `load-handoff.sh` and
`load-compact.sh` in one place. Root files keep their own path through
`_handoff_has_body`.

## Rows

Red before the change on an assertion: legacy symlinks to bodies are not read
(`handoff_frame` returned 0 with both halves framed), a root file with a body
beside symlinked legacy files is not shadowed (the shadowed flags were 1),
`load-handoff.sh` with symlinked legacy files and no root file says
`No task frame or todo.` on both channels, and `load-compact.sh` with a
symlinked legacy todo says `No todo` and injects nothing. Dangling-link rows for
`handoff_frame` and `load-handoff.sh` were green before the change, since `-f`
already fails on a dangling link; they pin the behaviour and do not
discriminate. Mutations: dropping the todo half's refusal reds four rows,
dropping the task half's reds three.
