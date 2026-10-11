# Step 2 (Checkpoint migration) — RED review

**Verdict: APPROVE WITH CHANGES.**

- The red is genuine. The 68 failures are all assertions about the missing
  behaviour. The 21 guards are each paired with a positive.
- The rows can all be satisfied together: an independent reference passes 301/301.
- Every mutant the brief names is killed, except four. Those four survive
  because of coverage gaps, not because the existing rows are weak: NFR1 over
  a tracked legacy file, `autoname`, the sentinel state, and mtime on a move.
- One assertion over-specifies: the action words are matched case-sensitively.

Add the rows in F1–F4 and relax F5 before GREEN starts. None of them needs
production code to go red: F1, F4 and F6 are red today, while F2 and F3 are
guards whose positives already exist.

Scope: `git diff tests/test_checkpoint.py` (the block "Legacy path migration",
`tests/test_checkpoint.py:2684-3488`), checked against `plan.md` (the Amended
blockquote and the amended Checkpoint contract), `reports/step2-red.md`, the
step 1 reports and `CLAUDE.md`. Read-only: the only repo file written is this
report. Scratch work (not durable) was in `/tmp/claude-1000`: `ref/`,
`rev/mut.py`, `rev/mut/`, `rev/gap_rows.py`.

## 1. Genuine red

| run | result |
|---|---|
| `pytest tests/test_checkpoint.py` on unchanged code (junit XML read) | 301 rows: 68 failed, 233 passed, 0 errors |
| the 212 pre-existing rows | all pass (233 − 21 new guards) |
| failure types | 68/68 `AssertionError`. Two of them are `assert "Traceback" not in stderr` (`:3450`, `:3467`), which fail because checkpoint.py raises `IsADirectoryError`. That is the behaviour under test, not a fixture slip. |

I read every failure message (`$TMPDIR/rev/base_fails.txt`). Each one stops on
the missing behaviour, as `step2-red.md`'s table states:

- `TODO.md` is `None` after a keep;
- the legacy file still exists;
- `edit requested but TODO.md does not exist`;
- `want one line naming …, got []`;
- the `git rm …` string is absent.

None fails in a helper, a fixture or an import.

The 21 expected-green guards are paired with positives:

- `test_stdout_with_no_legacy_file_anywhere_is_what_it_was` ×8: the same calls
  over a legacy file (`:3253`).
- The 6 non-(with-commit, legacy) ids of `:3340`: their positives are in the
  same parametrization.
- The 4 dir/dangling ids of `:3415`: their positives are the `file` ids.
- `:3438[edit]`: the `keep` and `content` ids.
- `:3110`: the four clear rows.
- `:2983`: the `edit` ids of `:2951`.

Each pairing holds. Three rejection ids (`schema_error`, `task_shape_error`,
`held_without_a_session_id`, `:3197`) go red only in their "fixed" half. Their
rejection half passes today by construction. The mutants below prove that it
discriminates.

## 2. Satisfiability: an independent reference

I wrote my own minimal implementation in `$TMPDIR/ref` (a copy of `scripts/`,
`tests/`, `bin/`, `pyproject.toml`):

- **`_half()`:** decides per half whether the root file has a body
  (`is_empty_body`) and whether the legacy file `is_file()`. It refuses when
  the legacy file is a file and the root path exists but is not a regular file.
- **`FilePlan`:** gains `legacy` / `legacy_act` (`moved`, `removed` or
  `ignored`). The `keep` move is `os.replace`. `edit` reads the effective file.
  A write over a body-less root moves; a write with a body over a root with a
  body is `ignored`; a body-less write over a root with a body is `removed`.
  `clear` removes both.
- **`legacy_reports()`:** returns one line per legacy file. It is the first
  directive part.
- **`commit_directive(legacy=())`:** appends the `git rm` line when it is given
  paths.

Against it, `pytest tests/test_checkpoint.py` passes 301/301 on the first run.
No row conflicts with another. The over-specification is in F5.

## 3. Teeth: mutants of the reference

`$TMPDIR/rev/mut.py` copies the reference for each mutant. Each edit is
asserted to land exactly once. It then runs the 89 new rows plus two
pre-existing `autoname` rows. The identity mutant fails 0/91.

