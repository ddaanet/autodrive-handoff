---
paths:
  - "scripts/**/*.sh"
  - "bin/*"
  - "tests/**/*.bats"
  - "tests/**/*.bash"
---

# Bash conventions

- `_lib.sh` is the one file a caller sources. It sources its three parts,
  `_lib_frame.sh`, `_lib_drive.sh` and `_lib_files.sh`; a part is never
  sourced by a caller.
- Above every `source` of `_lib.sh` goes
  `# shellcheck source-path=SCRIPTDIR source=_lib.sh` (from `bin/` and
  `tests/`, `source=../scripts/_lib.sh`), so `shellcheck -x` follows it. A
  test file sourcing a helper carries the same form naming the helper
  (`source=hook-helpers.bash`, `source=checkpoint-helpers.bash`).
- Inside `_lib.sh`, the nested `source` of a part carries
  `# shellcheck source-path=SCRIPTDIR/../scripts source=<part>` instead: a
  bare `SCRIPTDIR` resolves against the top-level script's directory, so from
  `bin/` and `tests/` shellcheck would silently skip the part.
- `# shellcheck disable=SC2034` goes on a variable only sourcing scripts read.
  The three `_checkpoint_*.py` modules are imported, not sourced, so none of
  this applies to them.
- Bash 3.2: parse with a `read` loop, never `mapfile`, and expand an array
  that may be empty as `${A[@]+"${A[@]}"}`.
- A field that can hold any string is read NUL-terminated (`read -r -d ''`).
  A `$(...)` capture strips a trailing newline, so a path is never printed to
  be captured: the root resolver answers NUL-terminated into variables.
- Hooks are mechanical and cwd-scoped. Every one anchors on
  `handoff_root_read` (the enclosing git-worktree root, else
  `CLAUDE_PROJECT_DIR`), never on the raw hook-input `.cwd` (drift-prone) nor
  on `CLAUDE_PROJECT_DIR` directly (pinned to the main tree in a worktree
  session). See `docs/design/scoping.md`.
- In bats, `run` captures the exit code and output without the `set +e`
  dance (`tests/bats-best-practices.md`). A function that answers in
  caller-scope variables, such as `handoff_frame`, is called directly, never
  through `run`, which runs it in a subshell.
