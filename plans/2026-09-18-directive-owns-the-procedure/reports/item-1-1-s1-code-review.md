# Item 1.1, slice 1/1 — code review

Scope: `scripts/_checkpoint_lib.py`, `scripts/checkpoint.py` as changed by
411f2c7. The fix below is applied and not committed.

## Findings

### Major (fixed): the commit act's closing phrase misreads in both cells

The old text was "Make the commit now, in whatever shape the request called for,
before what follows here runs."

- "what follows here runs" does not fit either successor. Held, the part after
  it is the arming instruction, which the agent runs. Not held, it is a closing
  line, which the agent says and does not run. So the phrase is right in one
  cell and wrong in the other. It also leaves "here" undefined for a fresh
  reader.
- The ordering it tries to state is already settled. The skill tells the agent
  to follow the printed parts in order (outline step 3), and the arming
  instruction will say "everything above" (R4). Per craft:directive-writing,
  restating a settled ordering is a cut ("what an earlier step already
  settled").
- "in whatever shape the request called for" is wordier than the act the
  outline gives: "make the commit the request asked for".

New text: **"Now make the commit the request called for."** It is one act with
no git verb and no mechanism, and it still contains `commit`. "Now" gives the
placement.

The docstring also lost its "States the act and its place… before what follows
here runs" sentence, since the text no longer says that. It keeps the
maintainer constraint (no git verb, because the request may call for an amend
or a fresh commit).

### Noted, not a defect of this slice

- Held cells print the parts in the wrong order until slice 1.1/4. Today
  `compose_sentinel` appends the arming text to the memory part, so a held
  `with-commit` cell prints memory+arming, then the boundary/nudge, then the
  commit act. That puts "run `handoff-approved`" ahead of the commit. Slice 4
  fixes it, as expected, but don't dogfood a held `with-commit` boundary from an
  intermediate commit.
- `print_output` puts two blank lines between parts. Each part already ends in
  `\n` from `_printf_lines`, and the join adds `\n\n`. This matches the old
  output byte for byte and the GREEN report checked that. It is left alone
  because the runbook's `print_output` interface fixes the join as two newlines.

### Composition and conventions

- Ordering is correct: `(memory, second, commit)` is the order the outline gives
  for parts 1–3.
- `autoname` and `restart` stay silent because their `commit_mode` is `""`.
- The new function sits between `memory_directive` and `arming_directive`, which
  is its print position. Naming and docstring style match the file.
- The tuple return in place of the runbook's `list[str]` / `MemoryPart` shape is
  a deliberate deferral (GREEN report). A later slice of Item 1.1 owns that
  reshape.

## Mutation check

In `compose_directives` I flipped the mode gate to `"without-commit"`, ran the
tests, and restored it with the inverse `sed`.
`pytest -k commit_act` gave 4 failed, 1 passed. The four parametrized
present/absent rows went red. `test_commit_act_names_no_git_verb` stayed green,
as expected, because it tests the text and not the gate. After restoring, the
diff touches only `_checkpoint_lib.py`.

## Gate

- After the fix, `pytest -k commit_act` gives 5 passed.
- `just precommit` passes: jq/shellcheck/ruff/docformatter/mypy/ty, bats, and
  pytest (244 passed, 11 deselected).

Refactor flagged: none
