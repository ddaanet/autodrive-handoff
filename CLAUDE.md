# Agent Instructions — autodrive-handoff plugin

## The plugin and its flow

A boundary skill decides the content and issues one `handoff-checkpoint` Bash
call, the whole wrap-up as a schema-validated JSON payload on stdin.
`scripts/checkpoint.py` writes `TASK.md` and `TODO.md` in the project root,
plain tracked files that nothing stages, and composes the sentinel,
`.claude/autodrive`; it does no git work (NFR1). As the turn ends, the mod
(`hooks/handoff.ts`) records the cwd and session id in `classic.Stop`; in
`turn.complete`, `scripts/drive-take.sh` takes the sentinel this session owns
and prints the plan, and the mod runs each line through `$.command.run` (a
`/`-line) or `$.prompt.submit`. The transition's own
`SessionStart(clear|compact)` loader consumes the `pending` sentinel and
injects the frame; `SessionStart(startup)` injects it into a fresh session.
The loaders start no continuation: the mod submits it. `README.md` has the
user-facing version.

`handoff` is the `/clear` boundary's skill, `precompact` the `/compact` one's,
and `autoname` a rename only: the payload's `skill` field names it and keys
what the checkpoint prints. Only `handoff` carries `task` (FR13: at most 1000
characters of prose, no list item); `precompact` removes `TASK.md`, while
`TODO.md` survives it. Both carry `todo`. `clear` (bool) under `handoff`,
`compact` (bool, or a focus directive) under `precompact` and `continue`
(bool) at both are required, with no default. `continue: true` is legal only
when the transition is carried out (`typed` in the code), and under `handoff`
is refused when neither file would have a body; the continuation is the fixed
line `CONTINUATION` in `checkpoint.py`, which points at the files and carries
nothing. `compact: false` writes a two-line marker that runs nothing (FR-G),
on which `SessionStart(compact)` gates the todo's re-injection.

The sentinel's line 1 is its state and line 2 its kind: `held <session>`
waits on `bin/handoff-approved`, `armed <session>` on its owner's turn end,
and an ownerless `pending` on the loader. It is held iff (it names a command
∧ a memory directive was emitted) ∨ (driven ∧ `with-commit`). A plan of
`kind: null` carries a message and runs nothing. The checkpoint is the
sentinel's one composer (FR3): past it, `handoff_drive_arm` rewrites the
state line, and `write-guard.sh` denies an agent `Write`/`Edit` to the file.

The checkpoint's stdout is the procedure for the call's cell, which no skill
restates. It includes a directive to the `gitlore:commit` skill when the
`gitlore-memory` submodule is dirty (so the plugin needs a gitlore that ships
that skill) and the commit act under `with-commit`, and ends with the
`handoff-approved` instruction or the closing line. Parts and order:
`docs/design/the-checkpoint-directive.md`. `.claude/handoff-task.md` and
`.claude/handoff-todo.md` are legacy files, read as a fallback while the
bridge lasts (`.claude/rules/legacy.md`). The mod needs Claude Code >= 2.1.287
and does not load under `--safe-mode`, on an older Claude Code or under
managed settings that omit the plugin; the sweep's note says so. The FR and
NFR labels: `docs/design.md#requirements`.

## Components

One line each, with the node under `docs/design/` that holds its behaviour.

- `.claude-plugin/plugin.json` — manifest, with no minimum-version field
- `hooks/hooks.json` — the mod and six command hooks → driving-the-transition.md
- `hooks/handoff.ts` — the mod, which runs the plan → driving-the-transition.md
- `skills/handoff/SKILL.md` — clear boundary; templates, seam → the-skills.md
- `skills/precompact/SKILL.md` — the compact boundary → the-skills.md
- `skills/autoname/SKILL.md` — a session title → the-skills.md
- `skills/pending/SKILL.md` — lists the frame's open items → the-skills.md
- `skills/handoff/references/design.md` — condensed design notes that ship
  with the skill
- `bin/handoff-checkpoint` — PATH shim that execs `scripts/checkpoint.py`,
  since `${CLAUDE_PLUGIN_ROOT}` is unset in the agent's Bash