| mutant | killed by (count, which rows) |
|---|---|
| root-wins dropped (`has_body = False`) | 16: every `ignored` row, `:2983`, `:3003`, the body-less-after-write `root_with_body` ids, both git-rm negatives, `:3415[file-root_with_body]` |
| task half applied before the todo half resolves | 6: `:3197[edit_old_string_absent, edit_old_string_ambiguous]`, `:3223`, the three `:3438` ids (snapshot assertion) |
| migration before schema validation | 38, including `:3197[schema_error]` on the rejection half's snapshot |
| migration before the task-shape check | 36, including `:3197[task_shape_error]` on the snapshot (`schema_error` correctly survives this one) |
| migration before the session-id check | 37, including `:3197[held_without_a_session_id]` on the snapshot |
| reports after the tail, always | 9: all 8 ids of `:3253` and `:3280` |
| … only when held | 3: `:3253[handoff/precompact-typed-with-commit]`, `:3280` |
| … only when armed | 6: the six armed ids of `:3253` |
| … only under with-commit | 5 |
| … only under without-commit | 4 |
| reports between the commit act and the tail | 1: `:3280` alone. That row carries this case. |
| `exists()` instead of `is_file()` for the legacy path | 4: the dir/dangling ids of `:3415` |
| body-less root counted as a body | 12: `:2912` keep ×3, edit ×3, content ×3, and `:2929` ×3, so each action kills it on its own |
| post-write body-less root keeps a beside-it legacy file | 3: `:3028[root_with_body]`, `:3042`, `:3061[root_with_body]` |
| `clear` spares legacy, root absent | 14 |
| `clear` spares legacy, root present | 4: `:3081`, `:3097`, `:3129` `root_with_body`, and `:3223` |
| precompact spares the legacy task | 7: `:3129` ×2, the four precompact ids of `:3253`, `:3340[with-commit-legacy-precompact]` |
| git-rm act missing under with-commit | 3 |
| git-rm act printed under without-commit | 2 |
| git-rm act lists an ignored file | 2: `:3362`, `:3379` |
| git-rm act printed when nothing legacy happened | 9 |
| second call re-reports | 3: `:3475`, plus two `:3415` ids |
| move by copy, legacy left behind | 13 |
| todo moved to `TASK.md` | 13 |
| task half paired with the legacy todo path | 48 |
| directory refusal at apply time, after the task half is written | 3: `:3438` ×3 |
| `edit` reads the legacy file although the root wins | 4 |
| **move by copy + unlink (loses the mtime)** | **0: survives (F4)** |
| **checkpoint runs `git rm --cached` itself (NFR1)** | **0: survives (F1)** |
| **`autoname` migrates the todo** | **0: survives (F3)** |
| **migration forces `held`** | **1, incidental (F2)** |
| reports capitalised (`Moved …`) | 36: over-specification, not teeth (F5) |

All four survivors are killed by the probe rows in the Appendix. Each probe
passes against the reference. On unchanged code:

- the tracked and edit-strike probes go red on an assertion;
- the mtime probe as I ran it errored with `FileNotFoundError`; the Appendix
  version asserts the bytes first, so it fails on an assertion;
- the autoname and sentinel probes are guards and pass.

| survivor | probe that kills it |
|---|---|
| NFR1 (checkpoint runs `git rm` itself) | `test_probe_tracked_legacy_index_untouched`, both ids |
| `autoname` migrates | `test_probe_autoname_leaves_legacy_files_alone` |
| migration forces `held` | `test_probe_migration_leaves_the_sentinel_state_alone`, 6 of 8 ids |
| copy + unlink loses the mtime | `test_probe_keep_move_preserves_mtime` |

## Findings, ranked

### F1 (high): no fixture tracks a legacy file, so NFR1 and the purpose of the git-rm act are untested — `tests/test_checkpoint.py:3340-3394`

- The plan says the 0.15.0 files are "in most repositories … tracked".
- Every row creates the legacy file untracked in a fresh `git init`.
- **Mutant:** the checkpoint itself runs
  `git rm --cached --ignore-unmatch -q -- <legacy>` (or a `git mv`). Over an
  untracked file that is a silent no-op, and all 91 rows pass. That breaks
  NFR1 ("the checkpoint renames on the filesystem and does no git work").
- A "no git subprocess" detector does not work here. `_resolve_submodule_path`
  (`scripts/_checkpoint_lib.py:56-65`) runs `git config --file .gitmodules` on
  every boundary call, and `memory_directive` runs `git status`. So the
  observable has to be the index, not process spawning.
- **Fix:** add one row parametrized over `commit`:
  1. `git add -f` and commit the legacy todo, then run a keep;
  2. assert `git status --porcelain` holds ` D .claude/handoff-todo.md` (index
     untouched) and `?? TODO.md`;
  3. under `with-commit`, run the printed act plus `git add TODO.md`, and
     assert `R  .claude/handoff-todo.md -> TODO.md`.

  Step 3 proves the act does what the plan claims ("git records a rename").
  The probe is in the Appendix. It is red today and kills the mutant.

