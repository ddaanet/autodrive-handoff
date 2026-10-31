# Step 1 report: `_lib.sh` into three parts (phase A)

Copy: `/tmp/claude/line-cap-split/step-1/repo` (tree of `c2fff7c`, tag `base`).
Nothing committed. Phase B not started.

## What moved where

`scripts/_lib.sh` (689 lines) is now 207 lines. It keeps `HANDOFF_LIB_DIR`, the
path constants, `HANDOFF_POINTER_DIR`, `handoff_owner_live`,
`handoff_lock_take`, `handoff_root_read`, `HANDOFF_UNRESOLVED_MSG` and
`handoff_deny`. After those, at the end of the file, it sources the parts:

    # shellcheck source-path=SCRIPTDIR/../scripts source=_lib_frame.sh
    source "$HANDOFF_LIB_DIR/_lib_frame.sh"
    (same two lines for _lib_drive.sh and _lib_files.sh)

| Part | Lines | Holds |
| --- | --- | --- |
| `scripts/_lib_frame.sh` | 118 | `handoff_frame`, `_handoff_has_body`, `handoff_frame_notes` |
| `scripts/_lib_drive.sh` | 286 | `_handoff_drive_expect/_command/_prose`, `handoff_drive_read`, `handoff_drive_has_source`, `handoff_drive_arm` |
| `scripts/_lib_files.sh` | 109 | `handoff_read_regular`, `handoff_replace`, `marker_dir_ok`, `handoff_write_marker`, `handoff_read_marker` |

Names follow `_lib` plus the subject, so `scripts/_lib*.sh` globs the family.
Each part has a shebang line, a one-line description, "Part of _lib.sh.
Source-only; ..." and the `source-path=SCRIPTDIR source=_lib.sh` example, so a
reader is told to source `_lib.sh` and never the part. Order of functions within
a part is the original order; in `_lib_drive.sh` `handoff_owner_live` (between
`handoff_drive_read` and `handoff_drive_has_source` originally) stays in
`_lib.sh`. The "Shape helpers for handoff_drive_read" comment moved with them.

## Cross-part dependencies (runtime-fine once all parts are sourced)

- `_lib_drive.sh`: `handoff_drive_read` calls `handoff_read_regular`, and
  `handoff_drive_arm` calls `handoff_replace` (both `_lib_files.sh`).
- `_lib_frame.sh`: `handoff_frame` reads `HANDOFF_LIB_DIR`;
  `handoff_frame_notes` reads `HANDOFF_REL_TASK/TODO` and
  `HANDOFF_LEGACY_REL_TASK/TODO` (all set in `_lib.sh`). Also reads
  `FRAME_*` flags `handoff_frame` sets (same part).
- `_lib_files.sh`: `marker_dir_ok` and `handoff_read_marker` read
  `HANDOFF_POINTER_DIR` (set in `_lib.sh`); `handoff_read_marker` calls
  `marker_dir_ok` and `handoff_read_regular` (same part).
- `_lib.sh` itself calls nothing in a part (`handoff_lock_take` uses only
  `HANDOFF_LIB_DIR`).
- `HANDOFF_LIB_DIR` is computed from `BASH_SOURCE[0]` of `_lib.sh` before the
  parts are sourced, so a part is found beside whichever `_lib.sh` was sourced.

## Line-multiset check

`comm -23 <(git show c2fff7c:scripts/_lib.sh | sort) <(cat "$D"/scripts/_lib.sh "$D"/scripts/_lib_*.sh | sort)`
printed nothing (no old line lost).

