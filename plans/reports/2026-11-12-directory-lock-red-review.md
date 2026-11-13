# Directory lock: red-phase review (2026-11-12)

Reviewer verdict: the red is genuine. No high or medium finding. Every red row
fails against the unchanged scripts, and every one goes green against a minimal
directory-lock implementation. The plan's mutants and a no-lock mutant all red
at least one row. The findings below are lows: report accuracy, and contract
points with no row that the report does not name.

## Full-suite counts against the unchanged scripts

- `git status --short`: nothing under `scripts/`, `bin/` or `hooks/` changed.
  Only `tests/` plus the expected TODO.md, TASK.md, memory and plans/ entries.
- `pytest -q`: **25 failed, 359 passed, 3 deselected**. These match the
  report's list exactly.
- `bats tests/*.bats` (all 347 rows): **331 ok, 16 not ok**. All 16 are lock
  ordering or contention rows: bin-commands 3, 4; drive-cancel 30, 31, 32;
  drive-take 33, 34; sentinel-lock 289, 290, 291, 292, 295, 296, 297, 298, 299.
  Each one fails at `hold_drive_lock` (31 and 32 fail through
  `cancel_while_file_changes`, which calls it), because the holder cannot lock a
  directory today. No other bats row fails, so there is no failure the change
  does not explain.

## Method: a scratch green, then mutants

All of this ran in a copy of the repo under `$TMPDIR`. Nothing in the repo was
edited.

1. A minimal green, applied to that copy:
   - `_lib.sh`: `HANDOFF_REL_DRIVE_LOCK_DIR=".claude"`. `handoff_lock_take`
     runs `[[ -d "$lock" ]] || return 2`, then `exec 9<"$lock"`, then `wait`.
   - `_drive_lock.py`: `_create` opens with `O_RDONLY|O_DIRECTORY` (it follows a
     link). `create` is removed from `main`. `wait` uses `os.stat` and
     `S_ISDIR`.
   - `checkpoint.py`: `HANDOFF_REL_DRIVE_LOCK_DIR = ".claude"`.
   - The six bash call sites pass `$HANDOFF_REL_DRIVE_LOCK_DIR`.

   Results against that green:
   - test_drive_lock, test_checkpoint_readback, test_checkpoint_root_files and
     test_checkpoint_rename: **82 passed**.
   - sentinel-lock, drive-take, bin-commands and drive-cancel bats: **69/69 ok**.

   So no red row comes from broken test code or from a fixture that cannot work
   under the new design.
2. Mutants run against that green:
   - **`locked()` opens `<dir>/autodrive.lock`.** 9 rows red, among them both
     no-new-entry rows, the link row, the readback contention and refused-flock
     rows, and the root-files row.
   - **`wait` skips the device/inode comparison.** Exactly one row reds,
     `test_wait_refuses_a_descriptor_that_is_not_what_the_path_names`.
   - **`handoff_lock_take` drops the `-d` test.** Only
     `test_bash_take_is_unavailable_without_a_directory_and_never_blocks[fifo]`
     reds, through `subprocess.TimeoutExpired` after 30 s. See L1.
   - **checkpoint drops its `mkdir` of `.claude`.**
     `test_root_without_a_claude_directory_gets_one_for_the_sentinel` reds, in
     test_checkpoint_rename.py, which is unchanged. So contract point 2's
     "the checkpoint still creates `.claude/`" is pinned.
   - **Fail-open (`handoff_lock_take` returns 0 where it returned 2).** All five
     "the lock helper fails" rows red: report-drive-failure, load-handoff,
     load-compact, drive-take and handoff-approved. So the `fail_lock_helper`
     shim does let each actor reach its lock call, and each row asserts the
     fail-closed outcome: the sentinel byte-identical (`cmp`), the actor's
     message, and for load-handoff the frame (`hook smoke test` in CTX).
   - **No lock at all (`handoff_lock_take` returns 0 at once, and checkpoint
     skips `locked()`).** Every bats ordering and contention row reds, along
     with the five helper-fails rows. Within the four lock files that is
     sentinel-lock 1–5 and 7–16, handoff-approved 40–42 and drive-cancel 67–69.
     All four test_checkpoint_readback lock rows red under the no-lock
     checkpoint (`4 failed, 4 passed`).

   So the rows that are red today only because the holder fails do exercise
   their actor once the holder works. Each reds again when that actor's lock
   is removed.