### F2 (medium): the tail oracle derives from the sentinel the code under test wrote, so "held/armed unaffected by migration" is pinned nowhere — `:2826-2833`, `:3327-3328`, `:3014`, `:3425`

- `assert_directive_tail` reads `.claude/autodrive` to decide whether to
  expect the arming line or the closing line.
- **Mutant:** `held = True` whenever a move or removal happened. The sentinel
  says `held`, the arming line is printed, and every tail row passes.
- The two snapshot rows `pop(SENTINEL_REL)` before comparing.
- Only `:3475` kills this mutant, and only incidentally: its second call's
  sentinel bytes differ from the first call's.
- **Fix:** in `:3253` (and `:3280`), compute the expected state from the
  parametrization, then assert it through the existing `drive_state()` (`:170`)
  and pick the tail from that expectation:
  - gitlore repo, clean memory: `held` iff `typed and commit == "with-commit"`;
  - `:3280` (dirty memory, untyped handoff, `/rename` is a command): `held`.

  The probe `test_probe_migration_leaves_the_sentinel_state_alone` does this.

### F3 (medium): `autoname` over legacy files is not covered — `:1871`

- `test_autoname_leaves_both_frame_files_byte_identical` seeds root files only.
- **Mutant:** `autoname` runs the todo `keep` plan. It survives.
- **Fix:** seed both legacy files with no root, run
  `{"skill": "autoname", "rename": "T"}`, then assert the snapshot is equal
  (sentinel popped) and no report line appears. Either add a parameter to
  `:1871` or add one row in the new block (probe in the Appendix). Its
  positive is `:2848[keep-plain]`, over the same fixture under `handoff`.

### F4 (medium-low): a move that loses the mtime passes — `:2848` (keep ids)

- `load-handoff.sh` reports the frame's age from the file that counts
  ("saved 52m ago"). A copy-and-unlink resets that age to "now".
- The plan says the checkpoint "renames on the filesystem".
- **Mutant:** `TODO.md.write_bytes(legacy.read_bytes())` in place of
  `os.replace`. It survives.
- **Fix:** add one `keep` row:
  1. `os.utime` the legacy file far into the past (so a same-second copy
     cannot pass by accident);
  2. assert `read(TODO.md) == TODO_LEGACY_BODY` first (my probe skipped this
     and errors with `FileNotFoundError` today; it should fail on an
     assertion);
  3. then assert that `st_mtime_ns` is preserved.

  Only `keep` can carry this row, because `edit` and content rewrite the bytes.

### F5 (medium): the action words are matched case-sensitively, which over-specifies wording the plan left free — `:2704-2706`, `:2813-2818`

- A natural report line such as `Moved .claude/handoff-todo.md to TODO.md.`
  fails 36 rows. The plan only says stdout "names" the file and "says so".
- **Fix:** match with `re.IGNORECASE`. The `\b` boundaries still keep
  "removed" from matching "moved".

### F6 (low): legacy-only `edit` that strikes the last item has no row — `:3042`

- Only the root-with-body variant exists. In the legacy-only case, the
  post-write rule and the move rule both apply.
- **Fix:** add a row: legacy `## Remaining\n\n- only item\n`, no root, edit to
  `""`. Assert `TODO.md == "## Remaining\n\n"`, the legacy file gone, and a
  `moved_or_removed` report. Probe in the Appendix; it is red today.

### F7 (low): smaller over-specifications

- `:3354` pins the act's path order as task before todo. The plan does not
  settle this. Either keep it (stated in `step2-red.md`) or compare as a set.
- `:2792-2794`: any second line naming the legacy path outside a `git rm`
  line counts as a duplicate report. For example, a commit act split over two
  lines with the path on the second fails `len == 1`. This is acceptable as
  documented, but it is a wording constraint GREEN must know about.
- `:3277`, `:3356` match the literal `"Once everything above is done"` rather
  than deriving the tail from `lib`. That couples these rows to lib wording,
  though the lib functions already pin that wording. Nit.
- `:3329` calls `lib.commit_directive()` with no arguments. GREEN must keep
  the legacy-paths parameter optional. That is reasonable; it should be stated
  to GREEN.

## 4. Contract coverage

