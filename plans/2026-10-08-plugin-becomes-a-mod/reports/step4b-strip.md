# Step 4b: the stripping

## Files removed
- scripts: `drive_when_idle.py`, `_watcher_lib.py`, `stop-drive.sh`, `session-end.sh`, `load-restart.sh`
- `skills/restart/`
- tests: `test_drive_when_idle.py`, `test_tui_conformance.py`, `test_watcher_lib.py`, `conftest.py` (nothing else imported its `tmux_stub`; no fixture needed moving)
- `inbox/2026-09-29-note-stale-restart-replay-claim.md` was not present; `inbox/brief-session-start-skill-checkpoint.md` untouched.

## Files changed
- `scripts/_lib.sh`: dropped `handoff_spawn_detached`, `HANDOFF_REL_DRIVE_EXITED`, `HANDOFF_REL_DRIVE_LOG`; `restart` removed from `handoff_drive_read` (header, shape, error texts) and `handoff_drive_has_source`; comments name the mod and `drive-take.sh` instead of the walker and Stop.
- `scripts/load-handoff.sh`, `scripts/load-compact.sh`: walker spawn, tmux check, paste fallback, `HANDOFF_*` exports and `transcript_path` handling gone. Both still consume `pending` of their own kind (malformed: discard + note; armed/other kind: left alone) and inject the frame exactly as before. `load-handoff.sh` consumes before the no-frame exit, so a clear with an empty task file still consumes. Contract kept with `drive-take.sh`: it leaves `pending` for `clear` and `compact`, the loader removes it.
- `hooks/hooks.json`: `Stop`, `SessionEnd`, `SessionStart(resume)` entries removed, `UserPromptSubmit` points at `report-drive-failure.sh`, `modules` kept, description rewritten (re-serialised by `json.dumps`, so `modules` is now multi-line).
- `scripts/checkpoint.py`, `scripts/_checkpoint_lib.py`, `bin/handoff-approved`: `_build_restart_transition`, `validate_restart_forbidden_fields`, the `restart` skill value and all its branches removed; the clause-file refusal now says `/restart` (the built-in) instead of `/handoff:restart`. `require_session_id` stays (the held sentinel uses it). `handoff-approved`'s unreachable `*)` unknown-kind arm and its bats row are removed: the parser now only admits `rename|clear|compact`.
- `scripts/report-watcher-failure.sh` renamed (git mv) to `scripts/report-drive-failure.sh`; wording "watcher" to "drive". New sweep note for a surviving `armed` sentinel: names the drive mod not loaded (`--safe-mode`, Claude Code older than 2.1.287; an interrupt leaves the same trace) and prints the lines, before then after, one per line, in a fenced-block instruction on the agent channel and as `Type in order:` plus the lines on the user channel. Kept: `held` exemption, dead-session reclassification (its own text, no lines offered), malformed (no lines), drift, `.claude/autodrive.failed`.
- `tests/hook-test.bats`: tmux stub, `HANDOFF_WATCHER_*`, `stub_walker`, `wait_for_walker_spawn`, restart shape rows, whole stop-drive, session-end and load-restart sections, "not in tmux" and "walker is handed" rows removed; loader rows adapted (no continuation echo, still consume); `run_load_handoff`/`run_load_compact` lost their tmux-prefix argument and `transcript_path`; sweep rows renamed; 3 new rows.
- `tests/test_checkpoint.py`: restart section, restart unknown-key row, `/handoff:restart` assertions now `/restart`. `tests/checkpoint.bats`: unexpected-kind row, `TMUX=fake` prefixes, stale comment.
- `justfile` (`tui-conformance` removed, `py-test` comment), `pyproject.toml` (`live` marker text, addopts comment, ruff RUF00x comment), `.gitignore` comment, `scripts/bash-post.sh` comment, `tests/test_worktree_root.py` comment, `tests/mod/fixtures/README.md` (stop-drive wording), skills: `autoname` and `precompact` lost the tmux/paste-outside-tmux wording, `handoff` example prompt "watcher tests" became "parser tests".
- `tests/test_mod_live.py`: see deviation 1.

