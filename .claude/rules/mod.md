---
paths:
  - "hooks/**"
  - "tests/mod/**"
  - "tests/gen_mod_fixtures.py"
  - "scripts/drive-take.sh"
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
- The mod reads neither the sentinel nor the prompt box: `drive-take.sh` is
  the one reader, and its stdout is the plan the mod runs.
- `claude plugin test` runs `tests/mod/handoff.test.ts` against
  `tests/mod/rig.ts`, a stub rig that answers every mods API call the mod makes
  and logs them in order. The kit rejects an unstubbed call, `process.run`,
  `fs.*` and the clock included, so a new call needs a stub and its place in
  each expected log. No expected log holds a prompt-box read and the rig stubs
  none, so a restored one fails as an unstubbed call.
- `tests/mod/fixtures/*.json` are the plans `drive-take.sh` prints;
  `tests/drive-take.bats` pins its stdout to them. `tests/mod/fixtures.ts` is
  rendered from them by `tests/gen_mod_fixtures.py`, because a hooks-module
  test can neither read files nor import JSON: regenerate it with
  `python3 tests/gen_mod_fixtures.py`, never by hand.
  `tests/test_mod_fixtures.py` fails when they disagree, and ties every prose
  line a fixture submits to `CONTINUATION`.
- A new mod row goes in `tests/mod/handoff.test.ts`; a new plan shape is a
  fixture JSON plus a regeneration.
- The load-bearing mod rows (driving inside `Stop`, continuing after a
  rejection, dropping the consume-once reset, skipping the fast path) are
  mutation-checked, not observed passing. A new load-bearing row is too.
- Run `just mod-smoke` whenever the mod, a loader or the sentinel's shape
  changes; it found the `Stop` call-context refusal no stub could. It boots a
  real `claude -p --model haiku` with this repo as `--plugin-dir` and a fixed
  `--session-id` in a throwaway git repo, whose first turn writes an armed
  sentinel through one allowed `printf` call (a sentinel that predates the
  prompt is swept by `UserPromptSubmit`). Marker `live`, deselected from
  `precommit`; env allowlisted; `-rs`, so a skip is never read as a pass.