| amended contract bullet / Steps item 2 row | rows | gap |
|---|---|---|
| Effective content = root with a body, else legacy; keep / edit / content | `:2848`, `:2912`, `:2951`, `:2983` | precompact `edit` over a legacy todo (only keep and content, `:3143`): low |
| Legacy present, root absent or body-less: rename, replacing a body-less root | `:2848`, `:2861`, `:2888`, `:2912`, `:2929` | rename-ness (mtime) not asserted: F4 |
| Root with a body + legacy (with a body or not): untouched, reported ignored | `:2951`, `:2970`, `:3003` | none |
| Post-write body-less root removes the legacy file and says so | `:3028`, `:3042`, `:3061` | legacy-only edit strike: F6 |
| `clear` / precompact remove legacy, root absent and present | `:3081`, `:3097`, `:3129` | none |
| Rejected payload leaves files byte-identical | `:3197` ×5, `:3223`, `:3438`, `:3455` | none |
| Reports ahead of the directive parts, closing line last | `:3253` ×8, `:3280` | oracle self-derived: F2 |
| git-rm act under with-commit, only for moved/removed files | `:3340`, `:3362`, `:3379` | tracked fixture: F1 |
| Both halves in one call | `:2873`, `:3253`, `:3197` | none |
| Root with a space in its path | `:2848[*-spaced]` | todo half only; enough, since nothing shells out with the path |
| `autoname` leaves legacy files untouched | none | F3 |
| held/armed sentinel unaffected | none (incidental only) | F2 |
| NFR1, no git work | none | F1 |
| Directory root refused cleanly (step 1 review note) | `:3438`, `:3455` | none |
| Same `is_file` predicate as the loader's `-f` | `:3415` | none |
| Idempotence | `:3475` | none |

## 5. Hygiene

| check (as the justfile runs it) | result |
|---|---|
| `ruff check scripts tests` | clean |
| `ruff format --check scripts tests` | clean |
| `docformatter --check scripts/*.py tests/*.py` | clean |
| `mypy` (strict, `files = scripts, tests`) | rc 0 |
| `ty check` | clean |

- **Placement:** the rows are in `tests/test_checkpoint.py`, as plan Steps
  requires. Names follow the file's `test_<behaviour>` pattern. No `.bats`
  row belongs to this step.
- **Order:**
  - Helpers come before their users (`:2751-2838`). That follows this file's
    own convention (`:39-180`), even though it departs from the repo rule.
  - The dicts and bodies used in `parametrize` decorators (`BODYLESS_ROOTS`,
    `TODO_OVER_*`, `REJECTIONS`, `TODO_LEGACY_BODY`, `HEADINGS_ONLY`) are a
    real evaluation-order constraint.
  - `MOVED`/`REMOVED`/`IGNORED`, `GIT_RM` and `SENTINEL_REL` are runtime-only
    and could sit below their users. The file has never done that, so I see it
    as consistent rather than a violation.
  - `make_legacy_of_kind` sits next to its single user (`:3400`), which is
    good.
- **Length:** `tests/test_checkpoint.py` is **3488 lines**: 2680 before plus
  808 new. That is far past the 400-line soft cap. A split is advisable, but
  as a separate change. The block is cohesive and the right seam is clear:
  - move the shared helpers (`make_repo`, `make_gitlore_repo`,
    `run_checkpoint`, `frame_payload`, `handoff_payload`,
    `precompact_payload`, `drive_state`, the `task_*`/`todo_*` builders, the
    `_session_id` autouse fixture) into `tests/conftest.py`;
  - then `tests/test_checkpoint_legacy.py` can hold this block, and the rest
    can be split by section.

  `--import-mode=importlib` is already set, so conftest is the vehicle, not a
  cross-test import. I did not split anything.

## Decisions for my human partner

1. **Reports under the clause-file refusal.**
   - `compose_directives` prints the refusal alone (`checkpoint.py:648-649`).
     Files are still written before that point, so a migration happens and its
     report, plus any git-rm act, is dropped.
   - On retry there is nothing legacy left, so the agent is never told about
     the move. Under with-commit, the tracked deletion is never staged.
   - Options: (a) the reports, and the act under with-commit, print ahead of
     the refusal; (b) skip migration when the refusal fires; (c) accept it.
     **Default: (a)**, plus one row with dirty memory, no clause file and a
     legacy todo.
2. **The git-rm act is owed only by the call that moved the file.** A
   `without-commit` migration followed later by a `with-commit` call leaves
   ` D .claude/handoff-todo.md` unstaged, because the second call has nothing
   legacy to report. It is visible in `git status`, not silent. **Default:
   accept**, and say so in the step 3 docs.
3. **The word for a content write over a legacy-only half** (`step2-red.md`
   Open question 1): the rows accept "moved" or "removed". **Default: keep
   both accepted.** The plan uses both words for this case.
