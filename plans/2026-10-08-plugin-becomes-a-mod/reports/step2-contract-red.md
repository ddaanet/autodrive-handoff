# Step 2 (RED): drive-take.sh contract fixtures

Status: red as intended. Nothing committed. `scripts/drive-take.sh` not created.

## Contract as pinned

`scripts/drive-take.sh <cwd>`: `stop-drive.sh` minus tmux/walker. Exit 0 always.
1. Resolve root from `<cwd>` via `handoff_root`; sentinel is `<root>/.claude/autodrive`.
2. No file: empty stdout. Parse with `handoff_drive_read` (malformed check precedes the state gate, as in `stop-drive.sh`).
3. Parse failure: `rm -f` the file; print the malformed plan (below).
4. State other than `armed` (`pending`, `held <sid>`): empty stdout, file untouched.
5. `armed`: kind `clear`/`compact` (`handoff_drive_has_source`) -> `handoff_drive_arm "$file" pending`; kind `rename` -> `rm -f`. Then print the plan. Only line 1 changes on arm.
6. FR-G (`compact` kind line alone, `before` empty): file left `pending` (arm still happens), plan with empty lists.
7. stdout is one line of compact JSON (+ newline), key order `kind, before, after, failFile, message`; `failFile` = `<root>/.claude/autodrive.failed` (always, absolute).
   - `before`/`after` = `DRIVE_BEFORE`/`DRIVE_AFTER` verbatim.
   - message normal: `handoff: will run <before[0]> once the turn ends.`
   - message FR-G: `handoff: prepared for compact; nothing to run, frame will be re-injected.`
   - malformed: `{"kind":null,"before":[],"after":[],"failFile":...,"message":"handoff: autodrive malformed — <DRIVE_ERR>; discarded, transition not armed."}`
   - Generate with `jq -nc` (UTF-8 em dash, backticks pass through unescaped).

## Files

- `tests/mod/fixtures/armed-compact.json`, `armed-clear.json`, `armed-rename.json`, `prepare-only-compact.json`, `malformed.json`, `README.md`
- `tests/drive-take.bats` (new; shellcheck -x clean)
- `justfile`: `tests/drive-take.bats` appended to the `bats` line in both `precommit` and `hook-test`

`@ROOT@` in fixtures = absolute session root (cwd or worktree root); the test substitutes it (documented in the README).

## Bats rows and state effects

1. no autodrive: empty stdout; nothing created
2. armed compact: fixture armed-compact; file -> `pending`
3. armed clear (+continuation): fixture armed-clear; `pending`, lines 2.. unchanged
4. armed rename: fixture armed-rename; file removed
5. FR-G compact kind line alone: fixture prepare-only-compact; stays `pending`
6. pending: empty; file byte-identical
7. held sess-hook-test: empty; file byte-identical
8. arms once only: second take empty
9. malformed (`clear` with 3 lines, DRIVE_ERR "kind `clear` takes 4 or 5 lines (found 3)"): fixture malformed; file removed
10. worktree cwd: fixture armed-compact with `@ROOT@` = worktree; worktree file -> `pending`
11. worktree cwd with sentinel only in the project root: empty; project file still `armed`

## Red run

`bats tests/drive-take.bats`: 11 of 11 `not ok`, e.g.

```
not ok 1 drive-take (no autodrive: empty stdout, exit 0)
# (in test file tests/drive-take.bats, line 47)
#   `[ "$status" -eq 0 ]' failed
...
BW01: `run`'s command `bash scripts/drive-take.sh /tmp/.../1/proj` exited with code 127, indicating 'Command not found'.
```

Red reason is "script not found" (status 127 at the first assertion), as the task allowed. Note for GREEN: row 1/6/7/8/11 assert only status+empty output, so they would pass on a stub that prints nothing; the other rows carry the fixture/state assertions.

## Ambiguities resolved

- Message wording: old `once the prompt is idle (tmux pane %N)` -> `once the turn ends.`; no tmux words.
- Malformed `kind` is `null` and the message is the old systemMessage text with the `handoff:` prefix kept.
- `failFile` is present in every plan, including FR-G and malformed.
- Temp repo is not `git init`ed: the script does no git work; worktrees use the on-disk `.git` file layout (as in `hook-test.bats`) that `worktree_root.py` reads.
- Rows use `run` combined output, so any stderr noise from the script would fail the comparison.
- The row-10 worktree path contains no `|`; `@ROOT@` substitution uses bash `${var//}`, not sed.
