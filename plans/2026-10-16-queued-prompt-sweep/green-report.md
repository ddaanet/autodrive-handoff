# Queued-prompt sweep: green-phase report

Implementation only; no test file touched; nothing committed.

## Files changed

- `scripts/_lib.sh`: `marker_dir_ok` moved here (with its comment); new `handoff_write_marker <path> <value>` (mktemp sibling `<path>.XXXXXX`, NUL-terminated, `handoff_replace`).
- `scripts/report-drive-failure.sh`: `prompt_id` read as a 4th NUL-terminated field in the existing jq call; queued = armed ∧ owner == session ∧ session_id and prompt_id non-empty ∧ marker (`handoff-prompt-<session_id>`, read through `marker_dir_ok` and `handoff_read_regular … own`) equals prompt_id. Queued rename: left in place, nothing printed. Queued clear/compact: `record_sweep`, msg `transition cancelled — a prompt arrived before it ran`, the agent note per the red-report (`/clear`+`handoff`, `/compact`+`precompact`), no lines. Armed unloaded note gains `, as does a prompt typed while that turn was still running` only when the input has no prompt_id. Drift writer now uses `handoff_write_marker`. Header point 2 rewritten to the reproduction's findings; the false premise and the parenthesis are gone. The marker is never written here.
- `scripts/inject-checkpoint-root.sh`: one jq parse now also reads `session_id` and `prompt_id` (NUL-terminated). After the root resolves, when both are non-empty: `mkdir -m 700 -p`, `marker_dir_ok`, `handoff_write_marker`, all stderr-silenced and `|| true`, so stdout is unchanged on failure.
- `scripts/session-pointer.sh`: sweeps `handoff-prompt-*` with the drift name, `-mtime +7`; comments updated.
- `hooks/handoff.ts`: `prompt.read` bail and its comment removed from `drive()`.
- `tests/mod/rig.ts`: `prompt.read` stub, `reads` counter, `promptTexts` and the type comment removed.

## Gates

- `bats tests/hook-test.bats tests/checkpoint.bats tests/drive-take.bats`: 323 tests, 0 not ok (last line `1..323`).
- `claude plugin test` (sandbox off): 16 pass, 0 fail.
- `shellcheck -x bin/* scripts/*.sh tests/*.bats`: clean, rc 0.
- `just precommit` (sandbox off): jq, validate-plugin, plugin test, shellcheck, ruff/docformatter/mypy/ty, bats (323 ok) and pytest all passed; pytest 497 passed, 3 deselected (live marker).

## Not done

- Mutation checks listed in the plan were not run; only the gates above.
- `docs/`, `CLAUDE.md`, `README.md` and `memory/` are untouched, as instructed. Docs and changelog still state the old sweep premise.
- Nothing could not be made to pass.
