# Driving the transition

Part of [handoff — Design](../design.md).

The dated records named here are in the `changelog-archive` tag's
`docs/changelog/`.

A **driven transition** is a short sequence of commands and a prompt that the
plugin runs for the user once the turn that prepared it ends. The checkpoint
composes a sentinel that names the transition as data; a Claude Code mod
(`hooks/handoff.ts`), which holds the commands and the prompt as literals,
runs it through the host's own command and prompt entry points. The code calls
a driven transition `typed`, a name from when the sequence was keystrokes in a
tmux pane; the payload fields `clear` and `compact` are what make one. Nothing
reads or writes the terminal.
2026-10-08 The plugin becomes a mod

What the sentinel holds, and the bound on what it can make the mod run, is in
[The sentinel](the-sentinel.md). The plan on this page is that file taken and
printed as data: a kind, a flag and one argument.

## Who runs it, and when

The mod registers three handlers. `classic.Stop` records the turn's cwd and session
id and does nothing else. `turn.complete`, which follows it by a fraction of a second,
consumes the recorded cwd and drives inline. `prompt.submit` answers only a
prompt a person sends between the two, or while a transition's earlier line is
in flight, and can stop the drive
([A prompt after `Stop`](queued-prompts.md#a-prompt-after-stop)).

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
  2026-07-19 Mid-turn TUI input: the taxonomy that shapes compaction driving

The cwd and the session id are the `Stop` payload's, because `turn.complete`
carries neither.

## `drive-take.sh` is the one reader

The mod never reads or writes the sentinel. `scripts/drive-take.sh <cwd>
<session-id>` takes it and prints the plan, for the same reason the checkpoint reads its own
output back: `handoff_drive_read` is the one parser, and a TypeScript copy of
it would be a second one that can drift. The mod also cannot do what the take
needs — `$.fs` has no rename or delete, so the atomic `armed` → `pending`
(`handoff_drive_arm`) and the removal for `rename` happen in the script, and
root resolution stays in `worktree_root.py`.

The contract, pinned by `tests/drive-take.bats` against fixtures the mod's own
tests also consume:

- **Empty stdout** means nothing was armed for this session: no file, a
  `pending` or a `held` one, or one `armed` by another session. Only this
  session's `armed` file is this turn's to take, so a transition already in
  flight cannot be taken twice, and another session's turn end cannot run the
  owner's `/rename` and `/clear` in itself.
- **No session id given** over an `armed` file takes nothing — whose file it
  is cannot be told — and prints a `kind: null` plan saying so. The mod writes
  that message to `failFile`, as for a rejected command, so the next prompt
  reports it and sweeps the file; a `Stop` that carried no id is a host fault
  nothing else would surface.
- Otherwise one line of JSON, `{kind, arg, continue, failFile, message}`, in
  that key order: the sentinel's kind, its argument and `continue` as a JSON
  boolean, data only; the message names the first line the transition will run.
  `armed` is left **before** the plan is printed: `pending` for a kind with a
  confirming `SessionStart`, removal for `rename`, which has none and would
  otherwise leave a `pending` nobody clears. A plan that carries a message and
  runs nothing (`kind: null`, and `prepare`) has `arg: ""` and
  `continue: false`.
- **FR-G.** A `prepare` kind runs nothing. The file is left `pending`, the plan
  has kind `prepare`, and the message says so; the mod toasts it and runs
  nothing. That `pending` state is what `SessionStart(compact)` gates the todo's
  re-injection on: a hand-typed `/compact` with the marker pending re-injects
  the todo and consumes the marker, and with no marker it re-injects nothing.
- **Malformed** files are removed and reported with `kind` null and the
  constraint that failed, so the complaint does not repeat each turn.

The mod skips the spawn on the every-turn path: when the recorded cwd is the
session's project root and `.claude/autodrive` does not exist, it skips the
take, whether the take runs at `turn.complete` or at a [prompt in the
window](queued-prompts.md#a-prompt-after-stop). A worktree or subdirectory cwd
falls through, because the script owns root resolution.

## Running the plan

The mod maps the plan's `kind` to its own commands, by a `switch` over literal
names, and the plan's `arg` is only their argument: `rename` runs
`$.command.run({command: 'rename', args: arg})`; `clear` runs that and then
`{command: 'clear', args: ''}`; `compact` runs `{command: 'compact', args: arg}`;
every other kind, `null` and `prepare` included, runs nothing. After all the
commands have run, a plan with `continue` true submits the mod's one fixed
prompt, `$.prompt.submit({text: CONTINUATION, asUser: true})`; a plan that runs
no command submits none. A plan field the mod does not name, such as a command
or a prompt text, is ignored, so a plan can reach only what the kind table
holds ([The sentinel](the-sentinel.md#what-holding-the-file-can-reach)). The
cancel check, before each command, and the window's close, as the last command
is issued, are in [A prompt after `Stop`](queued-prompts.md#a-prompt-after-stop).

The mod does not read the prompt box. It once stopped on any text there, to
avoid typing over a person; but `command.run` and `prompt.submit` do not type
into the box. With text in the composer, `/rename`, `/clear` and
`/compact <focus>` all took effect, `prompt.submit` sent the mod's text alone,
and the person's text was still in the box afterwards, through the fresh
session and the compaction too. The check cost transitions instead: text
stashed and then restored before the turn ended made the mod take the
sentinel, toast that it would run, and run nothing.
2026-10-16 A prompt queued into the arming turn

**A command or prompt that fails ends the sequence**, which is what makes a
`/rename` that never lands under kind `clear` cost a wrong title and nothing
more. The mod writes `<root>/.claude/autodrive.failed` with the command as it
would be typed (`/rename T`), or the prompt's text, and the host's reason, and
toasts the same text. `$.fs.write` follows a link and the mods API has no
write that replaces one, so the mod stats the name first (`isLink`) and, on a
link, skips the record and says so in the toast. A link put there between the
stat and the write is still followed: the bound, in a project directory the
user trusts.

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
own kind and inject the frame; neither starts the continuation, because the mod
submits it itself once the command resolves. The read of `pending` and its
removal are one step under [the sentinel's lock](sentinel-lock.md): a
checkpoint replaces whatever sentinel is there, so a loader must not remove a
file it never read. Each consumes only
its own kind in state `pending`: an `armed` file is left for the sweep, and a
`clear` armed in this session and overtaken by a threshold auto-compaction is
not consumed by the compact loader. The consume comes first and does not
depend on the frame, so a `clear` with nothing to inject still consumes. A
loader that cannot take the lock consumes nothing and still injects the frame,
saying so.

What each says afterwards differs. `load-handoff.sh` always reports, on both
channels: the frame's size and age, plus `No task frame` or `No todo` when one
half has no body, or `No task frame or todo.` alone. `load-compact.sh` runs
after a compaction whose checkpoint removed the task file, so what it
re-injects is the todo, and it tells the user `todo re-injected` or `No todo`.
With no `pending` compaction it is silent, which is what keeps a hand-typed
`/compact` or a threshold auto-compaction from re-injecting a stale list.

## Reporting a failure, sweeping a stale sentinel

A rejected command has no turn left to speak in, so the mod's report is the
`autodrive.failed` file and `report-drive-failure.sh`, which reads it at the
next `UserPromptSubmit` — the first moment anything can act on the news — and
reports on both channels. The mod writes the record only on what it observed
itself: a rejected command, or a turn end that carried no session id, which is
recorded like one. A failure part-way through a sequence strands the
sentinel in `pending`, because the confirming `SessionStart` never fires; the
same hook clears it with the report. Nothing is inferred from a file merely
being `pending`, which is the legitimate state for the whole window between
the take and the transition. A symbolic link at `autodrive.failed`, dangling
or not, is no record the mod wrote: it is removed unread and named on both
channels, and a `pending` sentinel is left where it is. The record is read
through the same single `O_NOFOLLOW` open, never a test followed by a read.

The hook also sweeps a sentinel still `armed`. `drive-take.sh` leaves it
`pending` or removes it at the end of the turn that wrote it, so one still
`armed` when a prompt arrives has not been taken, and unless that prompt was
typed into the arming turn it never will ([A prompt queued into the arming
turn](queued-prompts.md)). What another session's prompt may sweep —
liveness, the `held` exemption and the sweep's record — is in [Sessions sharing
a root](sessions-sharing-a-root.md).

For the owner's own `armed` file, or another's whose owner is not live, there are
two causes the hook cannot tell apart (three, when the input carries no
`prompt_id` to rule out a prompt typed ahead): an aborted turn (an Esc, which fires no `Stop`, a crash or a quit), and **the mod
not being loaded** —
`--safe-mode`, a Claude Code older than 2.1.287, or an organization-managed
Claude Code that does not list the plugin in managed settings (Claude Code
2.1.301: there, `classic.Stop` hooks pass over the plugins a person installs,
and the mod learns the turn ended only through that event). The mod needs
2.1.287 and the plugin manifest has no field to pin a minimum, so this note is
where the requirement surfaces: it names the mod as the likely cause, discards the
file so it cannot fire into unrelated work days later, and prints the lines its
kind would have run (`handoff_drive_lines`, rendered for display from the
kind, argument and flag) for the user to type in order. A file that will not parse is swept too,
without lines — it describes no transition anyone can complete. `held` is
exempt whoever owns it: it waits on an approval whose answer arrives at this
very hook, so surviving the turn boundary is what it is for. Lines are offered
only for the owner's own `armed` file: another session's would be replayed
into this conversation.

## A prompt queued into the arming turn

The owner's own prompt can fire this hook inside the arming turn, before its
`Stop`: the sweep tells it from an aborted turn by its `prompt_id` and leaves a
`rename`, cancels a `clear`, `compact` or `prepare` and offers no lines. The argument, the
marker that carries the id and the bounds are in
[A prompt queued into the arming turn](queued-prompts.md).

## The sentinel's lock

The sweep and the take can interleave: the host does not order a new prompt's
`UserPromptSubmit` against the mod's take, which runs at `turn.complete` or at a prompt in the window, so
a sweep that read `armed` could delete the `pending` file the take had just
armed. Every actor of the sentinel, the checkpoint, `handoff-approved`,
`drive-take.sh`, `drive-cancel.sh`, the sweep and the two loaders, holds an advisory lock
(`.claude/autodrive.lock`) across its read-decide-write, with a bounded wait
that fails closed: an actor that cannot take it leaves the sentinel as it is
and says so. The mechanism, its bounds and what each actor does are in [The
sentinel's lock](sentinel-lock.md).

## Verification

Three layers, because the mod's own seams are each reachable only one way:

- `tests/drive-take.bats` runs the real script over real sentinel files and
  asserts stdout equals the fixtures in `tests/mod/fixtures/`, plus each state
  gate and the worktree-scoped paths; `tests/lib-drive.bats` pins the reader's
  shapes and every malformed form, an old form whose line count breaks the
  grammar among them (one that fits is not malformed, see
  [The kinds](the-sentinel.md#the-kinds)).
- `tests/mod/handoff.test.ts` and `window.test.ts`, run by `claude plugin test`,
  stub every mods API call the mod makes and assert the exact call sequence: the deferral to
  `turn.complete`, stop-on-first-failure with the `failFile` write, the
  absence of any prompt-box read, the no-op on empty stdout and on an aborted
  turn, and that a plan runs only its kind's commands: an unknown kind runs
  nothing, extra `before`, `after` or `text` fields are ignored, and a `/plugin`
  argument is only a rename's argument. It consumes the same fixtures through a
  generated module, `tests/gen_mod_fixtures.py`, which `tests/test_mod_fixtures.py`
  keeps in step, and which also pins the mod's `CONTINUATION` literal to
  `HANDOFF_CONTINUATION`. Both gate `just precommit`.
- `tests/test_mod_live.py` (`just mod-smoke`, outside precommit) drives a real
  `claude -p` in a throwaway repo with an armed sentinel and reads the session
  transcripts: a `custom-title` entry for `rename`, the continuation as a fresh
  session's first user prompt for `clear` (with the sentinel consumed), and a
  compact summary carrying the focus plus the continuation for `compact`.

The live test is what found the `Stop` refusal: the first design deferred the
drive with a zero-delay timer from `Stop` and was wrong, which no stub could
have shown, because the stub answers whatever it is told to. A change to the
mod or to a loader lands with a `just mod-smoke` run for the same reason.

**The rejection path has no live coverage.** The mod issues only `/rename`,
`/clear` and `/compact`, with free-text arguments, from `turn.complete`, where
the call-context refusal does not apply, so no sentinel can make the host
reject a command today. A forced-failure dogfood with a well-formed `/compact`
was accepted and compacted the session (step 7, check 3). The `failFile`
write, the toast and the next prompt's report rest on the stub rig's
stop-on-first-failure row and the `report-drive-failure.sh` rows in
`tests/report-drive-failure*.bats`. The path stays because a host change is the failure
class the live test has already caught once, and without it a rejection would
end the drive with nothing said. No test seam is added to reach it: that would
loosen the mod's fixed commands to test code that exists to report a failure.
