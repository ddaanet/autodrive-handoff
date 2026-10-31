# Step 2 review: `a19ff32` (`♻️ split hook-test.bats by hook`)

Read-only review at the bar of `/code-review medium`. Everything was read from
the commit (`git show a19ff32:<path>`, `a19ff32^:<path>`) or from its export at
`/tmp/claude/line-cap-split/review-2/`. Probes ran in scratch copies under
`/tmp/claude/line-cap-split/review-2-scratch/`. Nothing in the repo was written
except this file.

Summary: the move is sound. All 289 blocks are verbatim, the suite is green,
shellcheck is clean, and every non-test line of the old file survives exactly
once. There are two findings proposed at medium: a helper comment cut away from
its helper, and two `CLAUDE.md` coverage claims (one lost, one contradicted).
The rest are low.

## Findings

### 1. A helper's comment stranded in the wrong file (proposed medium)

`tests/report-drive-failure-queued.bats:277-279` ends the file with this
comment, and no definition follows it:

```
# <directory> — an armed rename, and in <directory> a marker holding the id the
# input will carry: a directory the hook must not read, since a read through it
# would spare the file.
```

It documents `seed_marker_in_untrusted_dir()`. That function now opens
`tests/report-drive-failure-trust.bats:5` with no comment above it. In the
parent (`a19ff32^:tests/hook-test.bats:3161-3164`) the comment sat directly
above the function. The plan cut the trust file at line 3163 of `c2fff7c`,
which is the function line, so the comment above it (3160-3162) stayed with
the queued half.

Evidence: a comparison, for every anchor (`@test`, `name() {`, `name=`), of the
contiguous comment block directly above it, old file against the 17 new files
plus the helper. It finds exactly three differences: the two directives listed
under findings 3 and 4, and this one (`old: [3-line block]`, `new: [()]`).

This contradicts the plan's helper invariant ("A helper only one file uses stays
in that file, as does the comment above it") and the phase-A report's "Helpers
one file uses stay there with their comment". A reader of the queued file meets
a comment describing a `<directory>` argument that nothing in that file takes.
A reader of the trust file gets an undocumented helper. Fix: move the three
lines to sit above the function in the trust file.

### 2. `CLAUDE.md`'s per-file list loses one claim and contradicts another (proposed medium)

Both problems are in `a19ff32:CLAUDE.md`, in the `just hook-test` list.

**a. Lost.** The old paragraph (`a19ff32^:CLAUDE.md:678`) read "the
`HANDOFF_OWNER_LIVE_SECS` window, each gate mutation-checked, a malformed file
with none, session-root drift…". Nothing in the new list carries "a malformed
file with none" in either sense: swept with no lines offered, or (on another
reading) the one sweep row with no mutation check. `git show a19ff32:CLAUDE.md
| grep -n malformed` finds no hit in the hook-test list. The row is
`report-drive-failure (malformed sentinel: discarded and reported)`, and the
plan's line ranges put it in `tests/sentinel-lock.bats:114`. That file's bullet
(line 701) says only "covers the sentinel's lock in the sweep and the loaders".
So the row is named nowhere, and it sits in a file whose bullet excludes it.
"each gate mutation-checked" survives only through the closing sentence ("the
loader, guard and sweep gates are mutation-checked", line 739). Fix: give the
`sentinel-lock.bats` bullet (or the `report-drive-failure.bats` one, with a
pointer) the malformed-sentinel row.

**b. Contradicted.** The `tests/load-compact.bats` bullet (lines 685-689) says
the file has "its legacy paths, the same fallback rows as
`load-handoff-legacy.bats`". It does not. Every `load-compact` row is listed by
`grep -n '^@test "load-compact' tests/*.bats`. None of them reads the
worktree's legacy file (load-handoff-legacy has
`worktree cwd: reads the worktree's legacy task, not main's`). None covers the
age (load-handoff-legacy has three `(age)` rows). Nor does load-compact have
counterparts for the both-halves root shadowing, the headings-only root task or
the dangling legacy symlinks. The old paragraph attributed one list to
"`handoff_frame` and both loaders" collectively, which was already loose. The
new sentence pins it to a specific file, and the file contradicts it. A reader
would take `load-compact.sh`'s worktree-legacy path and age as pinned when no
row pins them. Fix: drop "the same fallback rows as `load-handoff-legacy.bats`"
and name what is there: each half alone and both from the old path, a root todo
or task shadowing, a headings-only root todo, a symlinked legacy todo, and
legacy files with no body.

