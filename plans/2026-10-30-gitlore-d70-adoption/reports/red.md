# Red phase report — gitlore D70 adoption

Tests only; nothing under `scripts/` or `bin/` touched, nothing committed.
`ruff check tests`, `ruff format --check tests`, `shellcheck -x tests/*.bats
tests/probe-helpers.bash` are clean. `mypy tests` has one error
(`commit_directive` has no `memory` kwarg) that goes away with the green phase.

## Changes by file

### tests/conftest.py
- Deleted: `GITLORE_MEMORY_APPROVAL_CLAUSE`, `unset_clause_file`, the clause
  file + `git config gitlore.memoryApprovalClauseFile` setup in
  `make_gitlore_repo`.
- Added three literal constants (the plan's exact strings):
  `MEMORY_DIRECTIVE_CLOSING`, `COMMIT_ACT` (today's sentence),
  `COMMIT_ACT_WITH_MEMORY` (the gitlink sentence).

### tests/test_checkpoint_directives.py
- Deleted: `test_dirty_memory_directive_names_both_ipc_paths`,
  `test_clause_resolved_content_is_its_own_block`,
  `test_clause_file_unset_names_key_and_restart`,
  `test_clause_file_missing_same_key_and_restart_report`,
  `test_unset_and_missing_clause_reports_are_the_same`,
  `test_with_commit_summary_write_only_no_trigger_mention`,
  `test_with_commit_states_commit_carries_the_memory`,
  `test_without_commit_keeps_standalone_two_file_instruction`,
  `test_with_commit_memory_text_drops_nothing_further`,
  `test_unset_clause_file_ignores_an_inherited_git_environment`; unused imports.
- Added (via `run_checkpoint`):
  `test_dirty_memory_directive_is_the_status_then_the_skill_sentence` (both
  modes; pins the whole block `head / blank / ?? feedback_x.md / blank /
  closing`), `test_dirty_memory_directive_names_no_file_handshake` (both modes;
  none of `gitlore-memory-message`, `gitlore-commit-memory`,
  `memoryapprovalclausefile`, `trigger`, `blockquote`, case-insensitive),
  `test_memory_part_is_byte_identical_under_both_commit_modes`,
  `test_with_commit_and_dirty_memory_names_the_staged_gitlink` (both skills; also
  asserts today's sentence absent).
- Changed: `test_with_commit_prints_the_commit_act` (literal `COMMIT_ACT`, plus
  no "gitlink" with clean memory); `test_without_commit_prints_no_commit_act`
  (now clean and dirty, neither sentence); `test_commit_act_is_the_exact_no_git_verb_sentence`
  now pins the whole stdout through `run_checkpoint` (precompact, with-commit,
  clean memory: `COMMIT_ACT + "\n" + closing`); the two ordering rows locate the
  memory part by `gitlore:commit` and the commit act by `COMMIT_ACT_WITH_MEMORY`
  (each first asserts both are present, so the red is an assertion).
- Unit rows that call the new signature (TypeError in red, by construction):
  `test_commit_directive_unit_follows_memory[memory_clean|memory_owed]`, calling
  `lib.commit_directive("", (), memory=...)`. No test calls
  `memory_directive` directly any more.

### tests/test_checkpoint_composition.py
- Deleted: `test_refusal_prints_alone_when_not_held`, `unset_clause_file` and
  `lib` imports, the `memory_directive(...)` precondition in
  `test_held_sentinel_prints_no_closing_line`.
- Changed: four rows that located the memory part by the message/trigger path
  now use `gitlore:commit` (`..._memory_first`, `..._own_directive_not_the_others`
  both params, `..._no_ledger_memory_directive_only`).

### tests/test_checkpoint_hold.py
- Deleted: `test_clause_refusal_is_followed_by_no_commit_or_arming`,
  `unset_clause_file` import.
- Changed: five rows that called `lib.commit_directive()` /
  `lib.memory_directive(...).text == ""` now use `COMMIT_ACT` and assert
  `"uncommitted changes" not in out` after the run instead.

### tests/test_checkpoint_legacy.py
- Deleted: `test_reports_and_the_git_rm_act_print_ahead_of_the_clause_file_refusal`,
  `unset_clause_file` import, and the now-false "legacy-paths parameter must be
  optional" constraint in the section comment (the other constraint stays).
- Changed: `test_stdout_with_no_legacy_file_anywhere_is_what_it_was` uses
  `COMMIT_ACT + "\n"` instead of `lib.commit_directive()`.

### tests/probe-helpers.bash
- Deleted the clause setup (comment, file, `git config`) in `make_gitlore_repo`.

### tests/checkpoint.bats
- `:76` clause assertion deleted. `:687` now `grep -qF "gitlore:commit"`.

## Failing rows (pytest: 22 failed, 498 passed; bats: 1 failed, 41 passed)

New or changed rows, red for the row's own reason:
- `test_dirty_memory_directive_is_the_status_then_the_skill_sentence[both]`:
  stdout lacks the status+closing-sentence block (today: clause refusal).
- `test_dirty_memory_directive_names_no_file_handshake[both]`: stdout contains
  `memoryapprovalclausefile` (refusal text).
- `test_memory_part_is_byte_identical_under_both_commit_modes`: closing sentence
  not found in stdout.
- `test_with_commit_and_dirty_memory_names_the_staged_gitlink[handoff|precompact]`:
  `COMMIT_ACT_WITH_MEMORY` absent.
- `test_commit_directive_unit_follows_memory[both]`: TypeError (unit rows).
- `test_handoff_parts_print_in_order`, `test_precompact_parts_print_in_order`:
  `MEMORY_DIRECTIVE_CLOSING` not in stdout.
- composition: `test_handoff_composition_carries_todo_boundary_not_sdd_nudge`
  does not itself assert the memory path; see knock-on below.
  `test_precompact_composition_carries_sdd_nudge_memory_first`,
  `test_each_boundary_composes_own_directive_not_the_others[handoff|precompact]`,
  `test_precompact_no_ledger_memory_directive_only`: `gitlore:commit` not in stdout.
- bats `shim: bin/handoff-checkpoint execs the checkpoint, forwards stdin`:
  `gitlore:commit` not in output.

Knock-on reds in rows I did not rewrite (caused only by the plan's deletion of
the clause setup from `make_gitlore_repo`: today's code, finding no clause file,
prints the refusal and suppresses the other parts, so any dirty-memory fixture
now behaves as in the refusal path). They should go green with the refusal
removal, no edit needed:
- `test_checkpoint_composition.py::test_handoff_composition_carries_todo_boundary_not_sdd_nudge`
  (todo boundary suppressed)
- `test_checkpoint_directives.py::test_parts_are_separated_by_one_blank_line`
  (stdout no longer ends with the closing line)
- `test_checkpoint_directives.py::test_run_checkpoint_ignores_an_inherited_git_environment`
  (`feedback_x.md` status not printed)
- `test_checkpoint_hold.py::test_arming_instruction_follows_every_other_part`,
  `test_typed_transition_with_memory_gate_pending_held`,
  `test_untyped_handoff_still_types_rename_so_it_holds_too` (no arming line)
- `test_checkpoint_legacy.py::test_reports_precede_every_directive_part`
  (`ValueError: substring not found` on "make the commit the request called for"
  — a pre-existing `.index` style, not an assertion).

All other rows pass (tests/mod, hook-test.bats, drive-take.bats not run:
neither uses the changed helpers per grep).

## Notes / things to flag
- `GITLORE_MEMORY_APPROVAL_CLAUSE` removal turns unchanged dirty-memory rows red
  (list above) rather than leaving them green; there is no way to follow the
  plan's deletion and keep them green against the current code.
- The "byte-identical memory part" row compares the slice head..closing sentence
  extracted from each mode's stdout and also equals the literal block; it does
  not cover text between the head and the closing sentence beyond that slice
  being identical, which is what the plan asks.
- Plan says `commit_directive(root, legacy_paths, *, memory)`; the unit row
  passes `root` and `legacy_paths` positionally (`"", ()`), so it works whether
  or not the green phase gives them defaults.
- The mutation checks the plan lists (act ignoring `memory`, memory part
  differing by mode) are covered by: `..._names_the_staged_gitlink` + the clean
  `test_with_commit_prints_the_commit_act` (both directions), and
  `test_memory_part_is_byte_identical_under_both_commit_modes`.
- The plan's docs section mentions CLAUDE.md test bullets naming the clause and
  trigger rows; not touched (tests only).
