# Item 1.1 / slice 5 — test review

Test: `tests/test_checkpoint.py::test_clause_refusal_is_followed_by_no_commit_or_arming`

## 1. Mechanical

`pytest tests/test_checkpoint.py -k test_clause_refusal_is_followed_by_no_commit_or_arming`
FAILED on an `AssertionError`, not ERROR and not PASSED, both before and after the fix below.
Before the fix it failed on `commit_act not in out`, as the RED report says. After the fix
it fails first on `boundary not in out`, because the todo boundary prints right after the
refusal today.

## 2. Wrong-reason hunting

- **Un-holding the sentinel on refusal** is caught by the
  `first_line == "held sess-checkpoint"` assertion.
- **Suppressing the refusal text itself** is caught by the key-name assertion.
  `gitlore.memoryApprovalClauseFile` appears in only one string in the SUT: the refusal
  (`scripts/_checkpoint_lib.py:113`). The normal memory directive does not name the key,
  so a fix that swaps in the normal memory text also fails this check.
- **Both absence checks have teeth.** The cell is typed clear + `with-commit` + dirty
  memory. Today that cell is held, since a refusal counts as `M`. The RED output shows
  that both the commit act and the arming instruction print after the refusal. The test
  asserts that both `lib.*()` values are non-empty before it checks for their absence,
  following the runbook's standing rule.
- **Todo boundary: fixed.** The original fixture had no SDD ledger, so
  `lib.todo_boundary(root)` returned `""`. Checking for its absence would therefore have
  proved nothing. Without that check, a fix that suppressed only parts 3–4 and still
  printed part 2 would pass. The interface says `[memory.text]` alone when
  `memory.refusal`, and the outline says "prints it alone". The fix adds three things to
  the test:
  - `add_sdd_ledger(repo)`
  - `assert boundary` on `lib.todo_boundary(str(repo))`
  - `assert boundary not in out`

  Re-run: still red, now on the boundary assertion. That is the defect: today the
  boundary prints after the refusal.

## Mutation check

The slice's mutation check still applies to this row: print parts 3–4 regardless of
`refusal` ⟹ this row alone reds. Printing the boundary regardless of `refusal` now reds it
too. The mutation check was not run here. Per the RED report, it runs after GREEN, at
code review.

## Changes

`tests/test_checkpoint.py`, this test only: the ledger fixture, the non-empty guard and the
boundary absence assertion. SUT untouched. Nothing committed.
