# Item 1.1 — slice 4 GREEN report

Commit: `31166d8` — "✨ Item 1.1/4 — arming instruction last, refers to
everything above".

## Implementation

`scripts/checkpoint.py`:

- New `hold_decision(transition: Transition, *, memory: bool) -> bool` —
  today's rule (`bool(transition.cmds) and memory`), unchanged in substance,
  now a named function rather than an inline condition inside
  `compose_sentinel`. Placed ahead of `compose_sentinel`, its only caller
  besides `main`.
- `compose_sentinel(root, transition, continuation, *, held: bool) -> None` —
  takes the hold decision as a keyword-only input instead of deriving it from
  `transition.cmds and memory`; appends no text to anything and returns
  `None`. The session-id lookup for the `held <sid>` state line is unchanged.
- `compose_directives(skill, root, commit_mode, memory: str, *, held: bool) -> list[str]`
  — now returns an ordered `list[str]` of non-empty parts instead of a
  3-tuple. Still resolves `second` (todo boundary / SDD nudge) and `commit`
  internally from `skill`/`commit_mode`/`root`; takes `memory` as a plain
  `str` parameter (per the dispatch, `MemoryPart` is slice 1.1/5, out of
  scope here) instead of calling `lib.memory_directive` itself. Appends
  `lib.arming_directive()` as the list's last element when `held` — the
  outline's part 4, always after parts 1–3.
- `print_output(parts: list[str]) -> None` — takes the ordered list directly
  rather than three separate strings; unchanged join/newline behavior
  (`"\n\n".join(parts) + "\n"`, nothing written for an empty list).
- `main()` — reordered per the Item's spec: resolve `memory` once via
  `lib.memory_directive(str(root), commit_mode)` (only for
  `skill in ("handoff", "precompact")`, matching the old
  `compose_directives`' own gating), compute `held` via `hold_decision`, call
  `compose_sentinel(..., held=held)`, then
  `compose_directives(..., memory, held=held)`, then `print_output(parts)`.

`scripts/_checkpoint_lib.py`:

- `arming_directive()` reworded: "Once everything above is done, run
  `handoff-approved` (Bash, no arguments)." (was "Once that is done, …").
  Drafted under `craft:directive-writing` — imperative directive-channel
  wording, no mechanism added, still names the one act (`handoff-approved`,
  Bash, no arguments) the reader performs.

## Test changes

None beyond what RED already added (`tests/test_checkpoint.py`'s `# Arming`
section: `test_arming_instruction_follows_every_other_part`,
`test_arming_text_refers_to_everything_above`, both already reviewed and
approved for GREEN in `item-1-1-s4-test-review.md`). No existing test asserted
the old arming text or the old three-tuple signatures of `compose_directives`
/ `compose_sentinel` / `print_output`, so no existing row needed updating.

## Verification

- `pytest tests/test_checkpoint.py -k "arming_instruction_follows or arming_text_refers"`
  — 2 passed (both new tests, RED → GREEN).
- `pytest tests/test_checkpoint.py` — 159 passed, no regressions.
- `just precommit` — green: lint (ruff/docformatter/mypy/ty), `shellcheck -x`,
  `bats tests/*.bats` (166 ok) and `pytest` (249 passed, 11 deselected).

## Scope

In scope only: slice 1.1/4 (arming moved into `compose_directives`,
`hold_decision` extracted, reworded text). `MemoryPart` and the refusal-alone
branch (slice 1.1/5), the `commit` parameter on `hold_decision` (Item 2.1),
the closing line and `bin/handoff-approved` (Items 3.1/3.2), and
skills/docs/CLAUDE.md updates were not touched.
