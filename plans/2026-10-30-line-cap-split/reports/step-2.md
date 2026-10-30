# Step 2 report: `tests/hook-test.bats` by hook (phase A)

Phase A only, in the copy `/tmp/claude/line-cap-split/step-2/repo` (tag `base`
= the `c2fff7c` tree). Nothing in the real tree was touched except this file.
The cut is re-runnable: `python3 -I /tmp/claude/line-cap-split/step-2/cut.py OUTDIR`
reads `c2fff7c:tests/hook-test.bats` with `git show` and writes
`OUTDIR/tests/*.bats` and `OUTDIR/tests/hook-helpers.bash`. It cuts by the
`# --- … ---` section lines (a table of line ranges), and moves shared helpers
by function name together with the comment block directly above each.

## File map

Line ranges are in the original. Every new file starts with `#!/usr/bin/env
bats`, a file-level `# shellcheck disable=SC2154` (the `$tmp`, `$other`
variables are assigned by `setup`, now in another file) and `load hook-helpers`.

| New file | Source lines | Lines | `@test` |
| --- | --- | --- | --- |
| `tests/lib.bats` | 57–251, 992–1043 | 250 | 24 |
| `tests/lib-frame.bats` | 252–397, 611–728 | 258 | 19 |
| `tests/lib-frame-legacy.bats` | 398–610 | 216 | 12 |
| `tests/lib-drive.bats` | 729–991, 1044–1128 | 352 | 36 |
| `tests/write-guard.bats` | 1129–1339 | 171 | 18 |
| `tests/load-handoff.bats` | 1340–1445, 1949–2070 | 208 | 16 |
| `tests/load-handoff-legacy.bats` | 1446–1789 | 347 | 23 |
| `tests/load-handoff-cwd.bats` | 1790–1948 | 153 | 12 |
| `tests/load-compact.bats` | 2071–2322 | 248 | 19 |
| `tests/sentinel-reader.bats` | 2323–2368, 3339–3463 | 174 | 12 |
| `tests/session-pointer.bats` | 2369–2487 | 122 | 8 |
| `tests/report-drive-failure.bats` | 2488–2825 | 322 | 24 |
| `tests/report-drive-failure-queued.bats` | 2826–3162 | 278 | 18 |
| `tests/report-drive-failure-trust.bats` | 3163–3221 | 62 | 4 |
| `tests/report-drive-failure-other-session.bats` | 3464–3594 | 116 | 10 |
| `tests/report-drive-failure-drift.bats` | 3595–3863 | 272 | 21 |
| `tests/sentinel-lock.bats` | 3222–3338, 3864–3985 | 244 | 13 |
| `tests/hook-helpers.bash` | 1–56 (header, setup, teardown) and the shared helpers below | 249 | n/a |

289 `@test` in total. The grouping is the plan's, unchanged. Largest file is
`lib-drive.bats` at 352. The queued-prompts pair stays cut at the marker-trust
rows: the first half is 278 lines with its helpers, so the cut did not move up.
The trust half is only 62 lines; merging it back would fit (278 + 62 < 400) and
is the plan's choice to revisit, not mine.

