# A prompt queued into the arming turn

Part of [handoff — Design](../design.md). The sweep of a stale sentinel it
refines is in [Driving the transition](driving-the-transition.md).

The dated records named here are in the `changelog-archive` tag's
`docs/changelog/`.

A prompt submitted while the arming turn still runs, during a tool call or the
final generation, fires `UserPromptSubmit` at once, inside that turn and before
its `Stop` (Claude Code 2.1.301). The owner's prompt is therefore not proof
that the turn ended. What tells it apart from a prompt after an Esc is its
`prompt_id`: a queued prompt carries the arming turn's own, and a prompt typed
at an idle composer carries a fresh one. Left alone, the sweep read the queued
prompt as an aborted turn, removed a file the mod was about to take, blamed an
unloaded mod and offered the lines for the user to type by hand.

`handoff-checkpoint` and `handoff-approved` record the turn's `prompt_id`.
`inject-checkpoint-root.sh` already rewrites both commands; on that matching
path, once the root resolves and the input carries a `session_id` and a
`prompt_id`, it writes the id, NUL-terminated, to
`$HANDOFF_POINTER_DIR/handoff-prompt-<session_id>`, under the drift marker's
guards ([Scoping](scoping.md)). A write that fails changes nothing the hook
prints. The marker is written here and not at every prompt because every real
prompt carries a `prompt_id`: recording each would fork `find`, `mktemp` and a
replace on every prompt of every session, for a case that needs the answer only
when an owner's `armed` file exists.

`report-drive-failure.sh` only reads the marker, and only for an `armed` file
this session owns, so an ordinary prompt forks nothing new. A prompt is
**queued** when the input's `prompt_id` is non-empty and equals the marker's.

- **`rename`** is left in place, and nothing is reported or recorded. The drive
  takes it at the end of the turn the prompt is in.
- **`clear` and `compact`** are swept and recorded (state `armed`), with the
  user told `transition cancelled — a prompt arrived before it ran` and the
  agent given a note to answer the prompt and then run the skill again with the
  same transition, unless the prompt changes it. No lines are offered: typing
  them would replay a transition and continuation composed before the prompt
  arrived.

Cancelling rather than sparing these two is not for want of a working drive: a
spared `clear` or `compact` runs cleanly after the prompt's turn. It is that
the prompt is lost as handoff state. The files were written before it arrived,
its answer lives only in the context `/clear` discards, and `TODO.md` does not
carry it across a `/compact`. Running the skill again after the answer
puts the prompt's outcome into the files first.

With no `prompt_id` in the input (the minimum supported Claude Code may not
send one), no marker, or a marker that differs, the file is swept as above. The
note also names a prompt typed while the turn was still running as a possible
cause when the input had no id, and when it had one but the marker could not
settle it: the marker directory exists and fails `marker_dir_ok`, or the read
is a link, a directory or another user's file, or its helper failed (empty
status). An `absent` marker and a differing one do settle it, as another
turn's, so the note leaves the phrase out; a marker directory that does not
exist is the first of these, since nothing has ever written a marker there; the sweep and the lines are the same either way.
`held`, `pending`, another session's file, a link, a malformed or unreadable
one and the failure record are as before. Both markers are read through
`handoff_read_marker` in `_lib_files.sh`.
2026-10-16 A prompt queued into the arming turn

**Residual bounds.** That a queued prompt carries the arming turn's id is
observed on one version, not documented; if it stops, a queued prompt is swept
as stale again, the earlier behaviour. The marker read's `own` check has no
test, because a marker owned by another user cannot be made without privilege.
The cancel note is a directive, and the agent's compliance is not pinned.

A marker write that failed silently, a full `/tmp` say, or a pointer directory
that could not be created (a missing directory reads `absent`), with a
`prompt_id` present leaves the marker `absent`, which settles nothing as unsettled: a
queued prompt then sweeps as stale, with the lines and without the phrase.

`inject-checkpoint-root.sh` writes the marker at `PreToolUse`, on a loose
substring match of `handoff-checkpoint` or `handoff-approved`, before the
permission decision and whether or not the command runs or succeeds. That is
harmless: the marker is read only for an `armed` file this session owns, which
was written in the current turn, and a stamp from a command that did not run
carries the same id a successful checkpoint would. Unverified: a subagent's
Bash call in the same session that matches the substring with a different
`prompt_id` would overwrite the marker, degrading a later queued prompt to the
stale sweep.

## A prompt after `Stop`

Observed on Claude Code 2.1.316
([the probe](../../plans/reports/2026-11-01-prompt-after-stop-probe.md)): a
prompt a person sends after the arming turn's `Stop` and before the mod issues
the transition command gets one of two outcomes by a sub-second race. Before
the take it reaches `UserPromptSubmit` with the sentinel still `armed`, and the
sweep removes it as stale, blaming an unloaded mod. After the take it finds
`pending`, which the sweep leaves, and the prompt is answered in the old
context, which the `/clear` then discards. A prompt queued into the arming turn
is cancelled with a note; this one should end the same way.

