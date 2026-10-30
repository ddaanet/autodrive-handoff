# Step 1 review: `351fc71` (`_lib.sh` into three parts)

Reviewer, at the bar of `/code-review medium`. Read only from git (`git show
351fc71…`) and from an export, `git archive 351fc71` into
`/tmp/claude/line-cap-split/review-1/repo` (with `351fc71^` in `…/old` to
compare against). Nothing fixed, nothing in the working tree touched besides
this file.

## Findings

**No high or medium findings.** All the code moved verbatim, every caller gets
the same 18 functions and the same 11 variables, a missing part fails closed in
every production caller, and both test changes still bite.

### Declined (low)

1. **`tests/hook-test.bats:252, 398, 611, 729, 992, 1044`**: the section
   headers still read `# --- _lib.sh: handoff_frame … ---`,
   `_lib.sh: handoff_drive_read …`, `_lib.sh: handoff_read_regular`,
   `_lib.sh: handoff_drive_arm`, but those functions now live in parts. This is
   not false, since callers reach every one of them through `_lib.sh`, and the
   dispatch leaves references inside `hook-test.bats` to step 2, which splits
   that file "one per hook or library part". *Low.* Step 2's reviewer should
   check that the new file names and headers say which part they test.
2. **Wrapping**: `docs/design/the-write-path.md:11` is 107 columns and
   `CLAUDE.md:646` is 100, in prose otherwise wrapped at about 80. No gate
   enforces the width (precommit was green). *Low.*
3. **`CLAUDE.md:253-254` and `:551`**: the caller directive is given as
   `source-path=SCRIPTDIR source=_lib.sh` "above each `source`", but the `bin/`
   and `tests/` callers carry `source=../scripts/_lib.sh`. That imprecision is
   older than this commit. Next to the three nested `source`s, "each" could
   be read as covering them too, but the directive names `_lib.sh` and the next
   sentence gives the parts' form. *Low.*
4. **A missing or unreadable part when the caller does not run `set -e`**
   (`scripts/checkpoint.py:305-312` `_read_back_drive`, plus `conftest.py` and
   `test_drive_lock.py`): `bash -c 'source _lib.sh; handoff_drive_read …'`
   carries on past a failed nested `source`. Probed with each part moved away:
   - `_lib_drive.sh` missing gives `handoff_drive_read: command not found`,
     rc 1. The read-back fails and the sentinel is removed (fail-closed).
   - `_lib_files.sh` missing gives `handoff_read_regular: command not found`,
     and the reason comes back as `the python3 helper that reads it failed, so
     its state is unknown` (misattributed), rc 1 (fail-closed).
   - `_lib_frame.sh` missing gives rc 0, with the source error on stderr only.

   All eight production `source` sites run under `set -euo pipefail`. There a
   missing or unreadable part aborts the hook with rc 1 and `_lib.sh: line 20N:
   …/_lib_<part>.sh: No such file or directory` (or `Permission denied`). That
   is the same class as a missing `_lib.sh` before the split, also probed
   (rc 1, `No such file or directory`). *Declined*: a partial install is a
   state nothing produces, because `dist.include` ships `scripts` as a whole
   directory.

### A note on the step-1 report's evidence (not a finding on the commit)

The executor's probe says the bare `source-path=SCRIPTDIR` form raised "2
SC2154 (one per caller)", from `bin/handoff-approved` and
`tests/checkpoint.bats`. It cannot have raised one from `checkpoint.bats`:
`tests/checkpoint.bats:16` disables SC2154 file-wide. My repeat of the probe
got the hit from `bin/handoff-approved` only. I repeated the `tests/` half
against `tests/hook-test.bats`, which has no file-wide disable. A lowercase
`zz_review_probe=1` appended to `_lib_frame.sh` and read from a function in
`hook-test.bats` gives:
- shipped `SCRIPTDIR/../scripts`: 0 SC2154;
- bare `SCRIPTDIR`: `tests/hook-test.bats:3988:11: warning: zz_review_probe is
  referenced but not assigned. [SC2154]`.

So the claim in `CLAUDE.md` and the plan, that shellcheck follows into a part
from `bin/` and `tests/` only with the `../scripts` form, holds. Only the
report's evidence for the `tests/` half was wrong. The shipped form also gives
0 from `cwd=/` with absolute paths. As a control, with the variable never
assigned, the shipped form does raise SC2154 from `bin/` and `scripts/`, so its
0 comes from following the source and not from the check being suppressed.

## Re-run checks

### Verbatim (line multiset)

`comm -23 <(git show 351fc71^:scripts/_lib.sh | sort) <(for f in _lib.sh
_lib_frame.sh _lib_drive.sh _lib_files.sh; do git show 351fc71:scripts/$f;
done | sort)`: **empty**.

`comm -13 … | sort | uniq -c`, 31 added lines (689 + 31 = 720 = 207 + 118 +
286 + 109), classified:

