# Driven restart: the continuation line did not land (2026-09-20 12:43)

Diagnosis only — nothing edited, nothing committed, no live TUI started, no
tmux socket touched.

## What actually happened, from the transcripts

Session `ad3489de-…` (`~/.claude/projects/-Users-david-code-handoff/ad3489de-ef12-4b5b-a8e0-f6db60b45d11.jsonl`):

| time (UTC) | event |
|---|---|
| 12:43:10.541 | `Stop` hook: `handoff: will run /exit once the prompt is idle (tmux pane %48)` — before-walker spawned by `stop-drive.sh` |
| 12:43:25.670 | `SessionStart:resume`, handoff hook: `handoff: resumed — will run "re-check whether the masking bind mounts are gone and remove the leftover phantom files if so" once the prompt is idle (tmux pane %48)` — `load-restart.sh` consumed the pending sentinel and spawned the continuation walker |
| 12:43:25.691 | gitmoji `SessionStart:resume` hook output |
| **12:43:46.152** | **gitlore `SessionStart:resume` hook output** — i.e. SessionStart hooks were still running **21 s after** the walker was spawned |
| 12:44:50.899 | user typed `restart removed the sandbox mounts\nhandoff and commit, clear, pending` |
| 12:44:51.231 | `UserPromptSubmit`: `handoff: transition watcher did not deliver — \`re-check whether the masking bind mounts are gone and remove the leftover phantom files if so\` did not land in the composer — a dead pane or copy mode may have swallowed it.` |

Three facts fall out of this and they constrain everything below.

1. **The recorded failure is `wait_for_landing`, not `wait_for_composer`.**
   The message is the one at `scripts/drive_when_idle.py:137-141`
   (`did not land in the composer — a dead pane or copy mode may have
   swallowed it`), *not* the boot-gate message at
   `scripts/drive_when_idle.py:110-112` (`was never typed: no composer
   appeared before boot timeout`). So `wait_for_composer`
   (`scripts/_watcher_lib.py:197-219`) **returned True**: it found a `❯`
   somewhere in `capture_full(pane)`, the walker proceeded through
   `wait_for_idle`, sent the line literally with `send-keys -l`, and the line
   was not visible in the composer region for the next 3 s.

2. **The line carries no ellipsis.** The `…` in the brief came from my human
   partner's own paraphrase in a later session (`c4779a43-…`,
   `e8535a4b-…`); the walker's own message quotes the line whole. So nothing
   here is evidence of composer truncation.

3. **The composer was empty when the user typed 65 s later.** The
   12:44:50 user message is clean prose with no prefix of the continuation
   line concatenated onto it. `_drive_line` bails *before* pressing Enter and
   does **not** clear the composer on the landing failure (the `C-u` at
   `drive_when_idle.py:143-147` is only on the slash-rejection path), so had
   the text landed-but-repainted-late it would still have been sitting there
   and would have prefixed the user's own prompt. It did not. The keystrokes
   were genuinely lost.

## Most likely cause

**`wait_for_composer` tests for the glyph's presence anywhere in the pane
capture, which is not the same question as "is there a composer reading
stdin".** `scripts/_watcher_lib.py:216`:

```python
if PROMPT_GLYPH in strip(capture_full(pane)):
    return True
```

The gate added on 2026-08-15 closed the case where the pane had **no** glyph
at all — which is exactly what the stub row stages
(`tests/test_drive_when_idle.py:748-798`: `booting` is a clean box with no
`❯`, flipped to `❯ ` after 0.3 s). It does not close the case where a glyph is
on screen but is not a live, input-accepting composer. Under
`claude --resume` on this box both of the following are live-only conditions
the stub cannot express:

- the pane still carries the **previous session's rendered frame and the
  `--resume` transcript replay** above the boot chrome — and in *this* repo
  the replayed conversation is about the walker itself, so a literal `❯`
  in replayed text is entirely plausible. `_composer_region`
  (`_watcher_lib.py:128-143`) anchors on the **last** glyph row, so if the
  last glyph on screen belongs to replayed text, `line_landed` is asking the
  wrong rows and can never become true;
- Claude Code paints its composer early in boot while `SessionStart` hooks
  are still running. The transcript proves the hook chain ran for **at least
  21 s** past the walker's spawn (gitlore finished at 12:43:46). A composer
  painted during that window is chrome, not an input sink.

