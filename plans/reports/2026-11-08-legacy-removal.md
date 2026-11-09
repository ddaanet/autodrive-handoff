# Legacy-path fallback removal

Commit: fee2ff5 on `dev` (not pushed). Subject starts `refactor:`.

## Deleted files
- `.claude/rules/legacy.md`
- `tests/test_checkpoint_legacy.py`, `tests/lib-frame-legacy.bats`, `tests/load-handoff-legacy.bats`
- the `tests/test_checkpoint_legacy.py` line in `size.exempt` (comments only remain)

## Removed pieces (all verified legacy-only, none kept)
- `_checkpoint_plan.py`: `Legacy`, `Half`, `read_half` (replaced by `check_target`, which keeps the symlink/directory refusal on the root name), `legacy_fate`, the `move` act, `move_legacy`, `copy_across_devices`, `legacy_reports`, `HANDOFF_LEGACY_REL_*`.
- `checkpoint.py`: `Boundary` (inlined as `skill, root, commit_mode` parameters of `compose_directives`) and the `plans` parameter of `compose_directives`. The `plans` list itself stays: `apply_plan` and `require_something_to_continue` use it.
- `_checkpoint_lib.py`: `legacy_unstage_directive`, `shlex` and `Sequence` imports; `commit_directive` is now `commit_directive(*, memory)`.
- Shell: `handoff_frame` takes two paths; `handoff_frame_notes`, `FRAME_*_LEGACY/SHADOWED`, `HANDOFF_LEGACY_REL_*`; both loaders updated.
- Tests: legacy rows in `lib-frame.bats`, `load-compact.bats`, `hook-helpers.bash`, and comments in two pytest files.
- Docs: `README.md` file-table row, `CLAUDE.md` sentence, `.claude/rules/write-path.md` mention, `the-write-path.md`, `the-checkpoint-directive.md` (parts renumbered 1-5), `driving-the-transition.md`, `the-skills.md`, `design.md` (FR5, FR6, FR9, NFR1, decision and rejected indexes), the decision in `decisions.md`, and two rejected alternatives (the old-paths fallback; the printed `git rm --cached` line) in `rejected-alternatives.md`.
- `TODO.md`: the removal item dropped.

## Notes / unsure
- `TODO.md` already carried an uncommitted deletion of its first bullet (the directory-move item) before I started; it rode into this commit.
- Behaviour change beyond the bridge: none intended. `skills/handoff/references/design.md` had no hits.
- The `memory` submodule was dirty (`m memory`); untouched and not staged.
- I ran `docformatter --in-place` on `scripts/*.py tests/*.py` to satisfy the gate (it reflowed docstrings in the four files I edited).
- The last `just precommit` run (cached gates) printed `precommit: check-plugin check-code check-refs check-size check-frontmatter passed`; the immediately prior run printed the full recap: `precommit passed: check-refs, check-size, check-frontmatter, task-files, gate-docs, gate-code`.
