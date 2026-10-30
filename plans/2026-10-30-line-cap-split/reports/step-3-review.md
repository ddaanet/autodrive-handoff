# Step 3 review: `3b884dd` (`♻️ split checkpoint.bats by subject`)

Everything was read from the commit (`git show 3b884dd:<path>`,
`3b884dd^:<path>`) and run in an export at
`/tmp/claude/line-cap-split/review-3/`. Probes ran in scratch copies under
`review-3/scratch/p1`–`p5`.

Verdict: the move is clean. Every `@test` block is verbatim, the counts hold,
every non-test line survives once and in order, and the gate's shellcheck line,
the three bats files and pytest collection all pass at the commit. One finding
is proposed at medium (stale "load" wording in the helper). The rest are low.

## Findings

### 1. The helper says it is loaded, but the files source it (proposed: medium)

`tests/checkpoint-helpers.bash` line 2: `# shellcheck disable=SC2034   # SHIM,
APPROVED and INJECT_ROOT are read by the files that load this`. Lines 5–6: `A
bats file loads this at its top, which gives it the shared `setup` and
`make_repo``.

The three files do not `load` it. They `source "$BATS_TEST_DIRNAME/checkpoint-helpers.bash"`
under `# shellcheck source-path=SCRIPTDIR source=checkpoint-helpers.bash`,
following dispatch.md's "A shared bats helper is sourced, not `load`ed". The
wording is left over from phase A, which used `load` (step-3.md, line 21). In a
bats file "loads" names the `load` builtin.

Evidence that following the text breaks the gate: probe p5 replaced the
directive and `source` lines with `load checkpoint-helpers` in
`validate-plugin.bats`. bats still passes, but `shellcheck -x` gives
`tests/validate-plugin.bats:61:59: warning: repo_root is referenced but not
assigned. [SC2154]`, rc 1. The same change in `inject-checkpoint-root.bats`
raises SC2154 too. So someone adding a fourth file as the header describes gets
a red `check-plugin`.

Fix: change "load"/"loads" to "source"/"sources" on lines 2 and 5. The SC2034
directive itself is needed and its reason is otherwise true (below).

### 2. The file-wide SC2119 disable in `bin-commands.bats` is not the narrowest form (proposed: low, but see the note)

`tests/bin-commands.bats` line 3: `# shellcheck disable=SC2119   # make_repo
(checkpoint-helpers.bash) takes an optional path; no row here passes one`.

What checks out:
- `make_repo` takes an optional path: `local repo="${1:-$BATS_TEST_TMPDIR/repo}"`
  (helper line 36).
- No row in `bin-commands.bats` passes one: all 16 calls are `$(make_repo)`.
  Two rows in `inject-checkpoint-root.bats` pass a path (lines 66 and 78), which
  is why that file raises none.
- The original file never saw SC2119. `shellcheck -x` on
  `3b884dd^:tests/checkpoint.bats` (exported to `scratch/parent`) gives rc 0.
  With its SC2154 line removed, the only hit is `stderr` at line 521.
