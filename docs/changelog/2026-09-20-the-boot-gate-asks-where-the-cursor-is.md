# 2026-09-20 — The boot gate asks where the cursor is

> **Superseded 2026-10-08** (see [The plugin becomes a
> mod](2026-10-08-the-plugin-becomes-a-mod.md)) wholly: the boot gate and the
> cursor predicates are removed with the walker.

The second end-to-end dogfood of a driven restart lost its continuation line
the same way the first one did, through the gate added to stop it:

```
handoff: transition watcher did not deliver — `re-check whether the masking
bind mounts are gone and remove the leftover phantom files if so` did not
land in the composer — a dead pane or copy mode may have swallowed it.
```

The transcripts fix what happened. `load-restart.sh` consumed the pending
sentinel and spawned the continuation walker 15s after `/exit`; the
`SessionStart` chain of that resumed session was still running **21s later**.
The recorded reason is `wait_for_landing`'s, not the boot gate's, so
`wait_for_composer` *returned true* — it found a `❯` in the capture, the
walker went on through `wait_for_idle` (a boot screen shows no spinner),
typed, and saw nothing in the composer for the next 3s. The user typed into
that pane 65s later and their own prompt carried no prefix of the
continuation, which rules out the line having landed unpainted: `_drive_line`
does not clear the composer on a landing failure, so text that had arrived
would still have been sitting there. The keystrokes were lost, not missed.

## The defect

`wait_for_composer` asked whether a `❯` was anywhere in the pane. That is not
the question the caller has. Under `claude --resume` the pane still carries
the exited session's last rendered frame and the replay of the conversation
being resumed — and in this repo that conversation is *about* the composer
glyph, so a literal `❯` in replayed text is not a contrived case. A glyph
that belongs to replayed text also defeats `line_landed` outright, since
`_composer_region` anchors on the **last** glyph row and would be reading rows
that can never hold the typed line.

The gate added on 2026-08-15 closed the case where the pane had no glyph at
all, which is what a bare `claude` launch shows. It could not close the case
where a glyph is on screen and nothing is reading input, and the whole
post-gate budget — `wait_for_idle` resolving at once, `VERIFY_DELAY` 0.5s,
`LANDING_DELAY` 3.0s — is about 3.8s sampled from whenever the gate opens.

## What was measured

> **Superseded 2026-09-21** (see [The landing window is sized by the boot, not
> a settle](2026-09-21-the-landing-window-is-sized-by-the-boot.md)) — scoped to
> the reading of the table, not the table. The row recorded when the *first*
> marker appeared in the composer and stopped; it never counted the markers
> sent before that moment, and counted, they are all there. So the pane does
> not discard keystrokes for 3 to 9 seconds past the cursor — it keeps them and
> paints them late. The four timings below stand as timings of the *paint*.

Sized from an observation rather than a guess, since nobody had measured a
`--resume`. A new `live` row in `tests/test_tui_conformance.py` boots
`claude --resume <sid>` in a shell pane on a private socket, then types a
marker every 250ms and polls for it. Resuming a 2.8MB transcript on the
author's box:

| moment | run 1 | run 2 | run 3 | run 4 |
|---|---|---|---|---|
| first `❯` on the pane | 3.56s | 8.18s | 6.57s | 11.18s |
| cursor in the composer | 3.61s | 8.23s | 6.64s | 11.27s |
| first keystroke the session kept | 6.80s | 13.40s | 15.17s | 18.57s |
| **glyph → input** | **3.23s** | **5.22s** | **8.59s** | **7.39s** |

So the cursor arrives with the glyph — 0.05s later, every time — and the pane
then discards keystrokes for another 3 to 9 seconds, tracking this box's load
rather than anything the pane shows. Two distinct failures, needing two
distinct answers:
the glyph a boot screen or a replay carries, which the cursor tells apart,
and the composer that is painted, holds the cursor, and is not yet reading,
which nothing on the pane tells apart at all.

## The fix

> **Superseded 2026-09-21** (see [The landing window is sized by the boot, not
> a settle](2026-09-21-the-landing-window-is-sized-by-the-boot.md)) — scoped to
> `HANDOFF_WATCHER_BOOT_SETTLE`, which is deleted. There was nothing for it to
> cover: input from the cursor onward is buffered, so the wait belongs behind
> the send, as `HANDOFF_WATCHER_BOOT_LANDING_DELAY`. `wait_for_composer` now
> returns `(opened, booting)` and the second is what picks that window. The
> cursor predicate this section describes, and its two-consecutive-readings
> rule, are unchanged.

`wait_for_composer` now requires `cursor_in_composer` — the terminal cursor
on the last glyph row at or past the composer's start column, or on a row
below it — over one frame, twice in a row. It is the complement of
`composer_has_user_text` one column along, reading the same frame and the same
two indices, and the two-consecutive-readings rule is
`wait_for_foreground_change`'s, so a mid-boot repaint that flashes the right
shape does not open the gate.

`HANDOFF_WATCHER_BOOT_SETTLE` (default 10.0s, above the slowest of the four
observations rather than near their middle) is the bounded residual for the
part that is not separately observable, the same shape as
`HANDOFF_WATCHER_SHELL_SETTLE` in `_drive_shell_line`. It is paid **only**
when the composer was absent on the first reading. Mid-session — every
`/rename`, `/compact` and `/clear` line, and the continuations of both other
driven kinds — the first reading already shows a live composer, and the whole
gate costs one poll.

## Alternatives weighed

