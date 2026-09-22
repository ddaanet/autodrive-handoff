# Prose pass — the composer row carries its own gap (2026-09-22)

Prose only. No file under `scripts/` or `tests/` was touched; no branch, no
commit, no push. `git status` shows the five working-tree code/test files
exactly as they were handed over.

## Files changed

### `docs/changelog/2026-09-22-the-composer-row-carries-its-own-gap.md` (new, 125 lines)

The dated entry, in the register of the two neighbours. Sections: the defect
(the cursor gate asked *where* the cursor was but still let the glyph alone
decide *which* row it had to be at or below, with the conformance failure —
gate at 0.43s, `booting` false, 7 of 52 gate-held markers lost — and the
starship/pure/fish installs that make the arrangement ordinary); **The
discriminator is one character** (`_composer_index` requiring
`PROMPT_GLYPH + COMPOSER_GAP`, the four callers inheriting it, the zero
mid-session cost of one poll, `composer_start_column` still deriving the
*width*, the tension with "never pin today's layout" resolved as *the character
is the one value that is not layout*, and the fail-closed direction with
conformance catching it first); **Alternatives weighed** (`#{alternate_on}` on
three counts — a second tmux query in a family deliberately pure over captured
text, nothing bought for the 2026-09-20 replayed-transcript case, and tying the
gate to a terminal mode rather than to the composer; plus accept-and-document,
the other half of the 2026-09-21 fork); **The tests**; **Residual**.

The tests section names the three rows
(`test_cursor_in_composer_false_on_a_shell_prompt_glyph`,
`test_composer_index_requires_the_nbsp_gap`,
`test_line_landed_false_when_the_gap_is_an_ascii_space`), says what the replaced
`whatever_whitespace_pads_the_composer` parametrization asserted and where that
reasoning survives, and records the mutation result (revert to
`PROMPT_GLYPH in line`, exactly those three red). The fixture flips are stated
as a **correction**: a stub pane standing in for a live composer whose gap is an
ASCII space mis-describes what it stands for, which is 2026-08-13's defect, and
the two swallowed-line rows are the concrete case — left ASCII-padded they would
still pass, but because the pane held no composer at all rather than a composer
not holding the line.

### `docs/changelog.md`

One index line at the top of the list, no version, in the existing long-single-
line format.

### `docs/changelog/2026-09-21-the-landing-window-is-sized-by-the-boot.md`

A `> **Superseded 2026-09-22** (see …)` blockquote heading the "Residual — a
`❯` above the shell's cursor opens the gate" section, scoped to that residual
and the "Undecided, deliberately" paragraph. It says which of the two candidates
landed, and names what still stands: the arrangement, the two CC 2.1.278 probes,
the fixture staging, and the glyph-free parametrization — the last on the
narrower ground that a real `/exit`'s screen is what the platform produces.
Nothing else in that entry is touched.

### `docs/design/driving-the-tui.md`

The paragraph that opened "`cursor_in_composer` is true for a cursor anywhere
below a `❯` row … Neither is taken" is replaced by two present-tense paragraphs
(now lines 185–205): the composer is the last row carrying `❯` + U+00A0, a
cursor below it still counts (scrolled composer), a shell's ASCII-padded glyph
opens nothing and holds nothing, `_composer_index` answers for all four
predicates at once, mid-session cost nil; then the character-pinned /
width-derived split, the fail-closed direction, the remaining residual, and the
new changelog link. The `#{alternate_on}` rejection moved out of the node into
`rejected-alternatives.md` rather than being restated here.

The 2026-08-13 passage (now ending line 119) gained one sentence: the gap now
does double duty — it also identifies the composer row, so a stub pane spelling
it with an ASCII space describes no composer rather than a subtly wrong one.
The node is 302 lines, still inside the 400 cap.

### `docs/design/decisions.md` and `docs/design/rejected-alternatives.md`

A new standing-decision entry, **The composer row is identified by its U+00A0
gap.**, and a new rejected-alternative entry, **Requiring `#{alternate_on}` for
the boot gate**. Both link the new changelog entry; the decision also links
`driving-the-tui.md` as the mechanism.

### `docs/design.md` (the hub)

Two index lines added and `Last updated:` bumped to 2026-09-22.

## The hub decision — what I did and why

