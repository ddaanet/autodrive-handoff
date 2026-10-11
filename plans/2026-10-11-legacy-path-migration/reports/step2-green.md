# Step 2 (Checkpoint migration) — GREEN report

Changed: `scripts/checkpoint.py` and `scripts/_checkpoint_lib.py`. Nothing under `tests/`, `bin/`, README, docs, CLAUDE.md or the plan; nothing staged or committed.

## Counts

| suite | before | after |
|---|---|---|
| `pytest -q tests/test_checkpoint.py` | 309 rows, 235 passed, 74 failed | 309 passed, 0 failed |
| `pytest -q` (full, `$TMPDIR/py.out`) | not run before the change | 321 passed, 3 deselected, 0 failed |
| `bats tests/checkpoint.bats tests/drive-take.bats` | not run before | 28 ok, 0 not ok |
| `bats tests/hook-test.bats` (extra) | 155 ok (step 1) | 155 ok, 0 not ok |
| `ruff check scripts tests`, `ruff format --check`, `docformatter --check`, `mypy`, `ty check`, `shellcheck -x scripts/*.sh bin/* tests/*.bats` | | all clean |

`just precommit` and `just mod-smoke` not run (step 4).

## Interface

`scripts/checkpoint.py`
- Constants `HANDOFF_LEGACY_REL_TASK`, `HANDOFF_LEGACY_REL_TODO` beside the `HANDOFF_REL_*` mirror, named like their `_lib.sh` originals. The comment points at `_lib.sh`, names the retirement condition (no sibling repository still has a `.claude/handoff-*.md`) and says `grep -rni legacy scripts/ tests/` lists all of it. No version, no private path.
- `Legacy(path, rel, fate)`, `fate` in `moved | removed | ignored`. `FilePlan` gains `act == "move"` (a rename of the legacy file onto the root name, via `Path.replace`, which keeps the mtime) and a trailing `legacy: Legacy | None = None`.
- `Half(path, legacy_path, legacy_rel, has_body)` and `read_half(field, root, rel, legacy_rel)`. `has_body` is `is_file()` plus `not lib.is_empty_body(...)`, the loader's predicate. `read_half` refuses (exit 2, `err(field, ...)`, message names the root file) when a legacy regular file exists and the root path is a directory; it runs inside plan resolution, before any write.
- `legacy_fate(half, *, after, carried)`: one rule for every action. No regular file at the legacy path -> None. Root had a body and will still have one -> `ignored` (untouched). Otherwise the legacy file goes: `moved` when its bytes become the root file (`keep`, `edit` sourced from it), else `removed` (`clear`, content write, task removal, edit of a root file leaving it body-less). This covers the plan's separate bullets (root-wins, replace a body-less root, body-less-after-write, clear with root present or absent) as one predicate.
- `plan_task` / `plan_todo` use it. `edit` reads the root file when it has a body, else the legacy file, else errors as before with `todo.old_string ... does not exist`. `apply_plan` does the write, unlink or rename, then unlinks the legacy file unless `ignored`. `main` resolves both plans, then applies both (a refusal in the todo half leaves the task half's legacy file alone); `autoname` has no plans and so touches nothing.
- `legacy_reports(plans)`: the one report builder. `Boundary(skill, root, commit_mode)`: new NamedTuple, because `compose_directives` with a sixth argument tripped ruff PLR0913; the signature is now `compose_directives(boundary, memory, ending, plans)`.
- `compose_directives` order: reports, memory, todo boundary / SDD nudge, commit act (carrying the git act), closing or arming line last. Under the clause-file refusal: reports, then (with-commit only) the git act alone, then the refusal text last. With no legacy anywhere the output is byte-identical to before.

`scripts/_checkpoint_lib.py`
- `commit_directive(legacy_paths: Sequence[str] = ())`: optional; with paths it is the git act, a blank line, then the unchanged commit sentence.
- `legacy_unstage_directive(paths)`: the act alone, `""` for no paths; the refusal branch prints it without the commit sentence (the existing test forbids the sentence there).

## Wording

Reports, one line per legacy file, in the register of the loader's notes (the ignored line mirrors the loader's sentence):
- `Legacy .claude/handoff-todo.md moved to TODO.md.`
- `Legacy .claude/handoff-todo.md removed.`
- `Legacy .claude/handoff-todo.md is ignored: TODO.md has a body.`

Git act (with-commit only, task before todo, only moved or removed files):
`Before committing, run `git rm --cached --ignore-unmatch -q -- .claude/handoff-task.md .claude/handoff-todo.md`.`

Decisions on the report's open questions: a content write over a legacy-only or body-less-root half reports `removed` (the legacy bytes are not carried); `keep` and a legacy-sourced `edit` report `moved`; a body-less legacy file beside an absent or body-less root is moved on `keep` (as the rows require).

## Mutation checks (temporary edits to `checkpoint.py`, restored from a copy; `diff` against the copy and `git diff --stat` confirm only the intended change remains)

| mutant | red rows |
|---|---|
| root-wins dropped (`ignored` branch never taken) | 12: the 6 root-todo-wins ids, 2 root-task-wins ids, `each_ignored_legacy_file_is_reported_once`, both git-rm-only-ignored/names-only rows, `only_a_regular_file...[file-root_with_body]` |
| migrate before validation (task plan applied before the todo half resolves) | 10: `test_a_failing_todo_edit_does_not_remove_a_legacy_task...`, 2 of the rejection ids (the edit ones), the 3 todo-directory ids, plus 4 pre-existing task-survives rows |
| reports after the closing line | 9: the 8 `tail_stays_last` ids and `reports_precede_every_directive_part` |

## Inconsistencies

None in the plan or the tests; no row conflicts. Notes:
- The directory refusal fires whenever a legacy file sits beside a directory at the root name, not only when the legacy file has a body (every action would otherwise fail on the directory: a move cannot land, a removal cannot unlink). The rows only pin the body case.
- A legacy path that is a symlink to a regular file counts (`is_file()` follows it, as the loader's `-f`); a move then renames the link. Unpinned, unchanged by this slice.
- `read_half` reads the root file with `errors="replace"` so a non-UTF-8 root file cannot raise on `keep`; `edited_body` still reads strictly, as before.
- The plan's "Step 3" docs will need: the git act is owed only to the call that moved or removed the file (settled in the red fixes), `compose_directives`'s new signature, and `FilePlan`'s `move`/`legacy` fields (CLAUDE.md's checkpoint bullet says "into `FilePlan`s" and describes the refusal printing alone).
