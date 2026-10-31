# Fixes for review-45bda99 (M1-M4)

- M1 (`tests.md`, git bullet): SKIPPED. `git_free_env` exists only in `tests/conftest.py`; `tests/probe-helpers.bash` has no such name, its `run_git` does the `--local-env-vars` unset inline. The decided sentence ("Every git call runs under `git_free_env` ... `run_git` ... applies it" for bats too) is false for bats, so I did not improvise wording. Bullet left as it was.
- M2 (`tests.md`, helper bullet): APPLIED. Four `tests/*-helpers.bash` exist (`checkpoint`, `hook`, `lock`, `probe`), each shared: `hook-helpers` by ~20 `.bats` files, `checkpoint-helpers` by 3, `lock-helpers` by `drive-take.bats`, `sentinel-lock.bats` and `checkpoint-helpers`, `probe-helpers` by `checkpoint-helpers` (`load probe-helpers`). `hook-helpers.bash` defines `setup` (line 15) and `teardown` (line 47).
- M3 (`tests.md`, lock bullet): APPLIED. Deleted only "Each actor's lock rows sit with that actor's tests."; the closing "See `docs/design/sentinel-lock.md`." stays.
- M4 (`mod.md`, mod reads neither): APPLIED. `hooks/handoff.ts` runs `bash .../scripts/drive-take.sh` via `$.process.run`, `JSON.parse`s its stdout and executes the plan lines; it never reads the sentinel's content (file header: "The sentinel is never read here"). Caveat: `drive()` does call `$.fs.exists(sentinel)` as a fast-path existence check, which the sentence's "reads" does not cover.

Precommit: `precommit: check-plugin check-code passed` (exit 0; check-plugin and check-code cached, check-refs ran: resolves 261 references in 34 files).

Line counts: `.claude/rules/tests.md` 45, `.claude/rules/mod.md` 49. No line over 80 characters in either.

M1, applied afterwards by the main session in other wording: in bats every
git call goes through `run_git` (a grep of `tests/*.bats` and `tests/*.bash`
finds no bare call), and in pytest it passes `env=git_free_env()`, directly
(the `conftest.py` builders) or through `run_git`.