## Mutation table, new bats rows (`report-drive-failure`)
| mutation of `scripts/report-drive-failure.sh` | red rows |
|---|---|
| paste text never built | "stale armed autodrive: names the mod and prints the lines to type" |
| cause sentence removed from the note | the same row, and "stale armed autodrive with no lines: names the mod, prints nothing to type" |
| lines also offered for the `abandoned` (dead-session held) state | "held file of a dead session: lines are not offered" |
| lines block offered even when the sentinel holds none | "stale armed autodrive with no lines ..." |
| lines emitted after-then-before | "stale armed autodrive: names the mod and prints the lines to type" |

The positive row uses odd content (double spaces, `"`, `$HOME`, `&`, `'`, `*`, `;`, backslash) and asserts the three lines are contiguous, in order, on both channels.

## Precommit
`just precommit` green. Checks that ran and passed: `jq` on plugin.json, hooks.json, settings.json; `shellcheck -x` bin/* scripts/*.sh tests/*.bats; `ruff check`; `ruff format --check`; `docformatter --check`; `mypy`; `ty check`; bats `hook-test`, `checkpoint`, `drive-take` (148 ok); pytest (178 passed, 3 deselected). `claude plugin test`: 16 pass, 0 fail (run by hand; not in precommit until step 5).

## mod-smoke
First run: 3 of 3 red, same cause for all rows, not a mod fault. The live test pre-armed `.claude/autodrive` before the first prompt, and the `UserPromptSubmit` sweep discards an `armed` sentinel that predates the prompt (it did before this step too; step 1's red rows hid it). Reproduced by hand: the sentinel vanished and the new note printed `/rename dbg-title`.

After the fix (deviation 1), `just mod-smoke`, run twice, 3 passed both times (about 33-35 s):
- `test_rename_row`: PASSED (custom-title in transcript).
- `test_clear_row_continues_in_the_fresh_session`: PASSED. `/rename`, `/clear` ran, the continuation was the new session's first user prompt, and `.claude/autodrive` and `.claude/autodrive.failed` are both absent afterwards, so `load-handoff.sh` consumed `pending` after the mod-run `/clear`. Mutation-checked: with the consume disabled this row reds on the new assertion.
- `test_compact_row_carries_the_focus_and_continues`: PASSED (compact summary, focus, continuation).

## Deviations
1. `tests/test_mod_live.py`: the arming moved from a pre-written file to the first turn, where the model runs one allowed `Bash(printf:*)` command that writes the sentinel (`--allowedTools=Bash(printf:*)`, `Edit,Write,NotebookEdit` still disallowed), plus the consume assertion on the clear row. Not asked for; needed for a meaningful green.
2. `hooks.json` was re-serialised, so `modules` is no longer on one line.
3. Removed `handoff-approved`'s unreachable unknown-kind arm and its bats row.
4. Kept the pyproject ruff `RUF001-003` ignores (comment reworded); not tested whether they could go.

## Left for step 5-6
- `CLAUDE.md`: layout and testing sections still describe the walker, `stop-drive.sh`, `session-end.sh`, `load-restart.sh`, `skills/restart/`, `tui-conformance`, `HANDOFF_WATCHER_*`, tmux stubs, restart rows (grep hits throughout; the hub text was untouched by instruction).
- `README.md` (lines about tmux, `/handoff:restart`, `autodrive.exited`, the Stop/watcher paragraph) and `docs/`, `plans/`.
- Skill prose: "typed into a composer" wording in `skills/handoff/SKILL.md` (lines 44, 167) and `skills/precompact/SKILL.md` (line 47); the `typed`/"closing line" vocabulary in `checkpoint.py` and `_checkpoint_lib.py`.
- `tests/bats-best-practices.md:406` mentions `watcher-test.bats` as an example.
- `.claude/handoff-todo.md` (agent scratch list) still lists step 4b items.
- `claude plugin validate --strict` / `claude plugin test` in precommit and the minimum-version pin (step 5).
