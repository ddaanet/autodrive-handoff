# Step 2 (Checkpoint migration) — RED review fixes

Changed: `tests/test_checkpoint.py` only (no `scripts/`, `bin/`, no staging, no
commits). `ruff check scripts tests`, `ruff format --check scripts tests`,
`docformatter --check scripts/*.py tests/*.py`, `mypy`, `ty check`: all clean.

## Counts

| `pytest -q tests/test_checkpoint.py` | rows | passed | failed |
|---|---|---|---|
| before this pass (step2-red state) | 301 | 233 | 68 |
| after | 309 | 235 | 74 |

8 rows added: 6 red, 2 expected-green guards. The 68 earlier failures are the
same 68 (diffed by node id); all 233 earlier passes, including the 21 listed
guards, still pass. The changed tail rows are still red/green exactly as
before (the 8 ids of `test_reports_come_first_and_the_tail_stays_last` still
fail on the missing report; `test_stdout_with_no_legacy_file_anywhere_is_what_it_was`
still passes).

## Rows added or changed

| finding | row | line | kind |
|---|---|---|---|
| F1 | `test_checkpoint_leaves_a_tracked_legacy_file_to_the_printed_git_act` x [without-commit, with-commit] (helpers `git_status_lines`, `run_printed_git_rm`) | 3486 (helpers 3455, 3467) | new, red |
| F2 | `assert_directive_tail` now takes `held` and asserts `drive_state()` against it; `test_reports_come_first_and_the_tail_stays_last` computes `held = typed and commit == "with-commit"`; `test_reports_precede_every_directive_part` passes `held=True`; `test_stdout_with_no_legacy_file_anywhere_is_what_it_was` computes the same and asserts `drive_state()` | 2833, 3302, 3332, 3401 | changed in place, no new row |
| F3 | `test_autoname_leaves_legacy_files_alone_and_reports_nothing` x [root_absent, root_with_body] | 3649 | new, guard |
| F4 | `test_keep_moves_the_legacy_todo_with_its_modification_time` | 2876 | new, red |
| F5 | `MOVED`/`REMOVED`/`IGNORED` are `re.compile(..., re.IGNORECASE)`, `\b` kept; block comment updated | ~2704 | changed |
| F6 | `test_edit_that_strikes_the_last_item_of_a_legacy_only_todo_leaves_no_legacy_file` | 3090 | new, red |
| F7 | path order kept (task before todo); comment above `GIT_RM` states both GREEN constraints | ~2710 | comment |
| Decision 1 | `test_reports_and_the_git_rm_act_print_ahead_of_the_clause_file_refusal` x [without-commit, with-commit] | 3362 | new, red |

## Newly red rows and the assertion each fails on today

| row | fails at |
|---|---|
| `test_keep_moves_the_legacy_todo_with_its_modification_time` | `assert read(TODO.md) == TODO_LEGACY_BODY` (`None`); the mtime assertion follows it |
| `test_edit_that_strikes_the_last_item_of_a_legacy_only_todo_leaves_no_legacy_file` | `ok(result)`: `returncode == 2`, stderr `edit requested but TODO.md does not exist` |
| `test_checkpoint_leaves_a_tracked_legacy_file_to_the_printed_git_act[both]` | `assert read(TODO.md) == TODO_LEGACY_BODY` (`None`); the index (` D`, `?? TODO.md`) and rename (`R  ...`) assertions follow it |
| `test_reports_and_the_git_rm_act_print_ahead_of_the_clause_file_refusal[both]` | `assert read(TODO.md) == TODO_LEGACY_BODY` (`None`); report, order and refusal assertions follow it |

The assertions after the first one are the ones that discriminate. They can
only be reached by an implementation that moves the file, so they are proven by
the reference and its mutants below, not by the red run.

## Guards that pass today (paired with a positive over the same fixture)

- `test_autoname_leaves_legacy_files_alone_and_reports_nothing[root_absent]`.
  Positive: `test_legacy_todo_with_no_root_file_is_moved_to_the_root_name[keep-plain]`
  (same legacy fixture under `handoff`).
