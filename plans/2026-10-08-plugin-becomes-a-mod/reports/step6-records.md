# Step 6: the records

## Files

Created: `docs/changelog/2026-10-08-the-plugin-becomes-a-mod.md` (+ index line at top of `docs/changelog.md`, no version).

Moved (git mv) and rewritten: `docs/design/driving-the-tui.md` -> `docs/design/driving-the-transition.md` (drive-take.sh contract, states, FR-G, `classic.Stop` cwd record + inline `turn.complete` drive and why, prompt bail, stop-on-first-failure + `autodrive.failed`, loaders consuming `pending`, sweep and the not-loaded note, three verification layers). Inbound links fixed in `the-skills.md`, `the-write-path.md`, `design.md`; the one remaining old name is inside a write-time changelog body (`2026-09-20-the-design-doc-becomes-a-hub.md`), which got a Superseded blockquote naming the new file. `plans/` hits are write-time records, untouched.

Changed:
- `docs/design.md` hub: FR-H retired (number kept, marked retired), NFR1 loses tmux, FR8/FR-G wording, routing entry, "Five skills ... eleven hooks" -> "Four skills, one write path, one mod, eight hooks", decisions index (three pane decisions out, "drive runs inline at `turn.complete`" in), rejected index (tmux/pane, restart kind, `/autoname` mod command, second parser).
- `docs/design/decisions.md`: the pane, U+00A0 gap and exiting-process decisions removed; the sentinel/state/observability decisions reworded for the mod; new decision for the inline drive.
- `docs/design/rejected-alternatives.md`: the three SHELL_SETTLE/alternate_on/exiting-process entries replaced by five entries (tmux walker family, reading the pane, restart kind, `/autoname` mod command, second parser).
- `docs/design/the-skills.md`, `the-write-path.md`, `the-checkpoint-directive.md`, `scoping.md`: restart skill, walker, tmux, `Stop`, keystroke, `report-watcher-failure` wording.
- 29 changelog entries: one `> **Superseded 2026-10-08**` blockquote each at the head, scoped per entry (whole vs the mechanism/consumer named); plus the hub-split entry for the renamed node.
- Skills: `skills/handoff/SKILL.md` (1807 words, was within limit), `skills/precompact/SKILL.md`, `skills/autoname/SKILL.md`: "typed" -> "driven", "typed into a composer"/paste wording -> "submitted as the next prompt"/"the plugin prints the lines itself", autoname's tail describes the mod.
- `scripts/checkpoint.py` (one error message "not typed" -> "not driven", `hold_decision` docstring), `scripts/_lib.sh`, `bin/handoff-approved` comments. No assertion needed changing (no test pinned "not typed").
- `scripts/report-drive-failure.sh`: local variable `paste` renamed `armed_lines` (no behavior change).
- `README.md`: intro, autoname, compact paragraph, the driving paragraph rewritten (mod, Claude Code >= 2.1.287, not-loaded behavior, `/restart` built-in, no `/handoff:restart`, autoname still a skill), requirements, files-touched (no `autodrive.exited`, no `restart` kind), further reading.
- `CLAUDE.md`: 1274 -> ~458 lines. Layout and Testing rewritten; Conventions/Frame assembly/Non-goals kept (one `_watcher_lib` mention dropped). New: `hooks/handoff.ts`, `drive-take.sh`, `gen_mod_fixtures.py`, `report-drive-failure.sh`, `tests/mod/`, `drive-take.bats`, `test_mod_fixtures.py`, `test_mod_live.py` + `just mod-smoke`, `just validate-plugin`, `claude plugin test`. The tmux/private-socket paragraph is gone: `test_mod_live.py` uses `claude -p` and no tmux.
- `tests/bats-best-practices.md:406`, `tests/mod/fixtures/README.md` (step/walker wording), `.claude/handoff-todo.md` (only step 7 dogfood, release call, delegation notes remain).

## Claims verified against source

- `hooks/handoff.ts`: Stop records cwd only; `turn.complete` drives inline; fast path via `$.session.root()` + `$.fs.exists`; `prompt.read` bail ends the whole sequence; `/`-line -> `command.run({command,args})`, prose -> `prompt.submit({text, asUser:true})`; first rejection writes `failFile` and toasts.
- `scripts/drive-take.sh`: armed-only gate, `armed`->`pending` before print, `rename` removed, FR-G message, malformed removed with `kind: null`, JSON key order.
- `report-drive-failure.sh`: armed sweep note names the mod / `--safe-mode` / 2.1.287 and prints lines; abandoned and malformed print none; stranded `pending` cleared with a failure report.
- `load-handoff.sh` consumes before the no-frame exit; loaders gate on `pending` + own kind; neither spawns.
- hooks.json has 8 command hooks + one module.
- Reports: Stop-context refusal covers timers; timers die under `-p`; autoname probe results; no minimum-version field.

Plan claims that turned out wrong or superseded: plan Design says `$.clock.after(0, drive)` from Stop (wrong; inline `turn.complete`); `/autoname` mod command and deleting `skills/autoname/` (superseded; skill stays); `plugin.json` minimum-version pin (no field); "eleven hooks" in the old hub (stale).

My own corrections while drafting: I first wrote that the mod "skips a line" on prompt text; the code ends the whole sequence, and README and design say so. I removed an unverified version claim ("hooks and skills need nothing newer") from the README. I replaced an unsupported "five repairs in two weeks" count with the date range.

Kept as is: the code identifier and parameter `typed` (`Transition.typed`, `closing_directive(typed=)`, test names) and "untyped" in comments. Renaming it touches many tests for no behavior; docs define it once ("the code calls a driven transition `typed`").

## Remaining grep hits (walker, tmux, drive_when_idle, _watcher_lib, stop-drive, session-end, load-restart, handoff:restart, tui-conformance, HANDOFF_WATCHER, paste)

Outside `.git`, `plugin-dev`, `memory`, `plans/`, and changelog bodies:
- `docs/design/rejected-alternatives.md`, `docs/design.md:281` (rejected index): the record of what was ruled out; justified.
- `docs/design/driving-the-transition.md:10,69`: names tmux once each to say what the mod replaced; justified.
- `docs/design/the-write-path.md:123`: "the walker that was ported with them is gone"; points to the new node; justified.
- `.gitlore/bin/claude:8`: `paste -sd:` the coreutils command; unrelated.
- `tests/mypy-guidelines.md`: matched only generic words (excluded from grep); unrelated.
- Changelog bodies and `plans/`: write-time records, by rule.
No hit remains in `CLAUDE.md`, `README.md`, skills, scripts, bin, hooks, tests, justfile or pyproject.

## Precommit

`just precommit` green on the final run: jq (plugin.json, hooks.json, settings.json); `validate-plugin`; `claude plugin test` 16 pass; shellcheck; ruff check; ruff format --check; docformatter --check; mypy; ty check; bats (hook-test, checkpoint, drive-take); pytest 178 passed, 3 deselected; "ok". Two earlier runs stopped at ruff E501 and docformatter on my `hold_decision` docstring edit; fixed. `just mod-smoke` not run in this step (no mod or loader code changed; only comments, one error string and a shell variable name).

## Commit

See the reply line.
