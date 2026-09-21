# 2026-09-21 — The landing window is sized by the boot, not a settle

The gate added the day before was right and the number behind it was sized on
a reading of the measurement that the measurement does not support. The
2026-09-20 row typed a marker every 250ms across a `claude --resume` boot and
recorded when the **first** one appeared in the composer. It stopped there. It
never counted how many of the markers sent before that moment were in the
composer beside it.

Counted, they all are. Twenty markers sent after the cursor reached the
composer, twenty in the composer 8.1s later when it first painted, in order.
The pane keeps what it is sent from the cursor onward and paints it late; it
does not discard it. So "the pane then discards keystrokes for another 3 to 9
seconds" described a paint delay, and `HANDOFF_WATCHER_BOOT_SETTLE` bought a
wait the line did not need before it was typed, while leaving it the 3s
mid-session landing window afterwards — far shorter than the paint it then had
to survive. The settle cost up to 10s on every driven restart and moved the
line no closer to landing.

It also hid itself. `gate_opened` was stamped after the settle slept, so the
landing failure reported `0.2s after it started reading input` for a line that
had waited five seconds. The one channel a detached walker has could not say
where the time went.

## The fix

The settle is gone. `wait_for_composer` returns `(opened, booting)` — whether a
composer ever appeared, and whether it was absent on the first reading — and
`_drive_line` sends the moment the gate opens, booting or not. The wait moves
behind the keystroke, where it is the line's own landing window:
`wait_for_landing(pane, line, *, booting)` polls for
`HANDOFF_WATCHER_BOOT_LANDING_DELAY` (30.0s) after a boot and the unchanged
`HANDOFF_WATCHER_LANDING_DELAY` (3.0s) everywhere else.

A tuple of two named booleans rather than a `bool | None` or an enum. `None`
for a timeout inverts `if not wait_for_composer(pane)` into a truthiness trap
where `False` and `None` mean opposite things, and a third state buys nothing:
on timeout the composer was definitionally absent, so `(False, True)` is not
undefined.

The two windows are not one window widened. Mid-session the composer has been
reading for as long as the session has, and a line that has not appeared in it
is not one that will — that window is also how long the walker waits before
reporting a keystroke it believes was swallowed, so widening it everywhere
would cost half a minute of silence on the one report that says a keystroke was
lost. A guard row pins the short window and is mutation-checked: make the boot
window unconditional and it alone reds, the line landing inside the widened
window and the failure moving past `did not land` to the confirmation stage.

The timing record drops `settle` — nothing sleeps between the steps now, so
`gate` alone is how long the boot took to put the cursor in the composer and
`landed` is how long the session then took to paint a line it had already
taken, which is the number `BOOT_LANDING_DELAY` is sized against. The landing
failure counts from the send rather than from a gate stamp.

## The gate now rests on two grounds

2026-09-20 justified `cursor_in_composer` on the stale `❯` alone and treated
the loss as a separate window needing its own answer. With the settle gone the
gate carries both: it is the predicate that tells a replayed or boot-chrome
glyph from a live composer, **and** it is what puts the send past the window
where input is actually lost.

That window is measured, not hypothesised. A new `live` conformance row —
`test_only_keystrokes_ahead_of_the_boot_gate_are_lost[post-exit-screen]` —
streams a distinct marker every ~0.35s from the moment the relaunch line runs,
records for each whether the gate's condition held on the reading before it,
and reads back afterwards which markers the composer holds. Over three runs:

| run | loss window | screen switch | gate open | sent | kept | lost |
|---|---|---|---|---|---|---|
| 1 | 1.73s → 2.72s | 4.63s | 5.36s | 38 | 34 | 4 |
| 2 | 2.88s → 3.26s | 6.26s | 7.02s | 46 | 44 | 2 |
| 3 | 1.80s → 2.86s | 5.45s | 6.23s | 41 | 37 | 4 |

Three things follow that the hand test could not say. The loss is a **discrete
band** about 1–1.5s wide, not a prefix: markers from 0.04s up to ~1.7s are kept,
a handful in the middle are eaten, and everything after is kept again. That is
`aoeuidhtnsaoe` typed across a resume boot arriving as `aoeunsaoe` — intact
head, intact tail, hole in the middle. The band **closes ~2s before** the
alternate-screen switch, not at the TUI's first paint, so it is over well before
anything the pane shows changes; what bounds it is not identified. And every
marker sent with the gate's condition held landed, in order, on all three runs —
the gate opens 2.5–3.7s past the end of the band.

