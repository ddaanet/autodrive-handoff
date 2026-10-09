# 2026-10-08 — The plugin becomes a mod

The tmux walker is gone. The transition a checkpoint arms is now run by a
Claude Code mod, `hooks/handoff.ts`, through the host's own command and prompt
entry points, and everything that existed to type into a pane and read the
pane back is deleted with it.

## The defect

Carrying a transition out meant typing `/rename`, `/clear` or
`/compact <focus>` and a continuation into the composer of a live TUI, from a
detached walker (`drive_when_idle.py`, spawned by a `Stop` hook and, for the
lines after the transition, by its `SessionStart` loader). That is a program
that has to decide, from a screen capture, when the composer is idle, whether
the line it typed landed, and when the terminal belongs to a shell again. None
of that is documented, and the record of the design is the record of those
guesses being wrong, one at a time:

- every driven line failed 100% with "did not land" until the predicates were
  rebuilt from captures of a real pane
  ([2026-08-13](2026-08-13-predicates-match-the-real-pane.md));
- three confirmation signals failed independently — a stale scrollback timer
  reading as busy, a queued submit with no spinner, a 103-second compaction
  with none either
  ([2026-07-22](2026-07-22-confirm-the-compaction.md));
- the driven restart needed a run of repairs between 2026-08-13 and 2026-09-22,
  each found by a real dogfood, ending in a gate keyed to one character the TUI pads its glyph with
  ([2026-09-22](2026-09-22-the-composer-row-carries-its-own-gap.md));
- outside tmux nothing could be driven at all, so the lines were printed for
  pasting, and the agent's sandbox could not reach tmux, which forced a
  detached process to carry everything that touched it.

Claude Code 2.1.287 added mods: a plugin's JS module can run any slash command
"as if the person typed it" (`$.command.run`), submit a prompt
(`$.prompt.submit`), read the prompt box (`$.prompt.read`) and show a toast.
That is the whole surface the walker approximated. My human partner decided
the plugin becomes a mod, all tmux machinery goes, `/handoff:restart` is
superseded by the built-in `/restart` and removed, and the relevant tests are
ported with the new code tested integration-first.

## What changed

- `hooks/handoff.ts` runs the transition. `classic.Stop` records the turn's
  cwd; `turn.complete` drives, inline. `scripts/drive-take.sh` — the old
  `stop-drive.sh` minus everything tmux — is the one reader of the sentinel:
  it takes it, leaves `armed` before printing, and prints the plan as JSON.
  The mod runs each line through `command.run` or `prompt.submit`, bails when
  the prompt box has text, stops at the first rejected line and records it in
  `.claude/autodrive.failed`.
- The loaders lose their walker spawn: `load-handoff.sh` and `load-compact.sh`
  consume `pending` and inject the frame, and the mod submits the continuation
  itself once the command resolves.
- `report-watcher-failure.sh` becomes `report-drive-failure.sh`, and its sweep
  of a surviving `armed` sentinel names the mod not being loaded as the likely
  cause and prints the lines for the user to run, the old not-in-tmux paste
  form relocated.
- Removed: `drive_when_idle.py`, `_watcher_lib.py`, `stop-drive.sh`,
  `session-end.sh`, `load-restart.sh`, `skills/restart/`, the `Stop`,
  `SessionEnd` and `SessionStart(resume)` hook entries, `handoff_spawn_detached`,
  the `restart` kind and skill value, FR-H, and the tmux stub, the
  tmux-conformance suite and the watcher tests with them.