4. **Path order in the git-rm act** (F7): **default: keep task before todo**,
   as documented.
5. **Splitting `tests/test_checkpoint.py`** through a `tests/conftest.py`: a
   separate change, not part of this step. **Default: a `TODO.md` item.**

`step2-red.md` Open question 2 (a body-less legacy file with no root is still
moved) is settled by the plan text ("Legacy present and root absent or without
a body: the plan includes a rename"), so it needs no decision.

## Appendix: probe rows (F1, F2, F3, F4, F6)

These rows were run against the reference and against the mutants above. They
use the block's own helpers, append after `:3488`, and are not ruff-formatted.
The `test_probe_` prefix is scratch naming; rename the rows to the block's
style when adopting them. F2 is better applied by changing `:3253` and `:3280`
in place, as F2 says, than by adding the separate row.

```python
# --- review probes: gaps found in the step 2 red review ---


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
def test_probe_tracked_legacy_index_untouched(tmp_path: Path, commit: str) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    git = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run([*git, "add", "-f", LEGACY_TODO_REL], cwd=repo, check=True)
    subprocess.run([*git, "commit", "-qm", "seed"], cwd=repo, check=True)
    payload = migration_payload(task_clear(), todo_keep(), commit)
    result = run_checkpoint(repo, payload)
    ok(result)
    status = subprocess.run(
        ["git", "status", "--porcelain"], cwd=repo, capture_output=True, text=True, check=True
    ).stdout
    assert f" D {LEGACY_TODO_REL}\n" in status, status
    assert "?? TODO.md\n" in status, status
    if commit == "with-commit":
        act = next(ln for ln in result.stdout.splitlines() if GIT_RM in ln)
        cmd = act[act.index(GIT_RM):].split("`")[0]
        subprocess.run(["bash", "-c", cmd + " && git add TODO.md"], cwd=repo, check=True)
        status = subprocess.run(
            ["git", "status", "--porcelain"], cwd=repo, capture_output=True, text=True, check=True
        ).stdout
        assert f"R  {LEGACY_TODO_REL} -> TODO.md\n" in status, status


def test_probe_autoname_leaves_legacy_files_alone(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    before = snapshot(repo)
    result = run_checkpoint(repo, {"skill": "autoname", "rename": "T"})
    ok(result)
    after = snapshot(repo)
    after.pop(SENTINEL_REL)
    assert after == before
    assert_not_reported(result.stdout, LEGACY_TASK_REL)
    assert_not_reported(result.stdout, LEGACY_TODO_REL)


@pytest.mark.parametrize("commit", ["without-commit", "with-commit"])
@pytest.mark.parametrize("typed", [False, True], ids=["untyped", "typed"])
@pytest.mark.parametrize("skill", ["handoff", "precompact"])
def test_probe_migration_leaves_the_sentinel_state_alone(
    tmp_path: Path, skill: str, *, typed: bool, commit: str
) -> None:
    repo = make_gitlore_repo(tmp_path)
    put(repo, LEGACY_TASK_REL, TASK_LEGACY_BODY)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    if skill == "handoff":
        payload = handoff_payload(commit)
        payload["clear"] = typed
    else:
        payload = precompact_payload(commit)
        payload["compact"] = typed
    result = run_checkpoint(repo, payload)
    ok(result)
    held = typed and commit == "with-commit"
    state, _owner = drive_state(repo / SENTINEL_REL)
    assert state == ("held" if held else "armed")
    tail = lib.arming_directive() if held else lib.closing_directive(skill, typed=typed)
    assert result.stdout.endswith(tail)


def test_probe_keep_move_preserves_mtime(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, TODO_LEGACY_BODY)
    then = 1_700_000_000_000_000_000
    os.utime(repo / LEGACY_TODO_REL, ns=(then, then))
    ok(run_checkpoint(repo, migration_payload(task_clear(), todo_keep())))
    assert read(repo / "TODO.md") == TODO_LEGACY_BODY
    assert (repo / "TODO.md").stat().st_mtime_ns == then


def test_probe_legacy_only_edit_striking_last_item(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    put(repo, LEGACY_TODO_REL, "## Remaining\n\n- only item\n")
    payload = migration_payload(task_clear(), todo_edit("- only item\n", ""))
    result = run_checkpoint(repo, payload)
    ok(result)
    assert read(repo / "TODO.md") == "## Remaining\n\n"
    assert not (repo / LEGACY_TODO_REL).exists()
    assert_reported(result.stdout, LEGACY_TODO_REL, "moved_or_removed")
```