| Count | Line | What |
| --- | --- | --- |
| 3 | `#!/usr/bin/env bash` | part shebangs (as `_lib.sh` has) |
| 3 | `# Part of _lib.sh. Source-only; no shebang` | part header |
| 3 | `# execution. Reached through _lib.sh, which sources it after its own` | part header |
| 3 | `# definitions, so callers source _lib.sh and never this file:` | part header |
| 3 | `#   # shellcheck source-path=SCRIPTDIR source=_lib.sh` | part header, the caller example (old `_lib.sh` had 1, now 4) |
| 3 | `#   source "$(dirname "$0")/_lib.sh"` | part header, same |
| 1 each | `# The frame: …`, `# The sentinel grammar: …`, `# The file-safety primitives: …` | one-line part descriptions |
| 1 each | `# The rest of the library, in parts: …`, `# at load. Sourced here, …`, `# directory it was found in.` | the sourcing comment in `_lib.sh` |
| 1 each | `# shellcheck source-path=SCRIPTDIR/../scripts source=_lib_{frame,drive,files}.sh` | the three directives |
| 1 each | `source "$HANDOFF_LIB_DIR/_lib_{frame,drive,files}.sh"` | the three sources |
| 1 | (blank) | before the sourcing block |

Order, beyond the multiset: each part's body (everything after its 7-line
header and blank line) is one contiguous excerpt of the old file. The drive
part is two excerpts, because `handoff_owner_live` sat between
`handoff_drive_read` and `handoff_drive_has_source` and stays in `_lib.sh`.
Each excerpt occurs exactly once in the old file. The new `_lib.sh`, up to the
sourcing block, equals the old file minus those excerpts, modulo runs of blank
lines.

### Every function, every variable, the same

`env -i bash`, sourcing the old and the new `_lib.sh`, then `declare -f`
together with `declare -p` of the `HANDOFF_`/`DRIVE_`/`FRAME_`/`MARKER_` names:
**identical**. That is 18 functions (`_handoff_drive_command`,
`_handoff_drive_expect`, `_handoff_drive_prose`, `_handoff_has_body`,
`handoff_deny`, `handoff_drive_arm`, `handoff_drive_has_source`,
`handoff_drive_read`, `handoff_frame`, `handoff_frame_notes`,
`handoff_lock_take`, `handoff_owner_live`, `handoff_read_marker`,
`handoff_read_regular`, `handoff_replace`, `handoff_root_read`,
`handoff_write_marker`, `marker_dir_ok`) and the same values. The names that
are new after load, `shopt -p` and `set -o`, are also identical, so no part
sets state at load. The parts use no `BASH_SOURCE`, `FUNCNAME`, `LINENO` or
`$0` except in the header comment.

### `HANDOFF_LIB_DIR` and load shapes

Each probe ran `set -euo pipefail`, sourced `_lib.sh` twice, then counted the
functions:

| Shape | `HANDOFF_LIB_DIR` | functions |
| --- | --- | --- |
| relative with a slash (`scripts/_lib.sh`) | `scripts` | 18 |
| `./_lib.sh` | `.` | 18 |
| a directory with a space (`…/a b/scripts`) | `…/a\ b/scripts` | 18 |
| a directory with a newline (`…/nl\n/scripts`) | `$'…/nl\n/scripts'` | 18 |
| no slash, found in cwd | `.` | 18 |
| no slash, found through `PATH` from another cwd | the absolute path (bash records the resolved path in `BASH_SOURCE`) | 18 |
| the caller idiom `source "$(dirname "$0")/_lib.sh"` from a hook in the newline directory | `$'…/nl\n/scripts'` | all present |

The nested sources always carry a slash (`.` or a directory), so they never
search `PATH`. They resolve at load, from the same cwd as `_lib.sh` itself, so
a relative `HANDOFF_LIB_DIR` exposes nothing new. bash 3.2 (the macOS target)
was not run here. The commit adds only `source` lines and comments to the load
path, all valid in 3.2, so there is nothing new on that axis to check.

Cost: sourcing 500 times took 2743 µs per source before the split and 2531 µs
after, so the difference is noise. No fork is added. `inject-checkpoint-root.sh`
sources on every Bash call, so its negative path now opens three more files
in-process.

### Test blocks and counts

`python3 -I /tmp/claude/line-cap-split/verbatim-check.py
351fc71^:tests/hook-test.bats -- 351fc71:tests/hook-test.bats`:

```
blocks: old 289, new 289
CHANGED: @test "every python3 -c in the hooks and bin runs isolated (-I)" {
-    run grep -c 'python3 -I -c' scripts/_lib.sh
-    [ "$output" -ge 1 ]
+    run grep -h 'python3 -I -c' scripts/_lib.sh scripts/_lib_*.sh
+    [ "$status" -eq 0 ]
verbatim: 1 problem(s)
```

That is exactly one CHANGED block, the expected one. The `hook-test.bats` diff
outside the test blocks is the `frame_with_stub_lib` hunk alone: the `cp` line
and its three-line comment, read by hand.

`@test` counts are hook-test 289/289, checkpoint 42/42 and drive-take 21/21
(`351fc71^`/`351fc71`).

