# checkpoint.py — move `main` to the top

Task: apply the repo's "entry points first" convention to
`scripts/checkpoint.py` — move `main` directly after the module docstring,
imports and anything that genuinely must precede it, leaving everything else
untouched. Pure move only.

## Where `main` was, where it is now

- Before: `def main() -> int:` at line 635 (of 680 total), just above the
  `if __name__ == "__main__":` block at line 679.
- After: `def main() -> int:` at line 52, immediately after `_LIB_SH = ...`
  (line 49) and before `class Transition(NamedTuple):` (now line 56, was
  line 52). The `if __name__ == "__main__": raise SystemExit(main())` block
  stays at the very bottom (now lines 679–680) — same two lines, same
  position relative to EOF, since the invocation must run after every name
  `main` calls is defined.
- File is still 680 lines total, confirming this was a pure relocation with
  no line added or removed.

## What stays above `main`, and why

Only what was already above it and is a genuine evaluation-order
dependency of the module's structure, none of it because of `main` itself:

- Shebang, module docstring, `from __future__ import annotations`, and the
  stdlib/third-party imports plus `import _checkpoint_lib as lib`.
- `JSONDict = dict[str, Any]` — a module-level type alias.
- The three `HANDOFF_REL_*` string constants and `_LIB_SH`.

`main`'s body calls `read_payload`, `validate_root`, `validate_skill`,
`validate_top_level_keys`, `validate_autoname_forbidden_fields`,
`validate_restart_forbidden_fields`, `validate_commit_mode`,
`validate_rename`, `build_transition`, `validate_continuation`,
`validate_task`, `validate_todo`, `plan_task`, `plan_todo`, `apply_plan`,
`write_manifest`, `lib.MemoryPart`, `lib.memory_directive`, `hold_decision`,
`compose_sentinel`, `Ending`, `compose_directives`, `print_output` — none of
these are resolved until `main()` actually runs (called only from the
`if __name__ == "__main__":` line at the bottom), so none of them needed to
move up. The file has `from __future__ import annotations` (line 23), so
`main`'s `-> int` return annotation is never evaluated at import time either
— no decorator and no non-string annotation issue applies here.

No layout comment anywhere in the file described "main is at the bottom" or
similar, so nothing needed rewording.

## Cross-check: does anything import `checkpoint` as a module?

`grep -rln "import checkpoint\|from checkpoint" --include='*.py' .` from the
repo root returned nothing. `scripts/checkpoint.py` is invoked as a script
(via `bin/handoff-checkpoint`), not imported as a Python module anywhere in
the tree, so the move cannot break an import-time dependency.

## Linter output

```
$ ruff check scripts/checkpoint.py
All checks passed!

$ ruff format --check scripts/checkpoint.py
1 file already formatted

$ docformatter --check scripts/checkpoint.py
(rc=0, no output)

$ mypy scripts/checkpoint.py
(rc=0, no output — mypy's default success is silent)

$ ty check scripts/checkpoint.py
All checks passed!
```

## pytest output

```
$ pytest tests/test_checkpoint.py -q
........................................................................ [ 41%]
........................................................................ [ 83%]
............................                                             [100%]
172 passed in 60.78s (0:01:00)
```

All green on the first run — no need for the "rerun a minute later" fallback
for the concurrent memory-refusal-wording change. Note: CLAUDE.md's own
description of this suite says "171 tests"; this run reports 172, presumably
because the concurrent agent (working in `scripts/_checkpoint_lib.py` +
`tests/test_checkpoint.py`) has added a row for the refusal-wording change.
Not something this task touched or needs to reconcile.

## Purity check

```
$ git diff --stat
 scripts/_checkpoint_lib.py |  4 +--
 scripts/checkpoint.py      | 88 +++++++++++++++++++++++-----------------------
 tests/test_checkpoint.py   |  7 ++++
 3 files changed, 53 insertions(+), 46 deletions(-)
```

(`_checkpoint_lib.py` and `test_checkpoint.py` are the concurrent agent's
files, not touched by this task — `scripts/checkpoint.py` is the only file
this task edited.)

```
$ diff <(git show HEAD:scripts/checkpoint.py | sort) <(sort scripts/checkpoint.py)
(empty)
```

The sorted-line multiset is byte-identical between `HEAD` and the working
tree — confirms the change is a pure reordering of existing lines with
nothing added, removed, or reworded (and no layout comment needed fixing, so
there's no divergence to explain in that diff).

## Anything surprising

Nothing. `main`'s only callers/dependents live below it structurally in the
original file but are all late-bound name lookups resolved at call time, so
the move required no other reordering, no signature/decorator/default
changes, and no constant promotion above `main`. The task's "do not reorder
anything else" constraint was easy to satisfy since nothing else needed to
move.
