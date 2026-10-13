# The write path

Part of [handoff — Design](../design.md).

## The seam

`TASK.md` and `TODO.md`, in the project root, are the durable side. Both are
plain tracked files: nothing is gitignored, nothing is force-added, and no hook
stages them. Both are injected verbatim at `SessionStart`, task first, under
one timestamp header — the *frame*, assembled in memory by `handoff_frame()`
in `scripts/_lib.sh` and shared by the two loaders so the two transitions
cannot drift.

- **`TASK.md`** — `## Current task` alone: the task in hand and where it
  stands, as prose. Authored whole by the checkpoint at the clear boundary and
  removed by it at the compact boundary, where the summary carries the task. A
  snapshot of a moment.
- **`TODO.md`** — `## Open decisions` when any remain, plus `## Remaining`,
  open items only. A scratch list the agent edits directly all session; the
  wrap-up only folds in the final remainder. A ledger, not a snapshot — open
  decisions live here rather than in the task file because they get revisited
  and resolved mid-session, same as any other open item. A project that
  already keeps a `TODO.md` shares it with the plugin, and a list already in
  another shape keeps its shape.

The frame carries no session id, no transcript, no file list, and no
commit/push status. The working set comes from the harness's own
`gitStatus` block at load time.

A file is part of the frame only when it has a body: something left once
blank lines and ATX headings are taken out, a heading being markdown's own —
so a shebang, a `#tag`, or a `# comment` inside an indented code block are all
content, and a line of spaces is not. The rule is `is_empty_body` in
`_checkpoint_lib.py`, reached from `handoff_frame()` through its
`--has-body` CLI, which answers a body with exit 0: an uncaught exception exits
1 and a library `python3` cannot open exits 2, so a check that crashes or never
ran counts as no body rather than injecting a file on its account. `load-handoff.sh` says what it found on both channels —
`No task frame`, `No todo`, or `No task frame or todo.` — because a loader
that stays silent on an empty frame cannot be told apart from one that never
ran.
[A heading is not a leading `#`](../changelog/2026-09-14-a-heading-is-not-a-leading-hash.md),
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

The two files lived at `.claude/handoff-task.md` and `.claude/handoff-todo.md`
before they moved to the root, and a repository that crossed the move still has
them. They are the *legacy* files, and the frame reads them as a bridge: per
half, the root file when it has a body, else the legacy file when it has a
body. The root file wins, and a legacy file that exists beside a root file with
a body, whatever it holds, is left as it is and reported ignored. A legacy
path that is a symlink is treated as absent by the loaders, neither read nor
reported ignored: the checkpoint refuses one naming the field, which is where
it is reported. The loader
names a half read from a legacy path and a legacy file left ignored on both
channels, from one producer, `handoff_frame_notes`, so the two channels and the
two loaders word them alike; the note carries a fact, and no advice to delete.
A todo read from a legacy path is told to be edited there until the checkpoint
moves it, since a new `TODO.md` written first would shadow the list the session
inherited. What a legacy file is, and when the bridge goes, is argued in
[Design decisions](decisions.md).
[Legacy paths are read, and the checkpoint moves them](../changelog/2026-10-11-legacy-paths-are-read-and-moved.md)

## One channel, one writer