- `bin/handoff-approved` — leaves `held` → the-checkpoint-directive.md
- `scripts/checkpoint.py` — the one write path → the-write-path.md,
  the-checkpoint-directive.md
- `scripts/_checkpoint_payload.py` — payload validation → the-write-path.md
- `scripts/_checkpoint_plan.py` — the file plans → the-write-path.md
- `scripts/_checkpoint_lib.py` — `err`, `is_empty_body`, the directive texts
  → the-write-path.md, the-checkpoint-directive.md
- `scripts/_drive_lock.py` — the sentinel's advisory lock → sentinel-lock.md
- `scripts/worktree_root.py` — the session-root resolver → scoping.md
- `scripts/_lib.sh` — the one sourced helper: constants, root resolver, lock,
  owner liveness; sources the next three → scoping.md,
  sessions-sharing-a-root.md
- `scripts/_lib_frame.sh` — `handoff_frame` and its notes → the-write-path.md
- `scripts/_lib_drive.sh` — the sentinel's grammar → driving-the-transition.md
- `scripts/_lib_files.sh` — no-follow reads, replacing writes → scoping.md
- `scripts/drive-take.sh` — takes this session's `armed` sentinel, prints the
  plan → driving-the-transition.md
- `scripts/load-handoff.sh` — `SessionStart(startup|clear)` loader →
  driving-the-transition.md
- `scripts/load-compact.sh` — `SessionStart(compact)` loader →
  driving-the-transition.md
- `scripts/report-drive-failure.sh` — `UserPromptSubmit`: failure report,
  sweep, drift note → driving-the-transition.md, queued-prompts.md,
  sessions-sharing-a-root.md
- `scripts/write-guard.sh` — `PreToolUse(Write|Edit)`: denies a direct write
  to the sentinel → the-write-path.md
- `scripts/inject-checkpoint-root.sh` — `PreToolUse(Bash)`: exports
  `HANDOFF_ROOT`, records the prompt marker → scoping.md
- `scripts/session-pointer.sh` — sweeps stale markers → scoping.md
- `tests/gen_mod_fixtures.py` — renders `tests/mod/fixtures.ts` from
  `tests/mod/fixtures/*.json`
- `plugin-dev/` — vendored toolkit, read-only → release-infrastructure.md
- `.envrc` — activates the venv and pulls in `~/code/.envrc`
- `.claude/rules/` — editing conventions, each scoped by its `paths:`

## Routing

What you are touching → what to read first, under `docs/design/`:

- `checkpoint.py`, `_checkpoint_payload.py`, `_checkpoint_plan.py`,
  `_checkpoint_lib.py`, `write-guard.sh`, `handoff_frame`,
  the two files, FR1–FR8, FR13, NFR1–NFR3 → `the-write-path.md`
- any `skills/*/SKILL.md`, a `skill` value, the `clear`/`compact`/`continue`/
  `commit` fields → `the-skills.md`
- `hooks/handoff.ts`, `drive-take.sh`, `load-handoff.sh`, `load-compact.sh`,
  `report-drive-failure.sh`'s sweep, `.claude/autodrive` and its states, FR-G
  → `driving-the-transition.md`; a prompt arriving while the arming turn runs,
  the prompt marker → `queued-prompts.md`; the sentinel's lock,
  `_drive_lock.py`, `handoff_lock_take` → `sentinel-lock.md`; a second session
  in the root, `handoff_owner_live`, `HANDOFF_OWNER_LIVE_SECS`,
  `autodrive.swept` → `sessions-sharing-a-root.md`
- `handoff-approved`, `closing_directive`, `ledger_path`, `held`,
  `with-commit`, the gitlore seam, FR9, FR12 → `the-checkpoint-directive.md`
- `worktree_root.py`, `handoff_root_read`, `inject-checkpoint-root.sh`,
  `session-pointer.sh`, `HANDOFF_ROOT` → `scoping.md`
- `plugin-dev/`, `release.just`, `$MARKETPLACE_DIR` →
  `release-infrastructure.md`
- weighing or adding a standing call → `decisions.md`; re-proposing something
  ruled out → `rejected-alternatives.md`

## Where documents go

- `docs/design.md` — the design hub; `docs/design/` — one node per
  mechanism, read before making a claim about it.
