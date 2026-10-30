# Dispatch protocol for the line-cap split

My human partner chose parallel step agents over `plan.md`'s single sequential
executor. All work lands on branch `line-cap-split` in the one working tree at
`/Users/david/code/handoff`, and every commit shares one index. So the work runs
in two phases. Phase A runs in parallel, each step in a private copy. Phase B
runs one step at a time in the real tree, when the orchestrator grants the slot.

Read `plan.md` beside this file first: its Invariants, your step, and its
Verification.

## Fixed facts

- Repo: `/Users/david/code/handoff`, branch `line-cap-split`, cut from `dev` at
  `c2fff7c`. Never create, switch or delete a branch or a worktree.
- Baselines at `c2fff7c`: `@test` counts are hook-test 289, checkpoint 42 and
  drive-take 21. `pytest --collect-only -q` gives `520/523 tests collected (3
  deselected)`. `tests/test_checkpoint_hold.py` has 25 `def test_` (27
  collected), and `tests/test_checkpoint_transition.py` has 26 (101 collected).
- Verbatim checker: `python3 -I /tmp/claude/line-cap-split/verbatim-check.py
  OLD... -- NEW...`. Each argument is a path, or `REV:PATH` read through `git
  show` in the current directory's repository. It compares `@test` blocks (in
  `.bats` files) or top-level `def test_*` blocks with their decorators (in
  `.py` files), by name. It exits 1 on a missing, extra, repeated or changed
  block. It does not see helpers, `setup` or comments, so those are checked by
  the tests running green.
- Python env, since your shell has no direnv: run `export
  VIRTUAL_ENV=/Users/david/code/handoff/.venv
  PATH=/Users/david/code/handoff/.venv/bin:$PATH` in each Bash call that runs
  pytest, ruff, mypy, ty, docformatter or `just`.
- Your scratch directory is `/tmp/claude/line-cap-split/step-<n>/`. Use it
  rather than `$TMPDIR`, which does not survive between calls.
- Your report goes to `plans/2026-10-30-line-cap-split/reports/step-<n>.md` in
  the real tree. It is the one file you write there during phase A. Do not stage
  or commit it.

## Phase A: in parallel, in your copy

1. Create the copy:

   ```sh
   D=/tmp/claude/line-cap-split/step-<n>/repo
   mkdir -p "$D" && git -C /Users/david/code/handoff archive c2fff7c | tar -x -C "$D"
   git -C "$D" init -q && git -C "$D" add -A && git -C "$D" tag base "$(git -C "$D" write-tree)"
   ```

   Use that tree, not `HEAD`: `HEAD` moves as other steps commit.
