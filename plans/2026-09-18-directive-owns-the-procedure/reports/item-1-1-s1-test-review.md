# Item 1.1, slice 1/1 — test review

Verdict: **pass, with two fixes applied.** Tests still red, all on assertions.

## Mechanical

`pytest tests/test_checkpoint.py -k commit_act -q` → `5 failed, 149 deselected`.
Each fails on `assert commit_act` (`AssertionError: assert ''`), not an
ImportError or collection error. Full file: `5 failed, 149 passed` (same 5).
The stub (`commit_directive()` returning `""`) is complete for this slice's
interface; no stub gap.

## Conformance to the slice

All three tests match the slice text: both skills parametrized over
`handoff_payload`/`precompact_payload` on a clean `make_gitlore_repo`; the
non-empty guard precedes every stdout comparison (standing rule); the
`commit` word anchor is present in the positive row; the negative row uses
the same fixture and the same non-empty text.

## Wrong-reason hunt

Baseline observed: all four fixture cells (2 skills x 2 modes) print
`stdout == ''` today. So:

- `test_with_commit_prints_the_commit_act` cannot pass by the act's text
  being a substring of some other part — there is no other part in this
  cell. Reds for: stub `""`; a real text never printed; a text printed only
  under `without-commit`.
- `test_without_commit_prints_no_commit_act` is a negative, but it is paired
  with the positive over the same fixture and guarded non-empty, so it is not
  vacuous: an implementation printing the act unconditionally reds it and
  only it. Residual: if a later part (Item 3.1's closing line) ever embedded
  the commit act's full text verbatim, this row would red — which is the
  correct outcome, not a false one.
- `test_commit_act_names_no_git_verb` — reds for stub `""` and for any text
  naming one of the three forms.

Mutation mapping once green: print unconditionally ⟹ negative reds alone;
never print ⟹ positive reds alone; git verb in text ⟹ third reds alone.

## Fixes applied

1. `test_commit_act_names_no_git_verb` now checks the case-folded text, so
   `Git commit` / `GIT ADD` spellings are caught too. Strictly stronger than
   the slice's assertion, same contract.
2. `ruff check` flagged `I001` on the RED's import placement
   (`import _checkpoint_lib as lib` in its own group after `pytest`); fixed
   with `ruff check --fix`, which sorts it into the same group as `pytest`
   — the same shape `tests/test_watcher_lib.py` uses for `_watcher_lib`.
   Would otherwise have failed `just precommit` at GREEN.

Re-run after fixes: `5 failed, 149 passed`; each failure still `assert ''`.
`ruff check` and `ruff format --check` clean on the file.

Nothing committed.
