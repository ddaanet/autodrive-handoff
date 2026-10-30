# Green phase: memory directive and commit act (D70)

## Diff summary

`scripts/_checkpoint_lib.py`:
- `memory_directive(root: str) -> str`. The `mode` argument is gone. The `.gitmodules`, materialized and `status --porcelain` gates are unchanged. When owed it returns `_printf_lines("gitlore memory has uncommitted changes:", "", status, "", "Commit them through the gitlore:commit skill: invoke it before drafting a summary, and follow it.")`. Otherwise `""`.
- Deleted: `_resolve_approval_clause`, the clause-file refusal, `msgfile`, `trigger`, `approve_files`, `MemoryPart`.
- Unused imports removed: `os` (only the clause reader used it) and `NamedTuple`.
- `commit_directive(root="", legacy_paths=(), *, memory=False)`. `memory=False` gives the sentence unchanged. `memory=True` gives the "and the memory gitlink `gitlore:commit` staged" sentence. Legacy unstage prefix unchanged.
- Docstrings of the module, `memory_directive` and `commit_directive` rewritten. No mention of trigger, message file, clause file or refusal.

`scripts/checkpoint.py`:
- `memory = ""`; `memory = lib.memory_directive(str(root))` for handoff/precompact; `hold_decision(..., memory=bool(memory), ...)`.
- `compose_directives(boundary, memory: str, ending, plans)`: the `memory.refusal` branch is deleted; `commit_directive(root_s, gone, memory=bool(memory))`; `memory` used where `memory.text` was. Docstring updated.
- `grep` of `scripts/` and `bin/` for `MemoryPart`, `refusal`, `.text`, `memory_directive(`, `clause`: no remaining callers. The only `clause` hit in `bin/handoff-approved` is a comment about the refusal wording (line 29, "and the same refusal") and is outside the contract's files; it was left alone and is noted under Follow-ups.

`git diff --stat -- scripts/`: 2 files, 49 insertions, 119 deletions. Nothing committed.

## Gates (after the edits, before mutations)

- `ruff format scripts`: 6 files unchanged. `ruff check scripts tests`: passed. `ruff format --check scripts tests`: 24 files formatted. `mypy scripts tests`: passed. `ty check`: passed.
- `pytest -q`: 520 passed, 3 deselected (`live`). Was 22 failed / 498 passed.
- `plugin-dev/run-bats.sh tests/checkpoint.bats`: 42 passed, 0 failed.

## Mutations

Each mutation was applied to the green files, the suite was run, and the green files were restored by `cp` from a backup and confirmed byte-identical (`cmp`).

a. `commit_directive` ignores `memory` (`if False:`). Red: 5 pytest rows:
   - `test_directives.py::test_with_commit_and_dirty_memory_names_the_staged_gitlink[handoff_payload]`
   - `test_directives.py::test_with_commit_and_dirty_memory_names_the_staged_gitlink[precompact_payload]`
   - `test_directives.py::test_commit_directive_unit_follows_memory[memory_owed]`
   - `test_directives.py::test_handoff_parts_print_in_order`
   - `test_directives.py::test_precompact_parts_print_in_order`
   The required row is red. Bats: 42 passed (no bats row pins the gitlink sentence).

b. `commit_directive` always uses the memory sentence (`if True:`). Red: 12 pytest rows, including the required `test_with_commit_prints_the_commit_act[handoff_payload]` and `[precompact_payload]`, plus `test_commit_act_is_the_exact_no_git_verb_sentence`, `test_commit_directive_unit_follows_memory[memory_clean]`, four rows in `test_checkpoint_hold.py` (`test_typed_with_commit_clean_memory_is_held[*]`, `test_untyped_handoff_with_commit_clean_memory_is_armed`, `test_handoff_commit_precedes_closing_line_when_armed`), and four rows in `test_checkpoint_legacy.py` (`test_stdout_with_no_legacy_file_anywhere_is_what_it_was[*-with-commit-*]`). Bats: 42 passed.

c. `compose_directives` passes `memory=False` always. Red: 4 rows, all in `test_checkpoint_directives.py`:
   - `test_with_commit_and_dirty_memory_names_the_staged_gitlink[handoff_payload]`
   - `test_with_commit_and_dirty_memory_names_the_staged_gitlink[precompact_payload]`
   - `test_handoff_parts_print_in_order`
   - `test_precompact_parts_print_in_order`
   Bats: 42 passed.

d. `memory_directive` gets a `mode` argument from the checkpoint and inserts a with-commit-only line inside the memory text, before the closing sentence. Red: 2 rows:
   - `test_directives.py::test_memory_part_is_byte_identical_under_both_commit_modes`
   - `test_directives.py::test_dirty_memory_directive_is_the_status_then_the_skill_sentence[with-commit]`
   Bats: 42 passed.

   Note: the first two attempts at d were invalid and are not counted. One placed the line before the memory text, and one placed it after the closing sentence. The test slices stdout from the memory head through the closing sentence, so neither was in the slice and both stayed green. The valid placement is the one recorded above.

## Follow-ups (not in this change)

- `bin/handoff-approved` line 29 contains the phrase "and the same refusal". It is a comment about the root-resolution channel, not a call site. Outside the allowed files; check whether the comment still means anything.
- `docs/` and `tests/` still reference the trigger file and the clause-file refusal in places. Not touched here.
