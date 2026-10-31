# Branch review: `c2fff7c...1304efb` (`line-cap-split` against `dev`)

Read-only, at the bar of `/code-review medium`. Everything was read through
`git show`/`git grep` at the two pinned shas, or from the export at
`/tmp/claude/line-cap-split/branch-review/tree` (`git archive 1304efb`). Probes
ran in `/tmp/claude/line-cap-split/branch-review/work/`. Nothing in the
repository was written.

**Verdict: no high finding, and one proposed medium (F1).** F1 is a guideline
doc whose sourcing advice the tip now contradicts. Nothing blocks the merge
mechanically: 331 bats blocks and 51 pytest blocks are verbatim, with the one
intended `-I` change. All 352 bats rows and 520 pytest rows pass. shellcheck,
ruff, mypy, ty, docformatter and check-refs are clean. The line-cap scan lists
only the two exempt files, and no stale name is left.

## Findings

### F1 (proposed medium): `tests/bats-tooling-and-checklist.md` §7 prescribes the sourcing form the tip rules out, and quotes a gate command that fails

`tests/bats-tooling-and-checklist.md:89-94` at `1304efb`:

````text
- For a sourced helper or script-under-test, add a source directive so
  `shellcheck -x` follows it:

```bash
# shellcheck source=tests/helpers.bash
load helpers
```
````

The tip prescribes the opposite in three places:

- `CLAUDE.md:640-642`: "each sourcing `tests/hook-helpers.bash` under a
  `# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash` line";
- `tests/hook-helpers.bash:4-6`;
- `tests/checkpoint-helpers.bash:5-8`.

`dispatch.md` ("A shared bats helper is sourced, not `load`ed") records the
reason: shellcheck does not follow `load`.

**Probe, with the doc's exact form.** In a copy of the tip, lines 2-3 of
`tests/validate-plugin.bats` were replaced with
`# shellcheck source=tests/checkpoint-helpers.bash` and
`load checkpoint-helpers`. Then:

```text
$ shellcheck -x tests/validate-plugin.bats
In tests/validate-plugin.bats line 62:
        PWD="${VALIDATE_CWD:-$root}" run just --justfile "$repo_root/justfile" ...
                                                          ^--------^ SC2154 (warning): repo_root is referenced but not assigned.
rc=1
```

The result was the same with `source=checkpoint-helpers.bash`. So a reader who
adds the next helper-sharing bats file by following §7 gets a red
`check-plugin`. That is the same failure as step 3's medium finding 1 (the
helper header said "load"), which was fixed in `4db689d`.

**The same section quotes the gate wrongly.** `:74-75` reads "(the precommit
does exactly this: `shellcheck -x scripts/*.sh tests/*.sh tests/*.bats`)". The
gate is `justfile:43`, `shellcheck -x bin/* scripts/*.sh tests/*.bats
tests/*.bash`. Run in the export, the quoted command fails:

```text
$ shellcheck -x scripts/*.sh tests/*.sh tests/*.bats
tests/*.sh: tests/*.sh: openBinaryFile: does not exist (No such file or directory)
rc=2
```

The quote also leaves out `tests/*.bash`, which this branch added to the gate
so that the new helpers are linted.

**Why I raise it again.** Step 3's review listed the `load` sentence under
"Out of scope: TODO candidates, pre-existing (proposed: low)". The text does
predate the branch: `c2fff7c:tests/bats-best-practices.md:355-356` and
`:373-374`. But at `c2fff7c` nothing in the repository prescribed the other
form. The contradiction comes from `a19ff32`'s `CLAUDE.md` and
`hook-helpers.bash` text, together with `4db689d`. Both landed after step 3's
review, so this is the whole-tip gap that no per-step review could see. The
item is also not in `TODO.md` at `1304efb`. Its memory bullet records the
shellcheck fact for memory, not a fix to the doc. The `$stderr` SC2154 claim at
`:79`, which `bin-commands.bats:2` contradicts, was already declined at step 3.
It is listed here only as a third stale sentence in the same section.

**Fix shape** (doc drift, no re-review per the shared rule): replace the
`load` example with the `source-path=SCRIPTDIR source=<helper>` +
`source "$BATS_TEST_DIRNAME/<helper>"` form, and correct the quoted gate line
or drop it.

### F2 (proposed low): rows that no `CLAUDE.md` bullet names, after the mechanical cut

These are named nowhere in the Testing list at `1304efb`. No bullet claims they
are elsewhere, so the list is incomplete but not contradicted.

- `tests/sentinel-reader.bats:138`, `:150`, `:165`: `pending file: left
  alone`, `held file owned by this session: left alone`, and `held file of
  another session, no transcript_path: left untouched`. The bullet at
  `CLAUDE.md:699-701` names only the reader's helper failing and the symlink.
  The last of the three rows is a held-by-another-session row. Its siblings are
  in `report-drive-failure-other-session.bats:76/89/99`, whose bullet
  (`CLAUDE.md:713-714`) a reader would take as the whole set.