The row asserts only the mechanism's own guarantee (the condition held for at
least one send, every such marker is in the composer, and in order) and prints
the rest under `-s`. A pinned threshold would red on a faster or slower box with
nothing wrong, and a run that loses nothing is not a failure. Nothing is ever
submitted.

## What 2026-09-20 got right

Unchanged, and load-bearing: the stale-glyph diagnosis — under `claude
--resume` the pane carries the exited session's frame and the replayed
conversation, and a `❯` in either is not a contrived case; `cursor_in_composer`
over one frame, twice in a row; the landing failure quoting what the composer
actually held instead of asserting a dead pane or copy mode; and `watcher_log`,
without which none of this would have been visible from a real restart.

## Alternatives weighed

**Widen `LANDING_DELAY` everywhere.** The uniform version of the fix, and
2026-09-20 rejected it outright. That rejection is reversed here for the boot
case and stands for every other: what it was rejected on — the composer was
still empty 65s after the 2026-09-20 loss, so there was nothing pending a late
repaint — was a true reading of *that* incident, where the line was typed into
the loss window through a gate the stale glyph had opened. It is not a general
argument against waiting for a paint, and the boot branch is the one place a
paint really is pending.

**Keep a shorter settle.** Any settle is a wait in front of a send the pane is
already ready for; shortening it only reduces what it wastes. The same seconds
spent behind the send are a window a slow paint can use.

**The readiness probe** — type one character, poll for it, verify a `C-u`
cleared it, then type the real line. Recorded on 2026-09-20 as the next move if
the settle proved too short. It is not what this needed: the settle was not too
short, it was answering a question that had no case. The probe stays parked, and
its own cost is unchanged — a stray character left in the user's composer on
every path where the clear is the keystroke that gets dropped.

## Residual — a `❯` above the shell's cursor opens the gate

`cursor_in_composer` is true for a cursor sitting *below* any `❯` row, which is
what makes it work on a composer that has scrolled. On a bare shell whose prompt
or scrollback carries a `❯` — starship, pure, and fish configurations that use
it are common — the same branch fires: the gate opens on the shell within half a
second, `booting` reads **false** because the composer was there on the first
reading, and the continuation is typed ahead of or into the loss window and then
given the 3s window rather than the 30s one.

This is not theoretical. The conformance fixture's default staging prints
`❯ /exit` into the shell before the relaunch line, and against it the new row
fails exactly that way: gate open at 0.43s, 7 of 52 gate-held markers never
reaching the composer. That is why the row is parametrized onto a glyph-free
screen — asserting the gate's promise over the staged glyph would be asserting
it over an arrangement the platform does not produce.

Two probes on CC 2.1.278 say it does not: Claude Code runs on the **alternate
screen** (`#{alternate_on}` flips 0 → 1 between t=4s and t=5s of boot), and
after a real `/exit` the restored normal screen holds two lines and no `❯` at
all — the TUI's frame went with the alternate screen. The user's own fish prompt
contains none either. That sits in tension with 2026-09-20's statement that
under `--resume` a `❯` is on screen from the first moment; the reading that
survives both is that the glyph comes from *replayed content* once the TUI is
up, not from the exited session's frame outliving it. Which of those the
2026-09-20 loss actually hit is not settled here.

Undecided, deliberately: accept and document the residual, or tighten the
predicate. Requiring `#{alternate_on}`, or requiring the glyph row to carry the
composer's U+00A0 gap, would each close it. Both are evidence for a later
decision and nothing more — `scripts/_watcher_lib.py`'s predicate is untouched.

The default staging has a second consequence worth naming. With it,
`test_the_first_composer_glyph_is_not_yet_accepting_input` measures its "first
`❯`" against the `printf`, not the TUI. The control run shows no `❯` appears
naturally under `--resume` until the composer paints, so the staged line is
standing in for a condition the fixture cannot otherwise produce, and that row's
own assertion (`t_input >= t_glyph`) holds either way.
