---
paths:
  - "hooks/**"
  - "tests/mod/**"
  - "tests/gen_mod_fixtures.py"
  - "scripts/drive-take.sh"
  - "scripts/drive-cancel.sh"
  - "scripts/load-*.sh"
  - "scripts/_lib_drive.sh"
---

# Mod and drive conventions

Behaviour lives in `docs/design/driving-the-transition.md`; read it first.

- `hooks/hooks.json` reaches every script through `${CLAUDE_PLUGIN_ROOT}`,
  for portability, and double-quotes each such path; the validator warns
  otherwise.
- Never drive from `Stop`: the host refuses `$.command.run` from a `Stop`
  hook's call context, `$.clock.after` included, and timers die under `-p`.
  `classic.Stop` only records; `turn.complete` drives, inline.
- A hooks module may pass `$` only to top-level functions (a static check at
  load).
- The mod reads neither the sentinel nor the prompt box: it runs
  `drive-take.sh` and executes the plan on its stdout, and a prompt in the
  window after `Stop` runs `drive-cancel.sh` once.
- The plan is data: `{kind, arg, continue, failFile, message}`. Every command
  name and the one prompt are literals in `hooks/handoff.ts` (`commandsFor`,
  `CONTINUATION`); a plan field is an argument, never a command or text to
  submit, and an unknown kind runs nothing. A new command or prompt is a new
  literal and a new kind in the sentinel's table
  (`docs/design/the-sentinel.md`), never a field read off the plan.
- `claude plugin test` runs `tests/mod/*.test.ts` against
  `tests/mod/rig.ts`, a stub rig that answers every mods API call the mod makes
  and logs them in order; `process.run` answers per script
  (`stdout` for the take, `cancelStdout` for the cancel, logged `process.run
  cancel`) and can hold an answer open (`hold`, `holdLine`). The kit rejects an unstubbed call, `process.run`,
  `fs.*` and the clock included, so a new call needs a stub and its place in
  each expected log. No expected log holds a prompt-box read and the rig stubs
  none, so a restored one fails as an unstubbed call.
- `tests/mod/fixtures/*.json` are the plans `drive-take.sh` prints and the
  `cancel-*` plans `drive-cancel.sh` prints; `tests/drive-take.bats` and
  `tests/drive-cancel.bats` pin their stdout to them. `tests/mod/fixtures.ts` is
  rendered from them by `tests/gen_mod_fixtures.py`, because a hooks-module
  test can neither read files nor import JSON: regenerate it with
  `python3 tests/gen_mod_fixtures.py`, never by hand.
  `tests/test_mod_fixtures.py` fails when they disagree, and pins the mod's
  `CONTINUATION` literal to `HANDOFF_CONTINUATION` in `_lib_drive.sh`.
- A new mod row goes in `tests/mod/handoff.test.ts`, or `window.test.ts` when it
  is about a prompt after `Stop`; a new plan shape is a
  fixture JSON plus a regeneration.
- The load-bearing mod rows (driving inside `Stop`, continuing after a
  rejection, dropping the consume-once reset, skipping the fast path, the
  cancel check before each command, closing the window before the last
  command, a drive clearing only its own window at its end and at the last
  command, the window's answer living on the window, an unknown kind running
  nothing, `continue` false submitting nothing) are mutation-checked, not
  observed passing. A new load-bearing row is too.
- Run `just mod-smoke` whenever the mod, a loader or the sentinel's shape
  changes; it found the `Stop` call-context refusal no stub could. It boots a
  real `claude -p --model haiku` with this repo as `--plugin-dir` and a fixed
  `--session-id` in a throwaway git repo, whose first turn writes an armed
  sentinel through one allowed `printf` call (a sentinel that predates the
  prompt is swept by `UserPromptSubmit`). Marker `live`, deselected from
  `precommit`; env allowlisted; `-rs`, so a skip is never read as a pass.
