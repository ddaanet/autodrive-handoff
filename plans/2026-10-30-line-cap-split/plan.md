# Split the oversized files under the 400-line cap

Decided by my human partner, 2026-10-30:

- The plan is written now. On approval it runs on a branch of its own,
  `line-cap-split`, cut from `dev`, and merges into `dev` after 0.19.0 ships.
  `dev` stays ready to release in the meantime.
- Scope follows claude-plugin-dev's `tests/line-cap-test.sh`: every file git
  does not ignore, except `plans/`, `docs/changelog/`, gitlinks, symlinks and
  binary files.
- Two files are exempt. `tests/test_checkpoint_legacy.py` (1563) is deleted
  whole by the legacy pass. `CLAUDE.md` (891) gets its own `TODO.md` item.
- The checker comes from the toolkit, so this plan adds no check to
  `precommit` (a brief sits in claude-plugin-dev's `inbox/`). The one-off scan
  under Verification stands in for it until then.

No mechanism changes, so there is no changelog entry and no `docs/design/`
rewrite beyond the references to moved files.

## Files

The scan as of 2026-10-30 (Verification, below):

| File | Lines | Step |
| --- | --- | --- |
| `tests/hook-test.bats` | 3985 | 2 |
| `tests/checkpoint.bats` | 695 | 3 |
| `scripts/_lib.sh` | 689 | 1 |
| `tests/bats-best-practices.md` | 574 | 5 |
| `tests/test_checkpoint_hold.py` | 548 | 4 |
| `tests/test_checkpoint_transition.py` | 532 | 4 |
| `tests/mypy-guidelines.md` | 404 | 5 |

## Invariants, every step

- Content moves verbatim. Every `@test` block and every `def test_` (its
  decorators included) is byte-identical to the original. This is checked by
  extracting the blocks by name from `git show HEAD:<old file>` and from the
  new files and diffing them. A block changes only where its step names the
  change.
- The counts are unchanged. The `@test` counts are compared before and after
  (hook-test 289, checkpoint 42), and so is `pytest --collect-only -q`.
- No file a step creates or edits is over 400 lines once its helpers have
  landed in it.
- A helper used by two or more of the new files goes to a shared file: a
  `tests/<name>-helpers.bash` loaded with `load`, as `lock-helpers.bash` is, or
  `tests/conftest.py`, per its own rule. A helper only one file uses stays in
  that file, as does the comment above it.
- Each commit updates every reference to what it moved. The references are
  found by grepping the old names outside `plans/` and `docs/changelog/`, so the
  docs never lag a commit. Load `craft:design-doc-writing` before touching
  `docs/design/`.
- `just precommit` is green on each commit (`claude` calls unsandboxed).

## Steps

1. **`_lib.sh` into three parts.** `scripts/_lib.sh` stays the one file
   callers source, so no caller changes: not the eight `source` sites,
   `checkpoint.py`'s `_LIB_SH`, nor `LIB` in `conftest.py` and
   `test_drive_lock.py`. It keeps `HANDOFF_LIB_DIR`, the path constants,
   `handoff_owner_live`, `handoff_lock_take`, `handoff_root_read`,
   `HANDOFF_UNRESOLVED_MSG` and `handoff_deny`. After those, it sources these
   parts from `$HANDOFF_LIB_DIR`:
   - the frame: `handoff_frame`, `_handoff_has_body`, `handoff_frame_notes`;
   - the sentinel grammar: `_handoff_drive_*`, `handoff_drive_read`,
     `handoff_drive_has_source`, `handoff_drive_arm`;
   - the file-safety primitives: `handoff_read_regular`, `handoff_replace`,
     `marker_dir_ok`, `handoff_write_marker`, `handoff_read_marker`.

   Each `source` carries `# shellcheck source-path=SCRIPTDIR/../scripts
   source=<part>`. A bare `source-path=SCRIPTDIR` does not work here: it
   resolves against the top-level script's directory, so from `bin/` and
   `tests/` shellcheck silently skips the part. A caller's use of a lowercase
   variable the part sets then raises SC2154, and nothing inside the part is
   checked from those callers. Uppercase names raise nothing either way,
   because SC2154 skips them by default. This was probed with shellcheck 0.10.0
   on 2026-10-30, and the `../scripts` form resolves from any cwd.

   `dist.include` ships `scripts/` as a directory, so the parts are packaged
   with no change there. `check-refs` finds no markdown link to any file this
   plan splits, so the frozen records in `plans/` and `docs/changelog/`, which
   name those files only in backticks, stay untouched.

   Two fixtures change:
   - The stub-library rows (`frame_with_stub_lib`) copy the parts beside the
     copied `_lib.sh`.
   - The `-I` row's positive half asserts at least one `python3 -I -c` across
     the library files, not in `_lib.sh` alone.

   `CLAUDE.md`'s Layout entry for `_lib.sh` (line 253) and its Conventions
   bullet calling it the one remaining sourced helper (line 537) name the
   parts and the nested directive.
2. **`hook-test.bats` by hook.** Cut at its `# --- … ---` sections, one file
   per hook or library part, named for it. The starting grouping uses today's
   line ranges. Adjust it only where a file passes the cap once its helpers
   land.
   - `_lib.sh`: `handoff_root_read` resolver, branch labels, a crashing
     resolver, `handoff_deny`, `handoff_read_regular` (57–251, 992–1043);
     `handoff_frame` assembly and body (252–397, 611–728); `handoff_frame`
     legacy (398–610); `handoff_drive_read` and `handoff_drive_arm` (729–991,
     1044–1128).
   - `write-guard` (1129–1339).
   - `load-handoff` and its `clear` consume (1340–1445, 1949–2070); its legacy
     paths (1446–1789); the cwd that survives a line-wise read (1790–1948).
   - `load-compact` and its legacy paths (2071–2322).
   - The sentinel reader's helper failing, plus the sentinel as a symlink
     (2323–2368, 3339–3463).
   - `session-pointer` (2369–2487).
   - `report-drive-failure` (2488–2825); queued prompts, cut in two at the
     marker-trust rows (2826–3162, 3163–3221), the cut moving up a row group
     if the first half passes 400 once its helpers land; another live session
     (3464–3594); drift (3595–3863).
   - The sentinel's lock: the sweep and the loaders (3222–3338, 3864–3985).

   The shared `setup`/`teardown` and the helpers several files call go to
   `tests/hook-helpers.bash`. `just`'s `check-code` and `hook-test` recipes
   pass `tests/*.bats` to `plugin-dev/run-bats.sh` instead of the three
   names.
3. **`checkpoint.bats` by subject.** The `validate-plugin` rows with their
   stub-`claude` helpers; `inject-checkpoint-root.sh` and the prompt marker;
   `bin/handoff-approved` and the shim. The `make_repo`/decoy harness row goes
   wherever its helpers are used, or to a shared helper.
4. **The two pytest files.**
   - `test_checkpoint_hold.py`: Arming, Hold rule and the session-id rows stay.
     The sentinel's lock and the read-back rows (330–548) go to
     `test_checkpoint_readback.py`.
   - `test_checkpoint_transition.py`: the field matrix and the line-break row
     stay. The `continue`-needs-a-body rows and the legal combinations with the
     sentinel's bytes go to `test_checkpoint_sentinel.py`.
   - Each new file has the module-level `pytestmark` of its siblings.
     `CLAUDE.md`'s per-file coverage list is rewritten to match.
5. **The two guideline docs**, cut at a `##` boundary. `bats-best-practices.md`
   splits into §1–4 and §5 through the checklist. `mypy-guidelines.md` splits
   into strict mode through annotations, then suppression debt through
   gotchas. Each half keeps the sources it cites and links to the other. No
   prose is cut to fit.

Commits: one per step, each given a delegated `/code-review medium` as it
lands.

Dispatch: one Sonnet executor runs steps 1–5 in order, reused by
`SendMessage` and writing its report to `reports/step-<n>.md` here. Each review
is done by a reviewer one rung up, which also re-runs the verbatim and count
checks.

## Verification

The scan that produced the table must list only the two exempt files:

```sh
cd /Users/david/code/handoff && git ls-files -z -co --exclude-standard |
while IFS= read -r -d '' f; do
  case "$f" in plans/*|docs/changelog/*) continue;; esac
  [ -L "$f" ] || [ ! -f "$f" ] && continue
  grep -Iq . "$f" 2>/dev/null || continue
  n=$(wc -l < "$f"); [ "$n" -gt 400 ] && printf '%6d %s\n' "$n" "$f"
done | sort -rn
```
