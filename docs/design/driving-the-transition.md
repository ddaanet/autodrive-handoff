# Driving the transition

Part of [handoff — Design](../design.md).

A **driven transition** is a short sequence of commands and prompts that the
plugin runs for the user once the turn that prepared it ends. The checkpoint
composes the sequence into a sentinel; a Claude Code mod
(`hooks/handoff.ts`) runs it through the host's own command and prompt entry
points. The code calls a driven transition `typed`, a name from when the
sequence was keystrokes in a tmux pane; the payload fields `clear` and
`compact` are what make one. Nothing reads or writes the terminal.

## The kinds and their lines

| kind | runs before | runs after | confirming source |
|---|---|---|---|
| `rename` | `/rename <title>` | — | — |
| `compact` | `/compact [directive]` | continuation prose, if any | `compact` |
| `clear` | `/rename <title>`, `/clear` | continuation prose, if any | `clear` |
| `compact` (prepared) | — | — | `compact` |

The after-line is optional on both driven kinds, because running the
transition and submitting a prompt into what it opens are separate decisions.
`/restart` is not a kind: it is a Claude Code built-in, and a relaunch with
`--resume` carries the conversation over whole, so nothing here has a frame or
a continuation to add to it. `/handoff:autoname` stays a skill; its checkpoint
call composes a `rename` sentinel and rides the same drive.
[The plugin becomes a mod](../changelog/2026-10-08-the-plugin-becomes-a-mod.md)

## The sentinel

One sentinel, `.claude/autodrive`, whose first line is its **state** and
second line the kind. The states are `held` → `armed` → `pending` → gone.
`checkpoint.py` is the file's one writer: it composes the sentinel and reads
its own output back through `handoff_drive_read`, so composer and parser
cannot drift, and a direct agent Write or Edit is denied at `PreToolUse`.
Everything after the first two lines is a command or a prompt, one per line,
and validation anchors it — the *n*th line of kind *k* must begin with the
expected command literal, and a prose line may not begin with `/` — so the
file cannot be made to run something else. One fact per line throughout.

`held` is the checkpoint's, released by `handoff-approved`
([The checkpoint directive](the-checkpoint-directive.md)). Everything after it
is a hook's: `drive-take.sh` moves `armed` to `pending`, and the transition's
own `SessionStart` loader removes `pending`.

## Who runs it, and when

The mod registers two handlers. `classic.Stop` records the turn's cwd and does
nothing else. `turn.complete`, which follows it by a fraction of a second,
consumes the recorded cwd and drives inline.

Both halves are forced by the host:

- **Not from `Stop`.** `$.command.run` is refused from a hook call context
  the turn is waiting on, and the refusal is by call context, not by time: a
  `$.clock.after(0)` started inside the `Stop` handler inherits it and is
  refused too. `turn.complete` is the first event outside that context.
- **Not from a timer.** Under `claude -p` the process outlives `Stop` by only a
  second or two, and a timer that fires after that finds no session bound.
  Driving inline from `turn.complete` keeps the process alive until the
  submitted continuation turn finishes.
- **Esc arms nothing.** `Stop` does not fire on an interrupt, so an aborted
  turn records no cwd, and a `turn.complete` without a recorded cwd drives
  nothing. The recorded cwd is consumed once, so a second `turn.complete` does
  not drive again.
- **Mid-turn input is never at stake.** Nothing is submitted while a turn runs:
  prose submitted mid-turn would land in the running turn's next model call,
  which is the hazard that made the earlier tmux design wait for the pane to
  go idle. The drive starts only after the turn is over.
  [Mid-turn input: the taxonomy](../changelog/2026-07-19-mid-turn-tui-input-taxonomy.md)

The cwd is the `Stop` payload's, because `turn.complete` carries none.

## `drive-take.sh` is the one reader

The mod never reads or writes the sentinel. `scripts/drive-take.sh <cwd>`
takes it and prints the plan, for the same reason the checkpoint reads its own
output back: `handoff_drive_read` is the one parser, and a TypeScript copy of
it would be a second one that can drift. The mod also cannot do what the take
needs — `$.fs` has no rename or delete, so the atomic `armed` → `pending`
(`handoff_drive_arm`) and the removal for `rename` happen in the script, and
root resolution stays in `worktree_root.py`.

