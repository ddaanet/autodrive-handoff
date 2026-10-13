# The test harness sheds git's environment

2026-10-13.

## The defect

`make_repo`, `make_gitlore_repo` and `run_checkpoint` in `tests/conftest.py`
passed the whole process environment to git and to `checkpoint.py`. gitlore's
pre-commit hook runs `just precommit` with `GIT_DIR`, `GIT_INDEX_FILE` and
`GIT_WORK_TREE` exported for the outer repository, and git obeys those over
`cwd` and `-C`: `git init` in a builder reinitialised the outer repository
instead of creating one under `tmp_path`, and the checkpoint's own git reads
(the memory directive's gate) read the outer repository's state, so a row could
pass or fail on the repository being committed rather than the one it built.

Two smaller things in the same file: `_run_checkpoint_no_session_id` was a copy
of `run_checkpoint` differing in one environment variable, and `task_content`
and `todo_content` returned their argument unchanged, wrappers from a payload
shape that has since become a bare string.

## The change

- `git_free_env()` is the environment minus git's repository-local variables,
  read from `git rev-parse --local-env-vars` (once), a superset of the three
  the hook exports. Both builders pass it to every git call, and
  `run_checkpoint` starts from it.
- `run_checkpoint` takes `with_session_id=False` for a run with no
  `CLAUDE_CODE_SESSION_ID`; `_run_checkpoint_no_session_id` is gone and its
  callers use the flag.
- `task_content` and `todo_content` are gone; every call is its argument.

## Rows

`tests/test_checkpoint_directives.py` builds a decoy repository with a staged
file, exports the three variables at it, and then: `make_repo` must create its
own `.git` and leave every byte under the decoy's `.git` as it was; a dirty
gitlore memory must still produce the memory directive through `run_checkpoint`,
the decoy untouched. Red before the change: `make_repo` made no `.git` (the
init went to the decoy), and the checkpoint printed the clause-file refusal
read from the decoy's config instead of the directive. Mutations: dropping the
scrub from `make_repo`'s init, and starting `run_checkpoint` from the raw
environment, each red their row.

## Left

The test files' own git calls (`test_checkpoint_composition.py` 3,
`test_checkpoint_directives.py` 6, `test_checkpoint_hold.py` 1,
`test_checkpoint_legacy.py` 7, `test_mod_live.py` 1) still inherit the
environment; they act on repositories the builders made, through `cwd` or
`-C`, which the exported variables override the same way.
