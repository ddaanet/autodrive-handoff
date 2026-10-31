---
paths:
  - "tests/**"
---

# Test conventions

A test's coverage is stated in the test file, in its rows, comments and
docstrings, not in `CLAUDE.md` or here.

- Tests live under `tests/`. A new scenario goes into the existing `.bats` or
  `test_*.py` file for what it covers; add no new `just` recipe. The test
  recipes (`hook-test`, `py-test`, `mod-smoke`) are one-liners that delegate.
- A bats file covers one hook or library part, against synthetic tool-event
  payloads; a hook with many rows splits across files named after it.
- A helper two or more files call goes in the shared helper for its suite:
  `tests/hook-helpers.bash` (with `setup` and `teardown`) for the hook files,
  `tests/checkpoint-helpers.bash` (`setup`, `make_repo`) for the three bash
  files around the checkpoint, `tests/conftest.py` for pytest. A helper only
  one file calls stays in that file. pytest's `pythonpath` carries `tests/`,
  so test files import from `conftest.py` by name.
- The `_session_id` fixture is not `autouse`: each `tests/test_checkpoint_*.py`
  applies it with a module-level `pytestmark`, a new one included.
- Every git call goes through `run_git` (`tests/probe-helpers.bash` in bats,
  `tests/conftest.py` in pytest) under `git_free_env`: git minus its
  repository-local variables (`git rev-parse --local-env-vars`), since a gate
  run from inside a git hook inherits `GIT_DIR`, `GIT_INDEX_FILE` and
  `GIT_WORK_TREE` for the outer repository.
- No lock row sleeps or polls. An ordering row holds the lock from a
  background process (`tests/lock_holder.py`, through
  `tests/lock-helpers.bash` in bats) and changes the sentinel only once the
  actor reports through `HANDOFF_LOCK_BLOCKED_FILE`, the one test-only seam,
  that it waits. A contention row holds the lock with a 0.05 s wait and
  asserts the sentinel byte-identical and the fail-closed report. Each actor's
  lock rows sit with that actor's tests. See `docs/design/sentinel-lock.md`.
- `tests/test_drive_lock.py` asserts each lock-taking hook's `timeout` in
  `hooks/hooks.json` against the lock's default wait: change them together.
- Each state gate is paired with the positive row over the same fixture.
- A load-bearing row is mutation-checked: a mutant of the code it pins turns
  it red. The mutant is recorded in the changelog entry or plan report of the
  change, not here. Where no test can red a mutant, name the residual bound
  (the prompt marker read's `own` argument: no unprivileged test can make a
  marker another user owns).
- `tests/validate-plugin.bats` runs the real recipe under a stub `claude`
  printing a fixture. `version-guard.sh` is tested in the toolkit, not here.
