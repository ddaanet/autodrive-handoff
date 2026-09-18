# Item 1.1 — slice 4 code review

Commit reviewed: `31166d8`. Scope: `scripts/checkpoint.py`,
`scripts/_checkpoint_lib.py`. Fixes applied to the working tree, not committed.

## Structure against the Item and Interfaces

- `main` order matches the Item: memory resolved once (only under
  `handoff`/`precompact`) → `hold_decision` → `compose_sentinel(held=)` →
  `compose_directives(held=)` → `print_output`. `memory_directive` has exactly
  one caller.
- `hold_decision(transition, *, memory: bool)` is today's rule
  (`bool(transition.cmds) and memory`). There is no `commit` parameter yet;
  Item 2.1 adds it.
- `compose_sentinel` appends no text and returns `None`. Its state is
  `held <sid>` iff `held`, so it matches `hold_decision` by construction. The
  read-back through `handoff_drive_read` is unchanged.
- `compose_directives` returns non-empty parts in print order, with arming
  appended last when held. It takes `memory: str`. `MemoryPart` belongs to
  slice 1.1/5, so that is expected.
- `print_output(parts)`: the join is unchanged (`"\n\n".join + "\n"`, nothing
  written for `[]`). The output is byte-identical to before in the
  memory-only, second-only and memory+second cases. The only change is in the
  held cases: arming moved from right after memory to last, which is the
  purpose of this slice.

## Arming wording

"Once everything above is done, run `handoff-approved` (Bash, no
arguments)." I rendered the full composed output (typed clear, `with-commit`,
dirty memory, SDD ledger). Every part above the arming line is an act:
approve and write the message file, keep the ledger's tasks out of the todo
file and bring the ledger current, and make the commit. It names no
mechanism, and it points at nothing outside this one tool result. A fresh
agent has one referent for "everything above", so the wording stays as it
is.

## Fixes applied

1. **Stale `compose_directives` docstring.** It said `"" for the second/commit
   parts under autoname/restart`, which described the old tuple. It now says
   the function returns `[]` under autoname/restart (no memory owed, no commit
   mode, never held).
2. **`hold_decision` docstring said "Today's rule:"**, which is narration that
   stops being true once Item 2.1 changes the rule. It now states the rule
   itself: held iff the sentinel types anything and a memory directive is
   owed.
3. **`compose_sentinel` docstring** read "Appends no text — the caller
   decides…", which describes the change rather than the contract. It now
   says: write the sentinel, held or armed per `held`, read it back through
   the bash parser, and remove and report a sentinel the parser rejects.
4. **Definition order.** The file puts `main` last and orders its helpers by
   call sequence. The commit left `compose_directives` ahead of
   `hold_decision`/`compose_sentinel` (`main` calls it after them), and
   `_read_back_drive` ahead of its only user, `compose_sentinel`. The new
   order is `hold_decision`, `compose_sentinel`, `_read_back_drive`,
   `compose_directives`, `print_output`, matching `main`'s call order with
   each definition after its user. The GREEN report's claim that
   `compose_sentinel` calls `hold_decision` is false (only `main` does), but
   that is not a code defect.

No leftover comment in `scripts/` describes arming as composed onto the
memory directive (grep for `arming`/`held` over both files).

## Mutation check (one run)

I changed `parts.append(lib.arming_directive())` to
`parts.insert(0, lib.arming_directive())`.
`test_arming_instruction_follows_every_other_part` went red on its assertion
(`todo_index < arming_index`, test_checkpoint.py:2311), and
`test_arming_text_refers_to_everything_above` stayed green, as expected. The
SUT was restored from a copy and verified.

## Gate

`just precommit` passed after `docformatter` rewrapped one docstring. Only the tail was captured: pytest 249 passed, 11 deselected. Pytest is the last recipe line and `just` stops at the first failure, so the jq, shellcheck, ruff, docformatter, mypy/ty and bats steps ahead of it all passed.

Refactor flagged: none. `main` sits last in `checkpoint.py`, which breaks the
entry-points-first rule, but that ordering predates this slice and covers the
whole file, so it is out of scope here.
