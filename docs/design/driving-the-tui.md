# Driving the TUI

Part of [handoff — Design](../design.md).

## The kinds and their lines

A **driven transition** is a sequence of lines to type, plus the
`SessionStart` source that confirms it happened:

| kind | typed before | typed after | confirming source |
|---|---|---|---|
| `rename` | `/rename <title>` | — | — |
| `compact` | `/compact [directive]` | continuation prose, if any | `compact` |
| `clear` | `/rename <title>`, `/clear` | continuation prose, if any | `clear` |
| `compact` (prepared) | — | — | `compact` |
| `restart` | `/exit`, `claude --resume <sid…>` | continuation prose, if any | `resume` |

## The relaunch line

`restart`'s shape mirrors `clear`'s exactly — two required before-lines, one
optional after-line — but crosses a boundary neither other kind does: its
second before-line is typed into a bare shell, not the Claude Code TUI, once
`/exit` has actually torn the process down. `checkpoint.py` composes only
`claude --resume <sid>` (the session id from `CLAUDE_CODE_SESSION_ID`; it has
no view of the process's own argv), and that is the whole line: it is typed
exactly as composed, and nothing fills in flags.

The bare name is what makes that sufficient. The shell resolves it through
PATH, so every launcher shim the original invocation went through runs again
and contributes what it contributes — here, one prepending `--plugin-dir
<repo root>` and gitlore's prepending `--settings
'{"autoMemoryDirectory":…}'`. Re-entering them is also the only way to
restore what is not on a command line at all: gitlore's shim `export`s
`GITLORE_LAUNCHED=1`, which its own anti-double-inject guard reads. A shim
`exec`s the real binary, so it occupies no process of its own and cannot be
found by inspecting the tree — running it again is the only handle on it.

### Why the argv replay went away

Replaying the exiting process's argv is what this replaced, and the reason is
that the two compose badly: that argv already contains what the shims
injected, so replaying it hands them a line they then inject into again —
one more copy of every flag per restart, growing without bound. Dropping the
replay costs a flag typed by hand on an install with no shim to resupply it,
which is now silently lost, and takes with it the `/proc` parent-chain walk
that existed only to read those flags.
[The relaunch stops replaying argv](../changelog/2026-08-14-the-relaunch-stops-replaying-argv.md)

`stop-drive.sh` touches no line of a `restart` sentinel, then. Its one
restart-specific act is to clear a stale `.claude/autodrive.exited` before it
arms and spawns, so an earlier, only-partly-successful attempt's leftover
cannot let this one's `/exit` confirmation false-positive.

## The sentinel

The after-line is optional on both driven kinds, because typing the
transition and submitting a prompt into what it opens are separate
decisions.

One sentinel, `.claude/autodrive`, whose first line is its **state** and
second line the kind. The states are `held` → `armed` → `pending` → gone,
and every one after the first is a hook's to write. `checkpoint.py` is the
file's one writer — it composes the sentinel and reads its own output back
through the parser, so composer and parser cannot drift, and a direct agent
Write or Edit is denied at `PreToolUse`. The remaining lines are the **literal keystrokes**, so
the walker never needs to know which command belongs to which kind;
validation anchors it instead — the *n*th line of kind *k* must begin with
the expected command literal, so the file cannot be made to type something
else. One fact per line throughout.

## Nothing is typed from inside a live turn

Mid-turn input has four distinct classes, and prose — not the slash command
— is the dangerous one: it is injected into the running turn's next model
call. So no line is ever typed from inside a live turn. `Stop`
(`stop-drive.sh`) arms the before-lines, rewriting the sentinel's state from
`armed` to `pending` *before* spawning; a later `Stop` acts only on `armed`,
so it cannot re-arm one in flight. The transition's own `SessionStart`
consumes that file — only in state `pending`, and only of its own kind — and
spawns the after-line. One walker,
`drive_when_idle.py`, serves every case: wait for idle, type, confirm,
re-gate on idle, next line. A line that fails to confirm stops the sequence,
which is what makes a `/rename` that never lands under kind `clear` cost a
wrong title and nothing more.

## Confirming a line dispatches on the command

Confirmation dispatches on the **command**, not the kind — which is what
lets `/rename` appear in two kinds with two different fates, and carries the
recognition check for free, since any line beginning `/` takes the
type-read-back-Enter path. Four primitives: a `custom-title` transcript
entry for `/rename`, the sentinel disappearing for `/compact`, `/clear` and
`claude --resume …` — a `SessionStart` is what removes it in every case,
though the TUI lines ask delivery and confirmation as one question
(`submit_consumed`) while the relaunch splits them (`submit_launched`, then
`wait_for_consumed`: see below) — a genuine
user-prompt transcript entry for prose, and `.claude/autodrive.exited`
appearing for `/exit` — the one primitive with the opposite polarity, since
`SessionEnd` can only ever create that marker, never remove one that
predates the attempt. The walker reads the pane only where the pane is the
sole witness — gating *typing into* the composer (`cursor_in_composer`,
`composer_has_user_text`, `line_landed`, `is_unknown_command`). Nothing that asks whether an action
*took effect* looks at it. Each carries no opinion about the chrome around
what it reads: `line_landed` asks whether the composer holds the line just
typed, rather than whether it holds anything — an idle composer is never
empty, since the TUI paints a faint suggestion into it — and the pre-send bail
keys on the **cursor**, the only signal that separates that suggestion from
something a person typed, with the composer's start column derived from the
captured line rather than pinned to today's layout. Both poll rather than
sampling once: the pane does not always repaint within `VERIFY_DELAY`, and
read once, a late repaint is indistinguishable from a swallowed keystroke.
Their fixtures are captures from a live TUI, and `just tui-conformance`
asserts those captures still match one — a hand-written fixture is how a
predicate comes to be tested against its own premise, which is what let
`is_typing` sit inverted against a U+00A0 composer gap while its suite stayed
green. [Composer predicates match the real
pane](../changelog/2026-08-13-predicates-match-the-real-pane.md)

## Submitting: press, retry, then wait

Every TUI submit sends Enter, retries three times fast, then waits without
pressing again — a registered Enter can take far longer than `VERIFY_DELAY`
to reach its signal, and a composer that already took the first would submit
the turn twice. Delivery and confirmation are one question there: the only
evidence the keystroke arrived is the thing it caused.

## The relaunch splits delivery from confirmation

The relaunch line separates them, which is what a shell prompt allows. The
pane's foreground leaving the shell says the line ran, and says it
immediately, so Enter repeats only while the shell is still in front and the
happy path presses once. Confirmation — the sentinel going, which the resumed
session's `SessionStart` does — is then waited for without touching the pane.
Retrying against that signal instead is guaranteed to press again before it
can arrive, since a whole Claude Code boot sits in between, and those presses
land in a starting session where an Enter answers whatever dialog is on
screen rather than costing an empty prompt line.
[The relaunch presses Enter once](../changelog/2026-08-14-relaunch-presses-once.md)
Neither suite reaches the whole path: confirming a `/compact` needs a real
compaction, so the submit primitives are proven only by driving a transition
for real against the change that touched them. That dogfood is part of
landing such a change, not a follow-up to it — until 2026-08-13 the Enter-and-
confirm path had never once executed in production, because every driven line
aborted at the composer check before reaching it, and its unit suite was green
throughout. [The first driven transition to
land](../changelog/2026-08-13-first-driven-transition-lands.md)
The first end-to-end restart dogfood, 2026-08-15, found the next thing only
that path could show: `/exit` and the relaunch landed, but the continuation
line — driven by a second, separate walker that `load-restart.sh` spawns at
`SessionStart(resume)` — did not. `_drive_line`'s budget (near-instant
`wait_for_idle`, a 0.5s verify sleep, a 3s landing poll) was sized for driving
a TUI that is already running, true for `/compact`/`/clear`'s continuations
since their `SessionStart` fires on a live process, but `restart`'s
continuation is the one case that budget faces a process that has just exec'd
and is reading nothing yet — measured at 3.9s for a bare launch of this
plugin's own hook chain to render a composer. `wait_for_composer` runs ahead
of every other check in `_drive_line` for that reason, and is a no-op
mid-session, where the composer has been reading for minutes. [The
continuation waits for the composer to
exist](../changelog/2026-08-15-continuation-waits-for-the-composer-to-exist.md)

What that gate asks is where the terminal **cursor** is, not whether a `❯` is
on screen. A glyph is not evidence of a live composer: the conversation a
`--resume` replays can hold one as text once the TUI is up, and a shell's own
prompt or scrollback can carry one before Claude Code starts at all.
`cursor_in_composer` is the complement of `composer_has_user_text` one column
along — same frame, same two indices — over two consecutive readings, which is
`wait_for_foreground_change`'s rule, so a mid-boot repaint that flashes the
right shape does not open it.

The gate rests on two grounds. The glyph is one. The other is that the window
in which a resuming process actually *loses* input closes before the gate can
open: measured against a real resume, that loss is a discrete band roughly
1–1.5s wide, 1.7–3.3s after the relaunch line runs, with keystrokes either
side of it kept — it ends about 2s before the alternate-screen switch and
2.5–3.7s before the gate opens, and what bounds it is not identified. From
the cursor onward input is kept whatever the pane shows: it is buffered and
painted seconds later, in full and in order. So nothing is owed after the
gate, and the line is typed the moment it opens. [The landing window is sized
by the boot, not a
settle](../changelog/2026-09-21-the-landing-window-is-sized-by-the-boot.md)

`cursor_in_composer` is true for a cursor anywhere below a `❯` row, which is
what lets it work on a composer that has scrolled, and is an open residual: a
bare shell whose prompt or scrollback carries one opens the gate at the shell
within half a second, with `booting` false, so the continuation is typed ahead
of or into the loss band and given the short window below. Requiring
`#{alternate_on}` — Claude Code runs on the alternate screen — or requiring
the glyph row to carry the composer's U+00A0 gap would each close it. Neither
is taken.

## Two landing windows

The wait for a paint belongs behind the keystroke, not in front of it.
`wait_for_composer` returns `(opened, booting)`: whether a composer ever
appeared, and whether it was absent on the first reading. The second is the
caller's only evidence that this is a process still starting rather than a
session that has been reading input for minutes, and it picks the window
`wait_for_landing` polls for — `HANDOFF_WATCHER_BOOT_LANDING_DELAY` (30s),
wide enough for a paint nothing bounds, or `HANDOFF_WATCHER_LANDING_DELAY`
(3s) everywhere else.

Not one window widened, because the short one is also how long the walker
waits before reporting a keystroke it believes was swallowed. Mid-session the
composer has been reading for as long as the session has, and a line that has
not appeared in it is not one that will, so granting the boot window there
would buy half a minute of silence on the one report that says a line was
lost.

A delivered line records what each step cost. The walker is detached and its
output goes nowhere, so `watcher_log` — the success-side sibling of
`watcher_fail` — appends one JSON row per line to `.claude/autodrive.log`
(`HANDOFF_LOG_FILE`, exported beside `HANDOFF_FAIL_FILE`): `gate`, `idle`,
`landed` and `confirmed`, each the time its own step took. Nothing sleeps
between them, so `gate` alone is how long a boot took to put the cursor in the
composer and `landed` is how long the session then took to paint a line it had
already taken — the number `BOOT_LANDING_DELAY` is sized against, and one only
a real boot supplies. Nothing consumes the file, so it keeps its last 50 rows,
and a failed write is swallowed — the line is already delivered.

## Typing into a bare shell

`claude --resume …` skips those composer checks entirely: it
targets a bare shell once `/exit` is confirmed, where neither the `❯`
composer glyph nor the "No commands match" text exist, and neither is a
reliable signal of a shell's own readiness across every user's shell prompt.
What stands in is the pane's own foreground command. Claude Code stops
consuming input well before it releases the terminal, and a keystroke sent
inside that window is dropped leaving no trace, so the line waits until
`#{pane_current_command}` reads as something other than the baseline sampled
before the sequence began. `HANDOFF_WATCHER_SHELL_SETTLE` survives that gate
as a bounded residual: the shell still redraws its prompt once it has the
foreground back, and that part is not separately observable.
[Restart drive repair](../changelog/2026-08-13-restart-drive-repair.md)

## Recognizing the relaunch line

Which line that is, the walker decides from the line itself — it is handed
literal keystrokes and knows no kinds. It parses the line as a shell word list
and matches argv[0]'s basename against `claude`, with `--resume` among the
arguments. A parse rather than a prefix test on the one spelling that reaches
it today: while `stop-drive.sh` rewrote the slot into the exiting process's
argv, argv[0] was the resolved binary, so the line began with `/` and read as
a slash command — the prefix test recognized only the shape nothing typed. The
`--resume` conjunct keeps a continuation prompt that opens with the word
`claude` as prose.
[Dispatch on the command, not the prefix](../changelog/2026-08-14-resume-line-dispatch.md)

## Reporting a non-delivery, sweeping a stale sentinel

A detached walker's exit status is read by nothing, so non-delivery is
written to `.claude/autodrive.failed` and reported by
`report-watcher-failure.sh` at the next `UserPromptSubmit` — the first
moment anything can act on the news. That hook also sweeps a sentinel still
in state `armed`, left by a turn that ended on Esc or a crash:
`UserPromptSubmit` is the exact discriminator, since it cannot fire between
the write and that turn's own `Stop`. A file that will not parse is swept
too — it describes no transition anyone can complete. `held` is exempt while
it belongs to the session at the prompt, and that is why the sweep names its
states rather than taking anything that is not `pending`.

## The prepare-only compact

The prepare-only compact path arms the kind line alone. Nothing is typed,
but the transition is *expected*, and that expectation is what
`SessionStart(compact)` gates the frame's re-injection on — otherwise a
hand-typed `/compact` re-injects nothing.

## A restart carries no frame

`load-restart.sh` (`SessionStart(resume)`) never assembles or injects the
task-frame the way `load-compact.sh` and `load-handoff.sh` do: `--resume`
already restores the full prior conversation on its own, so there is nothing
for a frame to hand a summariser's paraphrase back to. The only effect there
is firing whatever continuation was typed after the resume — which is the
whole reason a restart costs no context at all.

## A restart that fails partway

A restart that fails partway has no live session to report into: if `/exit`
itself never lands, the original session is still up and its own next
`UserPromptSubmit` reports the non-delivery as usual; if `/exit` succeeds but
the resume command then fails, that session is gone, and the report waits —
`report-watcher-failure.sh`'s files are project-scoped, so whatever session
next opens in that directory drains `.claude/autodrive.failed` at its own
first `UserPromptSubmit`, however much later that is. A deferred report, not
a lost one.
