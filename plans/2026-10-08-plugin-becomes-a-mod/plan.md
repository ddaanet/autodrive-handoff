# handoff becomes a mod: replace the tmux walker with `$.command.run`

## Context

Claude Code mods (v2.1.287+, installed 2.1.294) let a plugin's JS/TS module run
any slash command "as if the person typed `/command args`"
(`$.command.run({command, args})`) and submit a prompt (`$.prompt.submit({text,
asUser})`). Everything the tmux walker exists for — typing `/rename`, `/clear`,
`/compact <focus>` and a continuation into the composer, then confirming each
landed by scraping the pane — becomes a handful of engine calls. My human
partner decided: the plugin becomes a mod; all tmux machinery goes;
`/handoff:restart` is superseded by a built-in `/restart` and is removed;
`/handoff:autoname` moves into the mod; relevant tests are ported and new code
is tested integration-first.

What stays (confirmed): the checkpoint write path, the memory/commit directive,
the `held` → `handoff-approved` gate, the sentinel as the one record of the
armed transition, and frame injection by the `SessionStart` loaders.

API facts this plan rests on (from `mods/types/claude-code.d.ts` + docs):
- `$.command.run` "rejects an unknown name, and inside a hook the turn is
  waiting on" → the Stop handler must return `next(e)` and defer the drive with
  `$.clock.after(0, …)`.
