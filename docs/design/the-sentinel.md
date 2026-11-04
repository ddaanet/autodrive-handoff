# The sentinel

Part of [handoff — Design](../design.md).

The dated records named here are in the `changelog-archive` tag's
`docs/changelog/`.

`.claude/autodrive` is the one file that says which transition the plugin
carries out when the turn ends. [Driving the transition](driving-the-transition.md)
runs it; this node is what the file holds, and the bound on what holding it can
make the mod do.

## The kinds

The file holds data only: a kind, a flag and at most one argument. Line 1 is
the state ([below](#the-states)), line 2 the kind, and line 3 the argument
where the kind takes one.

| kind | line 2 | line 3 | the mod runs | confirming source |
|---|---|---|---|---|
| `rename` | `rename` | the title, required | `/rename <title>` | — |
| `clear` | `clear`, or `clear continue` | the title, required | `/rename <title>`, `/clear`, then the continuation if flagged | `clear` |
| `compact` | `compact`, or `compact continue` | the focus, optional | `/compact [focus]`, then the continuation if flagged | `compact` |
| `prepare` | `prepare` | none | nothing (FR-G) | `compact` |

An argument present is non-blank, and a single line: the file's line is the
unit. Anything else is malformed through the reader's one error path: an
unknown kind or second token (`rename continue`, `prepare continue`, a doubled
space), a missing or blank argument, a `prepare` with a line 3, a fourth line.
The `continue` flag is optional on the two driven kinds, because running the
transition and submitting a prompt into what it opens are separate decisions.
`prepare` is the marker `compact: false` writes: nothing runs, but a
transition is expected, and that expectation is what `SessionStart(compact)`
gates the todo's re-injection on.

The grammar holds no version, so a file from the version before the mod held
the commands is refused only where its line count breaks its kind's rule, as an
old `clear` does. An old form that fits reads as the new shape: a command line
as line 3 is a free-text argument, and the marker for `compact: false`, two
lines of `<state>` and `compact`, is a driven bare compact. Such a file survives
as `armed` only if the mod did not take it at the turn end; the prompt-time
sweep then discards it and offers its owner the lines to type. Left `pending`,
`load-compact.sh` consumes it as it would any compact.

`/restart` is not a kind: it is a Claude Code built-in, and a relaunch with
`--resume` carries the conversation over whole, so nothing here has a frame or
a continuation to add to it. `/autodrive-handoff:autoname` stays a skill; its
checkpoint call composes a `rename` sentinel and rides the same drive.

## What holding the file can reach

The commands and the one prompt are literals in `hooks/handoff.ts`. The file
names a kind, and the mod maps the kind to its own commands (`/rename`,
`/clear`, `/compact`); the argument is the free text those commands take, and
`continue` is the flag that submits the mod's one fixed prompt. No command name
and no prompt text is read from the file, from the plan or from anywhere else.
So whatever writes the file can reach `/rename`, `/clear` and `/compact` with a
free-text argument, plus the fixed prompt, and nothing else: a `/plugin …`
line is only the argument of a rename.

The bound is the mod's, not the file's guard. `write-guard.sh` denies an agent
`Write` or `Edit` to the file and covers no other way of writing it, so a Bash
write can compose any well-formed file; a well-formed file names no command
and holds no prompt, so what writes it reaches only `/rename`, `/clear` and
`/compact` with a free-text argument, plus the fixed prompt. The fixed prompt exists twice: as the
mod's literal, and as `HANDOFF_CONTINUATION` in `scripts/_lib_drive.sh`, which
only renders the lines the sweep offers a person to type. A test pins the two
together. The decision and its reasons are in [Design
decisions](decisions.md).

## The states

The first line is the **state**: `held` → `armed` → `pending` → gone. `held`
and `armed` name their **owner** on the same line, `held <session-id>` and
`armed <session-id>`: the session that composed or approved the transition,
whose turn end takes it. `pending` names none, because past the take the
transition belongs to the confirming `SessionStart` in whichever session it
opened.

`checkpoint.py` is the file's one composer (`handoff_drive_arm` rewrites only
line 1): it reads its own output back through `handoff_drive_read`, so
composer and parser cannot drift, and a direct agent Write or Edit is denied at
`PreToolUse`. One fact per line throughout.

`held` is the checkpoint's, released by `handoff-approved`
([The checkpoint directive](the-checkpoint-directive.md)). Everything after it
is a hook's: `drive-take.sh` moves `armed` to `pending`, dropping the owner, and
the transition's own `SessionStart` loader removes `pending`. Which session may
take or sweep a file another session owns is in [Sessions sharing a
root](sessions-sharing-a-root.md).

## Links and an unreadable file

A symbolic link at the sentinel is never followed. No writer makes one, and a
repository can commit one to any readable file, whose bytes a reader would
then parse, quote into a report, offer as lines to type or rewrite on arming.
`handoff_drive_read` refuses a link, dangling or not, before reading a byte:
the test and the read are one `O_NOFOLLOW` open (`handoff_read_regular`), so a
link put at the name after a caller looked at it is refused too. Every caller
gates on the name existing as a link or a file, so a dangling one is refused
too rather than read as no file and left for ever. Each takes its malformed
path: the loaders and `drive-take.sh` remove the link and report it, the sweep
removes it as its own `link` state, and `handoff-approved` refuses to arm. Both
writers rename a file into place: the checkpoint, and `handoff_drive_arm`,
whose temporary file is `mktemp`'s rather than a name a repository could commit
a link at, and whose rename is `os.replace`, which replaces a link put at the
sentinel since it was read where `mv` would move the file into the directory it
points at. The bound is the last component, as for the root files: a symlinked
`.claude/` is read and written where it points, and one shared between roots is
unsupported (see [Sessions sharing a
root](sessions-sharing-a-root.md#limits)).

A reader whose `python3 -I` helper fails prints nothing, which says nothing
about the file. `handoff_drive_read` returns 2 for it rather than 1, and every
caller keeps the file and says so: `drive-take.sh` prints a `kind: null` plan
carrying only the message, the loaders report it, and the sweep records it as
its own `unread` state and removes nothing.
