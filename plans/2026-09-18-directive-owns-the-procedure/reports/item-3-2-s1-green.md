# Item 3.2 slice 1 — GREEN report

Commit: `fcc6d00` — "Item 3.2/1 — handoff-approved prints the closing line"

## What changed

`bin/handoff-approved`'s final block: the status-fact `printf` is now
followed by a `case "$DRIVE_KIND"` selecting the closing line —

- `rename` → `` End on one line: `Ready to /clear`. ``
- `clear` → `` End on one line: `Clear armed — it runs when this turn ends.` ``
- `compact` → `` End on one line: `Compaction armed — it runs when this turn ends.` ``
- any other kind → empty (falls back to the status fact alone)

— then one `printf '%s\n\n%s\n'` when a closing line was selected, else the
bare status-fact `printf` as before. Text copied literally from
`closing_directive()` in `scripts/_checkpoint_lib.py:196-208` (`rename` uses
`closing_directive("handoff", typed=False)`; `clear` uses
`closing_directive("handoff", typed=True)`; `compact` uses
`closing_directive("precompact", typed=True)`), including the em dash.
No Python call, no git, no tmux — NFR1's one-file-rewrite shape is
unchanged; the case/printf is the whole addition.

`restart` (and any future kind) hits the `*)` branch: `handoff-approved`
can only reach `armed` here for a sentinel it already parsed via
`handoff_drive_read`, and per the plan `restart` never holds, but the
fallback exists so an unrecognized kind still prints the status fact rather
than crashing or emitting garbage.

## Lint note

`shellcheck` flagged SC2016 (info) on the three single-quoted `closing='...'`
assignments — a false positive, since the backticks inside are literal text
that would instead open command substitution if double-quoted. Suppressed
with one `# shellcheck disable=SC2016` above the `case`, which shellcheck
applies to the whole compound statement (verified: `shellcheck -x
bin/handoff-approved` is clean after the disable).

## Verification

- `bats tests/checkpoint.bats`: 27/27 green, including the three new rows
  (`status fact then closing content — {rename,clear,compact}`).
- `just precommit`: green in full (manifests/settings lint, shellcheck -x,
  ruff/docformatter/mypy/ty, `bats tests/hook-test.bats tests/checkpoint.bats`
  — 169/169 — and `pytest` — 261 passed, 11 deselected).
- `git diff` reviewed before staging: only the three new bats rows plus the
  `bin/handoff-approved` edit; nothing else swept in.

## Scope

Touched only `bin/handoff-approved` and `tests/checkpoint.bats`, per the
item's interface. No `scripts/`, `skills/`, or `docs/` changes — slice 3.2/2
(the byte-for-byte drift row against the Python producer) is separately
scoped. `plans/` reports left uncommitted as instructed.
