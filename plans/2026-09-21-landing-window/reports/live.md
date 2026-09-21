# LIVE — the boot loss window, pinned against a real resume

2026-09-21. One new `live` row in
`/Users/david/code/handoff/tests/test_tui_conformance.py`. The hand test
reproduced: a stream of ordered markers typed across a `claude --resume` boot
loses a discrete mid-boot window and keeps everything either side of it. The
loss falls entirely **ahead** of `wait_for_composer`'s gate, which is the claim
the walker now rests on with no settle behind it.

Final state: the row passes on three consecutive runs, `just tui-conformance`
is **14 passed** and `just precommit` is **283 passed, 13 deselected** plus
**170 bats rows**, every lint clean.

## The row

`test_only_keystrokes_ahead_of_the_boot_gate_are_lost[post-exit-screen]`

From the moment the relaunch line is run in the shell pane it sends one
distinct marker (`zq000v`, `zq001v`, …) every ~0.35s, recording per marker a
monotonic timestamp and whether `cursor_in_composer` held on the reading taken
immediately before the send. It runs until the resumed session is demonstrably
reading and painting, polls the composer to stillness, then reads back which
markers are in it.

**Asserted** (the mechanism's own guarantee):

- the gate's condition held for at least one send, so the row is not vacuous;
- every marker sent while the gate's condition held — `cursor_in_composer` true
  on that reading *and* the one before it, which is `wait_for_composer`'s own
  `seen >= 2` rule — is in the composer afterwards;
- and they are there in order.

**Printed, never asserted** (`pytest -s`): the screen switch, the composer
paint, first cursor-in-composer, gate open, first proof the session is reading;
marker count sent/kept/lost; the loss window's bounds; a `+`/`-` trace with `/`
at the screen switch and `|` where the gate opens; and every lost marker with
its send time. A run that loses nothing is not a failure.

Nothing is ever submitted — no Enter is sent after the relaunch line, and the
pane and server die in the fixture's teardown.

### Supporting changes in the same file

- `resuming_pane` now takes the screen the relaunch is typed over from
  `request.param`, defaulting to the existing `❯ /exit` staging. The two
  existing rows are untouched and still get that default; the new row is
  parametrized `indirect=True` onto `EXITED_SCREEN` (`"session exited"`). See
  "The staged glyph" below for why this mattered.
- Helpers: `_marker`, `_Send`, `_Boot`, `_pane_state` (cursor and
  `#{alternate_on}` in one `display-message`), `_composer_text` /
  `_squash_composer`, `_stream_markers`, `_settled_composer`, `_report_sends`.

## Did the hand test reproduce?

Yes, on every run. The measurements, all relative to the relaunch line running:

| run | screen switch | composer painted | cursor in composer | gate open | session reading | sent | kept | lost | loss window |
|-----|------|------|------|------|------|----|----|---|------|
| 1 | 4.63s | 5.00s | 5.00s | 5.36s | 9.08s | 38 | 34 | 4 | 1.73s → 2.72s |
| 2 | 6.26s | 6.63s | 6.63s | 7.02s | 12.55s | 46 | 44 | 2 | 2.88s → 3.26s |
| 3 | 5.45s | 5.85s | 5.85s | 6.23s | 10.27s | 41 | 37 | 4 | 1.80s → 2.86s |

Traces (`+` kept, `-` lost, `/` screen switch, `|` gate opens):

```
run 1  +++++----++++/++|+++++++++++++++++++++++
run 2  ++++++++--+++++++/++|+++++++++++++++++++++++++++
run 3  +++++----++++++/++|++++++++++++++++++++++++
```

Lost markers, with send times:

```
run 1  zq005v@1.73s zq006v@2.06s zq007v@2.40s zq008v@2.72s
run 2  zq008v@2.88s zq009v@3.26s
run 3  zq005v@1.80s zq006v@2.16s zq007v@2.52s zq008v@2.86s
```

Three things the instrument says that the hand test could not:

1. **The loss is a discrete window, not a prefix.** Markers sent from 0.04s up
   to ~1.7s are kept — the tty buffers them and the resumed process is handed
   them. Only a ~1–1.5s band is eaten, and everything after it is kept again.
   This is `aoeuidhtnsaoe` → `aoeunsaoe` exactly: intact head, intact tail,
   hole in the middle.
2. **The window closes ~2s *before* the alternate-screen switch**, not at the
   TUI's first paint. The brief's model ("after the terminal's screen switch
   and before the TUI's first paint") puts it later than it is: the loss ends
   at 2.72s / 3.26s / 2.86s while `#{alternate_on}` flips at 4.63s / 6.26s /
   5.45s. What bounds the window is not identified here; it is over well before
   anything the pane shows changes.
3. **Every gate-held marker landed, in order, on all three runs.** The gate
   opens one poll after the composer paints (5.36s vs 5.00s, 7.02s vs 6.63s,
   6.23s vs 5.85s), which is 2.5–3.7s past the end of the loss window. Input
   accepted there is buffered and painted late — first proof of reading comes
   3.7–5.5s after the paint — but none of it is lost. That is the margin
   `BOOT_LANDING_DELAY` covers now that `BOOT_SETTLE` is gone.

## The staged glyph — a finding, and the one judgement call

The row **failed** against the fixture's default staging, and the reason is not
the gate:

```
resume boot: screen switch at 9.55s, composer painted at 10.36s,
             cursor in composer at 0.05s, gate open at 0.43s,
             session reading at 17.10s
56 markers sent: 49 in the composer, 7 lost
loss window: 3.83s → 6.07s
+|+++++++++-------++++++++/+++++++++++++++++++++++++++++++
AssertionError: 7 of 52 markers sent with the walker's boot gate open never
reached the composer: zq010v … zq016v
```

`cursor_in_composer` was true at **0.05s**, before the resumed process had
rendered anything. The fixture prints `❯ /exit` into the shell before typing
the relaunch line; `_composer_index` finds that row, the shell's cursor sits
below it, and `cursor_in_composer` returns on its `cursor_y > index` branch.
The gate opens at 0.43s and the loss window then falls behind it.

Two probes settle whether that is production or staging (both on private tmux
sockets, CC 2.1.278):

- **Claude Code runs on the alternate screen.** `#{alternate_on}` flips 0 → 1
  between t=4s and t=5s of boot.
- **A real `/exit` leaves no `❯` at all.** After `/exit` the pane is
  `alternate_on=0`, `pane_current_command=sh`, cursor `2,1`, and the restored
  normal screen is two lines — `$ claude` and the prompt. `grep '❯'` over it
  returns nothing: the TUI's frame went with the alternate screen.
- The user's own prompt cannot supply one either —
  `~/.config/fish/functions/fish_prompt.fish` contains zero `❯`.

So the staged line reproduces an arrangement the platform does not produce
after a restart, and asserting the gate's promise over it would be asserting it
over a counterfactual. A control run with the staging swapped for a glyph-free
line of the same length and timing passed cleanly (gate at 5.26s, loss
1.72s → 2.70s) — which is what the parametrization now does for this row only.

**This is still a real residual, and it is the lead's call what to do with it.**
`cursor_in_composer` reads *any* `❯` at or above the cursor as a composer, so on
a pane whose shell prompt or scrollback carries one — starship, pure, and fish
configs that use `❯` are common, and this repo's own `printf` demonstrates the
shape — the boot gate opens at the shell and the walker types its continuation
into the loss window. Two directions, neither taken here: accept and document
it as a residual, or tighten the predicate (requiring `#{alternate_on}`, or
requiring the glyph row to carry the composer's U+00A0 gap, would each close
it). I did not touch `scripts/_watcher_lib.py`.

One nuance the lead should know, since I left it alone: with the default
staging, `test_the_first_composer_glyph_is_not_yet_accepting_input` measures
its "first `❯`" against the `printf`, not the TUI — that glyph is on screen at
~0s by construction. The control run shows no `❯` appears naturally under
`--resume` until the composer paints (~4.9s), so the staged line is doing real
work for that row, standing in for a condition the fixture cannot otherwise
produce. Its assertion (`t_input >= t_glyph`) is unaffected either way.

## Runs

Row, three times, each a fresh resume — `.venv/bin/pytest -m live -s -v
tests/test_tui_conformance.py -k only_keystrokes_ahead`:

```
1 passed, 13 deselected in 18.38s
1 passed, 13 deselected in 22.15s
1 passed, 13 deselected in 19.10s
```

Full live suite — `just tui-conformance`:

```
14 passed, 283 deselected in 95.01s
```

All fourteen rows green, including the new one and the two that share the
`resuming_pane` fixture at its unchanged default.

Gate — `just precommit` (sandboxed):

```
jq . .claude-plugin/plugin.json    jq . hooks/hooks.json
jq . .claude/settings.json         shellcheck -x .bin/* bin/* scripts/*.sh tests/*.bats
ruff check scripts tests           ruff format --check scripts tests
docformatter --check               mypy / ty check → All checks passed!
bats tests/hook-test.bats tests/checkpoint.bats → 170 rows ok
pytest → 283 passed, 14 deselected in 63.28s
```

Every live run used a private tmux socket (`-L handoff-resume-<pid>` and the
probes' own), never the default socket, and ran one at a time. The only file
changed is `/Users/david/code/handoff/tests/test_tui_conformance.py`; nothing
was committed and no branch was created.
