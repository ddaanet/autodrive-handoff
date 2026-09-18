# Item 1.1, slice 1/1 — GREEN report

Mode: GREEN. Commit: `411f2c71a441a3423daa37dc7842047816b8c363`.

## Implementation

`scripts/_checkpoint_lib.py`: `commit_directive()` implemented for real
(replacing the RED stub) — one imperative line, no git verb, no other
mechanism: "Make the commit now, in whatever shape the request called for,
before what follows here runs." Contains "commit", excludes `git commit`,
`--amend`, `git add` (case-folded).

`scripts/checkpoint.py`: minimal wiring, no restructuring toward the full
Item 1.1 interface set (`MemoryPart`, `hold_decision`, `compose_sentinel(...,
held=)`, list-returning `compose_directives`) — none of that is exercised by
this slice's three tests, and the dispatch left it optional ("if that is the
natural way to make this slice pass"). It was not: adding the commit act as a
third element next to the existing `(memory, second)` pair was the smaller
diff, kept every currently-passing test's fixture untouched, and still lands
the parts in the outline's print order (memory, second, commit) so slice 2's
ordering test needs no further reshuffling here.

- `compose_directives(skill, root, commit_mode) -> tuple[str, str, str]` —
  now returns `(memory, second, commit)`; `commit` is
  `lib.commit_directive()` under `"with-commit"`, else `""` (so
  autoname/restart, whose `commit_mode` is always `""`, stay silent
  unchanged).
- `print_output(memory, second, commit)` — joins the non-empty parts with a
  blank line and one trailing newline; verified byte-identical to the old
  two-arg version in the 0/1/2-non-empty cases (no test asserts this
  directly, but the full suite's pre-existing exact-stdout and
  substring-containment rows over `without-commit`/clean-memory fixtures all
  stayed green, which pins it).
- `main()` unpacks the third element and passes it through.

`arming_directive`, `memory_directive`, `compose_sentinel`'s hold rule: all
untouched, as scoped.

## Tests

Un-stubbed the RED tests as-is (no changes beyond what the test-review report
already applied at RED: the case-folded `test_commit_act_names_no_git_verb`
assertion and the ruff `I001` import-sort fix).

`pytest tests/test_checkpoint.py -k commit_act -v` → 5 passed (was 5 failed
at RED, each on `assert commit_act`).

`pytest tests/test_checkpoint.py -q` → 154 passed (0 regressions).

`just precommit` → green end to end: jq/shellcheck/ruff
check+format/docformatter/mypy/ty, `bats tests/hook-test.bats
tests/checkpoint.bats` (166 ok), `pytest` (244 passed, 11 deselected
`live`-marked).

One precommit round-trip: `docformatter` (configured `in-place = true`,
`wrap-summaries = 80`) rewrote `print_output`'s and `compose_directives`'
new/changed docstrings on the first `--check` run because the initial
one-liner ran a few characters past the 80-column summary wrap; reworded
both to fit (`print_output`'s split into summary + one description line)
and reran clean.

## Scope confirmation

Touched only `scripts/_checkpoint_lib.py`, `scripts/checkpoint.py`,
`tests/test_checkpoint.py` — no `bin/handoff-approved`, no
`tests/checkpoint.bats`, no skill body, no `hold_decision`/`MemoryPart`/list
restructuring. Nothing under `plans/` was committed; the two report files
from RED and test-review are left in place per instructions.
