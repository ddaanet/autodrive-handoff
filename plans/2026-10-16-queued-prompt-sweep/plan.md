# Queued-prompt sweep: plan

Evidence: `plans/reports/2026-10-16-queued-prompt-sweep-repro.md`,
`plans/reports/2026-10-16-stashed-prompt-sweep.md`,
`plans/reports/2026-10-16-drive-with-composer-text.md`. Decided by my human
partner 2026-10-16: questions 1–3 at their defaults, 4 agreed.

## Contract

### 1. The sweep spares a prompt queued into the arming turn

`scripts/report-drive-failure.sh`:

- Reads `.prompt_id` from the hook input as a fourth NUL-terminated field,
  beside `cwd`, `session_id` and `transcript_path`.
- Reads a per-session prompt marker,
  `$HANDOFF_POINTER_DIR/handoff-prompt-<session_id>`, holding the `prompt_id`
  of the turn that last ran the checkpoint or `handoff-approved`,
  NUL-terminated. It reads it only when the file is `armed` and owned by this
  session, so an ordinary prompt forks nothing new. The read goes through
  `marker_dir_ok` and `handoff_read_regular … own`. This hook never writes the
  marker.
- **Queued** means: the file is `armed`, its owner is this session, the input's
  `prompt_id` is non-empty, and it equals the marker's value. A
  queued `rename` is left in place and nothing is reported: the drive takes it
  at that turn's end. A queued `clear` or `compact` is swept (`record_sweep`,
  state `armed`) and **no lines are offered**. Typing them would replay a
  transition and continuation composed before the prompt arrived. The
  `systemMessage` fragment is `transition cancelled — a prompt arrived before it
  ran`. The agent's note is a directive written per `craft:directive-writing`:
  acts only, with no mechanism, rationale or file name. For a clear it reads
  `The driven /clear did not run. Answer this prompt, then run the handoff skill
  again with the same transition, unless this prompt changes that.` For a
  compact it is the same with `/compact` and `precompact`.

  Why, revised twice on 2026-10-16. A live run
  (`plans/reports/2026-10-16-queued-prompt-with-clear-compact.md`) showed
  that with the sweep off the prompt is answered in the old context and the
  `clear` or `compact` then runs cleanly, so a second draft spared every kind.
  My human partner then pointed out that the prompt is still lost as handoff
  state. The files were written before it, its answer lives only in the context
  `/clear` discards, and `TODO.md` does not carry it across `/compact`.
- Not queued (a fresh `prompt_id`, none in the input, or no marker): behaviour
  unchanged, except that when the input has no `prompt_id` the armed note also
  names, mid-sentence, `a prompt typed while that turn was still running` as a
  possible cause. An absent `$HANDOFF_POINTER_DIR` is no marker: the sweep
  creates nothing and sweeps as today.
- Another session's file, `held`, `pending`, `link`, `malformed`, `unread` and
  the failure record are untouched by this change.
- The header comment's claim that the owner's prompt "cannot fire between the
  write and that turn's own end" is rewritten to what the reproduction showed,
  and so is the parenthesis about prose injected into a running turn.

`scripts/inject-checkpoint-root.sh` writes the marker on its matching path:
after the root resolves, when the input's `session_id` and `prompt_id` are both
non-empty. It writes with the drift marker's guards: `mkdir -m 700 -p`,
`marker_dir_ok`, a `mktemp` sibling matching `handoff-prompt-*`, and
`handoff_replace`. Shared with the sweep, so the guard and the writer move into
`_lib.sh`. A marker failure never changes the hook's output. The negative path
(NFR2) stays one jq parse and a substring test, now reading `session_id` and
`prompt_id` in the same parse. Writing at the checkpoint call rather than at
every prompt is the 2026-10-16 revision, after the red review found per-prompt
forks. Every real prompt carries a `prompt_id`, so recording each one in the
sweep would fork `find`, `mktemp` and a replace on every prompt.

`scripts/session-pointer.sh` sweeps `handoff-prompt-*` older than 7 days, as it
does `handoff-drift-*`.

### 2. The mod drives whatever is in the input box

`hooks/handoff.ts`: the `$.prompt.read()` bail before each line and its comment
go. `tests/mod/handoff.test.ts`: `prompt.read` leaves every expected log, and
the two bail rows go. Once the mod never reads the box, its absence from every
log pins the change. `tests/mod/rig.ts`: the `prompt.read` stub and `promptTexts` go,
since nothing calls them.

### 3. Records

A changelog entry and its index line; `docs/design/driving-the-transition.md`
and whatever else states the composer bail or the sweep's premise
(`CLAUDE.md`, `README.md`, `docs/design/`). The memory note
(`memory/cc-queued-prompt-hooks.md`) has already been committed on its own.

## Tests (red first)

Rows for the marker's writer go in `tests/checkpoint.bats`, beside the
`inject-checkpoint-root.sh` rows. They cover:

- the marker written NUL-terminated with the input's `prompt_id`, on
  `handoff-checkpoint` and on `handoff-approved`;
- not written for a non-matching command, nor without a `session_id` or
  `prompt_id`;
- a symlinked marker not written through;
- the hook's output byte-identical with and without a marker failure;
- an id holding a space or ending in a newline round-tripping.

The sweep's rows go in `tests/hook-test.bats`, each with its positive over the
same fixture:

- the `no find forked` row keeps holding with a `prompt_id` in the input;
- a marker id differing from the input's by a trailing space is swept, and a
  whitespace-shaped id that matches is spared;

- an owner's `armed` `rename` with the marker holding the input's
  `prompt_id`: left byte-identical, no output, no sweep record;
- the same fixture with a different `prompt_id`: swept with the
  unloaded-mod note, as today;
- the same as `clear` and as `compact`: swept, recorded, the cancel message and
  note (naming `handoff` for clear, `precompact` for compact), no lines offered
  (no `Type in order`), the unloaded-mod note absent;
- no `prompt_id` in the input: swept, and the note names a typed-ahead prompt;
- no marker yet (first prompt): swept;
- a symlinked marker not read, the sweep still running;
- the sweep writing no marker;
- another session's armed file whose `prompt_id` happens to match: unaffected
  by the marker (the existing liveness rule decides);
- `session-pointer.sh` sweeping a stale `handoff-prompt-*`.

Mutation checks: drop the owner test, drop the `prompt_id`-non-empty test,
drop the kind test, drop the marker write in `inject-checkpoint-root.sh`,
write the marker in the sweep on every prompt; each reds at least one row.
