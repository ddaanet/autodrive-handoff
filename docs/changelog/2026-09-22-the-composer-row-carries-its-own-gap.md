# 2026-09-22 — The composer row carries its own gap

The residual the day before left open is closed, and it is closed by one
character. `wait_for_composer` asks where the terminal cursor is, but *which*
row it has to be at or below was still decided by the glyph alone: the last row
carrying a `❯`. On a bare shell whose prompt or scrollback holds one, that row
is the shell's, the cursor sits below it, and the gate opens on a terminal
Claude Code has not started in yet.

Not theoretical, and not a story about a hypothetical user's prompt. The
conformance fixture's own staging prints `❯ /exit` before the relaunch line
runs, and against it the new `live` row failed exactly that way: the gate open
at 0.43s, `booting` reading **false** because the composer was there on the
first reading, and 7 of 52 gate-held markers never reaching the composer at
all. `❯` prompts are common besides — starship, pure, and fish configurations
that use one — so on those installs the continuation of every driven restart is
typed at the shell, ahead of or into the loss band, and then given the 3s
mid-session landing window rather than the 30s boot one.

## The discriminator is one character

The TUI pads its composer glyph with U+00A0. A shell prompt pads the same glyph
with an ordinary ASCII space. That is the whole of the one observed failing
arrangement, so `_composer_index` now requires `PROMPT_GLYPH + COMPOSER_GAP` —
a new module constant, `"\N{NO-BREAK SPACE}"`, spelled as an escape — before it
will call a row the composer.

All four callers share that one answer, which is why the fix is one line:
`line_landed` through `_composer_region`, `composer_has_user_text`,
`cursor_in_composer`, and `composer_excerpt`. A shell prompt therefore does not
open the gate, does not hold a landed line, and is not what a landing failure
quotes back.

Mid-session the cost is zero. A live composer's own row carries the gap, so the
gate still opens on the first poll, exactly as it did — the tightening is paid
for only by a pane that has no composer, which is the pane it exists to
recognise.

`composer_start_column` is untouched, and the distinction it draws is the one
worth holding onto. The *width* of the gap stays derived from the captured line
— `lstrip()` takes U+00A0 as whitespace like any other, so nothing there had to
change. What is now pinned is the gap's *character*, and only because that
character is the discriminator. The standing stance behind
`composer_start_column` is that pinning today's layout is how a predicate comes
to invert in silence; this does not reverse it, it names the one value that is
not layout. The 2026-08-13 defect is the same character biting the other way: a
hand-written ASCII gap made `is_typing` false for every line the walker had ever
typed, while its suite stayed green. That the gap has already been the thing
that separates a hand-written fixture from a real pane is the evidence that it
separates a shell prompt from a composer.

If Claude Code ever drops the NBSP, the gate fails **closed**: no row reads as
a composer, `wait_for_composer` times out at `BOOT_TIMEOUT`, and the walker
reports a non-delivery without typing anything. That is the right direction to
fail in — the defect being fixed here is typing into a shell — and
`just tui-conformance` sees it first, since every composer capture the offline
suite rests on is re-asserted against a live TUI there.

## Alternatives weighed

**Require `#{alternate_on}`.** The other candidate named on 2026-09-21, and it
would close the case too: Claude Code runs on the alternate screen, with
`#{alternate_on}` flipping 0 → 1 between t=4s and t=5s of boot, probed on CC
2.1.278. Rejected on three counts. It adds a second tmux query to a predicate
family that is deliberately pure over captured pane text — every one of them is
a function of the text plus the cursor, which is exactly what lets them be
tested offline against captures and re-checked against a live TUI, and
`TmuxStub` would have to learn to answer a new format field. It buys nothing
for the 2026-09-20 case, where the `❯` is in replayed transcript text that is
already on the alternate screen and the cursor is what tells it apart. And it
ties the gate to a terminal mode rather than to the composer, which is the
thing the caller actually wants to know about.

**Accept and document the residual.** The other half of the fork, and the
cheaper one. Refused because the arrangement is not exotic and the failure it
produces is the one this whole line of work has been chasing: a keystroke typed
into something that is not reading, reported only if it also fails to land.

## The tests

Three rows in `tests/test_watcher_lib.py`:
`test_cursor_in_composer_false_on_a_shell_prompt_glyph` puts the 2026-09-21
finding in the suite as a fixture — a pane whose `❯ /exit` sits above the
shell's cursor; `test_composer_index_requires_the_nbsp_gap` pins the predicate
directly, both ways, over two rows differing in that character alone; and
`test_line_landed_false_when_the_gap_is_an_ascii_space` replaces the
`test_line_landed_whatever_whitespace_pads_the_composer` parametrization, which
asserted the opposite — that either gap reads as a composer — on the reasoning
that the gap is the TUI's choice and had already changed once. That reasoning
survives as the sentence above about the width. Mutation check: revert
`_composer_index` to `PROMPT_GLYPH in line` and exactly those three red.

Every hand-composed stub pane standing for a real composer was flipped from
`❯ ` to `❯` + NBSP — in `tests/test_drive_when_idle.py`, `tests/conftest.py`,
`tests/hook-test.bats`, and `tests/test_watcher_lib.py`'s own composed strings.
That is a **correction**, not a convenience for the new predicate. A pane
standing in for a live composer whose gap is an ASCII space is
mis-describing the thing it stands for, which is 2026-08-13's defect exactly;
the tightening is only what made it visible again. Two of the flipped rows show
why it matters on its own terms: the swallowed-line rows assert that a typed
line never landed *in a composer*, and left ASCII-padded under the new
predicate they would pass because the pane held no composer at all — the right
verdict reached through the wrong state of the world.

The conformance fixture's `PREVIOUS_SCREEN = "❯ /exit"` keeps its ASCII space
deliberately: it stands for a shell line, and a shell line not reading as a
composer is now the property under test rather than the defect. One consequence
is worth naming — that staging's confound on
`test_the_first_composer_glyph_is_not_yet_accepting_input` narrows. That row
measures its first `❯` by grepping the pane, so the `printf` still stands in for
a glyph the fixture cannot otherwise produce, but its `cursor_in_composer`
reading no longer opens against the staged line, so the cursor moment it records
is the resumed session's. The live run answered the follow-on question:
`test_only_keystrokes_ahead_of_the_boot_gate_are_lost` now passes against the
default `❯ /exit` staging too — one probe on a loaded box, screen switch at
10.58s, gate open at 11.77s, the loss window at 7.41–7.77s entirely ahead of
it, 68 of 70 markers kept and every gate-held one in order. The staged shell
line no longer opens anything. Its `[post-exit-screen]` parametrization stays
regardless, because asserting the gate's promise over the screen a real
`/exit` leaves is asserting it about the platform rather than about the
fixture. The full suite, `just tui-conformance`, was 14 passed against the
tightened predicate.

## Residual

A shell prompt that pads its own `❯` with a NO-BREAK SPACE still reads as a
composer. Nothing known does — the character is not on a keyboard and no prompt
framework has a reason to emit it — and the failure mode is unchanged from
2026-09-21's, so this is recorded rather than defended against.