The contract, pinned by `tests/drive-take.bats` against fixtures the mod's own
tests also consume:

- **Empty stdout** means nothing was armed: no file, a `pending` or a `held`
  one. Only `armed` is this turn's to take, so a transition already in flight
  cannot be taken twice.
- Otherwise one line of JSON, `{kind, before[], after[], failFile, message}`.
  `armed` is left **before** the plan is printed: `pending` for a kind with a
  confirming `SessionStart`, removal for `rename`, which has none and would
  otherwise leave a `pending` nobody clears.
- **FR-G.** A `compact` kind line alone (the prepare-only compact) has no
  before-lines. The file is left `pending`, the lists are empty, and the
  message says so; the mod toasts it and runs nothing. That `pending` state is
  what `SessionStart(compact)` gates the todo's re-injection on, so a
  hand-typed `/compact` re-injects nothing.
- **Malformed** files are removed and reported with `kind` null and the
  constraint that failed, so the complaint does not repeat each turn.

The mod skips the spawn on the every-turn path: when the recorded cwd is the
session's project root and `.claude/autodrive` does not exist, it returns
without running the script. A worktree or subdirectory cwd falls through,
because the script owns root resolution.

## Running the plan

For each line of `before` then `after`, in order, the mod first reads the
prompt and **stops everything** if the person has text in it — it never runs
over someone mid-sentence. A line starting with `/` runs as
`$.command.run({command, args})`, the command name without its slash; any
other line is `$.prompt.submit({text, asUser: true})`.

**A line that fails ends the sequence**, which is what makes a `/rename` that
never lands under kind `clear` cost a wrong title and nothing more. The mod
writes `<root>/.claude/autodrive.failed` with the line and the host's reason,
and toasts the same text.

The host's own resolution is the confirmation. `command.run` resolves when the
command has taken effect — `/rename` once the title is set, `/clear` once the
session is fresh, `/compact <focus>` after the whole compaction, seconds
later — and `prompt.submit` when the turn starts. Nothing is read back from the
screen or the transcript, and nothing waits on a timeout. The transcript is
still where the live smoke test looks, because it is the one record the
harness itself writes.
[Nothing that asks whether an action took effect reads the pane](decisions.md)

## The loaders consume `pending`

`SessionStart(clear)` fires for a mod-run `/clear`, and `SessionStart(compact)`
for a mod-run `/compact`, exactly as for a hand-typed one.
`load-handoff.sh` and `load-compact.sh` each remove a `pending` file of their
own kind and inject the frame; neither spawns anything, because the mod
submits the continuation itself once the command resolves. Each consumes only
its own kind in state `pending`: an `armed` file is left for the sweep, and a
`clear` armed in this session and overtaken by a threshold auto-compaction is
not consumed by the compact loader. The consume comes first and does not
depend on the frame, so a `clear` with nothing to inject still consumes.

What each says afterwards differs. `load-handoff.sh` always reports, on both
channels: the frame's size and age, plus `No task frame` or `No todo` when one
half has no body, or `No task frame or todo.` alone. `load-compact.sh` runs
after a compaction whose checkpoint removed the task file, so what it
re-injects is the todo, and it tells the user `todo re-injected` or `No todo`.
With no `pending` compaction it is silent, which is what keeps a hand-typed
`/compact` or a threshold auto-compaction from re-injecting a stale list.

Both loaders read a half from its legacy path when the root file has no body,
and both say so, with the same notes from `handoff_frame_notes`: a half read
from a legacy path, and a legacy file left ignored beside a root file with a
body. `load-handoff.sh` puts the notes after the frame and before the gap note,
and a legacy fragment per note in its message, between the size and age and
`No todo`. The age is taken from the files that count, which includes a legacy
file when its half came from it. `load-compact.sh` appends the fragments to its
`todo re-injected` or `No todo`, so a compaction with no legacy file says what
it always said. The bridge, and the condition that retires it, are argued in
[Design decisions](decisions.md).
[Legacy paths are read, and the checkpoint moves them](../changelog/2026-10-11-legacy-paths-are-read-and-moved.md)

