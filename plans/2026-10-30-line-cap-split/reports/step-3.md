# Step 3 report, phase A: `checkpoint.bats` by subject

Copy: `/tmp/claude/line-cap-split/step-3/repo` (base tag `base` = `c2fff7c`'s tree). Phase A only; nothing committed, nothing in the real tree but this report.

## What moved where

`tests/checkpoint.bats` (695 lines, 42 `@test`) is deleted and replaced by:

| File | Lines | `@test` | Holds |
| --- | --- | --- | --- |
| `tests/validate-plugin.bats` | 119 | 8 | the `validate-plugin` section, with its helpers (`validate_entry`, `mcp_syntax_entry`, `claude_md_entry`, `physical_dir`, `validate_run`), used by no other file |
| `tests/inject-checkpoint-root.bats` | 288 | 17 | the `inject-checkpoint-root.sh` section and the prompt marker, with `run_inject_root`, `run_inject_root_ids`, `marker_holds` |
| `tests/bin-commands.bats` | 283 | 17 | the harness row with `export_decoy_git_env` and `decoy_snapshot`; the `bin/handoff-approved` section with `run_approved` and `expected_closing`; the shim section with `handoff_payload` |
| `tests/checkpoint-helpers.bash` | 40 | - | the shared `setup` (unchanged, byte for byte) and `make_repo` |

Names: `bin-commands` because `handoff-approved` and the shim are both `bin/` entry points and `handoff-approved.bats` would misname the shim. `checkpoint-helpers` because the three files test the bash neighbors of the checkpoint channel.

Choices:
- **Harness row**: goes to `bin-commands.bats`, with `export_decoy_git_env` and `decoy_snapshot` (only it uses them). It checks `make_repo` and `make_gitlore_repo`; the shim row there is the one caller of `make_gitlore_repo`. `make_repo` itself is called by the inject and bin files, so it lives in `checkpoint-helpers.bash`.
- **Shared `setup`**: all three files use the one `setup` in `checkpoint-helpers.bash`, unchanged. That includes the `load probe-helpers` / `load lock-helpers` lines (inside `setup`, as before), the session id, the pointer dir and the `source _lib.sh`. `validate-plugin.bats` needs only `repo_root` from it. I kept the setup whole rather than trimming per file, so no behavior moves with the split.
- Each bats file starts with `#!/usr/bin/env bats`, then the shellcheck `disable=SC2154` directive, then `load checkpoint-helpers`. The directive has to precede the first command to cover the whole file, and shellcheck does not follow bats' `load`, so `$repo_root` (assigned in the helper's `setup`) otherwise raises SC2154. `bin-commands.bats` keeps its `$stderr` reason in the same directive; `bats_require_minimum_version 1.5.0` stays only there (the only file using `run --separate-stderr`). `checkpoint-helpers.bash` carries `disable=SC2034` for `SHIM`/`APPROVED`/`INJECT_ROOT`, per the CLAUDE.md convention for vars read by the sourcing files. Step 2 will likely need the same two directives for its `hook-helpers.bash`.
- Section comments and the prose between tests moved with their tests. The old file's header comment was replaced by a header per new file that says what it covers and where the siblings are; the old header's changelog pointers survive in the helper's header.

## References updated

- `justfile`: `check-code` runs `plugin-dev/run-bats.sh tests/*.bats`; `hook-test` runs `bats tests/*.bats`. Step 2 makes the same change; a clean merge if the text is identical (it is the natural form: the three names replaced by `tests/*.bats`).
- `CLAUDE.md`: the `check-code` description and the `just hook-test` bullet take `tests/*.bats`. The per-file coverage paragraph is split into three sentences-groups, one per file, each naming its file, with a lead sentence naming `tests/checkpoint-helpers.bash`; no content shortened (the mutation-checked clauses, the harness row, the `validate-plugin` rows all kept). The final sentence now reads "`handoff-approved`'s bare-name row in `tests/bin-commands.bats`".
- `docs/design/sentinel-lock.md` line 124: `tests/checkpoint.bats` became `tests/bin-commands.bats` (the lock rows are the `handoff-approved` ones).
- `tests/test_drive_lock.py` docstring: `tests/bin-commands.bats` (same reason).
- `tests/conftest.py`: module docstring (the port of the bash rows, and where the bash side is tested) and the `task_clear` comment (`handoff_payload()` is in `tests/bin-commands.bats`). The docstring is reworded so `docformatter --check` passes; its hyphen-breaking would otherwise split `inject-checkpoint-root.sh`. The old text said the Python files were "the port of the rows of `tests/checkpoint.bats`"; I wrote "the bash tests" instead of a name for the file that no longer exists.
- `tests/probe-helpers.bash` header: `tests/bin-commands.bats`'s shim test.
- Left for phase B, inside a file another step splits: `tests/hook-test.bats` line 2832 (`its rows are in tests/checkpoint.bats`; the rows are in `tests/inject-checkpoint-root.bats`). `TASK.md` also names `checkpoint.bats` and is the session frame; untouched. `docs/changelog/` and `plans/` not touched.
- No `docs/design/` node other than `sentinel-lock.md` names the file; I did not need to load `craft:design-doc-writing` for a one-word path swap in an index sentence, but the swap keeps the sentence's prose true.

