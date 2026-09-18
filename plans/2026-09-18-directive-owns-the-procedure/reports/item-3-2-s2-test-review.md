# Item 3.2 slice 2 — test review

Scope: the three `closing line matches the checkpoint's, per kind` rows and
`expected_closing()` in `tests/checkpoint.bats`, plus the RED report.

Verdict: the rows are sound evidence. One fix applied: the comment above
`expected_closing()` was trimmed, and its trailing-newline claim corrected
(it was wrong; see Check 2).

## Check 1: mutations reproduced, one per producer arm

Each mutation was applied in place with both producers saved to `$TMPDIR`,
then `bats tests/checkpoint.bats` was run and both files restored (mode
preserved). Rows 13–15 are slice 1's shape rows and 16–18 are this slice's.

| # | Mutation | Red rows |
|---|----------|----------|
| M1 | `bin/handoff-approved` `clear` arm: em dash to hyphen | 17 only |
| M2 | `closing_directive`: `"Clear"` to `"CLEAR"` | 17 only |
| M3 | `bin` `rename` arm: trailing `.` dropped | 16 only |
| M4 | `bin` `compact` arm: `it` to `It` | 18 only |
| M5 | `closing_directive` prepared line: `` `.`` to `.` `` `` | 16 only |
| M6 | `closing_directive`: `"Compaction"` to `"Compacting"` | 18 only |

Slice 1's rows 13–15 stayed green under all six, so these rows are the only
thing that catches drift at this level of detail. Each of the six arms (three
per producer) is shown to be caught by its own row. After every restore,
`git diff bin scripts` is empty.

## Check 2: trailing newlines, and the comment

M7 added an extra trailing newline to the `bin` `clear` arm (`printf
'%s\n\n'`). All six rows stayed green. This contradicts both the old comment
and the RED report, which said "a real drift in trailing-newline count would
still show up as differing content". It does not: `$(...)` strips every
trailing newline on both sides, so neither the count of trailing newlines nor
their absence is observable.

Judgement: this is an acceptable residual, not a gap worth closing. A trailing
blank line changes nothing the agent reads or relays. Comparing bytes exactly
would mean dropping `run` for a hand-rolled `$(…; printf x)` capture, which
costs more than it buys. I kept the residual and stated it accurately. The
comment went from 15 lines to 4, which matches the density of the file's other
section comments:

```
# Drift guard between the closing line's two producers: bin/handoff-approved's
# literal `case` arms and closing_directive() in scripts/_checkpoint_lib.py.
# Both sides pass through `$(...)`, so trailing newlines are the one
# difference these rows cannot see.
```

The RED report's paragraph on this is wrong on that one point. The report is a
write-time record and falls outside this review's fix scope, so it is left
unedited and flagged here.

## Check 3: order of the assertions, and the blank-line split

- In all three rows, `[ -n "$expected" ]` comes before the equality check.
- `${output#*$'\n\n'}` removes the shortest prefix that ends in the first
  blank line, which leaves everything after the status fact's separator.
- A missing separator does not produce a vacuous pass. M8 changed the status
  `printf` to a single `\n`. The expansion then returned the whole output, so
  rows 16–18 all went red on the equality check, as did slice 1's rows 13–15.

## Check 4: other ways to pass for the wrong reason

- **stderr**: `run_approved` uses `run --separate-stderr`, so the script's
  stderr never reaches `$output`. Python's stderr from `expected_closing` goes
  to the test's stderr and not into `$expected`.
- **Import path**: M9 pointed `PYTHONPATH` at a missing directory. All three
  rows went red at the `expected=` line: `set -e` fails the step on python's
  non-zero exit, before the non-empty guard is reached. A broken import cannot
  compare empty to empty. With `-c`, `sys.path[0]` is the bats cwd (the repo
  root), which has no `_checkpoint_lib.py`, so nothing shadows the module.
- **Quoting**: `typed=$typed` interpolates the literal `True`/`False` inside a
  double-quoted `-c` string, and `'$skill'` becomes a Python string literal.
  Both are fixed, test-controlled tokens, so neither can inject anything or
  change meaning. A misspelling such as `true` would raise `NameError`, which
  goes red (see M9's path) instead of passing.
- **Mapping**: each row calls one `(skill, typed)` pair, and M3 to M6 show a
  per-arm swap reds only the matching row, so a mapping that is crossed between
  kinds would also go red.

## Final state

- `bats tests/checkpoint.bats`: 30/30 ok.
- `shellcheck -x tests/checkpoint.bats`: clean.
- `git diff bin scripts`: empty. `git status --short bin scripts tests` shows
  only `M tests/checkpoint.bats`.
- Nothing committed.
