# Item 3.2 slice 1 — RED report

Rows added to `tests/checkpoint.bats`, after the existing `handoff-approved:
runs by bare name off PATH` row and before the shim section:

- `handoff-approved: status fact then closing content — rename`
- `handoff-approved: status fact then closing content — clear`
- `handoff-approved: status fact then closing content — compact`

Each builds its kind's sentinel shape exactly as specified (`rename`: `held
$CLAUDE_CODE_SESSION_ID` / `rename` / `/rename A Title`; `clear`: state /
kind / `/rename A Title` / `/clear`; `compact`: state / kind / `/compact`),
runs it through the existing `run_approved` helper (`run --separate-stderr`),
then asserts line 1 of stdout is the status fact, followed by the per-kind
content check (`rename` → output contains `Ready to /clear`; `clear` and
`compact` → output contains `End on one line` and does not contain `Ready
to`).

`bin/handoff-approved` and `bin/handoff-checkpoint`/`scripts/` were not
touched — SUT unmodified per instructions.

## Discrepancy check

Verified the status-fact text in `bin/handoff-approved`'s final `printf`
(line 64) matches the spec exactly:
`printf 'handoff: %s armed; it runs at the end of this turn.\n' "$DRIVE_KIND"`
→ `handoff: <kind> armed; it runs at the end of this turn.`. No bending
needed.

## `bats tests/checkpoint.bats` — full output

```
1..27
ok 1 inject-checkpoint-root: rewrites a handoff-checkpoint call, carrying the resolved root
ok 2 inject-checkpoint-root: rewrites a handoff-approved call too
ok 3 inject-checkpoint-root: leaves an unrelated Bash command untouched
ok 4 inject-checkpoint-root: a root containing whitespace round-trips through the rewrite
ok 5 inject-checkpoint-root: export survives a batched command, unlike a bare VAR= prefix
ok 6 inject-checkpoint-root: hooks.json dispatches PreToolUse(Bash) to it
ok 7 handoff-approved: a held sentinel becomes armed, every line below preserved
ok 8 handoff-approved: a held sentinel from another session -> exit 2, left held
ok 9 handoff-approved: no sentinel -> exit 2 naming the absence
ok 10 handoff-approved: an armed sentinel -> exit 2 naming the state it found
ok 11 handoff-approved: HANDOFF_ROOT unset -> refuses, naming the unrecognised invocation
ok 12 handoff-approved: runs by bare name off PATH
not ok 13 handoff-approved: status fact then closing content — rename
# (in test file tests/checkpoint.bats, line 218)
#   `[[ "$output" == *"Ready to /clear"* ]]' failed
not ok 14 handoff-approved: status fact then closing content — clear
# (in test file tests/checkpoint.bats, line 228)
#   `[[ "$output" == *"End on one line"* ]]' failed
not ok 15 handoff-approved: status fact then closing content — compact
# (in test file tests/checkpoint.bats, line 239)
#   `[[ "$output" == *"End on one line"* ]]' failed
ok 16 shim: bin/handoff-checkpoint execs the checkpoint, forwards stdin
ok 17 shim: bin/handoff-checkpoint surfaces a schema violation
ok 18 bash-post: manifest absent -> silent no-op, negative path never resolves the root
ok 19 bash-post: manifest present -> stages W and D paths, deletes manifest
ok 20 bash-post: empty manifest (rename-only checkpoint call) -> consumed, sentinel untouched
ok 21 bash-post: worktree cwd -> resolves the worktree root, not the main tree
ok 22 bash-post: D for a path in the index -> counted in deleted, no failure
ok 23 bash-post: D for a path never in the index -> silent, uncounted, no failure
ok 24 bash-post: a path that cannot be staged -> reported on both channels, named
ok 25 bash-post: root is not a git repository -> reported once, not once per path
ok 26 bash-post: D whose index cannot be read -> reported, not swallowed by the guard
ok 27 bash-post: one staged and one failed -> both clauses compose in order
```

## Interpretation

All three new rows (13–15) fail on their trailing content assertion — the
closing line is genuinely absent from today's `handoff-approved` output,
since the script's final `printf` only emits the status fact. Each fails
*after* its line-1 status-fact assertion (`[ "${lines[0]}" = "handoff: <kind>
armed; it runs at the end of this turn." ]`), proving that assertion passed
first — a genuine red on a failed assertion, not an early bail. Rows 1–12
and 16–27 (pre-existing) stay green, unaffected.

`shellcheck -x tests/checkpoint.bats` — clean, no output.
