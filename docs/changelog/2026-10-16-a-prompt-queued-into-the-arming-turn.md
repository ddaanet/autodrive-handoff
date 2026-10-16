# 2026-10-16 — A prompt queued into the arming turn

A prompt typed while the turn that armed a transition was still running swept
the transition, blamed an unloaded mod and offered lines for the user to type
by hand. Reproducing it showed that the sweep's central premise, that the
owner's `UserPromptSubmit` cannot fire before the arming turn's own end, is
false on Claude Code 2.1.301. Fixing it also removed the mod's composer check,
which the same investigation showed to be both unnecessary and harmful.

## The defect

`report-drive-failure.sh` swept an `armed` sentinel its owner's prompt found,
on the reasoning that `drive-take.sh` takes the file at the turn end that
follows the write, so one still `armed` when the owner's next prompt arrives
never ran. A prompt submitted while the arming turn runs, during a tool call or
during the final generation, fires `UserPromptSubmit` at once, inside that
turn and before its `Stop`. The sweep removed a file the mod was about to take.
Interactive runs on 2.1.301, in both places a prompt can be queued, showed:

- **The queued prompt carries the arming turn's own `prompt_id`.** A prompt
  typed at an idle composer, after an Esc included, carries a fresh one. No
  other field of the hook input differs. The `PreToolUse(Bash)` input of the
  checkpoint call carries the same id as that turn's `UserPromptSubmit`.
- **The sweep's note was wrong for this case.** It named an unloaded mod and
  printed the lines, although the mod was loaded and would have driven. The old
  header already named the case ("prose injected into a still-running turn")
  and called the outcome a cancellation that is "said so"; the cancellation
  happened and the saying did not.
- **Stashing a prompt (`ctrl+s`) fires nothing.** Text typed and stashed
  leaves the sentinel alone, and the drive runs. Text stashed and then
  restored to the composer before the turn ends is another matter, below.
- **The mod's composer check lost transitions.** The mod read the prompt box
  before each line and stopped entirely on text there. With text un-stashed
  into the composer before `Stop`, it took the sentinel, toasted that it
  would run `/rename`, saw the text, and ran nothing: no sentinel, no failure
  record, and a toast that says the opposite of what happened.
- **The check protected nothing.** With the check removed, `command.run`
  succeeded with text in the composer for `/rename`, `/clear` and
  `/compact <focus>`, and `prompt.submit({asUser: true})` submitted the mod's
  text alone. The user's text survived every one of them unchanged, through
  the fresh session after a `/clear` and the compaction.
- **A queued prompt the sweep spared is answered in the old context.** With
  the sweep disabled and the check removed, the queued prompt was answered once
  in the old context, whether the host folded it into the running turn or
  started a turn of its own, and the mod's commands ran after that turn.
  The `clear` or `compact` then ran cleanly. Nothing was lost or delivered
  twice at the host level.

## What was decided

**Spare a queued `rename`; cancel a queued `clear` or `compact`.** A `rename`
drive is a title and costs nothing if it runs after the prompt. A `clear` or
`compact` does not come out the same, even though it runs cleanly: the prompt
is lost as handoff state. `TASK.md` and `TODO.md` were written before the
prompt arrived, its answer lives only in the context `/clear` discards, and
`TODO.md` does not carry it across a `/compact`. The continuation, a fixed
line that carries nothing, cannot make up for it. So the sweep removes the
file, records the removal and tells the agent to answer the prompt and then
run the skill again with the same transition, unless the prompt changes it.
The user sees `transition cancelled — a prompt arrived before it ran`, and is
not offered lines: typing them would replay a transition composed before the
prompt arrived. An earlier draft of this change spared every kind, on the
evidence that a spared clear runs cleanly; it was revised when the loss of the
prompt as state was named.

