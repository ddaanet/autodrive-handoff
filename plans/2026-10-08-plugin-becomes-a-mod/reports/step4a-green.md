# Step 4a (GREEN): drive-take.sh and the turn.complete mod

## Implemented
- `scripts/drive-take.sh <cwd>` (100755, shellcheck clean): the step-2 contract exactly. Reuses `handoff_root`, `handoff_drive_read/arm/has_source`; JSON via `jq -nc` (lines passed NUL-delimited). `bats tests/drive-take.bats` 11/11.
- `hooks/handoff.ts` (~100 lines): `classic.Stop` records cwd; `turn.complete` drives inline (no timer, per step 1); fast path via `$.session.root()` + `$.fs.exists`; `prompt.read` bail before each line; first rejection writes failFile + toasts and stops; no `/autoname`: the user decided `handoff:autoname` stays a skill riding the driver, so the mod's command, `model.fork` path, `pendingTitle` and rename branch were removed before commit (and their tests and stubs).
- Tests: the 7 autoname rows are gone. `claude plugin test`: `16 pass, 0 fail`.
- Fixtures drift: `scripts/gen_mod_fixtures.py` regenerates `tests/mod/fixtures.ts` (sorted, deterministic; header now names the generator); `tests/test_mod_fixtures.py` compares. Mutation: edited one byte of `malformed.json` -> pytest red; restored -> green.

## Mutations
| mutation | red |
|---|---|
| drive inside classic.Stop | 7 rows, incl. "Stop records the cwd and drives nothing" |
| drop prompt.read bail | "text in the prompt box before the first line bails", "text typed mid-sequence" (+5) |
| continue after rejection | "first rejected line ends the sequence and writes failFile" |
| drop consume-once reset (`stoppedIn = null` in turn.complete) | "a recorded cwd is consumed once" |
| skip project-root fast path | "project-root cwd without a sentinel never spawns" |
| drive-take: drop file check | bats 1, 11 |
| drive-take: drop armed gate | bats 6, 7, 8 |
| drive-take: ignore cwd (project root) | bats 10, 11 |
| drive-take: never arm | bats 2, 3, 5, 8, 10 |

## Results
- `just precommit`: green (`286 passed, 17 deselected`, ok). Two earlier runs failed on `tests/test_drive_when_idle.py::test_prose_confirms_submit_landing_after_fast_retry_window` (walker timing test, untouched by this step) while the box was loaded by concurrent runs; it passes alone (3/3) and at HEAD, and the quiet rerun was green.
- `claude plugin test`: ` 16 pass / 0 fail / Ran 16 tests across 1 file`.

## Deviations
- Drive is inline in `turn.complete` (step 1 finding), not `clock.after` in Stop.
- `just mod-smoke` not run (stays red until step 4b).

- Autoname removed from the mod per the user's decision; mutation rows 1-5 re-run after the removal, same reds.
