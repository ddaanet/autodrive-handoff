# CODE — the composer row carries its own gap

2026-09-22. `_composer_index` in `scripts/_watcher_lib.py` now counts a row as
the composer only when `PROMPT_GLYPH` is immediately followed by
`COMPOSER_GAP = "\N{NO-BREAK SPACE}"`, a module constant defined below it. All
four callers share the index, so `wait_for_composer`'s boot gate no longer
opens on a shell whose prompt or scrollback carries an ASCII-padded `❯`.
`composer_start_column` is unchanged: the gap's *width* stays derived from the
line, only the *character* is pinned, since it is the discriminator.

The dispatched sonnet agent applied the predicate change, the docstrings and
the fixture flips, then went idle without running the gate or writing this
report; the mutation check, the gate and the live run below were done by the
orchestrating session.

## Fixtures flipped from `❯ ` to `❯` + NBSP

Every hand-composed pane that stands for a real composer:

- `tests/test_watcher_lib.py` — `BUSY_TEXT`, `IDLE_TEXT`, `TYPING_TEXT`, the
  two `is_unknown_command` rows, the late-boot `wait_for_composer` row.
- `tests/test_drive_when_idle.py` — every staged pane (a module `NBSP`
  constant, f-strings; no literal NBSP).
- `tests/conftest.py` — `TmuxStub`'s default `pane_idle.txt` /
  `pane_after_enter.txt`.
- `tests/hook-test.bats` — the `tmux` stub's `capture-pane` answer, spelled
  `\302\240`.

Left as is, on purpose: `tests/test_tui_conformance.py`'s
`PREVIOUS_SCREEN = "❯ /exit"` (it stands for a shell line), and the remaining
`❯ ` occurrences, which are all prose in comments and docstrings.

## New rows

- `test_cursor_in_composer_false_on_a_shell_prompt_glyph` — the 2026-09-21
  conformance finding: `"$ claude\n❯ /exit\n$ claude --resume abc\n"` with
  the cursor on the last row is not a composer.
- `test_composer_index_requires_the_nbsp_gap`.
- `test_line_landed_false_when_the_gap_is_an_ascii_space` — replaces the
  `whatever_whitespace_pads_the_composer` parametrization, which asserted the
  opposite.

## Mutation check

`_composer_index` reverted to `PROMPT_GLYPH in lines[index]`, then
`pytest tests/test_watcher_lib.py`:

```
FAILED tests/test_watcher_lib.py::test_line_landed_false_when_the_gap_is_an_ascii_space
FAILED tests/test_watcher_lib.py::test_cursor_in_composer_false_on_a_shell_prompt_glyph
FAILED tests/test_watcher_lib.py::test_composer_index_requires_the_nbsp_gap
3 failed, 58 passed in 6.06s
```

Exactly the three rows, nothing else. Restored.

## Gate and live run

`just precommit` (sandboxed): every lint clean, bats ok, `283 passed, 14
deselected` before the three new rows — re-run after them below with the
docs pass.

`just tui-conformance` (private tmux socket, unsandboxed):

```
14 passed, 285 deselected in 145.73s (0:02:25)
```

All fourteen live rows green against the tightened predicate, including the
two `resuming_pane` rows that still boot over the staged `❯ /exit` shell line
— the gate now waits for the TUI's own composer there, as it should.