Either way the walker's whole post-gate budget is
`wait_for_idle` (~0.3 s: three stable polls, boot shows no spinner —
`_watcher_lib.py:222-240`) + `VERIFY_DELAY` 0.5 s + `LANDING_DELAY` 3.0 s ≈
**3.8 s**, sampled from a moment the gate can open tens of seconds too early.
That is the same shape of defect 2026-08-15 fixed, one predicate along: the
2026-08-15 measurement was "3.9 s to a rendered composer on a *bare* launch";
nobody has measured "time from first `❯` on screen to first keystroke that
actually lands" for a `--resume` of a large conversation.

Code path, end to end:
`scripts/load-restart.sh:57-63` (spawn) → `drive_when_idle.py:220-231`
(`main` → `_drive_line`, since `_is_resume_line` is false for prose) →
`drive_when_idle.py:108-112` (`wait_for_composer`, opens early) →
`drive_when_idle.py:129` (`_send_literal`) →
`drive_when_idle.py:136-141` (`wait_for_landing` fails) →
`_watcher_lib.watcher_fail` → `.claude/autodrive.failed` →
`scripts/report-watcher-failure.sh` at the next `UserPromptSubmit`.

## The hypotheses, each against what the code does

**(a) A dialog/picker/summary screen whose chrome contains the glyph.**
Plausible as one *instance* of the mechanism above, and it is the only one
that would also survive a "wait for stability" fix. Against it specifically:
`claude --resume <sid>` with an explicit id shows no picker, and the
directory was already trusted. Not separately confirmable from the
transcript. Treat as a sub-case of the general "glyph ≠ live composer".

**(b) The glyph is present during boot before input is read.** *This is the
leading hypothesis.* Consistent with every recorded fact: the gate opened
(so a glyph existed), the send produced nothing in the composer region within
3 s, and the text was absent from the composer a minute later — which is what
a TUI that discards pending stdin when it takes the terminal into raw mode,
or a React tree not yet mounted on the input handler, produces. The 21 s of
`SessionStart` hooks documented above sizes the window generously. Nothing in
`_watcher_lib.py` distinguishes a painted composer from a reading one.

**(c) Timeouts too short.** Partly true and *necessary but not sufficient*.
`LANDING_DELAY` 3.0 s (`_watcher_lib.py:84`) is short for this box, but
fact 3 above (empty composer 65 s later) rules out the pure false-negative
reading — the line was not sitting there unpainted. Raising `LANDING_DELAY`
alone would not have delivered the line; it would only have widened the window
in which the *same* lost keystrokes were waited for. `BOOT_TIMEOUT` (30 s) was
not the binding constraint, since the gate opened rather than timing out.

**(d) `line_landed` defeated by wrapping/truncation.** Weak.
`_squash` (`_watcher_lib.py:146-147`) deletes **all** whitespace on both
sides, so a row wrap — even mid-word — still matches, and
`tests/test_watcher_lib.py:95-102` pins that. The captured composer in the
fixtures carries no box borders, only `─` rules above and below, so there is
no `│` to be interleaved into the squashed text. And fact 2 kills the
truncation premise. **One residual worth naming:** the wrap fixture at
`tests/test_watcher_lib.py:98-101` is *composed* (a capture split by hand),
not captured — so if today's composer wraps inside a bordered box, or
right-pads each row with a border glyph, `line_landed` would fail on a long
line and no offline test would see it. The continuation line here is 92
characters, so it certainly wrapped. This is the one hypothesis I could not
fully close from the repo, and the conformance row below closes it for one
extra assertion.

**(e) Wrong environment from `load-restart.sh`.** Ruled out. The hook's own
`systemMessage` names pane `%48`, the same pane the `Stop` walker drove
15 s earlier, so `TMUX_PANE` was right (`load-restart.sh:53-58`). It exports
`HANDOFF_FAIL_FILE` and `HANDOFF_TRANSCRIPT` and the failure *did* arrive
through `HANDOFF_FAIL_FILE`, which proves that export. `HANDOFF_PENDING_FILE`
is deliberately absent — a prose line confirms via the transcript, not the
sentinel. (Note the known trap of `SessionStart(resume)` carrying the
*resuming* cwd — `memory/ddaanet/sessionstart-resume-cwd.md` — but
`handoff_root` resolved correctly here, since the sentinel was found and
consumed.)

**(f) The launcher shim.** No mechanism: the shim affects the relaunched
process's flags, and that line landed — the session resumed. Ruled out.

**(g) The fish prompt glyph** (my own hypothesis, checked and ruled out).
`~/.config/fish/functions/fish_prompt.fish:60,77` ends the prompt with the
ASCII `>` suffix, not `❯`, so the shell prompt left on the pane by the
relaunch is not what opened the gate.

