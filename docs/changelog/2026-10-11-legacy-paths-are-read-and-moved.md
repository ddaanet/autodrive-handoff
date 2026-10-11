# Legacy paths are read, and the checkpoint moves them (2026-10-11)

The release that moved the frame to `TASK.md` and `TODO.md` in the project root
was pulled from the marketplace because it had no upgrade path: the entry was
pinned back to the previous release. A repository upgraded across that line kept
its frame in `.claude/handoff-task.md` and `.claude/handoff-todo.md`, nothing
read those names, and the loader's report was `No task frame or todo.`, which
reads as an empty frame and not as a stranded one. [TASK.md and TODO.md move to
the root](2026-10-11-task-and-todo-move-to-the-root.md) had decided there would
be no migration code, on the ground that a user base of one moves two files by
hand and that a fallback would outlive the restart it covers. The first half did
not hold: the frame sits in every repository the plugin has run in, and each one
is moved only when someone next opens it, with nothing to say it needs moving.

My human partner's call: the loader reads both names, and the checkpoint
performs the migration. The fallback is a conditional bridge, not a permanent
feature, and the rest of this entry is what that sentence had to settle.

## Root wins

When a root file and its legacy file both exist, the root file is the frame.
The legacy file is never overwritten, merged or removed by a migration, and the
agent is told it is there: the loader's `additionalContext` and the checkpoint's
stdout each name it and say it is ignored. A project's own `TODO.md` makes the
case real, since that name is one a project may have used for years.

**Both ends decide by body.** The first draft of the checkpoint's contract said
the root file is current "whenever it exists", while the loader had always
decided by body, so a headings-only `TODO.md` beside a legacy list with a body
would have been ignored by the checkpoint and loaded from legacy by the loader.
Both now use `is_empty_body`, the loader's own predicate: a root file without a
body counts as absent. That is also what makes the loader's note true, that the
next checkpoint moves the legacy file, since a body-less root file is replaced
by the move.

**Shadowed is decided by existence, not body.** A legacy file that is a regular
file beside a root file with a body is reported ignored whatever it holds, even
zero bytes, because the note's job is to say that a file the agent may find on
disk is not part of the frame. A directory, or a symlink that points nowhere, is
not a file and gets no note. The note ends at "has a body." and gives no advice:
a sentence telling the agent to delete a file it did not write and was not asked
about would be self-authorising advice in a channel the agent obeys.

## The loader

`handoff_frame` takes the two legacy paths as optional third and fourth
arguments and sets four flags beside `FRAME_TASK` and `FRAME_TODO`: which
halves came from a legacy path and which have a legacy file shadowed by a root
one. `handoff_frame_notes` turns the flags into the notes, so the two loaders
and the two channels cannot word them differently, and appends them after the
frame and before the "No todo" gap note. The age in `load-handoff.sh` is taken
from the files that count, which now includes a legacy file when its half came
from it. `load-compact.sh` appends the same fragments to its one-line message,
so with no legacy file its bytes are unchanged. The no-legacy path spawns what
it spawned before: a shadowed legacy file is tested with `-f` and never sent to
Python.

The note for a todo loaded from legacy says to edit it there until the next
checkpoint moves it. Without that, an agent that follows the convention of
appending found work to `TODO.md` finds no such file, writes a new one, and the
one-item `TODO.md` now has a body and shadows the handed-over list, which is
still on disk and ignored.

## The checkpoint

Migration is part of plan resolution, so nothing moves unless both halves
resolve, and a rejected payload leaves legacy and root files byte-identical.
Each half's effective content is the root file when it has a body, else the
legacy file. Then, per action:

- `keep` on the todo moves a legacy file onto `TODO.md` with a rename, so the
  modification time is kept and the age the next loader reports stays true.
- `edit` applies to the effective content. Sourced from the legacy file, the
  result is written to `TODO.md` and the legacy file removed, which the report
  calls a move; the modification time is the write's.
- A content string replaces the effective content, so the legacy file's bytes
  are carried nowhere and it is reported removed.
- `clear` removes both files of the half, and says so.
- Any call after which the root file has no body while a legacy file exists
  removes the legacy file, because it would otherwise come back as the frame.
- A root file with a body before and after leaves the legacy file as it is and
  reports it ignored.

The task half is replaced, never moved: `handoff` writes it whole or clears it
and `precompact` removes it, so a legacy task file is always reported removed or
ignored. The loader's note for a task loaded from legacy still says the next
checkpoint moves it. For the task half, the checkpoint replaces it.

The root file is read only when a legacy file exists, so the path with no
legacy file is unchanged and keeps the FR4 property that `keep` neither reads
nor stats the todo file.

**Write before unlink.** The legacy file is taken off its path after the root
file is current, never before. If the root write fails the legacy list is still
on disk and the next load says so; the reverse order loses the list and the
next load says `No todo`.