> **Superseded 2026-09-21** (see [The landing window is sized by the boot, not
> a settle](2026-09-21-the-landing-window-is-sized-by-the-boot.md)) — scoped to
> the three bullets that turn on the settle. Raising `LANDING_DELAY` is what
> landed, for the boot branch alone and at 30s; the argument against it below
> is a true reading of *this* incident, where the line was typed into the loss
> window, and not a general argument against waiting for a paint. "Wait for the
> cursor and nothing else" is what the gate now does. The readiness probe stays
> parked, but not as the answer to a settle proving too short. The retype
> refusal is untouched.

**Raise `LANDING_DELAY`.** Necessary-looking and not sufficient. The composer
was empty 65s later, so there was no late repaint to wait for; a wider window
only waits longer for keystrokes that were already discarded. Left at 3.0s.

**Retype when the line does not land.** Refused, and it would be refused
again: if a send ever does land unpainted, a retype concatenates onto it, and
`composer_has_user_text` cannot tell that apart from a user mid-prompt.

**Wait for the cursor and nothing else.** What the diagnosis proposed, and
the measurement is what ruled it out as a complete fix — the cursor was in
the composer 3 to 9 seconds before the composer kept anything. Kept as half
of the answer because it is the half that generalises: it closes the
replayed-glyph case for good, where a settle only postpones it.

**Probe readiness instead of sleeping** — type one character, poll for it,
verify a `C-u` cleared it, then type the real line. It is the only variant
that would *measure* readiness rather than assume it, and the spread above is
an argument for it. Not taken now: it leaves a stray character in the user's
composer on every path where the clear is the keystroke that gets dropped,
and each step needs its own confirmation before it may be trusted. The row
below records it as the next move if the settle proves too short.

**A longer `BOOT_TIMEOUT`.** Never the binding constraint: the gate opened,
it did not time out. Left at 30s.

## Dogfooded

> **Superseded 2026-09-21** (see [The landing window is sized by the boot, not
> a settle](2026-09-21-the-landing-window-is-sized-by-the-boot.md)) — scoped to
> the record's `settle` key, which is gone with the tunable. Nothing sleeps
> between the steps now, so `gate` alone is the boot and `landed` is how long
> the session took to paint a line it had already taken — the number
> `BOOT_LANDING_DELAY` is sized against. `watcher_log` itself, its four other
> figures, the bounded file and the untested exports all stand.

A driven restart with a continuation, run against this working tree the same
night (the dev shim launches with `--plugin-dir <repo root>`, and hook scripts
are read when they run, so the gate that ran was this one). The continuation
landed. The transcript has `Stop` at 22:05:11Z and the continuation logged as
a user prompt at 22:05:47Z — 36 seconds covering `/exit`, the relaunch, the
boot, the gate, the settle and the send — and `.claude/autodrive`,
`.claude/autodrive.failed` and `.claude/autodrive.exited` were all gone
afterwards.

That is one delivery against a fault that was intermittent, so it shows the
fix can work, not that 10s always covers the window. It also showed what the
walker could not say for itself: those 36 seconds could only be read off
transcript timestamps, with no way to split the boot from the settle. So a
delivered line now records its own timings — `watcher_log`, the success-side
sibling of `watcher_fail`, appending one JSON row per line to
`.claude/autodrive.log` (`HANDOFF_LOG_FILE`, exported by the same four hooks
that export `HANDOFF_FAIL_FILE`; unset is tolerated). Each figure is the time
its own step took — `gate`, `idle`, `landed`, `confirmed` — beside the
`settle` in force, so `gate` minus `settle` is how long the composer took to
start reading: the number the settle is sized against, from real boots
instead of a conformance run. Nothing consumes the file, so it keeps its last
50 rows, and a failure to write it is swallowed, since the line is already
delivered. It is gitignored with the rest of `.claude/autodrive*`.

The exports are not pinned by a test of their own: the walker side is (a row
in `tests/test_drive_when_idle.py` that stages a 0.3s boot and reads the
record back, bounded file included), but the hooks spawn the walker detached,
and no synchronous seam shows what it was handed. A dropped export costs the
record and nothing else.

## Residual

> **Superseded 2026-09-21** (see [The landing window is sized by the boot, not
> a settle](2026-09-21-the-landing-window-is-sized-by-the-boot.md)) — scoped to
> the two paragraphs about the settle's sizing. There is no settle to outrun; a
> slow box costs a longer paint, which `BOOT_LANDING_DELAY` waits out. The
> keep-one-drop-the-next observation was the uncounted reading again: the
> markers either side of the one that first painted were in the composer with
> it. The report's wording, the printed-not-pinned rule and the wrap row below
> stand.

The settle is a fixed number sized on one box, and the four observations
spread by a factor of nearly three, so it is a bound on load rather than on
the mechanism. A machine slow enough to need more than 10s past its own
cursor gate loses the line again — reported, not silent, and the report now
says how long the pane had been reading and quotes what the composer actually
held, in place of the two causes the old message asserted (a dead pane, copy
mode) that were false both times it has fired. The readiness probe above is
what to reach for if that report arrives.

A resuming session also keeps one keystroke and then drops the next: the wrap
row had to retry to the deadline, and the run that first exposed it showed
eleven markers accepted and the following `C-u` and long send both lost. So
the window is not a clean before/after, which is another reason the settle
sits well past the observed mean.

The conformance row prints its numbers rather than asserting a threshold: a
pinned one would red on a faster or slower machine with nothing wrong. Re-run
`just tui-conformance` with `-s` to read them.

The same row, on an 80-column pane, also closes the one hypothesis the
diagnosis could not close from the repo — that `line_landed` might be
defeated by a real wrap. The offline wrap fixture is a capture split by hand;
this one types a 93-character line into a pane narrower than it and asserts
the predicate still sees it.