Also in that bullet, "a dropped task-shadowed note among them" lifts a mutation
from the closing paragraph into a list of rows. That is phrasing, so low.

### 3. SC2317 in `lib-drive.bats`: the directive is right, the report's cause is wrong (proposed low)

The directive is `tests/lib-drive.bats:340`, `# shellcheck disable=SC2317   #
tail() below is called by handoff_drive_arm, in _lib.sh, which setup sources`.

- Probe, directive removed: shellcheck raises SC2317 three times on line 345,
  the `tail()` override (its three commands). This confirms the report.
- The report's cause is wrong. It says "Shellcheck used to reach `_lib.sh`
  through the old file's `setup`; it no longer does". Probes:
  - A 70-line file made of the parent's lines 1-56 (its `setup` sourcing
    `_lib.sh`) plus that one row raises the same three SC2317.
  - Re-adding each new file's body to setup + row, one at a time: only
    `lib-frame.bats` silences it.
  - Deleting `source "$stub/_lib.sh"` (inside `frame_with_stub_lib`, the
    SC1090-disabled source of a computed path) from that composite brings the
    three back.

  So the old file was clean because of `frame_with_stub_lib`'s second source,
  not because of `setup`. Adding a `tail -n1` call elsewhere does not silence
  it either. The phase-B section repeats the claim only by implication. The
  wrong sentence is in the phase-A section ("One edit outside a section").
- Narrower form: a `# shellcheck disable=SC2317` directly above `tail()` inside
  the `@test` also clears all three (probe: 0 hits). It edits the block,
  though, and breaks the verbatim invariant. The directive above the `@test`
  is scoped to that one test, and it is the narrowest form compatible with the
  plan. Keep it.
- The reason text says "in `_lib.sh`". Since step 1, `handoff_drive_arm` is
  defined in `scripts/_lib_drive.sh:278`, which `_lib.sh` sources. That is loose
  but not wrong in effect, so low.

### 4. SC2034 in `hook-helpers.bash` is file-wide and unlisted (proposed low)

The directive is `tests/hook-helpers.bash:14`, `# shellcheck disable=SC2034   #
read by the rows of the files that source this one`, directly above `setup()`.
The old file had no SC2034 directive.

- It sits before the first command, so shellcheck applies it to the whole
  file, not to `setup`. Probe: append an unused `local` inside a new function
  and an unused top-level assignment. Both pass silently.
- Probe, directive removed: SC2034 fires on nine top-level assignments only.
  These are `loaded_re` (line 93) and the eight
  `legacy_*`/`shadowed_*` notes (104-111), the shared variables other files
  read. Nothing in `setup` needs it.
- The project's own convention in `scripts/_lib.sh` is one directive per
  variable. Probe: nine per-variable directives give a clean run, and a dead
  local is then flagged again.
- The phase-B report says "No other new code appeared; no directive was
  added". This directive is missing from that list, against the dispatch's rule
  that each such directive is "added in the narrowest form that covers the
  hits, always with its reason, and listed in the step's report".
- Mitigating: step 3's `tests/checkpoint-helpers.bash:2` uses the same
  file-wide pattern. That one sits right after the shebang, where it reads as
  file-wide, and its reason names the variables. The orchestrator may prefer
  consistency with that sibling.

### 5. Smaller prose points (proposed low)

- `tests/inject-checkpoint-root.bats:127-128`: "(its rows are in
  tests/report-drive-failure-queued.bats, where the marker is a fixture)". The
  comparison rows are there. The marker-trust rows that also seed the marker
  are in `tests/report-drive-failure-trust.bats`, and so is the
  `prompt_id and its marker … no find forked` row in `-drift.bats`. It is true
  as far as it goes.
- `docs/design/driving-the-transition.md:370` is now 87 columns. This is
  wrapping only.