## Reporting a failure, sweeping a stale sentinel

A rejected line has no turn left to speak in, so the mod's report is the
`autodrive.failed` file and `report-drive-failure.sh`, which reads it at the
next `UserPromptSubmit` — the first moment anything can act on the news — and
reports on both channels. A failure part-way through a sequence strands the
sentinel in `pending`, because the confirming `SessionStart` never fires; the
same hook clears it with the report. Nothing is inferred from a file merely
being `pending`, which is the legitimate state for the whole window between
the take and the transition.

The hook also sweeps a sentinel still `armed`. `drive-take.sh` leaves it
`pending` or removes it at the end of the turn that wrote it, so one still
`armed` when a later prompt arrives never ran. There are two causes the hook
cannot tell apart: an aborted turn, and **the mod not being loaded** —
`--safe-mode`, or a Claude Code older than 2.1.287. The mod needs that version
and the plugin manifest has no field to pin a minimum, so this note is where
the requirement surfaces: it names the mod as the likely cause, discards the
file so it cannot fire into unrelated work days later, and prints the lines it
held for the user to run in order. A file that will not parse is swept too,
without lines — it describes no transition anyone can complete. `held` is
exempt while it belongs to the session at the prompt, which is why the sweep
names its states rather than taking anything that is not `pending`; a `held`
file whose owner is another session is reclassified as abandoned first, and
no lines are offered for it.

Each removal the sweep makes also appends a line to `.claude/autodrive.swept`:
time, the removing session, the file's state, owner, kind and age, and the
cwd. The sweep's report lands on the removing session's own channels, which
the session that composed the file never sees, and background sessions
sharing the root (the commit review) run this hook too; without the record a
vanished sentinel names no remover. It is newest first, trimmed to 50 lines,
never consumed, and a failed write never blocks the sweep. It says who took
the file and how old it was; it does not decide whether the sweep was right.

## Verification

Three layers, because the mod's own seams are each reachable only one way:

- `tests/drive-take.bats` runs the real script over real sentinel files and
  asserts stdout equals the fixtures in `tests/mod/fixtures/`, plus each state
  gate and the worktree-scoped paths.
- `tests/mod/handoff.test.ts`, run by `claude plugin test`, stubs every mods
  API call the mod makes and asserts the exact call sequence: the deferral to
  `turn.complete`, stop-on-first-failure with the `failFile` write, the
  prompt bail, the no-op on empty stdout and on an aborted turn. It consumes
  the same fixtures through a generated module, `scripts/gen_mod_fixtures.py`,
  which `tests/test_mod_fixtures.py` keeps in step. Both gate `just precommit`.
- `tests/test_mod_live.py` (`just mod-smoke`, outside precommit) drives a real
  `claude -p` in a throwaway repo with an armed sentinel and reads the session
  transcripts: a `custom-title` entry for `rename`, the continuation as a fresh
  session's first user prompt for `clear` (with the sentinel consumed), and a
  compact summary carrying the focus plus the continuation for `compact`.

The live test is what found the `Stop` refusal: the first design deferred the
drive with a zero-delay timer from `Stop` and was wrong, which no stub could
have shown, because the stub answers whatever it is told to. A change to the
mod or to a loader lands with a `just mod-smoke` run for the same reason.

**The rejection path has no live coverage.** `handoff_drive_read` pins every
slot to a literal the host accepts and the mod drives from `turn.complete`,
where the call-context refusal does not apply, so no sentinel can make the host
reject a line today. A forced-failure dogfood with a well-formed `/compact`
was accepted and compacted the session (step 7, check 3). The `failFile`
write, the toast and the next prompt's report rest on the stub rig's
stop-on-first-failure row and the `report-drive-failure.sh` rows in
`tests/hook-test.bats`. The path stays because a host change is the failure
class the live test has already caught once, and without it a rejection would
end the drive with nothing said. No test seam is added to reach it: that would
loosen the pinned slots to test code that exists to report a failure.
