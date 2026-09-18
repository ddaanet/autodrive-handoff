# Item 3.1, slices 2–5 — test review

Mode: test review (TDD step b). Repo: /Users/david/code/handoff. SUT untouched
(`git diff --quiet scripts/` true before, between and after every mutation).
Nothing committed.

## Verdict

The rows are accepted, with one fix applied to slice 2 (below). The deviation
is justified: the SUT landed in 3.1/1, so these rows pass unmutated, and the
mutations below are the red evidence. Slice 5 still earns its place. The
refusal-guard mutation in the runbook doesn't match the SUT's shape. Under the
mutation that does match it, slice 5's row reds and nothing else does.

## Fixes applied (`tests/test_checkpoint.py` only)

1. **Slice 2 didn't check that the fixture was armed, or that the closing line
   was the only thing printed.** It asserted `startswith("End on one line")`
   and one substring. With that, a checkpoint that printed the closing line and
   then more parts (for example, the arming instruction) would still pass. It
   also never checked that the sentinel was `armed`, which is the reason given
   for "the closing line is the only part". I added:
   `autodrive` line 1 `== "armed"`, and `assert_stdout_is_closing(result,
   skill, typed=typed)` (slice 1's helper: `closing_directive` is non-empty,
   and stdout equals it plus `\n`). I kept the substring checks, since they pin
   the content per cell, which the exact-equality check alone would only get
   from the function under test. Mutation M7 below confirms the fix.
2. **ruff FBT001** on slice 2's `typed: bool` positional parameter
   (`just precommit` would have failed on it). I made it keyword-only
   (`skill: str, *, typed: bool`). Pytest passes parametrized arguments by
   keyword, so this works.

I checked slice 5's armed fixture. Its test already asserts `autodrive` line 1
`== "armed"`, and that `refusal.text != ""` and `refusal.refusal` hold, before
the exact-stdout assertion. Nothing needed adding.

Slice 2 runs through a real `run_checkpoint` subprocess in all four cells.
Clean `make_gitlore_repo` plus `without-commit` gives `M` false and `C` false,
so the hold rule gives `armed` in every cell. The new line-1 assertion now
pins that.

After the fixes: `ruff check`, `ruff format --check` and `mypy` are clean on
the file. Unmutated: `171 passed`. Targeted: `8 passed, 163 deselected`.

## Mutations reproduced

Each mutation was applied to `scripts/checkpoint.py:compose_directives` by
exact string replacement and reverted by the inverse replacement. After each
one the full `tests/test_checkpoint.py` was run, and `git diff --quiet
scripts/` was checked after each revert.

| id | mutation | failed rows |
|---|---|---|
| M2 | closing line gets `typed=False` | slice 2 `[handoff-True]`, `[precompact-True]` — only these |
| M3 (RED's form) | closing line appended before the `if held` block, unconditionally | slice 3's two rows only |
| M3′ | `else:` → `if True:` (closing appended *after* arming) | slice 3's two rows **plus** `test_arming_instruction_follows_every_other_part` |
| M4/5 | refusal branch returns `[memory.text, closing]` | slice 4's row and slice 5's row |
| M6 | refusal branch returns `[memory.text] + ([closing] if not ending.held else [])` | **slice 5's row only** |
| M7 | not-held branch appends arming after closing | 12 rows, including all four slice-2 cells (red only because of fix 1) |

M3′ is a note, not a defect. When the stray closing line lands after the arming
instruction, it also breaks the "arming is last" ordering row, which is
correct. The runbook's rule that "this row alone reds" holds for RED's
placement, which is the one that isolates the `held` gate.

## The deviation: why M4/5 reds slice 4, and whether slice 5 earns its place

In the SUT, `compose_directives` handles the refusal with an early return
(`if memory.refusal: return [memory.text]`) that runs before `ending.held` is
read. The `held`/closing branch is only reached for non-refusals. So there is
no "refusal guard on the closing-line branch" to drop. The runbook's mutation
assumed a structure the SUT doesn't have. Every mutation that adds the closing
line inside the refusal branch applies independently of hold state, so slice
4's held fixture catches it. That's why M4/5 reds both rows.

Slice 5 is there for a different possible defect: a refusal branch that still
leaves out the commit act and the arming instruction, but decides the closing
line by `held` the same way the normal path does. M6 is that defect. Slice 4's
fixture is held, so it suppresses the closing line either way and stays green.
Only slice 5's armed fixture shows the leaked closing line, and it reds on its
exact-stdout assertion. So slice 5 guards a defect no other row catches, and
it stays in. In this SUT, "drop the refusal guard from the closing-line
branch" means M6.
