#!/usr/bin/env python3
"""Shared machinery for drive_when_idle.py, the one detached watcher.

Pure predicates over captured tmux pane text, the readers that feed them (snap,
capture_full, cursor_position), the pane-polling scaffold (wait_for_idle and the
four submit confirmations, all pane-scoped) and the tunables, read from the
environment at call time so tests can override them per call rather than at
import time.

Port of _watcher-lib.sh — see docs/changelog/2026-08-10-python-split.md.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

# A parsed transcript JSONL entry. Its shape is read defensively field by
# field below, never assumed — see _read_transcript_entries.
JSONDict = dict[str, Any]

_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def _env_float(name: str, default: float) -> float:
    """Read a tunable from the environment, falling back to ``default``."""
    return float(os.environ.get(name, default))


def strip(text: str) -> str:
    """Strip ANSI escapes and carriage returns from captured pane text."""
    return _ANSI_RE.sub("", text).replace("\r", "")


def is_busy(text: str) -> bool:
    r"""Report whether the Claude TUI chrome spinner is on screen.

    The elapsed timer carries a unit per magnitude once it passes a minute —
    ``(37s ·`` becomes ``(8m 30s ·`` — so the seconds no longer abut the ``(``.
    Every gap is ``\s``, never a literal space, for the reason in line_landed:
    the TUI's own padding is not the ASCII one an author assumes.
    """
    return bool(
        re.search(r"\((?:[0-9]+[hm]\s)*[0-9]+s\s·|esc to interrupt", strip(text))
    )


PROMPT_GLYPH = "❯"


def line_landed(text: str, line: str) -> bool:
    """Report whether ``line`` is sitting in the composer.

    Asks for the text the walker just typed, rather than whether the composer
    is non-empty: an idle composer is *not* empty — the TUI paints a faint
    placeholder into it — so non-emptiness answers a different question than
    the caller is asking. Matching the line itself needs no opinion about the
    padding around it, which is what made the older predicate invert when that
    padding turned out to be U+00A0.

    Whitespace is squashed on both sides, so a composer row-wrap that splits
    the line — mid-word, at whatever width the pane happens to be — still
    matches.
    """
    wanted = _squash(line)
    return bool(wanted) and wanted in _squash(_composer_region(text))


def wait_for_landing(pane: str, line: str, *, booting: bool) -> bool:
    """Poll until ``line`` is in the composer, for a window the caller picks.

    A single read at VERIFY_DELAY is a race the pane loses often enough to
    matter: the composer had still not repainted 0.5s after the send on one
    run in four of the conformance probe, showing its idle placeholder where
    the line should have been. Read once, that is indistinguishable from a
    swallowed keystroke, and the walker aborts a line it successfully typed.

    How long that race can run depends on which pane this is. A booting
    process takes the keystrokes and paints them seconds later — measured at 3
    to 9s past the cursor over four resumes, the spread tracking the box's
    load — so BOOT_LANDING_DELAY is wide enough to cover a paint nobody can
    bound. Mid-session the composer has been reading for as long as the
    session has, and a line that has not appeared in it is not one that will,
    so LANDING_DELAY stays short: this window is also how long the walker
    waits before reporting a keystroke it believes was swallowed.
    """
    delay = (
        _env_float("HANDOFF_WATCHER_BOOT_LANDING_DELAY", 30.0)
        if booting
        else _env_float("HANDOFF_WATCHER_LANDING_DELAY", 3.0)
    )
    deadline = time.monotonic() + delay
    poll = _env_float("HANDOFF_WATCHER_POLL", 0.1)
    while time.monotonic() < deadline:
        if line_landed(snap(pane), line):
            return True
        time.sleep(poll)
    return False


def composer_has_user_text(text: str, cursor_x: int, cursor_y: int) -> bool:
    """Report whether the user has something half-typed in the composer.

    Keys on the cursor, not the text, for the placeholder reason in
    line_landed: the glyph row carries painted characters either way, and only
    the cursor distinguishes the TUI's own suggestion from something a person
    typed.

    Residual: a user who has typed and then sent the cursor home reads as
    empty here. No signal on this pane separates that from an idle composer,
    and the walker's send would concatenate onto their text.
    """
    lines = strip(text).split("\n")
    index = _composer_index(lines)
    if index is None:
        return False
    if cursor_y != index:
        # Below the glyph row means their text wrapped onto it; above means
        # the cursor is not in the composer at all.
        return cursor_y > index
    return cursor_x > composer_start_column(lines[index])


def cursor_in_composer(text: str, cursor_x: int, cursor_y: int) -> bool:
    """Report whether the terminal cursor sits in a composer reading input.

    The same frame and the same two indices composer_has_user_text reads, one
    column along: that predicate asks whether the cursor is *past* the start
    column, this one whether it is in the composer at all. A ❯ in replayed
    transcript text or in boot chrome never has the cursor parked in it; a
    composer the TUI is actually reading does, at the start column when
    nothing is typed yet.

    A cursor on any row *below* the glyph row still counts, which is what
    makes this work on a composer that has scrolled. The glyph row itself
    must also carry the COMPOSER_GAP after the ❯ (see _composer_index),
    which is what keeps a bare shell's prompt or scrollback — its ❯ padded
    with an ordinary ASCII space — from opening the gate.

    Residual: a shell prompt that happens to pad its own ❯ with a NO-BREAK
    SPACE would still read as a live composer.
    """
    lines = strip(text).split("\n")
    index = _composer_index(lines)
    if index is None:
        return False
    if cursor_y != index:
        return cursor_y > index
    return cursor_x >= composer_start_column(lines[index])


def composer_start_column(line: str) -> int:
    """Return where composer content begins, derived from the line itself.

    Never a constant. The glyph's column and the width of the gap after it are
    the TUI's layout, and pinning today's values is exactly what makes a
    predicate invert in silence when they move.
    """
    index = line.find(PROMPT_GLYPH)
    after = line[index + 1 :]
    return index + 1 + (len(after) - len(after.lstrip()))


def _composer_region(text: str) -> str:
    """Return the composer's rows: the last glyph row through end of capture.

    The conversation renders above the composer, so starting at the last glyph
    is what stops a prose line quoted earlier in the scrollback from matching.
    """
    lines = strip(text).split("\n")
    index = _composer_index(lines)
    return "\n".join(lines[index:]) if index is not None else ""


def composer_excerpt(text: str, rows: int = 3) -> str:
    """Return the composer's first non-blank ``rows``, for a failure to quote.

    A non-delivery is reported once, into a file nobody can re-run, so the
    report carries what a reader would otherwise reconstruct from transcript
    archaeology: what the composer held at the moment the line was given up
    on. Counted from the glyph row down, which is where a typed line and its
    wraps are — the rows below it are the box rule and the status chrome.
    """
    lines = [line for line in _composer_region(text).split("\n") if line.strip()]
    return "\n".join(lines[:rows])


def _composer_index(lines: list[str]) -> int | None:
    """Return the last row that is genuinely the composer, or None.

    A shell prompt's ❯ is padded with an ordinary ASCII space; the TUI's
    composer pads the same glyph with U+00A0 (COMPOSER_GAP). That one character
    is what keeps a shell prompt — or one sitting in scrollback — from reading
    as a composer.
    """
    for index in range(len(lines) - 1, -1, -1):
        if PROMPT_GLYPH + COMPOSER_GAP in lines[index]:
            return index
    return None


COMPOSER_GAP = "\N{NO-BREAK SPACE}"


def _squash(text: str) -> str:
    return re.sub(r"\s+", "", strip(text))


def is_unknown_command(text: str) -> bool:
    """Report whether the composer holds a command the TUI will not run."""
    return "No commands match" in strip(text)


def snap(pane: str) -> str:
    """Capture the visible pane text (never scrollback), last 40 lines."""
    return "\n".join(capture_full(pane).split("\n")[-40:])


def capture_full(pane: str) -> str:
    """Capture every visible row, untruncated.

    composer_has_user_text compares the cursor's row against the glyph's, and
    both must be indices into the same frame — snap's 40-line tail would shift
    one and not the other.
    """
    result = subprocess.run(
        ["tmux", "capture-pane", "-p", "-t", pane],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout


def cursor_position(pane: str) -> tuple[int, int]:
    """Read the pane's cursor as ``(x, y)``, both 0-based rows/columns.

    An unreadable answer returns ``(-1, -1)``, which every caller reads as "no
    user text". Failing open is deliberate: the bail this feeds is protective,
    and failing closed would abort every line the walker ever types the moment
    this one query broke.
    """
    result = subprocess.run(
        ["tmux", "display-message", "-p", "-t", pane, "#{cursor_x},#{cursor_y}"],
        capture_output=True,
        text=True,
        check=False,
    )
    x, _, y = result.stdout.strip().partition(",")
    try:
        return int(x), int(y)
    except ValueError:
        return -1, -1


def wait_for_composer(pane: str, timeout: float | None = None) -> tuple[bool, bool]:
    """Poll until the pane holds a composer reading input, up to ``timeout``.

    Returns ``(opened, booting)``: whether a composer ever appeared, and
    whether it was absent on the first reading. The second is the caller's
    only evidence that this pane is a process still booting rather than a
    session that has been reading input for minutes, and it is what sizes the
    landing window the line is then given — see wait_for_landing.

    A freshly exec'd process — the state `restart`'s continuation walker
    always finds the pane in, since `SessionStart(resume)` fires at the very
    start of a new process's boot — reads no input for the first several
    seconds: SessionStart hooks, a --resume transcript replay, an
    autoMemoryDirectory settings load all run before anything reads a
    keystroke. wait_for_idle only reads the busy spinner's absence, which a
    boot screen satisfies at once, so without this gate a line got typed into
    a screen nothing was reading and lost for good.

    The glyph's mere presence answered a different question, which is how a
    continuation was lost a second time on 2026-09-20: under `claude --resume`
    the pane still carries the exited session's frame and the replayed
    conversation, so a ❯ is on screen from the first moment. The cursor is the
    discriminator — replayed text and boot chrome never have it parked in
    them — and two consecutive readings are asked for, so a mid-boot repaint
    that flashes the right shape does not open the gate, the same rule
    wait_for_foreground_change uses.

    What the cursor buys is the whole loss window, and nothing is owed after
    it. A resuming process loses input over a discrete band, measured at 1 to
    1.5s wide and 1.7-3.3s after the relaunch line runs, with keystrokes
    either side of it kept — typed by hand, `aoeuidhtnsaoe` arrived as
    `aoeunsaoe`. What bounds that band is not identified; it closes about 2s
    before the alternate-screen switch and 2.5-3.7s before this gate opens.
    From the cursor onward input is kept whatever the pane shows: it is
    buffered and painted seconds later, in full and in order. So the gate ends
    here, and the wait for the paint belongs to the line, after it is typed.

    Mid-session, where the caller is about to type into a composer that has
    been reading for minutes, this whole gate costs one poll.
    """
    if timeout is None:
        timeout = _env_float("HANDOFF_WATCHER_BOOT_TIMEOUT", 30.0)
    poll = _env_float("HANDOFF_WATCHER_POLL", 0.1)
    deadline = time.monotonic() + timeout
    seen = 0
    was_absent = False
    while time.monotonic() < deadline:
        if cursor_in_composer(capture_full(pane), *cursor_position(pane)):
            seen += 1
            if seen >= 2:
                return True, was_absent
        else:
            seen = 0
            was_absent = True
        time.sleep(poll)
    return False, was_absent


def wait_for_idle(pane: str) -> None:
    """Wait until idle is stable for ~3 consecutive polls, up to TIMEOUT.

    Falls through on timeout — the caller's composer_has_user_text check is the
    real gate against typing over a live composer.
    """
    timeout = _env_float("HANDOFF_WATCHER_TIMEOUT", 30)
    poll = _env_float("HANDOFF_WATCHER_POLL", 0.1)
    deadline = time.monotonic() + timeout
    stable = 0
    while time.monotonic() < deadline:
        if is_busy(snap(pane)):
            stable = 0
            time.sleep(poll)
            continue
        stable += 1
        if stable >= 3:
            return
        time.sleep(poll)


def wait_for_foreground_change(pane: str, baseline: str, timeout: float) -> bool:
    """Wait until the pane's foreground command is no longer ``baseline``.

    Claude Code stops consuming input well before it releases the terminal,
    and a keystroke sent inside that window is dropped leaving no trace: the
    pane looks untouched and the line simply never appears. The foreground
    command reverting from Claude Code to the pane's own shell is the
    observable end of that window, which a fixed sleep can only guess at.

    Two consecutive readings, so a transient during teardown does not release
    the gate early. Returns False on timeout rather than raising — the walker
    owns failure for the whole sequence.
    """
    poll = _env_float("HANDOFF_WATCHER_FOREGROUND_POLL", 0.1)
    deadline = time.monotonic() + timeout
    seen = 0
    while time.monotonic() < deadline:
        if pane_foreground(pane) != baseline:
            seen += 1
            if seen >= 2:
                return True
        else:
            seen = 0
        time.sleep(poll)
    return False


def pane_foreground(pane: str) -> str:
    """Read what tmux reports as the pane's foreground process."""
    result = subprocess.run(
        ["tmux", "display-message", "-p", "-t", pane, "#{pane_current_command}"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip()


def _submit_until(pane: str, check: Callable[[], bool]) -> bool:
    """Enter, then wait for ``check()`` to pass.

    Retry 3x, then poll long without pressing again: a registered Enter can take
    far longer than VERIFY_DELAY to reach the signal, and a composer that
    already took the first one would submit the turn twice.
    """
    verify_delay = _env_float("HANDOFF_WATCHER_VERIFY_DELAY", 0.5)
    consume_timeout = _env_float("HANDOFF_WATCHER_CONSUME_TIMEOUT", 300)
    consume_poll = _env_float("HANDOFF_WATCHER_CONSUME_POLL", 1)

    for _ in range(3):
        subprocess.run(["tmux", "send-keys", "-t", pane, "Enter"], check=False)
        time.sleep(verify_delay)
        if check():
            return True

    deadline = time.monotonic() + consume_timeout
    while time.monotonic() < deadline:
        if check():
            return True
        time.sleep(consume_poll)
    return False


def submit_consumed(pane: str) -> bool:
    """Confirm /compact and /clear: HANDOFF_PENDING_FILE disappearing."""
    pending = os.environ.get("HANDOFF_PENDING_FILE", "")
    if not pending:
        subprocess.run(["tmux", "send-keys", "-t", pane, "Enter"], check=False)
        return True
    return _submit_until(pane, lambda: not Path(pending).exists())


def submit_launched(pane: str, shell: str) -> bool:
    """Confirm a shell line ran: the pane's foreground leaving ``shell``.

    The relaunch's own confirmation — HANDOFF_PENDING_FILE going, which the
    resumed session's SessionStart does — cannot arrive for seconds, because a
    whole Claude Code boot sits in between. Retrying Enter against it presses
    blind into a session that is already starting, where a stray Enter is not
    the empty prompt line it would be at a shell: it answers whatever dialog
    the new session happens to be showing.

    The foreground command leaving the shell says the line ran, and says it at
    once. So Enter repeats only while the shell is still in front — evidence
    the keystroke has not been taken — and stops the moment something else is.
    """
    verify_delay = _env_float("HANDOFF_WATCHER_VERIFY_DELAY", 0.5)
    deadline = time.monotonic() + _env_float("HANDOFF_WATCHER_EXIT_TIMEOUT", 30.0)
    while time.monotonic() < deadline:
        subprocess.run(["tmux", "send-keys", "-t", pane, "Enter"], check=False)
        time.sleep(verify_delay)
        if pane_foreground(pane) != shell:
            return True
    return False


def wait_for_consumed() -> bool:
    """Wait for HANDOFF_PENDING_FILE to go, pressing nothing.

    The confirmation half of a line whose delivery is already established — see
    submit_launched. Unset tolerates the same way submit_consumed does: an
    unconfirmable submit is not a failed one.
    """
    pending = os.environ.get("HANDOFF_PENDING_FILE", "")
    if not pending:
        return True
    deadline = time.monotonic() + _env_float("HANDOFF_WATCHER_CONSUME_TIMEOUT", 300)
    poll = _env_float("HANDOFF_WATCHER_CONSUME_POLL", 1)
    while time.monotonic() < deadline:
        if not Path(pending).exists():
            return True
        time.sleep(poll)
    return False


def _read_transcript_entries(transcript: str) -> list[JSONDict]:
    if not transcript or not Path(transcript).is_file():
        return []
    entries: list[JSONDict] = []
    with Path(transcript).open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(entry, dict):
                entries.append(entry)
    return entries


def transcript_prompt_count(transcript: str, marker: str) -> int:
    """Count genuine user-prompt entries whose decoded text contains marker.

    "Genuine" excludes harness-injected user entries (isMeta, isCompactSummary,
    isSidechain) — only a real submitted prompt counts.
    """
    n = 0
    for entry in _read_transcript_entries(transcript):
        if entry.get("type") != "user":
            continue
        if (
            entry.get("isMeta")
            or entry.get("isCompactSummary")
            or entry.get("isSidechain")
        ):
            continue
        content = (entry.get("message") or {}).get("content")
        if isinstance(content, list):
            content = " ".join(
                block.get("text", "") for block in content if isinstance(block, dict)
            )
        if isinstance(content, str) and marker in content:
            n += 1
    return n


def transcript_title_count(transcript: str, title: str) -> int:
    """Count custom-title entries whose customTitle is EXACTLY title."""
    n = 0
    for entry in _read_transcript_entries(transcript):
        if entry.get("type") == "custom-title" and entry.get("customTitle") == title:
            n += 1
    return n


def submit_titled(pane: str, title: str) -> bool:
    """/rename <title>: confirmed by a custom-title entry carrying it."""
    transcript = os.environ.get("HANDOFF_TRANSCRIPT", "")
    baseline = transcript_title_count(transcript, title)
    return _submit_until(
        pane, lambda: transcript_title_count(transcript, title) > baseline
    )


def submit_prompted(marker: str, pane: str) -> bool:
    """Prose: confirmed by a new genuine user-prompt entry containing marker."""
    transcript = os.environ.get("HANDOFF_TRANSCRIPT", "")
    baseline = transcript_prompt_count(transcript, marker)
    return _submit_until(
        pane, lambda: transcript_prompt_count(transcript, marker) > baseline
    )


def submit_exited(pane: str) -> bool:
    """Confirm /exit: HANDOFF_EXIT_FILE appearing, then consume it.

    The opposite polarity of submit_consumed (which waits for a file to
    disappear): SessionEnd, not a SessionStart, is the confirming event, and it
    can only ever CREATE the marker — stop-drive.sh clears any copy a stale,
    only-partly-successful earlier restart left behind before spawning the
    walker, so a leftover cannot false-positive this attempt.
    """
    exit_file = os.environ.get("HANDOFF_EXIT_FILE", "")
    if not exit_file:
        subprocess.run(["tmux", "send-keys", "-t", pane, "Enter"], check=False)
        return True
    if _submit_until(pane, lambda: Path(exit_file).exists()):
        Path(exit_file).unlink(missing_ok=True)
        return True
    return False


def watcher_fail(reason: str) -> None:
    """Record a non-delivery reason, then raise SystemExit(1).

    Unset HANDOFF_FAIL_FILE is tolerated: recording is additive, never a
    precondition for driving the pane.
    """
    fail_file = os.environ.get("HANDOFF_FAIL_FILE", "")
    if fail_file:
        Path(fail_file).write_text(reason + "\n", encoding="utf-8")
    raise SystemExit(1)


def watcher_log(record: dict[str, Any]) -> None:
    """Append one delivered line's timings to HANDOFF_LOG_FILE, newest last.

    The success-side sibling of watcher_fail: the walker is detached and its
    output goes nowhere, so without this a delivery can only be timed by
    reading transcript timestamps around it. Nothing consumes the file, so it
    is kept to its last LOG_ROWS rows rather than left to grow, and a failure
    to write it is swallowed — the line is already delivered, and a record of
    that is never worth failing it for. Unset is tolerated, as there.
    """
    log_file = os.environ.get("HANDOFF_LOG_FILE", "")
    if not log_file:
        return
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    try:
        path = Path(log_file)
        rows = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
        rows.append(json.dumps({"at": stamp, **record}, ensure_ascii=False))
        path.write_text("\n".join(rows[-LOG_ROWS:]) + "\n", encoding="utf-8")
    except OSError:
        pass


LOG_ROWS = 50
