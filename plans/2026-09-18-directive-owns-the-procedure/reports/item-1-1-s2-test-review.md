# Item 1.1, slice 2/2 — test review

Scope: the uncommitted `# Ordering` section in `tests/test_checkpoint.py`
(`test_handoff_parts_print_in_order`, `test_precompact_parts_print_in_order`).
Verdict: **accept as written. No test changes made.**

## Conformance to the slice

Both rows match the runbook's slice 1.1/2 text: `make_gitlore_repo` +
`dirty_memory` + `add_sdd_ledger`, `with-commit`, the middle part and
`commit_directive()` each asserted non-empty before the lookups, then
`memory < middle < commit` over stdout. `handoff_payload` is untyped
(`clear: False`, `continue: None`). It carries a `rename`, so the sentinel is
held and the arming instruction prints between memory and the todo boundary.
Slice 4 handles the arming instruction and neither index looks it up, so it does
not interfere here.

## Deviation: pass on an unmutated SUT

Accepted. Slice 1.1/1's GREEN already printed the parts in this order, so the
stub-then-assert approach could not produce a red. Mutating `compose_directives`'
return tuple (`scripts/checkpoint.py:542`) in place gave the red instead. I
applied each mutation with `sed` and restored it by inverting the same `sed`,
not by copying back a backup.

| mutation (`return …`)       | handoff row                | precompact row            |
|-----------------------------|----------------------------|---------------------------|
| `memory, commit, second` (RED's) | red, `assert 1048 < 1002` | red, `assert 982 < 936` |
| `second, memory, commit` (memory after middle) | red, `assert 389 < 0` | red, `assert 658 < 0` |
| `second, commit, memory`    | red, `assert 435 < 0`      | red, `assert 704 < 0`     |
| `commit, memory, second`    | red, `assert 1048 < 0`     | red, `assert 982 < 0`     |

Every red comes from the ordering inequality, never from a non-empty guard or a
`ValueError`. All permutations other than the correct one red both rows. Only
the RED's mutation fails the second inequality. The other three fail the first.
Afterwards `git diff scripts/` is empty (0 lines).

## Wrong-reason hunt

- **Fixture produces all three parts.** I captured stdout for both skills over
  the exact fixture. The memory directive, the todo boundary / SDD nudge and
  `Now make the commit the request called for.` are all present.
- **Lookups are unique.** In each output, the memory marker, the middle part and
  the commit act each occur exactly once (`str.count == 1`). So `str.index`
  cannot resolve to an earlier stray copy. The commit act does not appear inside
  the memory text, whose closing sentence is a different string.
- **`ValueError` cannot pass.** `str.index` raises on a missing substring, and
  pytest reports that as a failure. No `try`, no `find` returning -1, and no
  conditional skip exist anywhere in either row.
- **The middle part is not vacuous.** Without `add_sdd_ledger`, both
  `todo_boundary` and `sdd_directive` return `""`, and the non-empty asserts
  would red first. Those asserts are what keep `out.index("")` (which returns 0)
  from making the rows vacuous.
- **Residual.** The memory marker is a literal and is not derived from
  `lib.memory_directive`. That is acceptable: the slice spec names it verbatim,
  and a missing marker raises rather than passes.

## Runs

- `pytest tests/test_checkpoint.py -q`: `156 passed`.
- `ruff check` and `ruff format --check` on the file: clean.

## Worth flagging (not in scope, untouched)

`git status` now lists untracked dotfile and `.claude/*` entries at the repo root
(`.bashrc`, `.gitconfig`, `.mcp.json`, `.claude/skills`, …) that were not in the
session-start snapshot. They look like sandbox mount placeholders, not something
this review wrote. I left them alone. Nothing was committed.