The hub **is** at that granularity (`Nothing that asks whether an action took
effect reads the pane.`, `Lengthening HANDOFF_WATCHER_SHELL_SETTLE`), so I added
both lines. One adjustment to the brief's shape, and this is the judgement call
to check: the hub's two indexes carry a **verbatim bolded lead line per entry in
`design/decisions.md` / `design/rejected-alternatives.md`**, with no per-line
links at all — that is the 2026-09-20 hub split's contract ("one verbatim
conclusion line per decision and per rejected alternative"). A hub line pointing
directly at `driving-the-tui.md` would be the only linked bullet in either list
and would have no entry behind it. So I wrote the entries in the two index nodes
and took the hub lines verbatim from their leads, and the pointer to
`driving-the-tui.md` lives inside the decision entry instead:

> **The composer row is identified by its U+00A0 gap.**

in the hub, and in `decisions.md` that same lead followed by the argument,
closing `[The mechanism](driving-the-tui.md), [The composer row carries its own
gap](../changelog/2026-09-22-the-composer-row-carries-its-own-gap.md)`. The
rejected line reads:

> **Requiring `#{alternate_on}` for the boot gate**

If you would rather the decision not have a hub line at all — it is narrower
than most of its neighbours — reverting is three deletions (the hub line, the
`decisions.md` entry, and optionally the rejected pair).

### `CLAUDE.md`

Three edits, all inside the existing wrapping:

1. The `scripts/_watcher_lib.py` bullet's `Open residual: cursor_in_composer
   fires for a cursor below *any* `❯` row …` clause is replaced by the present
   rule — `_composer_index` requiring `COMPOSER_GAP` (named, with U+00A0
   spelled out), the shell prompt and scrollback both excluded, the cursor
   below the composer row still counting, all four predicates inheriting the
   one answer, zero mid-session cost, `composer_start_column` still deriving
   the width — and the remaining residual (a prompt padding its own `❯` with a
   no-break space). The `wait_for_composer` parenthetical still closes
   correctly.
2. The `tests/test_watcher_lib.py` paragraph names the three rows and the
   mutation result in its neighbours' style, and the "captures, not
   hand-written" sentence now adds that an ASCII-padded stand-in describes no
   composer at all.
3. The `tests/test_tui_conformance.py` paragraph no longer calls the residual
   open: the `[post-exit-screen]` parametrization now "reproduces the
   arrangement the composer predicates were tightened against rather than the
   platform", with the 0.43s gate in the past tense against the glyph-presence
   gate, plus the positive ground (asserting over a real `/exit`'s screen is
   asserting about the platform) and the note that since the tightening the
   staged glyph counts as a glyph without counting as a composer, so the
   measuring row's cursor moment is the resumed session's.

## Verification done

- Every link added resolves on disk (checked by path existence, not by eye).
- Every line I wrote is ≤80 **characters**; the only >80 lines in the edited
  files are pre-existing unbreakable changelog-link lines. `awk length` reports
  bytes, so `❯` and `—` inflate it — the check was run in Python on characters.
- `git status` confirms the prose files plus the new changelog entry, and the
  five code/test files unchanged by me.

## Two observations for you (no action taken)

1. **Literal NBSPs in `tests/test_drive_when_idle.py`.** That file defines
   `NBSP = "\N{NO-BREAK SPACE}"` and uses it in five f-strings, but 19 of its
   lines carry a **literal** U+00A0 instead (the flips that render as `❯ ` in
   the diff). `tests/test_watcher_lib.py`, `tests/conftest.py` and
   `tests/hook-test.bats` all spell it as an escape or an octal, which is the
   house rule stated in `test_watcher_lib.py`'s own header comment ("Spelled as
   an escape so it survives an edit and a reader can see it"). An invisible
   literal is exactly what a reformatting pass or an editor's whitespace
   normalisation eats silently, and the predicate it feeds now depends on that
   character. Worth a pass in `gap-code`'s lane, not mine.
2. **The `[post-exit-screen]` parametrization may no longer be load-bearing.**
   With the tightened predicate the staged `❯ /exit` should not open the gate,
   so the row would plausibly pass against the default staging too. I wrote it
   as an open question for the live run rather than asserting either way, and
   kept the parametrization's justification on the ground that survives
   regardless (asserting the gate's promise over the screen a real `/exit`
   leaves is asserting it about the platform). If `just tui-conformance` passes
   against the default, that is a fact worth adding to the entry — as a
   sentence, not a change to the row.