- `docs/changelog.md` — the index; `docs/changelog/` — a frozen archive of
  the write-time records up to 2026-10-31. Later design history is `git log`.
- `plans/` — specs, proposals, implementation plans and their reports.
- `inbox/` — what arrives from a session in another repository.
- The editing rules for all four: `.claude/rules/docs.md`.

## Conventions

- `TASK.md` and `TODO.md` live in the project root (FR4), plain tracked
  files that no hook guards or stages. Changing either's path or shape is a
  breaking change and requires a version bump.
- `TODO.md` holds **open items only**. A finished item is dropped, never
  checked off: what landed is reconstructable from `git log`, and a done item
  still listed reads as outstanding and gets redone.
- `plugin-dev/` is vendored and read-only.
- When acknowledging a `release X.Y.Z` request, name both push targets up
  front — "bumps `handoff` (tag + GH release) and `claude-plugins`
  (marketplace entry)" — since auto-mode's permission harness reads only the
  current message.
- `version-guard.sh` (wired in `.claude/settings.json`) refuses agent edits
  that change `plugin.json`'s `.version`.
- A design change rewrites the design prose it invalidates, in the same
  commit; the commit body says why it changed.

## Gates

The shell hooks are tested with bats, the Python with pytest, the mod with
`claude plugin test` (`tests/mod/handoff.test.ts` against `tests/mod/rig.ts`).
pytest runs off a uv-managed venv that direnv activates (`.envrc` exports
`VIRTUAL_ENV` and prepends its `bin` to `PATH`), so the recipes call bare
`pytest`, never `uv run`; `uv sync` materializes it (`uv.lock` is committed,
`.venv/` gitignored). `claude` is excluded from the command sandbox: every
`claude` call from the agent's Bash, and so `just precommit`,
`just validate-plugin` and `just mod-smoke`, needs `dangerouslyDisableSandbox`.

- `just precommit` — the gate, run before every commit; needs the venv. It
  depends on `check-plugin` and `check-code`, cached gates that skip while
  their inputs are unchanged (`PLUGIN_DEV_GATE_FORCE=1` runs them regardless),
  and on `check-refs` and `check-size`, uncached checks that run every time:
  Markdown links, and the toolkit's byte caps (20000, 10000 for a `SKILL.md`).
  A file kept over a cap is listed in the root `size.exempt`, with what ends
  its overage. `release` depends on `precommit` through `prerelease`.
- The `justfile` lists each gate's inputs: a new component directory the
  plugin validator reads (`agents/`, `commands/`) goes into `check-plugin`'s.
- `just validate-plugin` — `claude plugin validate --strict --json`, failing
  on any error or warning except two that cannot be fixed: the root
  `CLAUDE.md` "not loaded as project context" warning, and the invalid-JSON
  error for an empty root `.mcp.json` the command sandbox creates.
- `just mod-smoke` — a live `claude -p` smoke test, deselected from
  `precommit`; run it when the mod, a loader or the sentinel's shape changes.
- `just hook-test` — `bats tests/*.bats` alone; `just py-test` — `pytest`.
- `just release` needs `MARKETPLACE_DIR`, which `~/code/.envrc` exports and
  this repo's `.envrc` pulls in with `source_up_if_exists`; `direnv allow`
  once per clone. See `docs/design/release-infrastructure.md`.

## Non-goals and the frame

- The frame is a timestamp header plus the inlined `TASK.md` and `TODO.md`,
  with no transcript, session id or file list:
  `docs/design/the-write-path.md#the-seam`.
- Non-goals: `docs/design.md#non-goals`. The one that changes what an agent
  does: concurrent sessions in one root are unsupported, so one session per
  root, or a worktree each.

## What this file holds

These are the conventions for editing the plugin's skill, hook, mod or script
inside this repo. Every session here loads this file, so it holds only what
is needed before any file is opened: the flow, one line per component, the
routing, the always-on conventions and the gates; no mechanism prose, no test
inventory. A behaviour goes in its design node, a test's coverage in the test
file, an editing convention in the `.claude/rules/` file whose `paths:` cover
the files it governs, and a new component adds one line to the index.

@memory/ddaanet/shared-claude.md