- Added to the gate: `claude plugin validate --strict` (filtered of the one
  warning that cannot be fixed, this repo's own `CLAUDE.md`) and
  `claude plugin test` over `tests/mod/`.

The design node is [Driving the transition](../design/driving-the-transition.md);
the rejected family is under "Driving the TUI through tmux".

## Alternatives weighed

**Defer from `Stop` with `$.clock.after(0)`.** The plan's first design, from
the API's own wording: `command.run` "rejects inside a hook the turn is
waiting on", so return from `Stop` at once and drive from a zero-delay timer.
Refuted by the live smoke test, below.

**Drive from `turn.complete`, recording the cwd in `Stop`.** Adopted.
`turn.complete` carries no cwd, so `Stop` records it; keeping `Stop` as the
gate also keeps "Esc arms nothing", because an interrupted turn fires no
`Stop`.

**A `/autoname` mod command.** The plan's first answer for the third `skill`
value: register a command that forks a title and runs `/rename`. A probe
refuted it. A local command ends in no `turn.complete` and no
`Stop`; `$.command.run` and `$.prompt.submit` are both refused from inside the
command's handler; a `$.clock.after(0)` from it never ran. The title could be
stored and applied only after the next ordinary model turn, and under `-p`
never. `$.model.fork` also resolves to a result object, not a string. So
`autoname` stays a skill whose one checkpoint call composes a `rename`
sentinel, which the drive runs at the end of the turn that wrote it, and the
mod registers no command.

**A TypeScript reader for the sentinel**, to skip the spawn. `handoff_drive_read`
already serves the checkpoint's read-back, both loaders, the sweep and
`handoff-approved`; a sixth copy drifts, `$.fs` has no rename or delete for the
atomic `armed` → `pending` or the removal for `rename`, and root resolution
lives in `worktree_root.py`. The every-turn cost is already one `exists` on the
project root.

**Pin the minimum Claude Code version in `plugin.json`.** No such field
exists: the manifest reference strips unknown keys, and `dependencies` names
other plugins. The requirement (2.1.287) is stated in the README and surfaces
at runtime through the sweep note when the mod did not load.

**A restart skill ported to the mod.** Claude Code ships `/restart`, and
`--resume` carries the conversation whole, so there was nothing for the kind to
add.

## What the live smoke test found

The test (`tests/test_mod_live.py`, `just mod-smoke`) was written first, red,
and doubled as the spike for four facts the design rested on, against Claude
Code 2.1.295 under `claude -p`:

- **`command.run` from `clock.after(0)` inside `classic.Stop` fails.** The host
  refuses it as "called from a classic.Stop hook, it would wait on the turn
  this hook is holding; run it from a later event (turn.complete)". The check
  follows the call context the timer inherits, not the delay: `after(0)` and
  `after(300)` both reject, and `after(2000)` ran after the process had torn
  down. This moved the drive into `turn.complete`, called with no timer, which
  fires 0.4–1.7s after `Stop`. A timer started from `turn.complete` fails under
  `-p` too, so the drive is inline there as well, and awaiting `command.run`
  inline did not deadlock.
- **`SessionStart(clear)` fires for a mod-run `/clear`**, with a new session id
  and transcript, so `load-handoff.sh` consuming `pending` and injecting the
  frame is reachable; the same holds for `SessionStart(compact)`.
- **`prompt.submit({asUser: true})` lands in the fresh conversation**, as a
  real user entry, after a clear or a compaction.
- **`-p` stays alive for the inline drive** until the submitted continuation
  turn finishes, so the live host needs no tmux fallback.

The test also found a flaw in its own setup. It pre-armed `.claude/autodrive`
before the first prompt, and the `UserPromptSubmit` sweep discards an `armed`
sentinel that predates the prompt — which it did before this change too; the
first red run of the test had hidden it. The first turn now writes the sentinel
through one allowed `printf`, which also makes the row exercise the real
sequence: checkpoint, turn end, take. The clear row additionally asserts the
sentinel is gone afterwards, so a loader that stops consuming `pending` fails
it.

## Left for the dogfood

A real `/handoff:handoff` with `clear: true` and a continuation, and
`/handoff:autoname`, run in this repo; then a forced failure, reported at the
next prompt. Breaking — two `skill` values and one kind are gone — so a version
bump is a release decision, not part of this change.
