# TASK.md and TODO.md move to the root (2026-10-11)

The task frame lived in two gitignored, force-added files under `.claude/`,
and five mechanisms kept them honest: a write guard on the task file, a
`PostToolUse(Write|Edit)` stager for the todo file, a manifest plus a
`PostToolUse(Bash)` stager for what the checkpoint wrote, and an empty-body
rule that two writers enforced. My human partner's call was that this
machinery guarded a distinction that does not exist. The todo file is a
pending-work list like any project's `TODO.md`. The task file is authored whole
by one checkpoint call, and that already gives it everything the guard was
for.

A second fact arrived with the first. The task file had stopped being a
pointer. Over the 441 versions written across nineteen repositories since the
todo file existed, the median body was 872 characters and the 90th percentile
2529. A reader labelled every sentence of those versions by what it was, and
one character in five described the task in hand. The rest was the plan still
to execute and open decisions (36%), what had already been done (27%), and
standing rules and conventions (17%). Each of those has a home that is not the
task file. The measurements are in
`plans/2026-10-11-task-and-todo-move-to-root/reports/`.

## Two plain files

The frame is `TASK.md` and `TODO.md` in the project root, tracked like any
other file. Nothing is gitignored, so nothing needs `git add -f`, and the hooks
that existed to run it are gone: `write-stage.sh`, `bash-post.sh` and the
manifest between the checkpoint and the second of them. The checkpoint still
does no git work. Under `with-commit` the commit act it prints names the two
files, because nothing has staged them; under `without-commit` they are left
modified in the tree, the way any edited file is.

A project that already has a `TODO.md` shares it with the plugin. That
collision is intended: it is the same list. A whole-content `todo` write
replaces the file, which was injected at session start and is tracked, so the
write is informed and recoverable. The skill tells the agent that a list
already in another shape keeps its shape.

The write guard keeps one file, `.claude/autodrive`. The sentinel's state is
content, so a wrong one is writable, and it runs commands at the end of the
turn. The task file is a different case. A direct edit of `TASK.md` changes a
note the next session reads, which is what editing `TODO.md` has always done.

A dirty `TASK.md` or `TODO.md` now refuses a release, where the toolkit used
to exempt everything under `.claude/`. That is accepted: the two files are
part of the tree.

## Only `clear` removes

The checkpoint used to remove a file whose body was empty once headings and
blank lines were set aside, and `write-stage.sh` did the same after a direct
edit, so that a file present meant content pending. With no hook watching
direct edits, one writer cannot hold that invariant alone, and a `TODO.md`
somebody else keeps is not the checkpoint's to delete for being empty. A
content string is written as given. `{"action": "clear"}` removes, and so does
the compact boundary for the task file.

The emptiness rule moves to the reader. `handoff_frame` counts a file only
when it has a body, by the same `is_empty_body` the checkpoint used, so a
headings-only file is not injected. `SessionStart` says what it found instead
of staying silent: `No task frame`, `No todo`, or `No task frame or todo.`,
to the user and to the agent. A silent loader could not be told apart from one
that never ran.

## The compact boundary drops the task

[One task file, two transitions](2026-07-20-one-task-file-two-transitions.md)
gave `precompact` a task file because the first driven compaction had nowhere
durable to put a commit range and a checklist, and crammed both into the
continuation prompt. The todo file did not exist yet. It arrived two days
later, and it is where a checklist belongs; the `compact` focus directive
tells the summariser what to keep. Meanwhile the task snapshot written before
a compaction sat on disk as a second account of the task, beside the summary,
and was re-injected at the next session start after the work had moved on.

`task` is now forbidden under `precompact`, by key presence like `rename`,
and the checkpoint removes `TASK.md` at that boundary so a stale one cannot
contradict the summary. What must survive verbatim goes in `TODO.md` or in the
focus directive.

## The task is bounded

A `task` content string is rejected when its body runs over 1000 characters,
headings not counted, or when any line opens a list item. The error names the
count or the line and says where the rest goes: remaining steps and open
decisions to the todo, finished work cut to one sentence, standing rules and
conventions to memory through its approval gate.

The cap was not set from how often task files exceeded it. That measures the
symptom, and it moved between 14% and 43% depending on which versions were
counted. It was set from what is left of a task file once its overflow is sent
where it belongs: the task in hand plus one sentence of what was just done has
a median of 354 characters and a 95th percentile of 867. 1000 is the first
round number above that. Sixteen of the 441 versions would still be over it
after the move, and those are the ones the rule is for.

The list rule catches what the cap does not: a short task file that carries
its steps as bullets. A list in the task file is a todo list in the wrong
file.

This reverses a non-goal. The checkpoint validated the JSON envelope and
trusted the markdown inside it. It now checks two properties of the task's
markdown, because the template's "usually one sentence" was advice, and advice
is what the survey measured failing.

## What was decided without being asked

> **Superseded 2026-10-11** (see [Legacy paths are read, and the checkpoint
> moves them](2026-10-11-legacy-paths-are-read-and-moved.md)): item 5 only.
> There is a fallback read of the old paths, and the checkpoint moves the
> files; it is retired by a condition, not a version. Items 1 to 4 and 6 stand.

My human partner settled the points above in conversation. Six more were
taken as defaults, written out, and confirmed together.

1. The `autodrive` guard stays, for the reason given above.
2. Checkpoint staging goes with the rest. Staging the todo file from a hook
   and the task file from a manifest were one decision.
3. The checkpoint stops deleting on an empty body.
4. A foreign `TODO.md` gets no protection beyond the skill's one line.
5. There is no migration code. A user base of one moves two files with `git
   mv`; a fallback read of the old paths would outlive the one restart it
   covers.
6. The empty-frame report comes from `load-handoff.sh` alone. `load-compact.sh`
   stays silent when no compaction was prepared, and after a prepared one says
   `todo re-injected` or `No todo`.

## Moving an existing frame

> **Superseded 2026-10-11** (see [Legacy paths are read, and the checkpoint
> moves them](2026-10-11-legacy-paths-are-read-and-moved.md)): the loader
> reads the old paths when the root file has no body, and the next checkpoint
> moves them. The two `git mv` lines remain the manual route.

```
git mv .claude/handoff-task.md TASK.md
git mv .claude/handoff-todo.md TODO.md
```

Nothing reads the old paths. A frame left there is not injected, and the
loader reports `No task frame or todo.`