- Probe p2 removed line 3 and got exactly 16 SC2119 notes, one per call (lines
  41, 64, 81, … 279 in the commit's numbering).

A narrower form exists and is probe-verified (p3). Put `# shellcheck
disable=SC2120` directly above `make_repo() {` in `checkpoint-helpers.bash` and
drop line 3 of `bin-commands.bats`. Then all 16 SC2119 notes are gone, the
helper alone is clean, and the gate's exact line (`shellcheck -x bin/*
scripts/*.sh tests/*.bats tests/*.bash`) gives rc 0.

That directive is scoped to the one function whose argument is optional. The
current one covers every function call in `bin-commands.bats`, including rows
added later. The trade: the narrower directive sits in the shared helper, so it
also covers any future caller of `make_repo` in any file, which is the intent
("the path is optional").

Note: dispatch.md's "Decided during the run" says such a directive is "added in
the narrowest form that covers the hits". The same bullet also records the
file-wide disable as what step 3 did. The commit therefore contradicts the
rule, though not the record. Nothing fails either way, so I propose low. The
orchestrator decides whether the rule is binding.

### 3. The SC2119 count is 16, not 17 (proposed: low)

`reports/step-3.md` line 57 and dispatch.md's "Decided during the run" both say
"17 argument-less `make_repo` calls". `grep -n 'make_repo' tests/bin-commands.bats`
gives 16 `repo="$(make_repo)"` lines. The 17th match is the harness row's
`@test` title. Probe p2 gives 16 SC2119. This is a correction to the plan
records, not to code.

### 4. A conftest docstring splits `bin-commands.bats` across a line break (proposed: low)

`tests/conftest.py` lines 8–9: `… stays tested in tests/inject-checkpoint-root.bats and tests/bin-` / `commands.bats; …`.
docformatter (`wrap-descriptions = 80`, hyphen breaking) splits the name, so
`git grep -n 'bin-commands\.bats' 3b884dd` misses this mention. The grep finds
eight files, but not `conftest.py`'s docstring. The text is true today.

The cost is in the future: the plan's reference rule ("the references are found
by grepping the old names") would leave this mention stale if
`bin-commands.bats` is ever renamed. step-3.md says the docstring was reworded
to avoid exactly this split for `inject-checkpoint-root.sh`. Reword it once
more so neither name ends a line.

### 5. The `validate-plugin` file and the helper header call the validate rows a neighbor of the checkpoint channel (proposed: low)

`tests/validate-plugin.bats` lines 7–8 say "The rest of the bash-side neighbors
of the checkpoint channel are in …". `tests/checkpoint-helpers.bash` lines 3–5
say "the bats files that test the bash-side neighbors of the checkpoint channel
…: validate-plugin.bats, …".

The `validate-plugin` rows test a justfile recipe, not something around the
checkpoint. The old header did not list them at all. CLAUDE.md line 712, "Three
files cover what stayed bash around the checkpoint", has the same grouping. This
is phrasing only, and no action follows from it.

### 6. The `docs/design/` edit was made without loading `craft:design-doc-writing` (proposed: low)

step-3.md line 33 says the skill was not loaded for the one-word path swap in
`docs/design/sentinel-lock.md`. The plan's invariants say to load it before
touching `docs/design/`. The edited sentence is true (below), so this is a
process note only.

## Not findings: checked and true

- **Non-test content.** Every non-`@test` line of the old file survives exactly
  once, in the file that uses it. A multiset diff of the non-test lines, old
  file against the three new files plus the helper, differs only in header
  lines. An ordered diff of each chunk is identical, ignoring the blank line
  that ends each old section:
  - old 19–45 to helper 14–40 (`setup`, `make_repo` and its comment);
  - old 46–77 to `bin-commands.bats` 19–50 (`export_decoy_git_env`,
    `decoy_snapshot` and the harness row);
  - old 78–184 to `validate-plugin.bats` 13–119;
  - old 186–460 to `inject-checkpoint-root.bats` 14–288 (including the
    top-level `prompt_marker=` and `marker_holds`);
  - old 462–695 to `bin-commands.bats` 51–284.

  Each single-use helper is defined, once, in the only file that calls it. The
  file holds no `teardown`, and no file other than the helper defines `setup`.
- **The old header.** Its content went to one header per file, plus the
  helper's header for the `test_checkpoint_*.py` and 2026-07-27 pointers. The
  one clause dropped is "and docs/changelog/2026-08-10-python-split.md for what
  moved". The pointer itself survives in the helper's first paragraph and in
  the inject and bin headers. Nothing material is lost.
- **SC2154 in `bin-commands.bats`.** The reason is true. Probe p1 removed line
  2, and the only hit is `stderr is referenced but not assigned. [SC2154]`
  (its first use, line 110 after the deletion). `$stderr` is set by
  `run --separate-stderr`, which appears on four lines of that file, and read
  on ten lines across nine rows. A directive per row would mean nine
  directives, and one per line would change `@test` blocks. The two other files have no SC2154 disable
  and lint clean.
- **SC2034 in the helper.** It is needed. Probe p4 removed it, and the helper
  alone gives SC2034 for `SHIM`, `APPROVED` and `INJECT_ROOT`, rc 1. The reason
  is true except for the "load" wording (finding 1): `SHIM` and `APPROVED` are
  read in `bin-commands.bats`, `INJECT_ROOT` in `inject-checkpoint-root.bats`.
- **Shellcheck follows the sourced helper.** With `source`, the files that use
  `$repo_root` lint clean without a disable. With `load` they raise SC2154
  (p5). Shellcheck also follows on into `_lib.sh`: dropping `disable=SC1091`
  from the helper's `source _lib.sh` directive still lints clean from the repo
  root and from another cwd.
- **`bats_require_minimum_version 1.5.0`** is needed only in
  `bin-commands.bats`. That file is the only one using `run` flags
  (`--separate-stderr` on lines 60, 186 and 196, `--separate-stderr -2` on line
  281). `grep -nE '\brun +-'` finds nothing in the other two. The bats run
  printed no BW warnings.
- **The justfile.** `tests/*.bats` at 3b884dd is `bin-commands`, `drive-take`,
  `hook-test`, `inject-checkpoint-root` and `validate-plugin`, for
  17 + 21 + 289 + 17 + 8 = 352 `@test`. `tests/*.bash` is `checkpoint-helpers`,
  `lock-helpers` and `probe-helpers`. `run-bats.sh` takes any bats arguments.
  The CLAUDE.md sentences for `check-plugin` (line 580), `check-code` (line 582)
  and `just hook-test` (line 638) match the recipes as written.
- **Prose edits.**
  - CLAUDE.md lines 712–736: each file's coverage clause matches its rows. The
    harness row is in `bin-commands.bats`, and nothing from the old paragraph
    is dropped. Line 874: the bare-name row is in `bin-commands.bats`.
  - `sentinel-lock.md` line 124: the approval's ordering row and both
    contention rows are in `bin-commands.bats`, and the
    `test_checkpoint_readback.py` mention from step 4 is kept.
  - `test_drive_lock.py` docstring: true, readback mention kept.
  - `conftest.py` docstring (apart from finding 4) and the `task_clear` comment
    (`handoff_payload()` is in `bin-commands.bats`): true.
  - `probe-helpers.bash` header: the shim row is the one that uses
    `make_gitlore_repo` with `dirty_memory`.
  - `hook-test.bats` lines 2831–2837: the prompt-marker writer rows are in
    `inject-checkpoint-root.bats`.
- **Stale mentions.** `git grep -n 'checkpoint\.bats' 3b884dd -- . ':!plans'
  ':!docs/changelog' ':!TASK.md' ':!TODO.md'` finds nothing (rc 1). Only
  `TASK.md` line 3 names it (the session frame, excluded).

## Out of scope: TODO candidates, pre-existing (proposed: low)

- `tests/bats-tooling-and-checklist.md` around line 79 says shellcheck 0.10.0
  "does **not** fire SC2154 for `$status`/`$output`/`$lines`/`$stderr`
  (verified)". It does fire for `$stderr`: SC2154 on the original file at line
  521 and on `bin-commands.bats` (p1), with shellcheck 0.10.0. The same doc
  around line 92 prescribes `# shellcheck source=tests/helpers.bash` above
  `load helpers`, the pattern dispatch.md ruled out because shellcheck does not
  follow `load`. Both sentences come from `bats-best-practices.md` before step
  5 and are not this commit's, but they prescribe the opposite of what this
  commit does.
- The helper's `setup` comment above `source _lib.sh` reads "For asserting
  that what handoff-approved writes is what a loader will accept, and for
  handoff_drive_read itself in the tests below". No row in the three files
  calls anything from `_lib.sh` (`handoff_drive*` and `DRIVE_*` find nothing),
  and "the tests below" now points at nothing in a helper. The executor already
  flagged it, and it moved verbatim as the invariant requires.

## Cross-step note for the orchestrator (not a finding against this commit)

This commit fixed the `tests/checkpoint.bats` mention inside `hook-test.bats`
(the queued-prompt comment, lines 2831–2837). Step 2's patch was cut from
`c2fff7c`, so the new file it creates for the queued-prompt section carries the
old comment, "(its rows are in tests/checkpoint.bats)". Its `--3way` apply will
also meet a delete/modify conflict on `hook-test.bats`.

Step 2's phase-B grep looks for its own old names, not `checkpoint.bats`. Once
step 2 lands, re-run `git grep -n 'checkpoint\.bats' HEAD -- . ':!plans'
':!docs/changelog' ':!TASK.md' ':!TODO.md'`. The verbatim checker cannot see
this, because it is a comment.

## Checks re-run

Verbatim checker (from `/Users/david/code/handoff`):

```
$ python3 -I /tmp/claude/line-cap-split/verbatim-check.py 3b884dd^:tests/checkpoint.bats -- 3b884dd:tests/validate-plugin.bats 3b884dd:tests/inject-checkpoint-root.bats 3b884dd:tests/bin-commands.bats
blocks: old 42, new 42
verbatim: OK            (rc 0)
$ python3 -I /tmp/claude/line-cap-split/verbatim-check.py 3b884dd^:tests/hook-test.bats -- 3b884dd:tests/hook-test.bats
blocks: old 289, new 289
verbatim: OK            (rc 0)
```

`@test` counts at 3b884dd: `bin-commands` 17, `drive-take` 21, `hook-test` 289,
`inject-checkpoint-root` 17, `validate-plugin` 8. The three new files give 42,
the old `checkpoint.bats` had 42, and `tests/*.bats` totals 352.

In the export, with the venv exported:
- `bats tests/validate-plugin.bats tests/inject-checkpoint-root.bats
  tests/bin-commands.bats`: `1..42`, 42 `ok`, 0 `not ok`, no BW warnings
  (bats 1.14.0).
- `shellcheck -x bin/* scripts/*.sh tests/*.bats tests/*.bash` (the justfile
  line as written): no output, rc 0 (shellcheck 0.10.0).
- `pytest --collect-only -q | tail -1`: `520/523 tests collected (3
  deselected) in 1.05s`.
- `docformatter --check tests/conftest.py tests/test_drive_lock.py`: rc 0.
  `ruff check` and `ruff format --check` on the same two files: `All checks
  passed!` and `2 files already formatted`.

Probes (scratch copies of the export):
- p1, line 2 of `bin-commands.bats` removed: one SC2154 (`stderr`).
- p2, line 3 removed: 16 SC2119.
- p3, line 3 removed and `disable=SC2120` added above `make_repo()`: clean,
  and the gate line gives rc 0.
- p4, the helper's SC2034 removed: 3 SC2034 when the helper is linted alone,
  clean through the bats files.
- p5, `load` in place of `source`: SC2154 `repo_root`. Also, `disable=SC1091`
  dropped from the `_lib.sh` source: still clean.
- Parent tree: the original `checkpoint.bats` is clean, and without its SC2154
  disable it gives one SC2154 (`stderr`, line 521).

Line counts (`git show 3b884dd:<path> | wc -l`):

| File | Lines | |
| --- | --- | --- |
| `tests/validate-plugin.bats` | 119 | new |
| `tests/inject-checkpoint-root.bats` | 288 | new |
| `tests/bin-commands.bats` | 284 | new |
| `tests/checkpoint-helpers.bash` | 40 | new |
| `tests/conftest.py` | 293 | edited |
| `tests/probe-helpers.bash` | 47 | edited |
| `tests/test_drive_lock.py` | 280 | edited |
| `docs/design/sentinel-lock.md` | 128 | edited |
| `justfile` | 114 | edited |
| `CLAUDE.md` | 914 | edited; exempt per plan.md (own `TODO.md` item) |
| `tests/hook-test.bats` | 3986 | edited (one comment, 3985 at `3b884dd^`); over the cap because it is step 2's file, still unsplit at this commit. The edit is the reference fix the invariants require, so the cap does not apply here. |