- `tests/lib.bats:245`: the `-I` row (`every python3 -c in the hooks and bin
  runs isolated`). The bullet at `CLAUDE.md:645-649` does not name it.
- `tests/load-handoff-legacy.bats:317`, `:330`: `size formatting: KiB
  threshold` and `worktree cwd: reads worktree task, not main`. Neither is a
  legacy row, and neither bullet names them.

The old single paragraph did not name these rows either. They are low because
nothing a reader acts on is false.

### F3 (proposed low, process): the amended `1304efb` commits the 2026-10-31 session frame

`1304efb` was amended at `2026-10-31 01:59 +0100` (its author date is
`2026-10-30 23:15`). It carries `TASK.md`, which describes this session's
release thread ("check out `main`, merge `dev`, … First action: dispatch the
reviewer"), and `TODO.md` edits. The message names the plan records and the
memory gitlink but not the frame. In this repo the two files are committed as
a matter of course, so the commit itself is not wrong. But when
`line-cap-split` is merged into `dev` after 0.19.0, it will meet whatever frame
`dev`/`main` carry by then, and that merge has to resolve `TASK.md`/`TODO.md`
by hand.

## The two commits with no re-review

- **`8466357`.** The moved comment is byte-identical to the original:
  `diff <(git show c2fff7c:tests/hook-test.bats | sed -n 3158,3166p)
  <(git show 1304efb:tests/report-drive-failure-trust.bats | sed -n 4,12p)`
  differs only in the leading `}` and a trailing blank line, which are the
  window edges. The comment occurs once at the tip
  (`report-drive-failure-trust.bats:5`), directly above
  `seed_marker_in_untrusted_dir()`. The queued file now ends `}`. Both
  `CLAUDE.md` bullets are true of the tip:
  - `load-compact.bats`: "each half alone and both from the old path" is rows
    68, 94 and 106; "the root todo or task shadowing" is 118 and 148; "a
    headings-only root todo not shadowing it" is 133; "a symlinked legacy
    todo" is 81; "legacy files with no body" is 163.
  - `sentinel-lock.bats:114` is the malformed row. It asserts the file is gone
    and that there is no `Type in order`.
- **`4db689d`.** The header's "Each `source`s this at its top, under the line
  `# shellcheck source-path=SCRIPTDIR source=checkpoint-helpers.bash`" is true
  of all three files: `validate-plugin.bats:2-3`,
  `inject-checkpoint-root.bats:2-3` and `bin-commands.bats:4-5`. SC2034's
  reason ("read by the files that source this") holds.

## Checked and true, not findings

- **The `-I` row change is the intended one.** It went from `run grep -c
  'python3 -I -c' scripts/_lib.sh; [ "$output" -ge 1 ]` to `run grep -h
  'python3 -I -c' scripts/_lib.sh scripts/_lib_*.sh; [ "$status" -eq 0 ]`,
  which is plan step 1's second fixture change: at least one hit across the
  library files. The negative half, `scripts/*.sh bin/*`, already covers the
  parts.
- **Non-test content, whole tip.** I compared the multiset of non-`@test` lines
  of `c2fff7c:{hook-test,checkpoint}.bats` against the 20 new files plus the
  two `*-helpers.bash`. The only lines found in one side alone are:
  - the reworded file headers;
  - the reflowed queued-prompt and prompt-marker comments, now pointing at
    `inject-checkpoint-root.bats` and `report-drive-failure-queued.bats`;
  - step 1's stub-lib `cp` and its comment;
  - `load lock-helpers`, which left `setup` for the top level of
    `sentinel-lock.bats:4`;
  - the 20 directive and `source` pairs, the shebangs, and the four shellcheck
    disables (SC2034 ×2, SC2119 and SC2317), all already reviewed.

  Every `# --- … ---` section header survives once.
- **Helper placement.** Every function or variable in `hook-helpers.bash` is
  used by two or more files. The two exceptions, `noprompt_phrase` and
  `unloaded_msg`, are reached through `assert_unloaded_report`, which two files
  use. `make_repo` in `checkpoint-helpers.bash` is used by `bin-commands.bats`
  and `inject-checkpoint-root.bats`. No local helper of a `.bats` file is
  called from another file (`reader_stub` appears in `-trust.bats` only in a
  comment). The duplicates `make_worktree` (`drive-take.bats`/`hook-helpers`),
  `marker_holds` and `prompt_marker` (`inject-checkpoint-root.bats`/
  `hook-helpers`) were already duplicated across the original files at
  `c2fff7c`.
- **`setup`/`teardown`.** These are defined only in `hook-helpers.bash`,
  `checkpoint-helpers.bash` and `drive-take.bats`, and no file overrides
  another's. `bats_require_minimum_version 1.5.0` is in `bin-commands.bats`,
  the only file that uses `run --separate-stderr`. The bats run printed no BW
  warnings.
- **References.** Every `tests/<file>` and bare `*.bats`/`*.bash` name in
  `CLAUDE.md`, `README.md`, `docs/design*`, `skills`, `scripts`, `bin`,
  `justfile` and `tests` exists at the tip. The only misses are generic
  examples (`foo.bats`, `name.bash`, `tests/helpers.bash`), and the
  `tests/bin-` + `commands.bats` docformatter break in `conftest.py:8-9`, which
  step 3 already declined. Every `_lib.sh` mention left in docs and code names
  something that stayed in `_lib.sh`. Each of `driving-the-transition.md:370`,
  `queued-prompts.md:57`, `scoping.md:92`, `sentinel-lock.md:124-126`,
  `the-write-path.md:11` and `:243`, and the docstrings of
  `test_drive_lock.py`, `conftest.py` and `probe-helpers.bash` is true of the
  tip.
- **`CLAUDE.md` file lists.** All 21 `tests/*.bats` and all 17 `tests/test_*.py`
  files at the tip are listed, and every listed file exists. Every clause I
  checked against `@test`/`def test_` names is in the file its bullet names,
  apart from what F2 lists as unnamed.
- **Gate wiring.** `justfile:43` and `:55`, and `hook-test` at `:103`, glob
  `tests/*.bats`/`tests/*.bash`. `CLAUDE.md:579-583` and `:638` match them, and
  `plugin-dev/run-bats.sh tests/*.bats` runs all 21 files.

## Re-run checks

Verbatim checker, run from `/Users/david/code/handoff`:

```text
$ python3 -I /tmp/claude/line-cap-split/verbatim-check.py c2fff7c:tests/hook-test.bats c2fff7c:tests/checkpoint.bats -- <the 20 added .bats at 1304efb>
blocks: old 331, new 331
CHANGED: @test "every python3 -c in the hooks and bin runs isolated (-I)" {
-    run grep -c 'python3 -I -c' scripts/_lib.sh
-    [ "$output" -ge 1 ]
+    run grep -h 'python3 -I -c' scripts/_lib.sh scripts/_lib_*.sh
+    [ "$status" -eq 0 ]
verbatim: 1 problem(s)          (rc 1, the intended change only)

$ … c2fff7c:tests/test_checkpoint_hold.py -- 1304efb:tests/test_checkpoint_hold.py 1304efb:tests/test_checkpoint_readback.py
blocks: old 25, new 25 / verbatim: OK
$ … c2fff7c:tests/test_checkpoint_transition.py -- 1304efb:tests/test_checkpoint_transition.py 1304efb:tests/test_checkpoint_sentinel.py
blocks: old 26, new 26 / verbatim: OK
$ … (both pairs at once)
blocks: old 51, new 51 / verbatim: OK
$ … drive-take.bats 21/21 OK; test_drive_lock.py 13/13 OK
```

In the export (bats 1.14.0, ShellCheck 0.10.0, venv exported):

```text
pytest --collect-only -q      520/523 tests collected (3 deselected)
pytest -q                     520 passed, 3 deselected in 85.39s
bats --jobs 4 tests/*.bats    1..352, 352 ok, 0 not ok, rc 0, no BW warnings
plugin-dev/run-bats.sh tests/*.bats   bats: 352 passed, 0 failed
shellcheck -x tests/*.bats tests/*.bash bin/* scripts/*.sh   no output, rc 0
ruff check scripts tests      All checks passed!
ruff format --check           26 files already formatted
docformatter --check          rc 0
mypy / ty check               rc 0 / All checks passed!
check-refs.sh (fresh git init of the tip)   resolves: 260 references in 27 files … rc 0
```

`@test` counts at the tip are 352 across 21 files: 331 from the two split
files plus `drive-take.bats`'s 21.

Line-cap scan, the plan's Verification over `git ls-tree -r 1304efb`:

```text
  1563 tests/test_checkpoint_legacy.py
   959 CLAUDE.md
```

Files the branch creates or edits, outside `plans/` and `docs/changelog/`:
`CLAUDE.md` has 959 lines (exempt). Every other file is at most 373 lines. The
largest are:

- `docs/design/driving-the-transition.md` 373;
- `tests/lib-drive.bats` 352;
- `tests/load-handoff-legacy.bats` 347;
- `tests/bats-best-practices.md` 334;
- `tests/report-drive-failure.bats` 322.

`memory` is a gitlink.

Stale-name grep:

```text
$ git grep -n -e hook-test.bats -e checkpoint.bats 1304efb -- . ':!plans' ':!docs/changelog' ':!TASK.md' ':!TODO.md'
(no output, rc 1)
```

A broader `hook-test` grep finds only the recipe name (`CLAUDE.md:638`,
`justfile:102`) and the `sess-hook-test` session id.