`comm -13` (added lines; the three headers repeat, hence the repeated lines):

    (blank line, 1)
    #   # shellcheck source-path=SCRIPTDIR source=_lib.sh          x3
    #   source "$(dirname "$0")/_lib.sh"                           x3
    # Part of _lib.sh. Source-only; no shebang                     x3
    # The file-safety primitives: no-follow reads, replacing writes, markers.
    # The frame: the injectable task-and-todo frame and its legacy notes.
    # The sentinel grammar: parse, validate and rewrite .claude/autodrive.
    # The rest of the library, in parts: each defines functions and sets no state
    # at load. Sourced here, after everything this file defines, from the
    # directory it was found in.
    # definitions, so callers source _lib.sh and never this file:  x3
    # execution. Reached through _lib.sh, which sources it after its own  x3
    # shellcheck source-path=SCRIPTDIR/../scripts source=_lib_drive.sh
    # shellcheck source-path=SCRIPTDIR/../scripts source=_lib_files.sh
    # shellcheck source-path=SCRIPTDIR/../scripts source=_lib_frame.sh
    #!/usr/bin/env bash                                            x3
    source "$HANDOFF_LIB_DIR/_lib_drive.sh"
    source "$HANDOFF_LIB_DIR/_lib_files.sh"
    source "$HANDOFF_LIB_DIR/_lib_frame.sh"

Only headers, the three-line sourcing comment in `_lib.sh`, `source` lines, and
one extra blank line.

## Fixtures (tests/hook-test.bats, 6 lines changed)

- `frame_with_stub_lib`: `cp "$repo_root/scripts/_lib.sh" "$repo_root"/scripts/_lib_*.sh "$stub/"`
  (and its comment now says "a copy of _lib.sh and its parts"). Mutation-checked:
  restoring the single-file `cp` fails all 5 `handoff_frame (library ...)`
  rows (5 `not ok`); with the change, 5 `ok`.
- The `-I` row's positive half: `run grep -h 'python3 -I -c' scripts/_lib.sh scripts/_lib_*.sh`
  then `[ "$status" -eq 0 ]`. (`grep -c` over several files prints `file:N`
  lines, so `[ "$output" -ge 1 ]` could not be kept; `-h` plus the status is the
  at-least-one test.) The negative half (`python3 -c` absent from `scripts/*.sh
  bin/*`) is unchanged and already covers the parts through the glob.

