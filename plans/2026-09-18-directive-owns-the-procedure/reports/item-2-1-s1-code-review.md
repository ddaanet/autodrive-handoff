# Item 2.1 / slice 1 — code review

Commit reviewed: `a9a2b6e`. Scope: `scripts/checkpoint.py:hold_decision` and
its `main` call site, plus comments in `scripts/` and `bin/` stating the old
hold condition.

## Predicate

`hold_decision(transition, *, memory: bool, commit: bool) -> bool` returns
`(bool(transition.cmds) and memory) or (transition.typed and commit)`. That is
the runbook's interface, verbatim.

`transition.typed` is the right field. `build_transition` sets it `True` only
where the transition itself is typed: handoff `clear: true` (`/rename`,
`/clear`), precompact `compact: true` or a focus directive (`/compact …`), and
`restart`. It is `False` for an untyped handoff (`/rename` alone), for an
untyped precompact (FR-G marker, no cmds) and for `autoname`. So a
`/rename`-only sentinel never holds through the second disjunct, as the
outline requires.

Call site: `commit=commit_mode == "with-commit"`. `validate_commit_mode`
returns `""` for `autoname`/`restart`, so `restart` (typed) cannot hold through
the commit disjunct. `autoname` and `restart` still never hold. Correct.

The docstring states both disjuncts and why the second is scoped to `typed`.
It is accurate.

## Stale comments (fixed)

- `bin/handoff-approved:4-7`: the header said the checkpoint holds only "when a
  memory approval is outstanding". It now names the second cause too: a typed
  transition that follows a commit this turn owes, held so that it cannot run
  over a commit that failed.
- `scripts/_lib.sh:139-141` (`held` state in the sentinel grammar comment): "a
  memory approval is outstanding" became "a memory approval or, ahead of a typed
  transition, the turn's commit is outstanding".

Left as they are: the other comments that use the word "approval"
(`_lib.sh:190-194` and `282-284`, `bin/handoff-approved:38,52-57`,
`report-watcher-failure.sh:97-100,124-130`). They explain why a held file names
its owner and why it is exempt from the sweep. Both reasons still hold for a
commit hold, because the release still has to come from the session that wrote
the file, and a failed commit can leave it held across a turn boundary. The
word "approval" is looser for the commit case, but none of those sentences is
false. `compose_sentinel` and `compose_directives` do not state the condition,
so they need no edit.

## Downstream effect: held without a memory directive

No path in `scripts/` or `bin/` assumes that a held file means a memory
directive was printed:

- `compose_directives` appends `arming_directive()` on `held` alone, whatever
  the memory state. The new row pins that the commit act comes before it.
- `bin/handoff-approved` checks only state, owner and parse. Its output line
  names only `DRIVE_KIND`.
- `report-watcher-failure.sh` treats `held` by owner alone: exempt from the
  sweep if it is this session's, reclassified as abandoned if not. It never
  checks memory.
- `stop-drive.sh` acts only on `armed`, so a held file is inert until it is
  released.

Behaviour note, not a defect: the outline already accepts that a forgotten
`handoff-approved` is silent. The new disjunct makes that cell reachable with
clean memory under every typed `with-commit` call. This is by design, and the
wording of the closing line belongs to Phase 3.

## Mutation re-run

I saved `scripts/checkpoint.py`, replaced the predicate with
`return bool(transition.cmds) and memory`, ran the full
`tests/test_checkpoint.py`, then restored the file:

- Mutated: `2 failed, 160 passed`. The two failures were
  `test_typed_with_commit_clean_memory_is_held[handoff_payload-clear]` and
  `[precompact_payload-compact]`, this row alone.
- Restored: `git diff scripts/checkpoint.py` is empty, and the run gives
  `162 passed`.

## Gate

`just precommit` after the comment fixes passed in full: jq, shellcheck -x,
ruff, docformatter, mypy, ty, both bats suites, and pytest
(`252 passed, 11 deselected`). Nothing is committed. The working-tree changes
are `bin/handoff-approved` and `scripts/_lib.sh`, comments only.

Refactor flagged: none.