- `CLAUDE.md:688`: the "dropped task-shadowed note" phrasing (see 2b).

### Pre-existing, not introduced by this commit

`tests/report-drive-failure-trust.bats` ends on `# The pair: a marker that
answers … as the rows above do.` with no row after it. It was already orphaned
at `c2fff7c:3218-3220`, where the lock section header followed it directly.

## Verified, no finding

- `setup`/`teardown` are byte-identical to `a19ff32^` except for the removed
  `    load lock-helpers` line.
- `load lock-helpers` is now top-level in `tests/sentinel-lock.bats:4` and
  nowhere else among the 17. `lock-helpers.bash` holds only comments and three
  functions (`hold_drive_lock`, `wait_until_blocked`, `release_drive_lock`).
  None of them clashes with a function in `hook-helpers.bash` or
  `sentinel-lock.bats`. A top-level `load` runs in each test process before
  `setup`, which keeps the old order relative to the `_lib.sh` source. No other
  new file, and not `hook-helpers.bash`, calls a lock-helpers function or reads
  `HANDOFF_LOCK_BLOCKED_FILE`/`LOCK_HOLDER`. All 13 rows of `sentinel-lock.bats`
  pass. Bats 1.14.0.
- Non-test content, as a multiset of the parent's non-`@test` lines against
  the 17 files plus `hook-helpers.bash`:
  - Only in old: the 5-line file header (reworded into the helper's header) and
    `    load lock-helpers`.
  - Only in new: the helper's header lines, 16 extra `#!/usr/bin/env bats`, one
    `#!/usr/bin/env bash`, 17 source directives with 17 `source` lines, the
    top-level `load lock-helpers`, the SC2034 and SC2317 directives, and 18
    blank lines.

  Every helper, top-level variable and section comment otherwise survives
  exactly once.
- Helper placement:
  - Every function or variable in `hook-helpers.bash` is used by at least two of
    the new files, or by a shared helper (`noprompt_phrase` and `unloaded_msg`
    through `assert_unloaded_report`).
  - Every local helper is used only in its own file. `reader_stub` is named in
    `-trust.bats:43` only in a comment.
- Ports:
  - `frame_with_stub_status`/`frame_with_stub_lib` with their comment, in
    `lib-frame.bats`, are identical to `a19ff32^`, including step 1's
    `_lib_*.sh` copy.
  - The queued section's prose in `report-drive-failure-queued.bats` is
    identical to `a19ff32^`, including step 3's `tests/inject-checkpoint-root.bats`
    wording. The only delta is the shared helpers that moved out.
  - The `-I` row (`lib.bats:245-250`) carries step 1's `grep -h`.
- Shellcheck directives: all 17 files carry `# shellcheck source-path=SCRIPTDIR
  source=hook-helpers.bash` over `source "$BATS_TEST_DIRNAME/hook-helpers.bash"`.
  No `SC2154` disable remains in any of them. The only other directives are 3
  and 4 above.
- `CLAUDE.md`: the three `+` lines of `git diff c2fff7c a19ff32^ -- CLAUDE.md`
  missing verbatim from `a19ff32` are rewraps, and their content is present:
  - the `just hook-test` lead line is now lines 638-639;
  - "a copy of `_lib.sh` and its parts sourced beside a stub library" is in the
    `lib-frame.bats` bullet;
  - "the `handoff_drive_read` shape matrix" is in the `lib-drive.bats` bullet.

  Every other `+` line is present. The bullets other than those in finding 2
  match their files: lib, lib-frame, lib-frame-legacy, lib-drive, load-handoff,
  load-handoff-legacy, load-handoff-cwd, write-guard, session-pointer,
  sentinel-reader, report-drive-failure, -other-session, -queued, -trust and
  -drift. The lock sentence ("the sweep's and the loaders' rows are in
  `tests/sentinel-lock.bats`") is true.
- `tests/bats-tooling-and-checklist.md:125-127`: true of `find_witness_stub`
  (`-drift.bats:144-151`), which writes a per-test script under
  `$BATS_TEST_TMPDIR/find-witness`. The script runs `: > find-ran`, then
  `exec <real find> "$@"`. It is `chmod +x` and on `PATH` for the one call only
  (a prefix assignment).
- Path swaps:
  - `the-write-path.md:243`: every spelling named is a `write-guard.bats` row.
  - `sentinel-lock.md:124-126`: the contention rows are at `sentinel-lock.bats`
    63/97/177/191/222/234.
  - `driving-the-transition.md:370`: correct.
  - The `test_drive_lock.py` docstring: correct.
  - `drive-take.bats:24`: `make_worktree` is in `hook-helpers.bash`.
- Stale mentions: `git grep -n -e 'hook-test' -e 'checkpoint\.bats' a19ff32 --
  . ':!plans' ':!docs/changelog' ':!TASK.md' ':!TODO.md'` finds only:
  - the recipe name (`CLAUDE.md:638`, `justfile:102`);
  - the `sess-hook-test` session id (`drive-take.bats`, `hook-helpers.bash:39,174`).

## Checks re-run

- Verbatim checker, from `/Users/david/code/handoff`:
  `python3 -I /tmp/claude/line-cap-split/verbatim-check.py
  a19ff32^:tests/hook-test.bats -- a19ff32:tests/<each of the 17>.bats`. It
  printed:

  ```
  blocks: old 289, new 289
  verbatim: OK
  ```

  The exit code was 0. The parent is `a19ff32^`, so step 1's `-I` row ported.
- `@test` counts: 289 in the old file and 289 across the 17 new ones.
  `drive-take.bats` 21 → 21 and `inject-checkpoint-root.bats` 17 → 17.
- `bats --jobs 4` over the 17 files in the export: `1..289`, 289 `ok`, 0
  `not ok`, rc 0.
- The justfile's shellcheck line, run in the export:
  `shellcheck -x bin/* scripts/*.sh tests/*.bats tests/*.bash` gave rc 0 and
  no output (ShellCheck 0.10.0).
- `pytest --collect-only -q` in the export: `520/523 tests collected (3
  deselected)`.
- On `tests/test_drive_lock.py`, `ruff check`, `ruff format --check` and
  `docformatter --check` are all clean.
- The plan's Verification scan over `git ls-tree a19ff32` lists only
  `1563 tests/test_checkpoint_legacy.py` and `958 CLAUDE.md`, the two exempt
  files.
- Line counts (`git show a19ff32:<path> | wc -l`):

  | Lines | File |
  | ---: | --- |
  | 958 | `CLAUDE.md` (exempt) |
  | 373 | `docs/design/driving-the-transition.md` |
  | 128 | `docs/design/sentinel-lock.md` |
  | 262 | `docs/design/the-write-path.md` |
  | 294 | `tests/bats-tooling-and-checklist.md` |
  | 282 | `tests/drive-take.bats` |
  | 251 | `tests/hook-helpers.bash` |
  | deleted | `tests/hook-test.bats` |
  | 289 | `tests/inject-checkpoint-root.bats` |
  | 352 | `tests/lib-drive.bats` |
  | 216 | `tests/lib-frame-legacy.bats` |
  | 258 | `tests/lib-frame.bats` |
  | 250 | `tests/lib.bats` |
  | 248 | `tests/load-compact.bats` |
  | 153 | `tests/load-handoff-cwd.bats` |
  | 347 | `tests/load-handoff-legacy.bats` |
  | 208 | `tests/load-handoff.bats` |
  | 272 | `tests/report-drive-failure-drift.bats` |
  | 116 | `tests/report-drive-failure-other-session.bats` |
  | 279 | `tests/report-drive-failure-queued.bats` |
  | 62 | `tests/report-drive-failure-trust.bats` |
  | 322 | `tests/report-drive-failure.bats` |
  | 244 | `tests/sentinel-lock.bats` |
  | 174 | `tests/sentinel-reader.bats` |
  | 122 | `tests/session-pointer.bats` |
  | 280 | `tests/test_drive_lock.py` |
  | 171 | `tests/write-guard.bats` |

  All are under 400 except the exempt `CLAUDE.md`. Fixing finding 1 moves 3
  lines from the queued file (279) to the trust file (62), so both stay under
  the cap.