- `test_autoname_leaves_legacy_files_alone_and_reports_nothing[root_with_body]`.
  Positive: `test_root_todo_with_a_body_wins_and_the_legacy_file_is_reported_ignored`
  (same fixture under `handoff`). No mutant exercises this id: the autoname
  mutant below only reds `root_absent`. It guards "autoname reports ignored
  files", which was not mutated.
- The held/armed assertions added to the F2 rows are not separate rows; they
  fail only with a migration that changes the state (see `migration_forces_held`).

## Mutation results (reference implementation, scratch copy)

Reference: `$TMPDIR/ref` (the review's reference), with `compose_directives`
extended so a refusal prints `[reports, git-rm act, refusal]`. The full file
passes against it: 309/309. Mutants run over the 89 migration rows, two
pre-existing autoname rows and the 8 new ones (97 rows). Harness:
`$TMPDIR/rev/mut.py`, `mut2.py`; each edit asserted to land once; identity: 0 failed.

| mutant | result |
|---|---|
| checkpoint runs `git rm --cached` itself (NFR1) | killed by the 2 F1 ids (was a survivor) |
| `autoname` migrates the todo | killed by `...autoname_leaves_legacy...[root_absent]` (was a survivor) |
| migration forces `held` | killed by 6 of 8 `...tail_stays_last` ids (untyped/typed combinations that are not held anyway cannot differ: the 2 typed+with-commit ids are held either way), plus `test_a_second_identical_call...`; it is now the explicit assertion, not the incidental one (was incidental) |
| move by `write_bytes` + unlink (loses mtime) | killed by the F4 row (was a survivor) |
| reports capitalised (`Moved ...`) | no longer killed (97 rows pass): F5 |
| refusal prints alone (today's behaviour) | killed by both clause-file ids |
| refusal: act after the refusal | killed by `[with-commit]` |
| refusal: reports after the refusal | killed by both ids |
| refusal: git-rm act dropped | killed by `[with-commit]` |

All four review survivors are killed, and the rows are jointly satisfiable
(309/309 against the reference).

## Ordering assumption for the clause-file refusal (GREEN must implement)

Decision 1, default (a). When `memory.refusal` fires, stdout is, in order:
the migration reports, then (with-commit only, and only for moved/removed legacy
files) the git-rm act, then the refusal text as the last thing printed. The
files are still written and moved first (the checkpoint still exits 0, state
`armed` or `held` as before). Today's `compose_directives` returns
`[memory.text]` and drops everything else; GREEN must change that branch.

## Interface additions GREEN must know

- The with-commit git act must be printable WITHOUT the rest of the commit act.
  The refusal row asserts only `git rm --cached --ignore-unmatch -q -- <path>`
  before the refusal. The usual commit sentence ("Once everything above is done,
  make the commit...") must not print ahead of a refusal (the existing
  `test_clause_refusal_is_followed_by_no_commit_or_arming` still requires
  `commit_directive()` text be absent). So the act needs its own function or
  `commit_directive`'s legacy part must be separable; the reference splits it
  in the refusal branch.
- `lib.commit_directive`'s legacy-paths parameter must be optional (the rows
  call it with no argument). Comment above `GIT_RM`.
- A legacy path named on any non-`git rm` line is one report: the act must
  carry its paths on the `git rm` line (a continuation line naming a path fails
  the one-report rows). Same comment.
- Action words are matched case-insensitively now (`Moved ...` is fine).
- `run_printed_git_rm` extracts the paths after the literal `git rm ... --` on
  the act's line: space-separated, optionally followed by punctuation or a
  backtick, nothing else between the literal and the paths.
- The move must be a rename (`os.replace` or equivalent that keeps the mtime);
  nothing in the checkpoint may stage or `git rm` anything (index untouched,
  tested over a tracked legacy file); `autoname` must not touch or report
  legacy files; migration must not change the held/armed state.

## Decisions 2 to 5

Accepted as the review's defaults, no test change: (2) the git-rm act is owed
only to the call that moved the file, say so in the step 3 docs; (3) "moved" or
"removed" both accepted for a content write over a legacy-only half; (4)
task-before-todo order of the act's paths kept; (5) the split of
`tests/test_checkpoint.py` (now 3.7k lines) is a separate `TODO.md` item, not
done here.
