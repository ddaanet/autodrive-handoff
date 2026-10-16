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
send one), no marker, or a marker that differs, the file is swept as above and,
when the input had no id, the note also names a prompt typed while the turn was
still running as a possible cause. `held`, `pending`, another session's file, a
link, a malformed or unreadable one and the failure record are as before.
[A prompt queued into the arming turn](../changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md)

**Residual bounds.** That a queued prompt carries the arming turn's id is
observed on one version, not documented; if it stops, a queued prompt is swept
as stale again, the earlier behaviour. The marker read's `own` check has no
test, because a marker owned by another user cannot be made without privilege.
The cancel note is a directive, and the agent's compliance is not pinned.
