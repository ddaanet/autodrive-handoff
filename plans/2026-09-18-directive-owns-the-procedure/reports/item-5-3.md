# Item 5.3 — CLAUDE.md describes the directive's procedure

Scope: `CLAUDE.md` only. Kept consistent with
`docs/changelog/2026-09-18-the-directive-owns-the-procedure.md` and
`docs/design.md` §"What the checkpoint prints" / §"Held: …", pointing at the
changelog rather than restating it.

## Passages changed (Layout)

- **`skills/handoff/SKILL.md` bullet** — the old step 1 (decide + tense
  clause + memory), step 2 (follow directive + commit placement) and step 3
  (report readiness) replaced by the three-step shape: memory first, then
  decide + one checkpoint call, then follow what it prints in order. States
  that the checkpoint carries memory approval, commit act, `handoff-approved`
  call and closing line. Tense clause ("write memory as if the change has
  landed") dropped. Changelog pointer added.
- **`skills/precompact/SKILL.md` bullet** — reordered to memory first; the
  directive list ("memory commit, ledger flush, and/or the arming
  instruction") now names memory approval, ledger nudge, commit act, and the
  arming instruction or closing line; "report readiness in one line" removed
  (the checkpoint prints it).
- **`bin/handoff-approved` bullet** — invoked when the checkpoint's *arming
  instruction* says so (was: memory directive). Added its success output:
  status fact, blank line, closing line picked from `DRIVE_KIND`, literal per
  `case` arm, byte-matched to `closing_directive()`.
- **`scripts/checkpoint.py` bullet** — hold condition now
  `(K ∧ M) ∨ (T ∧ C)` in words, computed once by `hold_decision`, with the
  second disjunct's reason and why it is scoped to typed transitions. The
  sentence "with the arming instruction composed onto the memory directive
  when the sentinel is held" replaced by `compose_directives`' ordered parts,
  the shared hold value selecting arming vs closing line, and the refusal
  printed alone. Changelog pointer added.
- **`scripts/_checkpoint_lib.py` bullet** — records the dropped "Nothing
  further is needed from you" sentence and why; "Couples only to the two IPC
  filenames" now also names `gitlore.memoryApprovalClauseFile`; added
  `memory_directive`'s `MemoryPart(text, refusal)` return, and
  `commit_directive`, `arming_directive`, `closing_directive`. The composition
  sentence at the end gains the commit act and ending, plus the changelog
  pointer.

## Passages changed (Testing)

- **`tests/checkpoint.bats` description** — gains `handoff-approved`'s
  closing-line rows (one per kind, whole output, drift guard against
  `closing_directive()`, each producer arm mutation-checked; trailing-newline
  residual stated).
- **`tests/test_checkpoint.py` count** — 140 → 171.
- **New load-bearing rows paragraph** (after the held-owner rows): the
  hold-matrix pair (`test_typed_with_commit_clean_memory_is_held`,
  `test_untyped_handoff_with_commit_clean_memory_is_armed`, with the
  corrected "reds together with the rename-only row" mapping from
  `item-2-1-s2-test-review.md`); the part-order rows and the closing-line-last
  row (`test_precompact_parts_print_in_order`, phase-3 corrector fix 1); the
  two refusal-alone rows (`test_clause_refusal_is_followed_by_no_commit_or_arming`
  held, `test_refusal_prints_alone_when_not_held` armed, M6 in
  `item-3-1-s2-test-review.md`); commit act present/absent; the
  empty-stdout rows now asserting exactly the closing line.

## Counts and how derived

`pytest --collect-only -q tests/<file>.py | tail -1` (bare pytest):

| file | stated | collected | action |
|---|---|---|---|
| `test_checkpoint.py` | 140 | 171 | fixed |
| `test_watcher_lib.py` | 49 | 49 | unchanged |
| `test_drive_when_idle.py` | 30 | 30 | unchanged |
| `test_tui_conformance.py` | 11 | 11 (`-m live`; 11 deselected by default) | unchanged |

## Not changed, noted

- `CLAUDE.md`'s `report-watcher-failure.sh` bullet says a held transition
  "waits on an approval whose answer arrives at this very hook". Under the new
  `T ∧ C` disjunct a held file may wait on the commit instead, released in the
  same turn. Not on the item's list; left for a decision.

## Gate

`just precommit` green: jq lint, shellcheck, ruff, docformatter, mypy, ty,
bats, pytest (261 passed, 11 deselected).