Both wrap-up skills decide their content and then make exactly one Bash
call: `handoff-checkpoint`, a PATH-resident shim (`bin/`) over
`scripts/checkpoint.py`, taking the whole wrap-up as a schema-validated
JSON payload on stdin — `skill`, `commit`, the boundary's transition field,
`continue`, `rename` at the clear boundary, and `task` / `todo` as a tagged
union: the file's content directly as a string, or an object naming an
action. `task` takes `{"action": "clear"}`; `todo` also takes
`{"action": "keep"}` and `{"action": "edit", "old_string": …,
"new_string": …}`. The task file is authored whole, so it has no edit
action, and no keep — a clear boundary with nothing to carry says so with
`clear`, which is the case an agent used to reach for `null` and get
silence. At the compact boundary `task` is forbidden by key presence, like
`rename`, and the checkpoint removes the file. Where a key is taken it is
required by key presence: `null` and an absent key
are each a named error, because a spelling that quietly does the wrong
thing is the defect this shape exists to prevent — a wrong one has to fail
loudly rather than acquire a meaning. The action object holds to the same
rule inside itself: its own `action` is read by key presence, so an explicit
`null` is reported as the value it is rather than as an omission, and any key
the named action does not take is a named error rather than a silent
discard. Ignoring one reopens the defect one level down — an agent told
`must be "clear", got "write"` that corrects only the action leaves its
`content` in place, and the frame is removed with nothing said. The payload's
own key set is closed the same way, a level up: a key outside the union any
skill takes is named rather than discarded, since a *misspelled required* key
already fails by key presence while a *superfluous* one — `tasks` beside a
well-formed `task` and `todo` — did not. That check is flat rather than
per-skill, because every known key under a skill that forbids it is already
rejected upstream by a message naming the skill or the transition, and a
per-skill check has no point to run but ahead of those, where it would
replace their wording with a generic one. What is left for it is a key
belonging to no skill's vocabulary, which has nothing skill-specific to say
about it. The two
`required` messages name the whole vocabulary for the same reason: that
branch is what an out-of-date producer sending the retired
`{"file_path": …, "content": …}` shape lands on, so it has to say what to
write instead. There is no `file_path` —
`plan_task`/`plan_todo` compose the real path from `HANDOFF_ROOT`, so a
payload-supplied one would ask the agent to derive a path from a root it
cannot read, only to be checked against the one the write uses anyway. A
violation exits non-zero naming the offending field. The wrap-up is applied
whole or not at all: both halves resolve to a plan — the path, the act, the
body and what becomes of the half's legacy file — before either file is
touched, so every failure the payload and the files can raise leaves the disk
as it was. A failure of the filesystem itself, found while a plan is applied,
is the one thing resolution cannot see: it can follow the first half having
been applied, as two writes in a row always could.
[The payload names its actions](../changelog/2026-09-07-the-payload-names-its-actions.md),
[Nothing is written until both halves resolve](../changelog/2026-09-13-nothing-is-written-until-both-halves-resolve.md),
[The vocabulary is closed at both levels](../changelog/2026-09-14-the-vocabulary-is-closed-at-both-levels.md)

It gets its root from `HANDOFF_ROOT`, injected into the command's
environment by a `PreToolUse(Bash)` hook (`inject-checkpoint-root.sh`) that
matches any command containing `handoff-checkpoint` or `handoff-approved`,
resolves the root fresh from the payload `cwd`, and rewrites the command to
`export HANDOFF_ROOT=<quoted>; <original>` via `updatedInput` — `export …;`
rather than a bare `VAR=…` prefix, so the value survives a batched command.
The checkpoint refuses when it is unset or not a directory, naming the
unrecognised-invocation cause. Resolving on every call, at the moment the
value is used, replaces an earlier session-keyed pointer file sampled once at
`SessionStart`: `SessionStart(resume)` fires with the *resuming* process's
cwd, before the harness moves the session into its own project dir, so a
sample taken there could stamp the wrong repo onto a pointer read later in
the same session. See
[`docs/changelog/2026-08-10-checkpoint-root-via-updatedinput.md`](../changelog/2026-08-10-checkpoint-root-via-updatedinput.md).