Verbatim checker, `c2fff7c:tests/hook-test.bats -- $D/tests/hook-test.bats`:

    blocks: old 289, new 289
    CHANGED: @test "every python3 -c in the hooks and bin runs isolated (-I)" {
    ...
    verbatim: 1 problem(s)

Exactly one CHANGED block, the `-I` row; no missing, extra or repeated block.

## Checks, all run from `$D`

- `bats tests/hook-test.bats tests/checkpoint.bats tests/drive-take.bats`: 352
  tests, all `ok` (289 + 42 + 21; the `@test` counts are unchanged).
- `pytest -q`: `520 passed, 3 deselected`; `pytest --collect-only -q`:
  `520/523 tests collected (3 deselected)`, equal to baseline.
- `shellcheck -x bin/* scripts/*.sh tests/*.bats`: clean. This includes the
  parts directly (`scripts/_lib_*.sh` match `scripts/*.sh`), with no new
  directive needed inside them.
- No Python was touched, so ruff/mypy/ty/docformatter were not run.
- Line counts: `_lib.sh` 207, `_lib_frame.sh` 118, `_lib_drive.sh` 286,
  `_lib_files.sh` 109, `tests/hook-test.bats` 3985 (step 2), `CLAUDE.md` 908
  (exempt, own TODO item; was 891).

## The nested-directive point, confirmed

Probe in a scratch copy (`/tmp/claude/line-cap-split/step-1/sc`): appended a
lowercase global assignment `zz_probe_part_var=1` to `_lib_files.sh` and
`echo "$zz_probe_part_var"` to `bin/handoff-approved` and
`tests/checkpoint.bats`, then ran `shellcheck -x` on those two.
- With the shipped `source-path=SCRIPTDIR/../scripts`: 0 SC2154, i.e. shellcheck
  followed into the part from both `bin/` and `tests/` and saw the assignment.
- With the bare `source-path=SCRIPTDIR` (sed-swapped in the scratch copy): 2
  SC2154 (one per caller), i.e. the part was silently skipped.
- From a `scripts/` caller (`session-pointer.sh`) under the bare form: 0, as
  expected since SCRIPTDIR is `scripts/` there.
The probe lived only in the scratch copy; `$D` does not contain it.

## References updated

- `CLAUDE.md`: the Layout entry for `_lib.sh` now opens by saying it is the one
  file callers source, what it keeps, and the three parts with their functions
  and the nested directive (the enumeration below it is unchanged and still
  correct, since each function is listed by name); the Conventions bullet
  names the three parts and the `SCRIPTDIR/../scripts` directive and why; the
  `hook-test.bats` coverage sentence says "a copy of `_lib.sh` and its parts".
- `docs/design/the-write-path.md:11`: `handoff_frame()` is in
  `scripts/_lib_frame.sh` (reached through `_lib.sh`).
- `docs/design/scoping.md:92`: `marker_dir_ok`/`handoff_write_marker` live in
  `_lib_files.sh`.
- `docs/design/queued-prompts.md:57`: `handoff_read_marker` is in
  `_lib_files.sh`.
- Left as true: `docs/design/sentinel-lock.md:34` and `scripts/_drive_lock.py:18`
  (`handoff_lock_take`), `scripts/worktree_root.py:104`
  (`handoff_root_read`) are in `_lib.sh`; `scripts/checkpoint.py` (`_LIB_SH`,
  sources `_lib.sh`), `tests/conftest.py`/`tests/test_drive_lock.py` (`LIB`),
  all eight `source` sites, and the "mirrors `_lib.sh`'s HANDOFF_REL_*" comments
  in `checkpoint.py`/`_checkpoint_plan.py` (constants stay in `_lib.sh`).
- Not touched (inside files other steps split or frozen records):
  `tests/hook-test.bats` section headers `# --- _lib.sh: handoff_frame ... ---`
  (step 2 renames them with the split), plans and changelog.

## Departures from the plan's text

None of substance. Two small notes: the `-I` row positive half uses `grep -h ...
; status` rather than `grep -c ...; output` (reason above), and `CLAUDE.md`'s
Layout entry was extended with a leading summary of the parts and left its
long per-function enumeration alone rather than redistributing it (no
mis-statement in it, and a rewrite would be a larger prose change than the plan
names). `_lib.sh` file modes are unchanged (644).

## Phase B notes

Patch applies to: `CLAUDE.md`, three `docs/design/*.md`, `scripts/_lib.sh`, new
`scripts/_lib_{frame,drive,files}.sh`, `tests/hook-test.bats`. The `hook-test.bats`
edits are two hunks (the `cp` and its comment near line 670-685, the `-I` row
near 1040); step 2 splits that file, so expect a conflict there if step 2
lands first, resolved by carrying both hunks into the file that holds
`frame_with_stub_lib` and the `-I` row. `CLAUDE.md` is also edited by other
steps; the hunks are in the Layout `_lib.sh` entry (~253), the Conventions
bullet (~537) and line ~629.

## Phase B

Applied `--3way` onto 192b0de cleanly (no conflicts, `memory` not staged).
Grep of old names found no stale mention beyond the three already-updated
design lines. Verbatim checker against `HEAD:tests/hook-test.bats`: 289/289,
one CHANGED block (the `-I` row); `comm -23` multiset check: 0 lost lines.

Committed as `351fc71` (`♻️ split _lib.sh into three sourced parts`), 9 paths.

`just precommit` (unsandboxed, venv exported), exit 0: `check-plugin` and
`check-code` passed (shellcheck, bats trio, ruff/mypy/ty/docformatter, pytest
520 passed with 3 deselected, `check-refs`: 260 references resolve, 2 shipped
references from 6 shipped files).
