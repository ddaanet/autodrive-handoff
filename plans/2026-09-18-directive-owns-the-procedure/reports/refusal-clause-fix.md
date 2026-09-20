# Clause-file refusal: drop the false "Nothing has been written"

Date: 2026-09-20. Branch: `main` (no branch change, no commit, no push).

## The text

Old (`scripts/_checkpoint_lib.py`, `memory_directive`, the `clause is None`
branch — one string, serving both variants, key unset and file missing):

> gitlore memory has uncommitted changes, but this session cannot read the
> memory-approval wording: git config gitlore.memoryApprovalClauseFile is unset
> or its file is missing. gitlore pins that key at SessionStart — run
> /handoff:restart (or exit and relaunch with --resume, by hand), then retry.
> Nothing has been written and the memory changes are still pending.

New:

> gitlore memory has uncommitted changes, but this session cannot read the
> memory-approval wording: git config gitlore.memoryApprovalClauseFile is unset
> or its file is missing. gitlore pins that key at SessionStart — run
> /handoff:restart (or exit and relaunch with --resume, by hand), then retry.
> The memory changes are still pending.

The clause `Nothing has been written and ` is gone and the survivor is
re-capitalised to `The memory changes are still pending.` — the sentence the
brief said to keep, byte for byte. Nothing else changed: no dangling `and`, no
doubled space, no orphaned punctuation. Only one refusal variant exists in the
source (the key-unset and file-missing cases share the same string, which
`test_unset_and_missing_clause_reports_are_the_same` already pins), so there was
one site to fix.

## Files changed

- `scripts/_checkpoint_lib.py` — the two string-literal lines above (the only
  production change; 2 lines out).
- `tests/test_checkpoint.py` — two existing refusal rows gained assertions, no
  new test function:
  - `test_clause_file_unset_names_key_and_restart` (~line 2130): a three-line
    comment naming why the claim is false, then
    `assert "Nothing has been written" not in result.stdout` and
    `assert "The memory changes are still pending." in result.stdout`.
  - `test_clause_file_missing_same_key_and_restart_report` (~line 2160): the
    same two assertions, uncommented (the comment on the first row covers
    both).

No comment or docstring near the branch restated the dropped claim:
`_resolve_approval_clause`'s docstring says "the caller reports the
key-and-restart fallback on None", `memory_directive`'s says "tells the agent
to restart and retry", and `MemoryPart`'s describes the suppression rule. All
three stay true.

## Red phase

Tests changed first, run against unchanged `_checkpoint_lib.py`:

```
$ direnv exec . pytest tests/test_checkpoint.py \
    -k "clause_file_unset_names_key_and_restart or clause_file_missing_same_key"
>       assert "Nothing has been written" not in result.stdout
E       AssertionError: assert 'Nothing has been written' not in 'gitlore mem...l pending.\n'
E         'Nothing has been written' is contained here:
E           en retry. Nothing has been written and the memory changes are still pending.
E         ?           ++++++++++++++++++++++++
tests/test_checkpoint.py:2160: AssertionError
=========================== short test summary info ===========================
FAILED tests/test_checkpoint.py::test_clause_file_unset_names_key_and_restart
FAILED tests/test_checkpoint.py::test_clause_file_missing_same_key_and_restart_report
====================== 2 failed, 170 deselected in 1.44s =======================
```

A real red on the assertion — both rows reached the checkpoint, exited 0, and
failed only on the substring. After the source edit:
`172 passed` for `tests/test_checkpoint.py`.

## Verification

`cd /Users/david/code/handoff && direnv exec . just precommit` — green. Checks
that ran and passed, in order:

1. `jq . .claude-plugin/plugin.json` (manifest well-formed)
2. `jq . hooks/hooks.json`
3. `jq . .claude/settings.json`
4. `shellcheck -x .bin/* bin/* scripts/*.sh tests/*.bats`
5. `ruff check scripts tests` — All checks passed
6. `ruff format --check scripts tests`
7. `docformatter --check scripts/*.py tests/*.py`
8. `mypy`
9. `ty check` — All checks passed
10. `bats tests/hook-test.bats tests/checkpoint.bats` — 169 ok, 0 not ok
11. `pytest` — 262 passed, 11 deselected (the `live` TUI-conformance marker) in
    104s

## Every other occurrence of the phrase

`git grep "Nothing has been written"` over the whole repo, plus the wider
`--include` grep the brief specified:

- `plans/2026-09-18-directive-owns-the-procedure/reports/phase-1-corrector.md:62`
  — the review that *found* this defect. Not touched: `plans/*` is a write-time
  record.
- `.claude/handoff-todo.md:9` — the live scratch item describing this very fix.
  Not touched: that ledger belongs to the session that dispatched me, editing it
  would fire `write-stage.sh` and stage it, and dropping a finished item is the
  owning session's call. It is now stale and can be dropped.

`docs/design.md` (the refusal-prints-alone paragraph, ~line 643) and `CLAUDE.md`
(lines 623, 702) describe the refusal as "tells the agent to restart and retry"
and "(key unset or its file missing — restart and retry)". Neither quotes nor
asserts the dropped claim, so neither was edited. `README.md`, `skills/` and
`tests/*.bats` contain no occurrence. `docs/changelog/*` untouched by rule.

## Surprising

The working tree was reported clean in my dispatch snapshot but is not: a
concurrent session is mid-edit in it. `git status` shows modifications I did not
make — `docs/design.md` (−1060/+… : split into a new untracked `docs/design/`
node tree), `CLAUDE.md`, `README.md`, `scripts/checkpoint.py` (88 lines),
`scripts/_lib.sh`, `tests/test_tui_conformance.py`, a dirty `memory` submodule,
and a *staged* `.claude/handoff-todo.md`. My own diff is confined to
`scripts/_checkpoint_lib.py` (2 lines) and `tests/test_checkpoint.py` (+7). The
green `just precommit` above therefore certifies the tree *including* that other
session's in-flight work, not my change alone — worth knowing before anyone
reads it as a sign-off on a commit.

Also visible in `git status`: untracked `$HOME` dotfiles at the repo root
(`.bashrc`, `.gitconfig`, `.zshrc`, `.claude/agents`, …). That is a sandbox
view artifact, not repository content; nothing was written to them.