**Recognise a queued prompt by its `prompt_id`, recorded at the checkpoint.**
`inject-checkpoint-root.sh` already fires on every `handoff-checkpoint` and
`handoff-approved` call. On that matching path, once the root resolves and the
input carries a `session_id` and a `prompt_id`, it records the id in
`$HANDOFF_POINTER_DIR/handoff-prompt-<session_id>`, NUL-terminated, with the
drift marker's guards (a directory that is no link, is this user's and is
writable by no one else; a `mktemp` sibling renamed over the name by
`handoff_replace`). The guard and the writer moved into `_lib.sh`
(`marker_dir_ok`, `handoff_write_marker`) because two hooks now use them. A
failure to write changes nothing the hook prints, and the negative path stays
one `jq` parse, now reading four fields, and a substring test (NFR2).
`report-drive-failure.sh` only reads the marker, and only for an `armed` file
its own session owns whose input has a non-empty `prompt_id`. An id that
matches is a queued prompt.

**The marker is written at the checkpoint call, not at every prompt.** The
first draft had the sweep record each prompt's `prompt_id`. Every real prompt
carries one, so that forks `find`, `mktemp` and a replace on every prompt of
every session, to serve a case that needs a read only when an owner's `armed`
file exists. The checkpoint call is the one place the arming turn's id is
known and the one place that already runs in that turn.

**No `prompt_id` in the input sweeps as before.** The minimum supported
Claude Code is 2.1.287, and that `prompt_id` is in its hook input is not
established. Without it the hook cannot rule a queued prompt out, so the file is
swept as it was and the unloaded-mod note adds "a prompt typed while that turn
was still running" as another possible cause. A missing marker (a first prompt,
an absent directory, a link, a directory another user can write) is the same.
`held`, `pending`, another session's file, a link, a malformed file and an
unreadable one are untouched by this change.

**The mod no longer reads the composer.** The `$.prompt.read()` check before
each line is gone, with its stub in the test rig and the two rows that pinned
it. Its purpose was parity with the walker, which typed into the composer and
could have typed over a person. The mod calls `command.run` and
`prompt.submit`, which leave composer text untouched, so the guard protected
nothing and cost the transition in the un-stash case. Every expected call log
in `tests/mod/handoff.test.ts` now omits `prompt.read`, and an unstubbed call
is a kit error, so its absence from every log is the pin.

`session-pointer.sh` sweeps `handoff-prompt-*` older than seven days with the
drift markers.

## Weighed and left

- **Sparing a queued `clear` or `compact` like a `rename`.** The runs support
  it at the host level and the prompt's answer is not lost at that level. It
  loses the prompt as state, above.
- **Recording every prompt's id in the sweep.** Rejected above for its
  per-prompt forks.

## Residual bounds

- `prompt_id` behaving this way is observed on one version, not documented.
  If a host change stops a queued prompt carrying the arming turn's id, a
  queued prompt is swept as stale again, with the unloaded-mod note: the
  pre-fix behaviour, not a new failure.
- Queued `compact`, and queued `rename` where the queued prompt becomes its
  own turn, were exercised without the sweep but not with the fix in the live
  run. The hook output for them is pinned by rows; the host behaviour after a
  cancelled `compact` is not.
- The cancel note is a directive, and what the model does with it varies: in
  the live run it re-ran the skill before answering. Only the hook's output is
  pinned.
- The `own` argument of the marker read (`handoff_read_regular … own`) has no
  row. Dropping it leaves the suite green, because a marker owned by another
  user cannot be made without privilege.

## What it touched

`report-drive-failure.sh` (the discriminator, the cancel path, the typed-ahead
note, the header's premise); `inject-checkpoint-root.sh` (the marker);
`_lib.sh` (`marker_dir_ok`, `handoff_write_marker`); `session-pointer.sh`;
`hooks/handoff.ts` and the test rig (the bail). Rows in `tests/checkpoint.bats`
for the writer and in `tests/hook-test.bats` for the sweep, each negative paired
with the positive over the same fixture. The mutations that red a row: the
owner test, the non-empty `prompt_id` test, the kind test in both directions,
the `armed` state test, `marker_dir_ok` on the read, the marker write in the
checkpoint hook, a marker write in the sweep, the `session-pointer.sh` glob, and
the restored composer check in the mod. Live: three interactive cases on
2.1.301 against the working tree, a queued `rename` spared and driven, a
queued `clear` cancelled with the note reaching the agent, and an Esc followed
by a prompt at the idle composer swept as stale with the lines offered.