## Checks (in the copy)

- Verbatim checker, `c2fff7c:tests/checkpoint.bats -- <3 new .bats>`: last two lines `blocks: old 42, new 42` / `verbatim: OK`.
- `@test` counts: 8 + 17 + 17 = 42.
- `bats tests/validate-plugin.bats tests/inject-checkpoint-root.bats tests/bin-commands.bats`: 42 ok, 0 not ok.
- `shellcheck -x` over the three .bats and `checkpoint-helpers.bash`: clean.
- `ruff check tests scripts`, `ruff format --check`, `mypy`, `ty check`: clean. `docformatter --check tests/conftest.py tests/test_drive_lock.py`: clean. `pytest --collect-only -q`: `520/523 tests collected (3 deselected)`, unchanged. `pytest tests/test_drive_lock.py tests/test_checkpoint_directives.py`: 43 passed.
- Not run in the copy: the whole `bats tests/*.bats` (hook-test.bats exceeds the command timeout, and none of it changed), `just precommit`.
- Line counts: `validate-plugin.bats` 119, `inject-checkpoint-root.bats` 288, `bin-commands.bats` 283, `checkpoint-helpers.bash` 40 (all under 400). Edited files: `conftest.py` 293, `test_drive_lock.py` 280, `probe-helpers.bash` 47, `sentinel-lock.md` 128, `justfile` 114, `CLAUDE.md` 894 (exempt, was 891).

## Notes and departures

- No departure from the plan's text.
- Observation, not acted on: the shared `setup` sources `scripts/_lib.sh` "for `handoff_drive_read` itself in the tests below", but no test in the old file called it (nothing in the 42 blocks uses `handoff_drive_read` or `DRIVE_*`). Left verbatim; it is a TODO candidate, not part of this step. Step 1's `_lib.sh` split changes what that `source` loads, so the line still has to work after step 1 lands.
- Phase B: apply the patch, then re-grep `checkpoint\.bats` (the `hook-test.bats` hit above), and merge the `justfile` and `CLAUDE.md` edits against step 2's (same `tests/*.bats` change; step 2 owns the `hook-test.bats` description).

## Phase B

Commit `3b884dd` (`♻️ split checkpoint.bats by subject`), on top of `47b3ab7`.

Changes made in the copy before export, per dispatch.md's "Decided during the run":
- Each `.bats` file now has `# shellcheck source-path=SCRIPTDIR source=checkpoint-helpers.bash` above `source "$BATS_TEST_DIRNAME/checkpoint-helpers.bash"` instead of `load`. The file-wide SC2154 disable is gone from `validate-plugin.bats` and `inject-checkpoint-root.bats` (no SC2154 remains there); `bin-commands.bats` keeps the original's `# shellcheck disable=SC2154   # $stderr is set by bats \`run --separate-stderr\``.
- Departure forced by sourcing: with the helper now followed, shellcheck sees `make_repo`'s optional `$1` and raises SC2119 on the 17 argument-less calls in `bin-commands.bats` (in the inject file one call passes a path, so it raised none). `bin-commands.bats` therefore carries a second file-wide directive, `disable=SC2119`, with its reason. This is the only file-wide disable besides SC2154.
- `justfile` `check-plugin`: `shellcheck -x bin/* scripts/*.sh tests/*.bats tests/*.bash`; `CLAUDE.md` sentence updated to match. `shellcheck -x tests/*.bash` is clean in the real tree.

Applying the patch: `git apply --3way` conflicted in `docs/design/sentinel-lock.md` and `tests/test_drive_lock.py` against step 4's rename of `test_checkpoint_hold.py` to `test_checkpoint_readback.py` in the same sentence; resolved keeping both (readback.py and bin-commands.bats).

Re-grep: the one leftover was the comment in `tests/hook-test.bats` (~line 2832), now pointing at `tests/inject-checkpoint-root.bats` and rewrapped to 80 columns; `tests/*.md` had no mention. Only `TASK.md`/`TODO.md` (session frame) still name `checkpoint.bats`.

Checks in the real tree: verbatim checker `HEAD:tests/checkpoint.bats -- <3 new files>`: `blocks: old 42, new 42` / `verbatim: OK`. `@test` counts: hook-test 289, drive-take 21, new files 8 + 17 + 17 = 42 (352 in the precommit bats run). `hook-test.bats` against `c2fff7c` differs in one block, the `python3 -I` row, which is step 1's change, not this commit's.

`just precommit` (unsandboxed, Python env exported): green. Recap: `check-plugin` and `check-code` passed, including bats over `tests/*.bats`, pytest `520 passed, 3 deselected`, and `check-refs` (260 references in 27 files). The commit holds my paths only; `TASK.md`, `TODO.md` and `memory` were not staged.