2. Do your step in `$D`, including the edits to the shared files: `CLAUDE.md`,
   `justfile` and `docs/design/`. Find the references by grepping the old names
   outside `plans/`, `docs/changelog/`, `TASK.md` and `TODO.md` (the last two
   are the session's frame; leave them alone). Load the
   `craft:design-doc-writing` skill before touching `docs/design/`. Leave any
   reference that sits inside a file another step splits: `scripts/_lib.sh`,
   `tests/hook-test.bats`, `tests/checkpoint.bats`,
   `tests/test_checkpoint_hold.py`, `tests/test_checkpoint_transition.py`,
   `tests/bats-best-practices.md` and `tests/mypy-guidelines.md`. Phase B
   catches those.
3. Verify in `$D`. Run the verbatim checker from `/Users/david/code/handoff`,
   with `c2fff7c:<old file>` against `$D/<new files>`, and compare the counts.
   Run the suites your files belong to (`bats <files>`, `pytest <files>`), then
   `shellcheck -x` on any shell you touched and `ruff check`, `ruff format
   --check`, `docformatter --check`, `mypy` and `ty check` on any Python you
   touched (run mypy and ty from `$D`). Also run the line count from the plan's
   Verification on every file you created or edited. `just precommit` is not
   run in the copy.
4. Write the report: what moved where, the file names you chose and why, every
   reference you updated, the check outputs (the checker's last two lines, the
   counts, the suite results and the line counts), and any departure from the
   plan's text with the reason. A departure that is a design choice rather than
   a mechanical consequence: stop and ask in the report instead of making it.
5. Reply with one line pointing at the report, then stop. Phase B waits for a
   message from the orchestrator.

Never write inside `/Users/david/code/handoff` in phase A except the report.

## Phase B: one step at a time, in the real tree, on the orchestrator's message

1. `cd /Users/david/code/handoff && git status --short`. Only the sandbox masks
   may show: untracked dotfiles (`.bashrc`, `.zshrc`, `.gitconfig`,
   `.profile`, `.claude/*` …), plus untracked files under
   `plans/2026-10-30-line-cap-split/`, plus ` M memory` (the memory gitlink,
   moved by a memory publish; the orchestrator commits it at the end), plus
   ` D TASK.md` and ` M TODO.md` (the session frame, rewritten by a
   checkpoint). Leave all of these alone, and never stage any of them. Anything else modified means
   another step is mid-flight: stop and report.
2. Export your change and apply it:

   ```sh
   D=/tmp/claude/line-cap-split/step-<n>/repo
   git -C "$D" add -A && git -C "$D" diff --cached --binary base > /tmp/claude/line-cap-split/step-<n>.patch
   git -C /Users/david/code/handoff apply --3way /tmp/claude/line-cap-split/step-<n>.patch
   ```

   `--3way` stages the result. A conflict in a shared file, against a step that
   landed since `c2fff7c`, is resolved by hand so that both edits survive, then
   staged.
3. Grep the real tree again for your old names, with the same exclusions, and
   fix every hit wherever it now sits, including in files another step has since
   split. Then re-run the verbatim checker against `HEAD:<old file>` and the
   counts, now in the real tree.
4. `just precommit`, with `dangerouslyDisableSandbox: true` because it calls
   `claude`, and with the Python env exported. It has to be green. Never use
   `--no-verify`.
5. Check `git diff --cached --stat` and confirm it holds your paths only. Then
   commit with `git commit -F -` and a quoted heredoc. The subject is gitmoji
   style and lower case, like `♻️ split _lib.sh into three sourced parts`. The
   body names the plan, `plans/2026-10-30-line-cap-split/plan.md`, and says why
   in a line or two, without narrating the diff. Add no trailer.
6. Append the commit sha and the precommit recap to your report, then reply with
   one line.

## Decided during the run

- **A shared bats helper is sourced, not `load`ed.** Shellcheck does not follow
  bats' `load`. So a `.bats` file whose `setup` moved into a helper raises
  SC2154 on every variable that `setup` assigns. Step 2's first cut silenced
  that with a file-wide `disable=SC2154` in all 17 files, where
  `hook-test.bats` had none. A probe on step 2's copy: with `load` and no
  disable, there were 44 SC2154. With `# shellcheck source-path=SCRIPTDIR
  source=<name>-helpers.bash` above `source
  "$BATS_TEST_DIRNAME/<name>-helpers.bash"`, there were none, shellcheck
  followed through to `_lib.sh`, and the tests stayed green. Steps 2 and 3 use
  that form. A file-wide SC2154 disable stays only where the original file had
  one, with its reason: `$stderr` in the `handoff-approved` file. Following
  the helper can raise a code the original file never saw: step 3 met SC2119
  on 16 argument-less `make_repo` calls in `tests/bin-commands.bats`, whose
  calls with a path had moved to a sibling, and added a file-wide disable with
  its reason. Such a directive is added in the narrowest form that covers the
  hits, always with its reason, and listed in the step's report.
- **The gate lints `tests/*.bash`.** The helpers now hold code that the gate's
  `shellcheck -x … tests/*.bats` used to check. So whichever of steps 2 and 3
  lands first adds `tests/*.bash` to `check-plugin`'s shellcheck line and to
  `CLAUDE.md`'s description of it. The existing helpers are already clean.

## Review (reviewer agents)

Each commit gets a reviewer, at the bar of `/code-review medium`. The reviewer
reports findings and fixes nothing until the orchestrator triages them and
grants a phase-B slot.

The reviewer works read-only against the commit, `git show <sha>` in
`/Users/david/code/handoff`. The tree may hold another step mid-commit, so
nothing is read from the working tree. It checks:

1. The invariants, re-run independently: the verbatim checker on `<sha>^:<old
   file> -- <sha>:<new file>...`, the `@test` and `def test_` counts on both
   sides, and the line count of every file the commit creates or edits (`git
   show <sha>:<path> | wc -l`, at most 400). For a commit touching Python, it
   also checks `pytest --collect-only -q` on the commit. Export the commit to
   `/tmp/claude/line-cap-split/review-<n>/` (`git archive <sha> | tar -x -C …`)
   and run it there with the Python env exported, expecting
   `520/523 tests collected (3 deselected)`.
2. Content that is not a test block, which the checker cannot see: helpers,
   `setup`/`teardown`, comments and section prose. Each must survive exactly
   once, and a helper must sit where the plan's helper rule puts it.
3. References: grep `<sha>` (`git grep <old name> <sha> -- . ':!plans'
   ':!docs/changelog' ':!TASK.md' ':!TODO.md'`) for a stale mention of a moved
   file or row. Each prose edit must still be true of the code.
4. Correctness of anything that is not a verbatim move: sourcing, `load` lines,
   imports, `pytestmark`, the shellcheck directives, the `justfile` recipes.

Severity follows `memory/ddaanet/shared-claude.md`. A finding is high or medium
when a reader or runner following the text would do the wrong thing. Phrasing
and placement are low. The report goes to
`plans/2026-10-30-line-cap-split/reports/step-<n>-review.md`: each finding with
its file and line, the evidence, and a proposed severity, followed by the
outputs of the re-run checks.

## Outcome

The five steps landed in the order 5, 1, 4, 3, 2, each through its own phase-B
slot with `just precommit` green. Each step's commit had an Opus review
(`reports/step-<n>-review.md`). Steps 5, 1 and 4 drew lows only, all declined.
Step 3 drew one medium, the helper's header saying its files `load` it, fixed
on the main thread. Step 2 drew two mediums, a helper comment stranded in the
wrong file and two `CLAUDE.md` claims, fixed by a fresh agent
(`reports/step-2-fix.md`). Both fixes are doc drift, with no re-review. Step 2's
phase B went to a fresh agent because its phase-A agent had passed 150k tokens.

At the branch tip, the plan's Verification scan lists only
`tests/test_checkpoint_legacy.py` and `CLAUDE.md`. The checker over
`c2fff7c:tests/hook-test.bats` and `c2fff7c:tests/checkpoint.bats` against the
20 new `.bats` files gives 331 blocks on each side. Exactly one is changed, the
`-I` row, which step 1 changed on purpose. The two pytest pairs give 51 blocks
and `verbatim: OK`.