**Two refusals, during resolution.** A directory at the root name leaves the
legacy file nowhere to go and is refused naming it. A legacy path that is a
symlink to a file is refused too: a rename moves the link, not its target, and a
relative target resolves differently from the root, so the move would leave a
dangling `TODO.md` and the next session `No todo`. A dangling symlink is no
legacy file at all, as for the loader. The symlink refusal runs ahead of the
root read, so it applies even when the root file has a body.

**Across devices.** `.claude` can be a symlink to another mount, where the
rename fails with `EXDEV` after the task half has already been applied, and
every later checkpoint that carries the legacy todo fails the same way until
someone moves it by hand. The move falls back to copying with its time and mode
to a temporary sibling in the root and renaming that onto the root name, so the
root file is whole or untouched. Any other failure in the move is an error that
names the legacy file. The write guarantee of the two halves is therefore about
payload failures: a failure in the filesystem itself, found while applying, can
still follow the task half having been applied, as two writes in a row could
always.

## One marker per language

The first draft said a single constant both the loader and the checkpoint read.
Python cannot read a bash constant and `checkpoint.py` already mirrored
`HANDOFF_REL_*`, so it is one name per language, `HANDOFF_LEGACY_REL_TASK` and
`HANDOFF_LEGACY_REL_TODO` in `scripts/_lib.sh` and again in
`scripts/checkpoint.py`, each commented as the other's mirror and each naming
the retirement condition.

What makes removal one pass is a word, not a constant: `grep -rni legacy
scripts/ tests/` lists the constants, the flags, the notes, the records and
every comment, and deleting only the constants would leave dead flags and note
loops behind. The grep is where the pass starts. A few pieces exist only for the
fallback and do not carry the word, the `Half` record, the `plans` list that
feeds the reports and the act, `Boundary` and the `move` member of
`FilePlan.act`, so the pass reads the code the grep lands in and not only the
lines it lists.

## Retirement is conditional

The fallback goes once no sibling repository still has
`.claude/handoff-*.md`. There is no tripwire and no version in code, docs or
tests: a version says nothing about which repositories still hold a frame under
the old names, and a tripwire that fires at a number would make a release the
moment a user's frame stops loading. `TODO.md` carries one item with the
condition and the check, an `ls` over the sibling repositories' `.claude/`
directories, and the deletion is the one pass above.

## No git work, and the act that stands in for it

The checkpoint renames and removes on the filesystem and does no git work
(NFR1). The 0.15 files were gitignored and force-added, so in most repositories
they are tracked, and a rename that git has not been told about is a deleted
file and an untracked one. Under `with-commit` the checkpoint prints one line,
ahead of the commit act, naming the legacy files this call moved or removed:

``Before committing, run `git rm --cached --ignore-unmatch -q -- :/<legacy
paths>`.``

It stages the deletion of a tracked old path, and once `TASK.md` and `TODO.md`
are added by the commit the request calls for, git records a rename. An
untracked legacy path is a no-op, and a file the call left in place, as ignored,
is never named.

**Why `:/`.** The first form was the bare relative path. A pathspec is
relative to the working directory, and the agent's Bash working directory
persists across calls and may be anywhere under the root; the plugin itself
resolves the root by walking up from it. Run from a subdirectory, the bare form
matched nothing, exited 0 and staged nothing, and `--ignore-unmatch -q` made the
miss invisible to everyone: the commit carried `TODO.md` as a new file and left
the old path in `HEAD` with an unstaged deletion behind it. `:/` is git's
top-level magic, so the line runs from any directory of the repository and
embeds no root, which is why a space or a newline in the root path needs no
quoting. `git -C <root> rm …` would have put the root on the line. The printed
line was run verbatim from a subdirectory of a root with a space in its path:
the tracked file came out staged as a deletion, and as a rename once the new
file was added.

**Where it prints.** The reports and the act lead the output, ahead of the
memory directive, and the closing line stays last. They also print ahead of the
clause-file refusal, which used to print alone. The move has already happened
on disk, and the refusal tells the agent to restart and retry; the retry finds
no legacy file and has nothing to print, so before the refusal is the only
place the act can be said.

**The consequence.** The act is owed only to the call that moved or removed a
file. A migration under `without-commit` followed by a `with-commit` call
leaves ` D .claude/handoff-todo.md` unstaged, because the second call has
nothing legacy to report. It shows in `git status`, a `git commit -a` takes it
and a commit of named files does not. Remembering across calls that a move
happened would take state the checkpoint does not keep, for a window one
migration wide.

## What stays visible

A repository that keeps a shadowed legacy file is told so at every startup,
every `clear` and every driven compact, and nothing clears the condition: the
note carries no advice to delete and the checkpoint leaves the file alone. This
repository is where it showed. The cost is one line a session in a repository
that chose to keep a second file. The alternative, deleting a file the root
file has not replaced the contents of, is the one outcome the settled rules
rule out.

## What was not touched

The release that carries this and the marketplace entry's pin and description
are separate requests. No other repository is migrated by this change, and
nothing here removes the fallback.