### The two test changes, mutation-checked on a copy of the export

- **The `-I` row change was needed.** `_lib.sh` now has 0 `python3 -I -c` and
  `_lib_files.sh` has 2, so the old positive half would have failed.
- **M1**: `-I` dropped from `handoff_replace` in `_lib_files.sh` turns the row
  red. The negative half's `scripts/*.sh` glob reaches the parts.
- **M2**: every `python3 -I -c` in the four library files rewritten (no match
  anywhere) turns the row red, on the positive half alone. A missing part would
  also make the `grep` exit 2, which is red.
- **M3**: the fixture reverted to `cp _lib.sh "$stub/_lib.sh"` turns all 5
  `handoff_frame (library …)` rows red, with `…/stub-lib-0/_lib.sh: line 203:
  …/_lib_frame.sh: No such file or directory`. This shows the fixture needs the
  parts. It does not show the rows test the library's semantics, which is what
  M4 is for.
- **M4**: `_handoff_has_body` mutated in the real `_lib_frame.sh` to read
  exit 2 as a body (`…; [ $? -ne 1 ]`) turns "library exits 2" and "library
  missing" red, while the 0, 1 and crash rows stay green. The stub copies the
  real parts, so the rows still exercise the production function and pass for
  the right reason.
- The `_lib_*.sh` glob picks up exactly the three parts, the prefix is quoted
  (`"$repo_root"/scripts/_lib_*.sh`), and nothing else under `scripts/` is
  needed by `handoff_frame` beyond the stubbed `_checkpoint_lib.py`.
- The copy was restored afterwards (`diff -r` against the export is clean).

`bats --filter 'python3 -c|library' tests/hook-test.bats` on the export gives
6/6 `ok`. The task's `\|` form is BRE, and bats' filter is ERE, so that form
found no tests.

### Suites, lint and line counts, on the export

- `bats --jobs 4 tests/hook-test.bats tests/checkpoint.bats
  tests/drive-take.bats`: 352/352 `ok`, rc 0.
- `pytest --collect-only -q`: `520/523 tests collected (3 deselected)`.
- `pytest -q`: `520 passed, 3 deselected`.
- `shellcheck -x bin/* scripts/*.sh tests/*.bats` (0.10.0): rc 0, no output.
- Directives: `scripts/_lib.sh:202-207`, with
  `# shellcheck source-path=SCRIPTDIR/../scripts source=<part>` above each of
  the three `source` lines, as the plan specifies.
- Modes: the parts are 100644, like `_lib.sh`. `dist.include` lists `scripts`
  as a directory, so the parts ship.
- Callers are unchanged: the eight `source` sites, `checkpoint.py:48`
  `_LIB_SH`, `tests/conftest.py:35` and `tests/test_drive_lock.py:25` `LIB`
  all still name `_lib.sh`, and the commit's diff touches none of them.
- Line counts (`git show 351fc71:<path> | wc -l`): `scripts/_lib.sh` 207,
  `_lib_frame.sh` 118, `_lib_drive.sh` 286, `_lib_files.sh` 109,
  `docs/design/queued-prompts.md` 79, `docs/design/scoping.md` 114,
  `docs/design/the-write-path.md` 262. All are under 400.
  `tests/hook-test.bats` (3985) is step 2's, and `CLAUDE.md` (908, was 891) is
  exempt.

### Prose against the code

- `CLAUDE.md:253-267` (Layout): what `_lib.sh` keeps, the three parts with
  their functions, "after those", `$HANDOFF_LIB_DIR` and the directive form all
  match the code. The enumeration after it still lists functions under the
  `_lib.sh` bullet with no per-part attribution, but the new summary assigns
  each function to its part, so nothing in it is misstated.
- `CLAUDE.md:549-556` (Conventions): accurate, and the `bin/`/`tests/` claim
  was probed as above.
- `CLAUDE.md:646`: accurate.
- `docs/design/the-write-path.md:11` (`handoff_frame()` in `_lib_frame.sh`),
  `scoping.md:92` (`marker_dir_ok`, `handoff_write_marker` in `_lib_files.sh`)
  and `queued-prompts.md:57` (`handoff_read_marker` in `_lib_files.sh`) are all
  accurate.
- `git grep -n '_lib.sh' 351fc71 -- . ':!plans' ':!docs/changelog' ':!TASK.md'
  ':!TODO.md'`, every remaining mention checked:
  - `CLAUDE.md:85` and `:440`, `_checkpoint_plan.py:315/321`,
    `checkpoint.py:43/271` and `test_checkpoint_legacy.py:57` name constants
    that stay in `_lib.sh`.
  - `sentinel-lock.md:34` and `_drive_lock.py:18` name `handoff_lock_take`,
    and `worktree_root.py:104` names `handoff_root_read`; both stay.
  - `bin/handoff-approved:13`'s "lints exactly as it does from scripts/" is
    now true because of the `../scripts` form.
  - The `hook-test.bats` headers are low 1 above.
  - No other doc names a moved function's file.
