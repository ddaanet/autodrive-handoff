# Step 2 (Checkpoint migration) — GREEN part of the review fix wave

Changed: `scripts/checkpoint.py` and `scripts/_checkpoint_lib.py` only. Nothing
under `tests/`, no commits, no staging. README, docs/, CLAUDE.md and the plan
are untouched (step 3 owns them).

## Counts

| | result |
|---|---|
| `pytest -q tests/test_checkpoint.py` before | 20 failed, 311 passed |
| `pytest -q tests/test_checkpoint.py` after | 331 passed |
| `pytest -q` full (`$TMPDIR/py.out`) | 343 passed, 3 deselected, 62.6 s |
| `bats tests/checkpoint.bats tests/drive-take.bats` | all ok, 0 `not ok` |

Clean: `ruff check scripts tests`, `ruff format --check scripts tests`
(8 files formatted), `docformatter --check scripts/*.py tests/*.py` (rc 0),
`mypy` (rc 0), `ty check`, `shellcheck -x scripts/*.sh bin/* tests/*.bats`
(rc 0). Ruff first flagged FBT003, E501 and two PTH105; fixed (keyword
`has_body=False`, a rewrapped docstring, `Path.replace` in place of
`os.replace`, which calls it).

## What changed

- **F1** `legacy_unstage_directive` prefixes each path with `:/`. Callers still
  pass bare rels (the reports use them); the form is the lib's concern. The
  parameter on `commit_directive` stays optional.
- **F3** `read_half` returns early with `has_body=False` when the legacy path is
  not a file: no stat, no read of the root file. `FilePlan` and `Half`
  docstrings say so.
- **F4** `read_half` refuses a legacy path that is a symlink to a file, during
  plan resolution, before anything is applied: exit 2, `<field>: <legacy rel> is
  a symbolic link, not a file`. A dangling link still counts as no legacy file
  (an existing row requires it).
- **F5** `apply_plan`'s move arm calls `move_legacy`: `Path.replace`, and on
  `OSError` with `errno.EXDEV` it falls to `copy_across_devices`. That copies
  with `shutil.copy2` (bytes, mtime, mode) to a sibling temp file in the root
  and renames it onto the root name, so the root file is whole or untouched,
  and the existing trailing unlink then removes the legacy file. Any other
  `OSError` in either step is a clean `err()` naming the legacy rel, and the
  temp file is removed. Write-before-unlink order unchanged (F2).
- **F7** the directory refusal reads `<rel> is a directory, not a file`.
- Docstrings made false by the change updated: `FilePlan`, `Half`, `read_half`,
  `plan_task`, `plan_todo` ("only `clear` removes the root file"), `apply_plan`.
  The single legacy-constants marker is unchanged; the new helper is named
  `move_legacy` so the grep finds it.

Noted, not changed: a legacy symlink is refused even when the root file has a
body (the refusal precedes the root read). The suite does not cover that case.

## The printed act, run verbatim

Throwaway repo `$TMPDIR/act demo repo` (space in the root path), both legacy
files tracked, checkpoint run with `todo: keep`, `task: clear`, with-commit. It
printed:

```
Legacy .claude/handoff-task.md removed.
Legacy .claude/handoff-todo.md moved to TODO.md.

Before committing, run `git rm --cached --ignore-unmatch -q -- :/.claude/handoff-task.md :/.claude/handoff-todo.md`.
```

From `$TMPDIR/act demo repo/sub`, before: ` D ../.claude/handoff-task.md`,
` D ../.claude/handoff-todo.md`. After the act (rc 0) and `git add ../TODO.md`:

```
D  ../.claude/handoff-task.md
R  ../.claude/handoff-todo.md -> ../TODO.md
```

## Mutation checks (temporary edits, reverted)

| mutant | result |
|---|---|
| bare pathspec in place of `:/` | 5 red: the four `git_rm` text rows and `test_checkpoint_leaves_a_tracked_legacy_file_to_the_printed_git_act[with-commit]` (the tracked row, from `sub/`) |
| root file read for `keep` with no legacy file | 2 red: `test_root_files_that_cannot_be_read_stay_unread_with_no_legacy_file[keep]` and `[clear]` |
| symlink check disabled | 12 red: all `symlinked_at_the_legacy_path` rows |

Backups were taken in `$TMPDIR/bak`; after the mutants `cmp` showed both files
identical to the pre-mutation copies, and `git diff --stat scripts/` shows only
the intended step 1 and step 2 diffs.