The checkpoint applies the writes, composes `.claude/autodrive` from the
transition fields — creating `.claude/` when the project has none, the
sentinel being the one thing left that needs it — and prints on stdout what
the agent does next (see [What the checkpoint
prints](the-checkpoint-directive.md#what-the-checkpoint-prints)). A content
string is written as given, whatever is in it; a root file is removed by
`{"action": "clear"}` and, for the task file, by the compact boundary, and by
nothing else. An empty `TODO.md` somebody keeps for another purpose is not the
checkpoint's to delete.

What the call does to a half's legacy file is decided in the same plan, by one
rule. The effective content of a half is the root file when it has a body,
else the legacy file. A root file with a body before the call and after it is
the frame, and the legacy file stays and is reported ignored. In any other
case the legacy file goes, because it would otherwise come back as the frame:
`keep` on the todo renames it onto `TODO.md`, keeping its modification time
(across devices, by a copy to a sibling temporary file and a rename onto the
root name); `edit` applies to the effective content and writes the result;
a content string replaces it; `clear` removes both files. The task file is
never moved, only replaced or removed, since the checkpoint always authors it
whole or clears it. The root file is read only when a legacy file exists. A
legacy path that is a symlink to a file is refused during resolution, naming
the field, since its relative target would dangle once moved. A dangling
symlink is no legacy file. The legacy file is taken off its path after the root
file is written, never before, so a failed write loses nothing.
[Legacy paths are read, and the checkpoint moves them](../changelog/2026-10-11-legacy-paths-are-read-and-moved.md)

What sits at a root name is checked during resolution, under every action,
`keep` included, and with or without a legacy file: a symbolic link there is
refused, since a write would follow it to a file the checkpoint does not own,
and so is a directory, which no write, removal or move can land on. A root file
the call has to read and cannot, unreadable or, for an `edit`, not valid UTF-8,
is refused the same way. Each refusal names the field and exits 2 with nothing
written. A write then lands through a sibling temporary file renamed onto the
root name, which replaces whatever is there, a link included, rather than
writing through it, and keeps the mode of the regular file it replaces; a
removal unlinks the name itself. So a link put at the name between resolution
and the write is replaced, not followed. The bound is the last component: a
root reached through a symlinked directory is written where that directory
lies, and the legacy paths are read through a symlinked `.claude/`.
[Root files are not followed through symlinks](../changelog/2026-10-13-root-files-are-not-followed-through-symlinks.md)

It **changes no git state** — it queries git read-only and stops there: it
runs in the agent's sandboxed Bash, where `git add` can leave
`.git/index.lock` behind and fail the *next* command (which in the routine
wrap-up is the user's `/commit`). Nothing else stages on its behalf. Moving or
removing a legacy file is a filesystem act and stays inside that line. Under
`with-commit` the commit act the checkpoint prints names the two files, and
leads with one line for the legacy paths this call moved or removed, `git
-C <root> rm --cached --ignore-unmatch -q -- <path> …`, so
git records a rename once the files are added. The agent's working directory can
be anywhere, and a bare relative path matched nothing from a subdirectory,
silently, so `-C` names the root and each `<path>` is relative to it, as the
reports name them. The line needs no query of where the root lies in its
repository, which a top-anchored form (`:/`) does, with failure modes git leaves
silent, and the root's name, a glob character or a leading `!` included, is a
directory change and never a pathspec; the legacy paths are fixed names with no
magic character, so no literal-pathspec option is printed. Every argument is shell-quoted; a newline in the root still splits the line. The
line is owed only by the call that moved or removed the file: under `without-commit`
nothing is printed and the files are left modified in the tree like any edited
file, and a `with-commit` call after it has no legacy file left to report, so
the deletion shows as unstaged in `git status`.

## The task is bounded

A `task` content string is rejected, before anything is written, when its
body runs over 1000 characters or when any line opens a list item (FR13). The
body is the content without its heading lines, stripped, counted in
characters. A list item is a line opening with `-`, `*`, `+` or a numbered
marker, then whitespace. One error carries whichever facts hold — the line
and its first words, the count against the limit — and then where the
overflow goes: remaining steps and open decisions to `todo`, finished work
cut to one sentence, standing rules and conventions to memory.

The rule exists because the task file had stopped being a pointer. Measured
over the versions written across nineteen repositories, one character in five
described the task in hand; the rest was a plan, a done-log, or working
conventions, each of which has a home. The list rule is the cap's complement:
a short task file that carries its steps as bullets is a todo list in the
wrong file, and no length catches it.
[The argument](decisions.md), [the measurements](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

## What is guarded

`write-guard.sh` (`PreToolUse(Write|Edit)`) denies a direct write to the
`autodrive` sentinel and to nothing else. The sentinel's state is content, so
a wrong one is writable, and what it holds is run as commands when the turn
ends. `TASK.md` and `TODO.md` are notes the next session reads, and a direct
edit of either is an ordinary edit.

The guard's negative path is one jq parse and a substring test on the path it
was given. Past that the verdict is never on the path as given. A trailing
slash, a `/.` and an `x/..` detour all normalise onto the sentinel under a
last component that is not its name; a JSON string may hold a newline that a
line-oriented read would cut the path at, which is why both fields are read
NUL-terminated; and resolving follows symlinks, so the sentinel's own
resolved name need not be `autodrive`. Three paths settle it: where the write
lands, where this project's sentinel lands, and the given path normalised
without following links. A write that lands on the sentinel is denied as
checkpoint-only. Anywhere else, a name of `autodrive` at either end is
another project's and is denied as a cross-project write. What the guard does
not catch is the sentinel reached by a path that does not mention its name —
through a symlink called something else, or a case variant on a
case-insensitive filesystem. Judging any one of the three paths alone lets
one of those spellings through, and each is a row in `tests/hook-test.bats`.

## The Python half

`checkpoint.py` and `_checkpoint_lib.py` are a 2026-08-10 Python port of what
was `checkpoint.sh` + `_checkpoint-lib.sh` (the walker that was ported with
them is gone: [Driving the transition](driving-the-transition.md)): both did
bash's worst work — structured data, not text streams — and both run once per
boundary, never on a hot path, so the interpreter-startup tax lands where it
is cheapest to pay. The hooks that fire on every tool call stay bash. See
[`docs/changelog/2026-08-10-python-split.md`](../changelog/2026-08-10-python-split.md).

The port is four modules. `checkpoint.py` runs the call in order, composes the
sentinel and orders the directives; `_checkpoint_payload.py` validates the
payload (FR2) and returns the transition and the two halves' actions, writing
nothing; `_checkpoint_plan.py` resolves each half to a plan, the legacy
migration included, and applies the plans; `_checkpoint_lib.py` holds what the
others import and the emptiness rule's CLI.