Names: `lib-*` for the `_lib.sh` parts as step 1 names them where they match
(frame, drive); the plan puts `handoff_read_regular` (step 1's `_lib_files.sh`)
in the same group as the resolver and `handoff_deny`, so that group is plain
`lib.bats`. `sentinel-reader` and `sentinel-lock` take the plan's subjects,
`report-drive-failure-*` and `load-handoff-*` share their hook's prefix.

## Helper placement

`tests/hook-helpers.bash` (shebang `bash`, with the old file's header reworded
for the shared role) holds:

- `setup` and `teardown`. The `load lock-helpers` line is no longer in `setup`:
  only the lock rows call `hold_drive_lock` and the like, so
  `sentinel-lock.bats` carries `load lock-helpers` itself, after
  `load hook-helpers`. (`drive-take.bats` and `checkpoint.bats` keep their own
  `load lock-helpers`.)
- Shared functions (each used by two or more new files, or by another shared
  helper): `make_worktree`, `assert_framed`, `run_write_guard`, `split_output`,
  `assert_msg_matches`, `make_worktree_nl_end`, `seed_pending`,
  `run_load_handoff`, `seed_drive`, `run_load_compact`, `run_report_failure`,
  `make_pointer_dir`, `seed_prompt_marker`, `marker_holds`, `seed_armed_kind`,
  `seed_queued`, `assert_unloaded_report`, `seed_transcript`, `seed_owned`.
- Shared top-level variables: `loaded_re` (load-handoff and sentinel-lock), the
  legacy/shadowed note block `legacy_*`/`shadowed_*` with its comment
  (load-handoff-legacy and load-compact), `noprompt_phrase`, `unloaded_msg`
  (read by `assert_unloaded_report`) and `prompt_marker`.

Helpers one file uses stay there with their comment: `broken_python` (lib),
`require_read_denied`, `frame_with_stub_status`, `frame_with_stub_lib`
(lib-frame), `read_drive` (lib-drive), `assert_notes`, `link_root`
(load-handoff-legacy), `context_of` (load-handoff-cwd), `reader_stub`,
`link_drive`, `assert_link_refused` (sentinel-reader), `start_report_failure`,
`become_pending`, `assert_sweep_left_pending`, `start_loader`, `become_armed`
(sentinel-lock), `run_session_pointer` (session-pointer), `swap_on_first`
(report-drive-failure), `assert_cancel_report` and `cancel_msg`
(…-queued), `seed_marker_in_untrusted_dir` (…-trust), `assert_drift_quoted`,
`find_witness_stub` (…-drift). A script check after the cut (re-runnable as
`/tmp/claude/line-cap-split/step-2/analyze.sh`) confirms every helper in
`hook-helpers.bash` is called by at least two new files (or by another shared
helper) and no local helper is called outside its file. `reader_stub` started
in the shared group (its comment says the trust rows use it) and moved back:
the trust file only names it in a comment.

## One edit outside a section, one outside a block

`lib-drive.bats` has `# shellcheck disable=SC2317` above the
`handoff_drive_arm (the sentinel became a link to a directory …)` row, among
the comment lines before its `@test` (not inside the block). Shellcheck used to
reach `_lib.sh` through the old file's `setup`; it no longer does, and flagged
the row's `tail()` override as unreachable. No `@test` block was edited.

## References updated

- `justfile`: `check-code` now runs `plugin-dev/run-bats.sh tests/*.bats`, and
  `hook-test` runs `bats tests/*.bats` (step 3 makes the same change).
- `CLAUDE.md` (Testing section): the `check-code` and `hook-test` bullets,
  the lock sentence (`tests/sentinel-lock.bats`), and the `tests/hook-test.bats`
  description, rewritten as one bullet per file: each covered area names its
  file, nothing was dropped; the mutation-check paragraph follows the list. The
  file grew from 891 to 933 lines (it is the exempt file with its own `TODO.md`
  item).
- `docs/design/the-write-path.md` (write-guard rows -> `tests/write-guard.bats`),
  `docs/design/sentinel-lock.md` (-> `tests/sentinel-lock.bats`),
  `docs/design/driving-the-transition.md` (-> `tests/report-drive-failure*.bats`).
- `tests/test_drive_lock.py` docstring (-> `tests/sentinel-lock.bats`) and the
  comment in `tests/drive-take.bats` (-> `hook-helpers.bash`).

Left for phase B (they sit in files other steps split): `tests/checkpoint.bats:300`
(`tests/hook-test.bats, where the marker is a fixture`; the marker rows are in
`tests/report-drive-failure-queued.bats`) and `tests/bats-best-practices.md:406`
(`hook-test.bats` named as the file that stubs a command; phase B points it at
the file that holds that stub after reading the paragraph).
Not changed: the `check-plugin` shellcheck line still lints `tests/*.bats` only,
so `hook-helpers.bash` (like `lock-helpers.bash` and `probe-helpers.bash`) is
not linted by the gate. It is clean under `shellcheck -x`.

## Checks, in the copy

- Verbatim checker `c2fff7c:tests/hook-test.bats -- <the 17 new .bats>`:
  `blocks: old 289, new 289` then `verbatim: OK`.
- `bats` over the 17 new files: `1..289`, 289 ok, 0 not ok. `bats tests/*.bats`
  (with `checkpoint.bats` and `drive-take.bats`): `1..352`, 352 ok (289 + 42 + 21).
- `shellcheck -x tests/*.bats tests/hook-helpers.bash`: exit 0, no output.
- `ruff check`, `ruff format --check`, `docformatter --check` on
  `tests/test_drive_lock.py`: clean. `pytest tests/test_drive_lock.py`: 18 passed.
- Line counts: the table above (all under 400); `hook-helpers.bash` 249.
  `justfile` 114, `CLAUDE.md` 933.
- Not run (as dispatched): `just precommit`, the full pytest, `claude plugin test`.

## Phase B plan

Step 1 lands first and edits `tests/hook-test.bats` twice (the
`frame_with_stub_lib` helper and the `python3 -I -c` count row), so the patch's
deletion of that file will conflict. Then: apply the patch with `--3way`, take
my deletion of `tests/hook-test.bats`, and port `git diff c2fff7c HEAD --
tests/hook-test.bats` into the split files by hand before `git rm`:

- the `frame_with_stub_lib` helper edit goes to `tests/lib-frame.bats` (the
  helper is defined there; verify with a hand diff of the helper body);
- the `python3 -I -c` count row is the `every python3 -c in the hooks and bin
  runs isolated (-I)` row at the end of `tests/lib.bats`; the verbatim checker
  against `HEAD:tests/hook-test.bats` (taken after step 1) proves it ported:
  it must print 289 blocks and `verbatim: OK`.

Then regenerate the patch from the copy only for the shared files that conflict
(`CLAUDE.md`, `justfile`), grep again for `hook-test` outside `plans/`,
`docs/changelog/`, `TASK.md`, `TODO.md`, fix the two left-over references above
if their files are split by then, and run `just precommit`.

## Phase B

Landed as `a19ff32` (`♻️ split hook-test.bats by hook`) on `line-cap-split`,
on top of `3b884dd`. 27 paths staged: the 17 new `.bats`, `tests/hook-helpers.bash`,
the deletion of `tests/hook-test.bats`, `CLAUDE.md`, three `docs/design/` files,
`tests/test_drive_lock.py`, `tests/drive-take.bats`,
`tests/inject-checkpoint-root.bats` and `tests/bats-tooling-and-checklist.md`.
`TASK.md`, `TODO.md`, `memory` and the masks were not staged.

Departure from the phase-A plan: the patch was not regenerated for the shared
files. Before export, the copy got the directive switch below and two
wording fixes (see Directives). In the real tree the conflicting shared files
were then spliced by hand from HEAD's text.

### Conflicts

- `tests/hook-test.bats`: `git apply --3way` refused the whole patch ("patch does
  not apply"), so it was re-run with `--exclude=tests/hook-test.bats`. The three
  hunks of `git diff c2fff7c HEAD -- tests/hook-test.bats` were ported by hand,
  then `git rm`: step 1's `frame_with_stub_lib` change and its comment into
  `tests/lib-frame.bats`, step 1's `-I` row (`grep -h … scripts/_lib.sh
  scripts/_lib_*.sh` plus the status check) into `tests/lib.bats`, step 3's
  comment edit into `tests/report-drive-failure-queued.bats`.
- `CLAUDE.md`: started from HEAD's text (`git checkout HEAD -- CLAUDE.md`) and
  replaced the one region from `- \`just hook-test\`` to `Each state gate is
  paired with the positive` with the copy's bullet list. Then re-applied step 1's
  "a copy of `_lib.sh` and its parts sourced beside a stub library" in the
  `lib-frame.bats` bullet and wrote the lock sentence as "the sweep's and the
  loaders' rows are in `tests/sentinel-lock.bats`". Every `+` line of
  `git diff c2fff7c HEAD -- CLAUDE.md` is present in the result except three,
  all intended rewraps into the bullet list (the `just hook-test` lead line,
  and the two lines of the old `handoff_frame` passage now in the `lib-frame.bats`
  bullet). HEAD's step 1 `_lib.sh` Layout and Conventions text, step 3's "Three
  files cover what stayed bash around the checkpoint" paragraph, step 4's
  per-file pytest bullets, the `tests/*.bash` shellcheck line, the
  `bin-commands.bats` bare-name row and the `run-bats.sh tests/*.bats` line all
  stand.
- `docs/design/sentinel-lock.md` and `tests/test_drive_lock.py`: both edits kept.
  The lists read `tests/drive-take.bats`, `tests/sentinel-lock.bats`,
  `tests/bin-commands.bats` and `tests/test_checkpoint_readback.py`
  (`tests/test_drive_lock.py` covers the lock itself in the .md).
- `justfile`: applied with no difference against HEAD (HEAD already had
  `tests/*.bats` twice and `tests/*.bash` on the shellcheck line).

### Directives

- Removed: the file-wide `# shellcheck disable=SC2154` from all 17 new files
  (`c2fff7c:tests/hook-test.bats` had none). Only `tests/checkpoint.bats` keeps
  one, with its `$stderr` reason.
- Replaced `load hook-helpers` with `# shellcheck source-path=SCRIPTDIR
  source=hook-helpers.bash` and `source "$BATS_TEST_DIRNAME/hook-helpers.bash"`
  in all 17. `load lock-helpers` in `sentinel-lock.bats` left as it was.
- Kept: `# shellcheck disable=SC2317` above the `handoff_drive_arm` link-swap row
  in `tests/lib-drive.bats`. Removing it was tried: shellcheck then reports
  SC2317 three times on the row's `tail()` override. With the directive,
  `shellcheck -x tests/*.bats tests/*.bash` is clean.
- No other new code appeared; no directive was added.
- Wording that still said `load` after the switch: the header comment of
  `tests/hook-helpers.bash` and the `just hook-test` lead-in in `CLAUDE.md`
  now say the files source the helper.

### References fixed

- `tests/inject-checkpoint-root.bats`: the marker comment now points at
  `tests/report-drive-failure-queued.bats` (rewrapped).
- `tests/bats-tooling-and-checklist.md`: the passage naming `hook-test.bats` as
  the file that stubs a command now names `tests/report-drive-failure-drift.bats`
  and its `find` stub. The old parenthetical ("logs its arguments and emits
  scripted output") described no row in the current suite (it was a reworded
  tmux stub from an earlier project), so it now says what that stub does: a
  per-test script under `$BATS_TEST_TMPDIR` that leaves a witness file when it
  runs, then execs the real command.
- `git grep -n hook-test` outside `plans/`, `docs/changelog/`, `TASK.md`,
  `TODO.md` now shows only the recipe name (`just hook-test` in `CLAUDE.md`
  and `justfile`) and `sess-hook-test`, a session id in `tests/drive-take.bats`
  that is not the file; both left.
- `git grep checkpoint.bats` finds no stale reference.

### Checks

Checker, against `HEAD:tests/hook-test.bats` (`3b884dd`, so step 1's `-I` row is
included), from `/Users/david/code/handoff`, over the 17 new files:

    blocks: old 289, new 289
    verbatim: OK

Hand diffs: `frame_with_stub_lib` and `frame_with_stub_status`, each with its
comment, equal their bodies in `git show HEAD:tests/hook-test.bats`; the step-3
comment in `report-drive-failure-queued.bats` equals HEAD's.

In the copy after the directive switch: `bats` over the 17 files, `1..289`,
289 ok, 0 not ok. In the real tree: `shellcheck -x tests/*.bats tests/*.bash`
clean; `pytest --collect-only -q`: `520/523 tests collected (3 deselected)`.

Line counts: every file created or edited is at most 400 except `CLAUDE.md`
(958), which is the exempt file. The plan's Verification scan lists only
`tests/test_checkpoint_legacy.py` (1563) and `CLAUDE.md` (958).

### Precommit

`just precommit` (unsandboxed, env exported): exit 0. Recap: jq checks,
`validate-plugin`, `claude plugin test` (17 pass, 0 fail), `shellcheck -x`
over `bin/* scripts/*.sh tests/*.bats tests/*.bash`, ruff check, ruff
format (26 files), docformatter, mypy, ty, `bats: 352 passed, 0 failed`,
pytest `520 passed, 3 deselected`, `check-refs: resolves: 260 references in 27
files … shipped stays shipped: 2 references from 6 shipped files`;
`precommit: check-plugin check-code passed`.

Commit: `a19ff32`.
