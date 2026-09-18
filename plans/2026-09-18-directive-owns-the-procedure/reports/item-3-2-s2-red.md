# Item 3.2 slice 2 — RED report

Three rows added to `tests/checkpoint.bats`, after the three "status fact
then closing content" rows from slice 1 and before the shim section:

- `handoff-approved: closing line matches the checkpoint's, per kind — rename`
- `handoff-approved: closing line matches the checkpoint's, per kind — clear`
- `handoff-approved: closing line matches the checkpoint's, per kind — compact`

Each builds its kind's sentinel exactly as slice 1's fixtures do, runs it
through `run_approved`, extracts everything after the blank line from
`$output` (`closing="${output#*$'\n\n'}"`), computes the expected text via a
new `expected_closing()` helper (`PYTHONPATH="$repo_root/scripts" python3 -c
"from _checkpoint_lib import closing_directive; print(closing_directive('<skill>',
typed=<bool>), end='')"`), asserts the expected text is non-empty first, then
asserts byte equality: `rename` → `closing_directive("handoff", typed=False)`,
`clear` → `closing_directive("handoff", typed=True)`, `compact` →
`closing_directive("precompact", typed=True)`.

`bin/handoff-approved` and `scripts/` were not touched in the final state —
`git diff bin scripts` is empty.

## Trailing-newline comparison — choice made

`closing_directive()` returns text ending in exactly one `\n`
(`_printf_lines`), and `bin/handoff-approved`'s matching `case` arm prints
its line with `printf '%s\n'` — also exactly one trailing newline. Both
sides of the comparison go through a `$(...)` command substitution: bats'
`run` internally for `$output`, and `expected_closing()`'s own
`$(expected_closing …)` capture for `$expected`. Command substitution strips
*all* trailing newlines uniformly on both sides, so the comparison is
insensitive to the exact count of trailing blank lines past the first —
but since neither producer has any reason to emit more than the one
`_printf_lines`/`printf '%s\n'` already adds, this is not a live drift this
row could miss: a producer starting to double up trailing blank lines would
be a change to the string content on at least one side already covered by
the byte-equality check on everything before the newline runs, since
`_printf_lines` joins multiple args with single `\n` and the case arms print
a single literal — there is no code path on either side that varies the
trailing-newline count independent of content. Stated explicitly since the
slice's instructions asked the choice be named.

> **Corrected at review, 2026-09-19.** "A producer starting to double up
> trailing blank lines would be a change to the string content … already
> covered by the byte-equality check" is wrong. The test review
> (`item-3-2-s2-test-review.md`, M7) changed the `clear` arm to
> `printf '%s\n\n'` and all six rows stayed green: `$(...)` strips every
> trailing newline on both sides, so no trailing-newline change is
> observable. What still stands: this is an accepted residual, since a
> trailing blank line changes nothing the agent reads, and the rows catch
> every content drift (M1–M6).

## Discrepancy check

None — `expected_closing()` and the extraction were written directly from
the interface (`closing_directive(skill: str, *, typed: bool) -> str`) and
slice 1's established `$output` shape; no spec text needed bending.

## `bats tests/checkpoint.bats` — full output, unmutated

```
1..30
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
ok 13 handoff-approved: status fact then closing content — rename
ok 14 handoff-approved: status fact then closing content — clear
ok 15 handoff-approved: status fact then closing content — compact
ok 16 handoff-approved: closing line matches the checkpoint's, per kind — rename
ok 17 handoff-approved: closing line matches the checkpoint's, per kind — clear
ok 18 handoff-approved: closing line matches the checkpoint's, per kind — compact
ok 19 shim: bin/handoff-checkpoint execs the checkpoint, forwards stdin
ok 20 shim: bin/handoff-checkpoint surfaces a schema violation
ok 21 bash-post: manifest absent -> silent no-op, negative path never resolves the root
ok 22 bash-post: manifest present -> stages W and D paths, deletes manifest
ok 23 bash-post: empty manifest (rename-only checkpoint call) -> consumed, sentinel untouched
ok 24 bash-post: worktree cwd -> resolves the worktree root, not the main tree
ok 25 bash-post: D for a path in the index -> counted in deleted, no failure
ok 26 bash-post: D for a path never in the index -> silent, uncounted, no failure
ok 27 bash-post: a path that cannot be staged -> reported on both channels, named
ok 28 bash-post: root is not a git repository -> reported once, not once per path
ok 29 bash-post: D whose index cannot be read -> reported, not swallowed by the guard
ok 30 bash-post: one staged and one failed -> both clauses compose in order
```

All 30 rows pass unmutated (the new rows PASS, as expected — the two
producers already agree; this row's value is in catching future drift, not
in failing today).

## Mutation check 1 — `bin/handoff-approved`

Changed the `clear` arm's em dash to a hyphen:
`'End on one line: \`Clear armed - it runs when this turn ends.\`'`.

```
ok 16 handoff-approved: closing line matches the checkpoint's, per kind — rename
not ok 17 handoff-approved: closing line matches the checkpoint's, per kind — clear
# (in test file tests/checkpoint.bats, line 293)
#   `[ "$closing" = "$expected" ]' failed
ok 18 handoff-approved: closing line matches the checkpoint's, per kind — compact
```

Only row 17 reds, on the equality assertion (not the non-empty guard) —
rows 13–15 (slice 1's content checks) stay green since they don't assert the
em dash. Restored via the saved copy; `git diff bin/handoff-approved` empty
afterward.

## Mutation check 2 — `scripts/_checkpoint_lib.py`

Changed `closing_directive`'s `clear` name from `"Clear"` to `"CLEAR"`.

```
ok 16 handoff-approved: closing line matches the checkpoint's, per kind — rename
not ok 17 handoff-approved: closing line matches the checkpoint's, per kind — clear
# (in test file tests/checkpoint.bats, line 293)
#   `[ "$closing" = "$expected" ]' failed
```

Only row 17 reds again. Restored via the saved copy; `git diff
scripts/_checkpoint_lib.py` empty afterward.

## Verification

- `bats tests/checkpoint.bats`: 30/30 green in the final (unmutated) state.
- `shellcheck -x tests/checkpoint.bats`: clean.
- `git diff bin scripts`: empty — both producers untouched in the final
  state.
- `git status --short tests/checkpoint.bats bin scripts`: only
  `tests/checkpoint.bats` modified.

## Scope

Touched only `tests/checkpoint.bats`. Nothing committed.