## What stays unknown

Which concrete thing carried the `❯` when the gate opened — replayed
transcript text, the previous frame, or a real-but-not-yet-interactive
composer — and how long after that first glyph the pane actually started
accepting keystrokes. Nothing in the failure record says; the walker records
a reason and no pane capture.

## Cheapest observation that would settle it

A `live` row in `tests/test_tui_conformance.py`, which is the only place
allowed to boot a real TUI (private socket, `just tui-conformance`):

> **`test_the_first_composer_glyph_is_not_yet_accepting_input`** — boot
> `claude --resume <a large session id>` in a pane whose scrollback already
> contains a literal `❯` (to model the post-`/exit` pane), then loop:
> record `t_glyph` = first `capture_full` containing `❯`; from `t_glyph`,
> every 250 ms `send-keys -l 'x'` once and poll `line_landed(snap, 'x')`;
> record `t_input` = first moment it lands. Assert nothing about the gap
> yet — **print it**. If `t_input − t_glyph` is materially > 3.8 s, (b) is
> confirmed with a number, and the number sizes the fix. While the pane is
> up, also capture the composer holding a 92-character line and assert
> `line_landed` on it — that closes residual (d) against a real wrap.

Offline, the row that is **red today** and should precede the fix:

> **`test_a_glyph_that_is_not_a_live_composer_does_not_open_the_boot_gate`**
> in `tests/test_drive_when_idle.py`, modelled on the 2026-08-15 row at
> line 748. Stage `pane_idle.txt` *and* `pane_after_l.txt` to a boot screen
> that **contains a `❯` in replayed-transcript text** (e.g.
> `"● the glyph is ❯ in _watcher_lib\n╭─ booting ─╮\n╰──────────╯"`) with
> `tmux_stub.compose(0, 0)` so the cursor is nowhere near it; after 0.3 s a
> thread writes the real composer and unlinks `pane_after_l.txt`. With
> `HANDOFF_WATCHER_LANDING_DELAY=0.1`, today's `wait_for_composer` opens on
> the first poll, the send is swallowed by the staged boot screen, and the
> walker exits non-zero having written the exact `did not land` reason —
> red. Fixed code waits and exits 0 with `-l|<line>|` in the stub log.
> (`TmuxStub` needs no new capability: `compose()` already stages the cursor
> and `pane_after_l.txt` already overrides the echo.)

## Proposed fix, as a prose outline

1. **Make the boot gate ask for a *live* composer, not a glyph.** Rewrite
   `wait_for_composer` (`_watcher_lib.py:197-219`) to require, in one
   reading of a single frame (`capture_full` + `cursor_position`, the same
   "must index the same frame" rule `composer_has_user_text` already obeys):
   the glyph row is the last glyph row, **and** the terminal cursor sits on
   that row at or past `composer_start_column`. A glyph in replayed text or
   in leftover chrome never has the cursor parked in it; a composer the TUI
   is actually reading does.
2. **Require the reading to be stable**, borrowing
   `wait_for_foreground_change`'s two-consecutive-readings rule
   (`_watcher_lib.py:~250`): the cursor must be in the composer on two polls
   in a row, so a mid-boot repaint that flashes the right shape does not
   open the gate. Keep `BOOT_TIMEOUT` at 30 s; it never bound.
3. **Add a bounded settle after the gate** — a new
   `HANDOFF_WATCHER_BOOT_SETTLE` (default ~1 s), the same bounded-residual
   shape as `HANDOFF_WATCHER_SHELL_SETTLE` in `_drive_shell_line` — for the
   part that is not separately observable.
4. **Only then consider widening `LANDING_DELAY`.** Size it from the number
   the conformance row prints rather than by guess; on its own it is not the
   fix (see (c)).
5. **Make the next occurrence diagnosable**: have the landing failure include
   the last three rows of the composer region and the elapsed time since the
   gate opened, so the same investigation next time costs one read instead of
   a transcript archaeology pass. Today the message asserts two causes
   (`a dead pane or copy mode`) that were false on 2026-08-15 and false
   again here.
6. Steps 1–3 change what `driving-the-tui.md` argues about the boot gate and
   supersede the "polls for the glyph's mere presence" claim in
   `docs/changelog/2026-08-15-…md`, so the pass owes a new changelog entry
   plus the hub/node rewrite in the same commit.

Do **not** add a retype-on-non-landing retry: if a send ever does land
unpainted, a retype concatenates onto it, and `composer_has_user_text` cannot
distinguish that from a user mid-prompt.