## Findings

### L1 (low): the report misstates which rows kill the "drop the directory test" mutant

- Where: report, "Not pinned", 2nd bullet.
- The claim: the mutant "reds the absent and file rows".
- Against a green implementation it reds neither:
  - absent: `exec 9<` fails, so the take still returns 2.
  - file: `exec 9<` succeeds, but `wait` refuses the non-directory, so the take
    still returns 2.
- Only the FIFO row kills it, and it does so by a 30 s timeout. The claim holds
  only against today's code, which creates a file.
- Evidence (the M3 run):
  `FAILED tests/test_drive_lock.py::test_bash_take_is_unavailable_without_a_directory_and_never_blocks[fifo]`,
  `subprocess.TimeoutExpired ... timed out after 30 seconds`, `1 failed, 27 passed`.
- Fix: the commit body should record that the FIFO row kills this mutant, by
  timeout. No row needs to change.

### L2 (low): the bats red count is 16, not 20

- The report says 20 ordering and contention rows red across the four files.
- The full run has 16.
- Fix the report's count.

### L3 (low): load-compact's helper-fails row seeds a todo but never asserts it is injected

- Where: tests/sentinel-lock.bats:232.
- The row writes `- finish the parser` to TODO.md and asserts only MSG.
- The design (`docs/design/sentinel-lock.md:136`) names "the frame still
  injected" for the loaders.
- The gap is pre-existing: HEAD's link-at-lock row had the same assertions.
- Why low: the busy row at :190 pins frame injection on the same
  `lock_rc != 0` path.
- Fix: add `[[ "$CTX" == *"- finish the parser"* ]]`.

### L4 (low): contract points with no row, not named in the report

- **Contract 2, "`handoff_lock_take` is one spawn every time".** No row counts
  the spawns. `create` being gone (`test_the_create_command_is_gone`) removes
  the obvious second spawn, but nothing pins the count.
- **Contract 5, part 1: "every in-repo caller is patched, with no alias".** The
  constant row pins the new names and the value `.claude`. Nothing fails if
  `HANDOFF_REL_DRIVE_LOCK` stays as an alias.
- **Contract 5, part 2: "user-facing messages that named
  `.claude/autodrive.lock` name `.claude/`".**
  - Only checkpoint.py's two `lock:` stderr lines named it.
  - The rows assert `"could not be set up" in stderr` and the `lock: ` prefix,
    not the path.
  - With the pinned constant `.claude`, the natural green prints `(.claude)`,
    with no trailing slash.
  - Either pin the text or accept `.claude`.
- **Contract 6: "the plugin does not remove an `autodrive.lock` an earlier
  version left".** No row plants an old `.claude/autodrive.lock` and asserts it
  survives a checkpoint or a take.

These are low because nothing in the tests pushes a green implementer toward
the wrong behaviour. They should be named in the report's "Not pinned", or
pinned, at the orchestrator's choice.

## Checked and found sound

- **Sleeps and polls.** None added. `take_in_bash`'s `timeout=30` is a bound on
  a hang, not a wait. Every ordering row still uses the blocked-file FIFO.
- **Skips.** None.
- **Lost coverage.** These are the deleted or replaced rows checked against
  `git show HEAD:`:
  - The `0600` mode assertions are moot: no file exists.
  - The old `directory` and `no_dir` shapes became `absent` and `file`.
  - The five link-at-lock actor rows became helper-fails rows. All five red on
    fail-open.
  - The checkpoint's link row became a refused-`flock` row. It reds on
    fail-open (returncode) and on the lock-file mutant.

  No row was dropped without a replacement.
- **Conventions.**
  - `fail_lock_helper` is used by three bats files and lives in
    `tests/lock-helpers.bash`.
  - `claude_dir`, `run_wait` and the checkpoint wrapper each have one caller and
    stay in their files.
  - The `_session_id` pytestmark is unchanged.
- **The shim seam.**
  - The shim matches `*_drive_lock.py*` in its arguments and passes every other
    `python3` call through, so the sentinel reader and `worktree_root.py` run
    for real.
  - Today the shim fails `create`. After green it fails `wait`. Both are lock
    calls.
  - A green implementation that ran the helper other than as
    `python3 … _drive_lock.py` would red these rows (the real lock succeeds and
    the actor consumes the sentinel). That couples the rows to the invocation
    form, which the contract leaves unchanged.

END OF REVIEW