**The window.** The mod's `prompt.submit` hook runs at Enter, ahead of
`UserPromptSubmit`, and the mod can call `$.process.run` and add to `e.context`
there. The window is open from `classic.Stop` to the moment the drive issues the
transition command: the turn is over and the transition has not begun, unless
another plugin's `Stop` hook blocked and the turn goes on (Bounds). A prompt
with no recorded `Stop` is not the mod's: it passes
untouched, as does a slash command or a meta prompt. The mod's own
continuation usually arrives after the window has closed. When a later `Stop`
is still unconsumed as it arrives, the continuation opens that later window
and is treated as a prompt in it, with no check on `e.origin`: skipping it
would leave the later turn's armed file to the `UserPromptSubmit` sweep, which
discards it with a false "mod did not load" note. A `rename` there is taken
and run by that later window's drive; a `clear` or `compact` is cancelled with
the note, and the agent re-runs the skill. Each window keeps its own state, so
the outer drive ending clears nothing of the later one.

**The handler.** The first prompt in a window runs `scripts/drive-cancel.sh
<cwd> <session-id>` and stores the answer as one promise; a later prompt in the
same window spawns nothing. The script takes the sentinel's lock and cancels
an `armed` file the session owns, or a `pending` one, when the kind is `clear`
or `compact` with at least one line to run. It records the sweep in
`.claude/autodrive.swept`, removes the file and prints `{kind, message, note}`;
the cancel texts are the sweep's own (`_lib_drive.sh`). The handler toasts the
message and appends the note to the prompt's context. An `armed` `rename` the
session owns is not cancelled but taken, as `drive-take.sh` would: the script
removes the file, records nothing and prints the take's plan, with no `note`.
Left in place it would be swept, because the sweep reads `armed` at the prompt,
ahead of the take. The prompt passes unchanged and the drive runs that plan
after the prompt's turn. An `armed` prepare-only `compact` the session owns
(FR-G) is moved to `pending` under the lock, as the take does, and nothing is
printed: the sweep that follows then spares the marker and a hand-typed
`/compact` still re-injects the todo. Anything else (a `pending` prepare-only
compact, `held`, another session's file, an unreadable one) prints nothing, the
file stays and the prompt passes unchanged.

**The drive awaits the answer.** The drive awaits that promise straight after the
take returns, and again before each line of the plan's `before` list, and stops
when it cancelled. The fast path (no sentinel at the session root) skips the
take, not the answer: the script may just have removed the file. When the
answer is a rename's plan the drive runs it in place of the take's stdout,
which is empty if the script won the lock. The promise is set before the handler awaits anything, so a
prompt that arrives while the take or a `/rename` is in flight is waited for.
The take may run first and leave `pending`; the cancel then removes it, which
is why `pending` is cancelled at all. `after` lines need no check: they run
only if the loop got past the last `before` line.

**Why the mod and not a `Stop` record.** A file the sweep reads at
`UserPromptSubmit` cannot stop a plan the mod already holds in memory, and a
sweep that removes `pending` mid-drive leaves the transition running with
nothing for its loader. The handler is the one place that sees the prompt and
owns the plan.

**Why the window closes at the command.** The window shuts just before the last
`before` line is issued. A prompt after that is held by the host until the
command resolves and answered in the new context ahead of the continuation, so
nothing is lost, and cancelling would remove the `pending` file the loader
needs. A `/rename` under `clear` is an earlier line, so a prompt after it still
stops the `/clear`. A plan with no `before` line issues nothing and is never
cancelled.

**Bounds.**

- A `Stop` another plugin's hook blocks fires with no `turn.complete` after it,
  so the window stays open through the continued turn, and a prompt there is
  handled as in the window. A `clear` or `compact` is cancelled, as a queued
  prompt's is. An `armed` `rename` is taken, and the turn's next `Stop` opens a
  new window that does not hold the plan, so the title is lost with no message
  (observed once on 2.1.316). This is left as it is: it takes a blocking `Stop`
  hook, a rename-only sentinel and a prompt in that turn, and it costs one title.
- `pending` has no owner ([Sessions sharing a root](sessions-sharing-a-root.md)),
  so `drive-cancel.sh` cannot tell whose it is. The cancel relies on the mod
  calling it only inside its own window, in which the file is the session's.
- Unverified: a prompt reaching `prompt.submit` between the command being
  issued and the host starting it. 0.08 s after the command was too late to hit
  it in the probe.
- The handler failing (the spawn rejecting, output that is not JSON) falls back
  to the racy outcomes above.
- The `prompt.submit` hook was probed on 2.1.316 and the oldest version
  installed here is 2.1.310; a Claude Code older than that is unprobed, while
  the stated minimum is 2.1.287.
