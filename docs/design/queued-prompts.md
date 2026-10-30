# A prompt queued into the arming turn

Part of [handoff — Design](../design.md). The sweep of a stale sentinel it
refines is in [Driving the transition](driving-the-transition.md).

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
[A prompt queued into the arming turn](../changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md)

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
