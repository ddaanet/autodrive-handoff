# Item 2.1 / slices 2 and 3 — test review

Verdict: **both rows approved as written. No test edits.** Slice 2 stays,
and the runbook's claim that its mutation reds "this row alone" is corrected
below.

## Reproduced

The SUT is unmutated and the file is green: `pytest tests/test_checkpoint.py -q`
gives `164 passed`. `ruff check` and `ruff format --check` are clean on the
test file. After every mutation below, `git diff scripts/ | wc -l` returned `0`.

| Mutation (in `scripts/checkpoint.py`) | Rows that red |
|---|---|
| A: 2nd disjunct → `bool(transition.cmds) and commit` | `test_rename_only_manifest_present_empty_sentinel_written`, slice 2 |
| B: 2nd disjunct → `commit` | the two rows above + slice 3 `[with-commit]` |
| C: `compose_directives` arms on `held or commit_mode == "with-commit"` | slice 2, slice 3 `[with-commit]` |
| D: `memory=` also true when the gitlore submodule is registered (clean) | slice 2 + 5 existing rows (`test_gitlore_clean_memory_silent`, `test_typed_transition_no_memory_gate_…`, …) |

The RED report's A and B results match exactly. C and D are new here.

Note: mutation A is also the rejected alternative from the outline,
`K and (M or C)`. Because `T` implies `K`, `(K and M) or (K and C)` is the same
predicate. So A's reds are exactly the cells where the chosen rule and the
rejected one disagree.

## Corrected mutation mapping

- Slice 2, mutation A: reds slice 2 **and**
  `test_rename_only_manifest_present_empty_sentinel_written`. It does not red
  slice 2 alone. That older row occupies the same hold-rule cell: untyped
  handoff, `with-commit`, `memory=False` (non-gitlore repo), `cmds=["/rename …"]`.
  It pins the exact sentinel bytes `armed\nrename\n…`, so it catches the change
  incidentally.
- Slice 3, mutation B: reds slice 3 `[with-commit]` among three rows. The
  `[without-commit]` parametrization stays green, as it should. Under A,
  slice 3 stays green on both parametrizations, which is correct: `cmds` is
  empty there, and the chosen rule and the rejected one agree on that cell.

## Is slice 2 redundant?

No mutation reds slice 2 alone. For A and B,
`test_rename_only_manifest_present_empty_sentinel_written` covers it. For C,
slice 3 `[with-commit]` covers it. For D, the existing clean-memory rows cover
it. I kept slice 2 anyway, for these reasons:

- It is the only row whose **name** states the outline's decision. That decision
  covers the one cell where the chosen rule and the rejected one differ, and the
  row targets the gitlore-managed, clean-memory case the outline names. The rename
  row guards the cell only as a side effect. If someone changed its `commit` to
  `without-commit` (the value is irrelevant to what that row is about), coverage
  of the decision would silently disappear.
- It is the only row that asserts both composition facts in that cell: the commit
  act is **present** and the arming instruction is **absent**. The rename row
  asserts nothing about stdout.
- The cost is one subprocess row.

## Wrong-reason hunt

- **Is the `handoff-approved` absence check meaningful?** Yes. The string appears
  only in `lib.arming_directive()`, and `compose_directives` appends that
  directive iff `held`, unless the part is a memory refusal. That cannot happen in
  either fixture: slice 2's memory is clean and slice 3's has a clause file.
  Mutation C shows the check discriminates: arming while `armed` reds both rows.
  It is not redundant with the `armed` first-line check, because C leaves the
  sentinel `armed` and still reds.
- **Slice 2's preconditions are asserted, not assumed.**
  `memory_directive(...).text == ""` proves the fixture is gitlore-registered with
  clean memory. `assert commit_act` guards the containment check against an empty
  `commit_directive()`, as the runbook's standing rule requires.
  `handoff_payload` defaults to `clear: False`, so the row is untyped by
  construction.
- **Slice 3 `[with-commit]` reds under B specifically.** Yes. B makes
  `commit=True` hold on its own, and this fixture is the only row where `K` is
  false and `C` is true. Its dirty memory also makes the first disjunct's
  exemption live (`cmds` is empty), so the row tests the FR-G marker and not a
  clean-memory accident.

## Scope

Nothing committed. `scripts/` is unchanged. The only change is in
`tests/test_checkpoint.py`, and it is the RED phase's diff, left as is.