- `$.session.compact` "rejects while a turn runs" (not used; `command.run
  ('compact', focus)` keeps the sentinel's literal lines meaningful).
- `$.prompt.submit` "runs when the session is idle".
- `session.start` never fires after `/clear`; `session.end` does (`reason: clear`).
- Every mods API call in `claude plugin test` must be stubbed (incl.
  `process.run`, `fs.*`, `clock`).
- `$.fs.write` is not atomic.

## Design

**One mod module, `hooks/handoff.ts`**, declared via `"modules": ["./handoff.ts"]`
in the existing `hooks/hooks.json` beside the classic hooks.

- `on('classic.Stop', …)`: return `next(e)` at once; schedule
  `$.clock.after(0, drive)` with `e.cwd`. Stop (not `turn.complete`) keeps the
  "Esc arms nothing" guarantee and the payload the scripts already read.
- `drive`: fast path in TS first — when `e.cwd` is the project root and
  `$.fs.exists(<cwd>/.claude/autodrive)` is false, return (no spawn on the
  every-turn path; a worktree/subdir cwd falls through to the script, which owns
  root resolution). Otherwise
  `$.process.run(['bash', `${$.plugin.root}/scripts/drive-take.sh`, cwd])`;
  empty stdout ⟹ nothing armed, else JSON
  `{kind, before[], after[], failFile, message}`.
  Why a script and not TS: `handoff_drive_read` is the one parser (checkpoint
  read-back, both loaders, the sweep, `handoff-approved`), and a TS copy is a
  second one that can drift; `$.fs` has no rename or delete, so the atomic
  `armed→pending` (`handoff_drive_arm`) and the `rm` for `rename` cannot be
  done from the mod; and root resolution lives in `worktree_root.py`.
- Execute lines in order: `/x args` → `$.command.run({command:'x', args})`;
  prose → `$.prompt.submit({text, asUser:true})`. Before each line,
  `$.prompt.read()` — bail if the user has text in the prompt (parity with
  `composer_has_user_text`). First rejection ends the sequence and is recorded
  to `failFile` (one-shot marker; non-atomic write accepted — it is created
  once, read once). `$.ui.toast` for immediate user visibility; the existing
  `UserPromptSubmit` report still carries it to the agent.
- **The mod never touches the sentinel.** `drive-take.sh` (today's
  `stop-drive.sh`, minus everything tmux) parses via `handoff_drive_read`, gates
  on `armed`, does `armed→pending` (`handoff_drive_arm`, atomic) or `rm` for
  `rename`, and prints the plan. FR-G (empty `before`) prints only `message`.
- **Loaders lose their walker spawn**: `load-handoff.sh` (clear branch) and
  `load-compact.sh` just consume `pending` and inject the frame; the mod submits
  the continuation after `command.run('clear'|'compact')` resolves.
- **Autoname as a mod command** (`/autoname`, registered last in
  `session.start`, try/catch — `register` throws on a taken name):
  `$.model.fork({prompt})` with the skill's title + punctuation rules over the
  current conversation, then `$.command.run({command:'rename', args: title})`.
  No agent turn, no checkpoint call. `skills/autoname/` and the `autoname`
  `skill` value are deleted.
- **Mod not loaded** (`--safe-mode`, CC < 2.1.287): the armed sentinel survives
  to the next prompt and the existing sweep reports it; extend its note to name
  this cause and print the lines to type (the old not-in-tmux paste form,
  relocated).
- Rename `report-watcher-failure.sh` → `report-drive-failure.sh` (no watcher left).

## Removed

- Walker: `scripts/drive_when_idle.py`, `scripts/_watcher_lib.py` (whole — the
  transcript readers only confirmed `/rename`, which `command.run` makes moot),
  `handoff_spawn_detached`, `HANDOFF_REL_DRIVE_EXITED`/`_LOG`, all paste
  fallbacks, the `Stop` and `SessionEnd` entries in `hooks.json`.
- Restart: `skills/restart/`, `scripts/load-restart.sh`, `scripts/session-end.sh`,
  `SessionStart(resume)` entry, `restart` kind in `handoff_drive_read`,
  `_build_restart_transition`, `restart` skill value.
- Tests: `tests/test_drive_when_idle.py`, `tests/test_tui_conformance.py`,
  `tests/conftest.py`, `tests/test_watcher_lib.py`; in `hook-test.bats` the tmux
  stub, walker-spawn stub, "walker is handed … paths" and "not in tmux" rows,
  session-end/load-restart sections; restart/autoname rows in
  `test_checkpoint.py`; justfile `tui-conformance`, pyproject `live` marker.
- `inbox/2026-09-29-note-stale-restart-replay-claim.md` (moot).
  `inbox/brief-session-start-skill-checkpoint.md` is out of scope.

## Steps (integration-first)

1. **Live smoke test first (red), which is also the spike.** `tests/test_mod_live.py`
   (`live` marker, `just mod-smoke`, outside precommit): a temp git repo with
   the plugin via `--plugin-dir`, a pre-staged `armed` sentinel, a cheap model
   turn. Exit criteria — four facts, each with its consequence:
   a. `command.run` from `clock.after(0)` inside `classic.Stop` succeeds →
      else find the right deferral before anything else.
   b. `SessionStart(clear)` fires for a mod-run `/clear` and `load-handoff.sh`
      consumes `pending` → else the frame must be injected by the mod
      (`prompt.context`), a different plan; stop and report.
   c. `prompt.submit({asUser:true})` lands in the fresh conversation after it.
   d. `-p` keeps the process alive for the deferred drive → else the live host
      needs an interactive session; see question 3.
   Rows: `rename` (custom-title in transcript), `clear` + continuation (new
   session's first user prompt), `compact` + focus.
2. **Contract fixtures.** `tests/mod/fixtures/*.json`: the plan `drive-take.sh`
   prints per kind/state. Bats runs the real script over real sentinel files
   and asserts stdout equals the fixture (ports `stop-drive.sh`'s state rows:
   armed-only, pending ignored, malformed discarded, rename removed, FR-G).
3. **Mod tests** (`tests/mod/handoff.test.ts`, `claude plugin test`): stub
   `process.run` with those same fixtures; assert the exact `command.run` /
   `prompt.submit` sequence, stop-on-first-failure + `failFile` write, bail on
   non-empty prompt, no-op on empty stdout, Stop handler returns before driving
   (`mock.clock` + `settle`), autoname fork→rename and the taken-name catch.
   Mutation-check the load-bearing rows (deferral, stop-on-failure, prompt bail).
4. Implement `drive-take.sh` + `hooks/handoff.ts` to green; strip loaders;
   delete walker/restart/autoname code and tests; schema/`handoff_drive_read`
   lose `restart`/`autoname`; rename the report hook; extend the sweep note.
5. Gate: `just precommit` gains `claude plugin validate --strict` and
   `claude plugin test` (needs `dangerouslyDisableSandbox` from agent Bash —
   `claude` is sandbox-excluded). Check whether `plugin.json` can pin a
   minimum CC version (≥2.1.287).
6. Records: new `docs/changelog/2026-10-08-the-plugin-becomes-a-mod.md` + index
   line; `driving-the-tui.md` → `driving-the-transition.md` rewritten; hub
   (`docs/design.md`): FR-H retired (number kept), NFR1 loses its tmux clause,
   the three pane-reading decisions move to rejected alternatives with "driving
   the TUI through tmux"; `Superseded` blockquotes on tmux-era changelog
   entries; `skills/*/SKILL.md` prose ("typed into a composer", "outside
   tmux"); `README.md`; `CLAUDE.md` layout/testing sections trimmed.
7. Dogfood the same day: a real `/handoff:handoff` with `clear: true` +
   continuation, and `/autoname`, in this repo.

Breaking (two `skill` values and one kind gone) → version bump via
`just release` is my human partner's call, not part of this plan.

## Verification

- `just precommit` green (bats incl. contract rows, pytest, `claude plugin
  validate --strict`, `claude plugin test`).
- `just mod-smoke` green against CC 2.1.294.
- Dogfood (step 7): title set, conversation cleared, frame injected,
  continuation submitted; then a forced failure (unknown command line) reported
  at the next prompt.

## Settled questions

My human partner approved the plan with these defaults standing:

1. **Autoname** — a mod command `/autoname` via `$.model.fork`; the skill is
   deleted. `fork` is one request over the current conversation (same model and
   system prompt, mostly prompt-cache reads, billed to the user's plan) that
   resolves to the reply text, which the mod passes to `$.command.run({command:
   'rename', args})`. Unverified, so asserted by the live test: the fork's
   exchange is not appended to the transcript, and no `turn.start` fires.
2. **`/restart`** — confirmed built-in by my human partner; `/handoff:restart`
   is removed.
3. **Live test host if `-p` exits before the deferred drive** — drive an
   interactive session on a private tmux socket *in the test only* (test
   infra, not product). Never the default socket; needs
   `dangerouslyDisableSandbox`.

## Execution

Delegated `/build`: a Sonnet orchestrator dispatching Haiku 5.5 for
well-defined implementation tasks, Sonnet 5.5 for tests and for tasks needing
judgement or prose, Opus 5.5 for code reviews. Every subagent is unnamed and
none is a teammate.
