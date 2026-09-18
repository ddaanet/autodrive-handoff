# Phase 1 corrector — commit act and part ordering (Item 1.1)

Scope: `git diff c723a32..HEAD -- scripts tests` (`scripts/_checkpoint_lib.py`,
`scripts/checkpoint.py`, `tests/test_checkpoint.py`). Fixes applied, not
committed. `just precommit` green after fixes: jq (manifest, hooks, settings),
shellcheck, ruff check, ruff format, docformatter, mypy/ty, bats, pytest
(250 passed, 11 live deselected).

## Requirements

| Req | Holds | Pinned by |
|---|---|---|
| R1 commit act iff `with-commit` | yes — `compose_directives` | `test_with_commit_prints_the_commit_act` / `test_without_commit_prints_no_commit_act` (both skills), `test_commit_act_names_no_git_verb` |
| R2 order memory, boundary/nudge, commit, arming | yes | `test_handoff_parts_print_in_order`, `test_precompact_parts_print_in_order` (mutation-checked in s2 report: swap second/commit reds both), `test_arming_instruction_follows_every_other_part` |
| R3 "Nothing further" dropped | yes | `test_with_commit_memory_text_drops_nothing_further`; trigger-file negative and `carries the memory` rows untouched and green |
| R4 arming refers to everything above | yes | `test_arming_text_refers_to_everything_above`, plus `Once that is done` absent in the held row |
| R5 refusal prints with no part 3–4 | yes; sentinel still `held` | `test_clause_refusal_is_followed_by_no_commit_or_arming` (mutation-checked in s5 report). Closing-line half is Item 3.1 |

Interfaces match the runbook verbatim: `MemoryPart(text, refusal)`,
`memory_directive(root, mode) -> MemoryPart`, `commit_directive()`,
`arming_directive()`, `hold_decision(transition, *, memory)`,
`compose_directives(skill, root, commit_mode, memory, *, held) -> list[str]`,
`compose_sentinel(root, transition, continuation, *, held) -> None`,
`print_output(parts)`. `memory_directive` is called once, from `main`; the
read-back is unchanged. No tuple leftovers, no dead parameters, no arming text
composed onto memory, no "Nothing further" anywhere in scripts/ or tests/.
`print_output` is byte-identical to the old form for memory-only,
second-only, and memory+second.

## Fixes applied

1. **Major — commit act wording (directive-writing).** `commit_directive()`
   read "Now make the commit the request called for." In the `with-commit` +
   dirty-memory cell it prints after the approval flow ("get their approval …
   Once approved, write the approved summary"), and "Now" instructs committing
   immediately — before the user has approved and before the message file
   exists, i.e. a commit that does not carry the memory. Reworded to
   "Once everything above is done, make the commit the request called for.",
   which is correct in every cell: after the memory approval, after the ledger
   instruction, and harmless when it is the only part. Still names no git
   verb; every test reads the text through `lib.commit_directive()`, so no
   test literal changed.
2. **Minor — `compose_directives` returned `[]` for autoname/restart only by
   coincidence** (empty memory, commit mode not `with-commit`, never held),
   while its docstring and the runbook interface state it as a contract. Made
   explicit with an early `return []` for any skill other than handoff /
   precompact, which also removed the `else: second = ""` branch; the
   docstring's reasoning clause went with it.
3. **Minor — stale module docstring** in `_checkpoint_lib.py`: "Each directive
   function takes the git worktree root and returns its directive text, or
   "" when silent" no longer held (`memory_directive` returns a `MemoryPart`;
   `commit_directive`/`arming_directive` take no root and are never empty).
   Rewritten.
4. **Minor — `memory_directive` docstring** said only "the directive, or an
   empty part"; added the third outcome, the refusal part flagged
   `refusal=True`.
5. **Minor — unused fixture**: `test_arming_text_refers_to_everything_above`
   took `tmp_path` and never used it. Dropped.

## Observations, not fixed (out of phase scope)

- The clause-file refusal text says "Nothing has been written", but by the
  time it prints the task/todo files, manifest and sentinel have all been
  written. Pre-existing text, and the outline puts the memory directive's own
  text out of scope; worth revisiting when Item 3.1 makes the refusal the
  whole output.
- Parts built by `_printf_lines` end in `\n`, so the `"\n\n"` join yields two
  blank lines between parts and the output ends in a blank line. Byte-identical
  to the pre-phase output (the runbook requires that), so left alone.

UNFIXABLE: none.
