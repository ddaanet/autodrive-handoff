"""Conformance probe: do the frozen pane fixtures still match a live TUI?

This is not a test of the predicates — ``tests/test_watcher_lib.py`` owns
those, offline and deterministic. It asserts the other half: that the strings
those tests freeze are still what Claude Code actually paints. A frozen fixture
cannot tell you it has gone stale, and that silence is what let ``is_typing``
sit inverted against a U+00A0 composer gap while its suite stayed green — see
``docs/changelog/2026-08-13-predicates-match-the-real-pane.md``.

Excluded from ``just precommit`` by the ``live`` marker: it needs a real
``claude`` on PATH and a real tmux server, so it cannot run inside the agent's
sandbox (which blocks socket creation), and it takes ~40s. Run it with
``just tui-conformance``.

It costs nothing to run. Every line is typed into the composer and then
cleared, never submitted, so no turn is ever taken.

Residual, deliberately uncovered: ``is_busy``'s timer forms. Reaching the
spinner at all needs a submitted turn, which this probe never does, so those
two fixtures stay frozen-only.
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterator
from pathlib import Path
from typing import NamedTuple

import _watcher_lib as wl
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_watcher_lib as fx

pytestmark = pytest.mark.live

REPO = Path(__file__).resolve().parent.parent

# Booting into a directory whose trust dialog has never been accepted parks a
# modal over the composer and every assertion below reads that instead. The
# repo root is already trusted, and its own SessionStart hooks only read.
PROBE_CWD = Path(os.environ.get("HANDOFF_CONFORMANCE_CWD", str(REPO)))

BOOT_TIMEOUT = 30.0
SETTLE = 12.0  # boot latency repaints the pane for several seconds after ❯


def _tmux(sock: str, *args: str) -> str:
    proc = subprocess.run(
        ["tmux", "-L", sock, *args], capture_output=True, text=True, check=False
    )
    return proc.stdout


def _capture(sock: str, pane: str) -> str:
    """Snapshot the pane the way the walker's own ``snap`` does."""
    return "\n".join(_tmux(sock, "capture-pane", "-p", "-t", pane).split("\n")[-40:])


def _composer_line(text: str) -> str:
    """Return the last ``❯`` line of a captured pane, verbatim."""
    lines = [ln for ln in wl.strip(text).split("\n") if "❯" in ln]
    return lines[-1] if lines else ""


def _type(sock: str, pane: str, line: str) -> str:
    """Type ``line`` and poll for it exactly as the walker does.

    Polls rather than reading once at VERIFY_DELAY, because the composer does
    not always repaint that fast — which is the race wait_for_landing exists to
    absorb, and asserting through it is what keeps this probe measuring the TUI
    rather than the paint latency of one run.
    """
    _tmux(sock, "send-keys", "-t", pane, "-l", line)
    deadline = time.monotonic() + wl._env_float("HANDOFF_WATCHER_LANDING_DELAY", 3.0)
    captured = _capture(sock, pane)
    while time.monotonic() < deadline and not wl.line_landed(captured, line):
        time.sleep(0.1)
        captured = _capture(sock, pane)
    return captured


def _clear(sock: str, pane: str) -> None:
    _tmux(sock, "send-keys", "-t", pane, "C-u")
    time.sleep(0.7)


def _foreground(sock: str, pane: str) -> str:
    """Read the pane's foreground command the way the walker's gate does."""
    return _tmux(
        sock, "display-message", "-p", "-t", pane, "#{pane_current_command}"
    ).strip()


def _cursor(sock: str, pane: str) -> tuple[int, int]:
    out = _tmux(sock, "display-message", "-p", "-t", pane, "#{cursor_x},#{cursor_y}")
    x, _, y = out.strip().partition(",")
    return int(x), int(y)


@pytest.fixture(scope="module")
def live_pane() -> Iterator[tuple[str, str]]:
    """Boot a real Claude Code TUI in a private tmux server; yield (sock, pane).

    A client is attached because an unattached server has no focus state to
    report, and the user's own tmux runs with ``focus-events on``.
    """
    for tool in ("tmux", "claude", "script"):
        if not shutil.which(tool):
            pytest.skip(f"{tool} not on PATH — conformance probe needs a real TUI")

    sock = f"handoff-conformance-{os.getpid()}"
    conf = Path(tempfile.gettempdir()) / f"{sock}.conf"
    conf.write_text("set -g focus-events on\nset -g status off\n", encoding="utf-8")

    client: subprocess.Popen[bytes] | None = None
    try:
        _tmux(
            sock,
            "-f",
            str(conf),
            "new-session",
            "-d",
            "-x",
            "200",
            "-y",
            "50",
            "-c",
            str(PROBE_CWD),
            "claude",
        )
        pane = _tmux(sock, "list-panes", "-t", "0", "-F", "#{pane_id}").split("\n")[0]
        if not pane:
            pytest.fail("tmux reported no pane — the probe server never started")

        client = subprocess.Popen(
            [
                "script",
                "-q",
                "-c",
                f"stty rows 50 cols 200; tmux -L {sock} attach -t 0",
                "/dev/null",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        deadline = time.monotonic() + BOOT_TIMEOUT
        while time.monotonic() < deadline:
            time.sleep(0.5)
            if "❯" in _capture(sock, pane):
                break
        else:
            pytest.fail(
                "the TUI never painted a ❯ composer within "
                f"{BOOT_TIMEOUT}s. Either it failed to boot, or the composer "
                f"glyph changed.\nPane:\n{_capture(sock, pane)}"
            )

        time.sleep(SETTLE)
        yield sock, pane
    finally:
        if client is not None:
            client.kill()
        _tmux(sock, "kill-server")
        conf.unlink(missing_ok=True)


@pytest.mark.parametrize(
    "line",
    ["/compact", "/rename Conformance Probe", "continue with the task"],
    ids=["slash", "slash-with-args", "prose"],
)
def test_composer_gap_is_still_the_frozen_one(
    live_pane: tuple[str, str], line: str
) -> None:
    """The load-bearing assertion: the gap character the fixtures encode.

    If this reds, re-capture and update ``test_watcher_lib``'s fixtures — the
    predicates match ``\\s`` and so will keep working, but the fixtures have
    stopped describing the pane and stop being evidence of anything.
    """
    sock, pane = live_pane
    _clear(sock, pane)
    captured = _composer_line(_type(sock, pane, line))
    _clear(sock, pane)
    assert captured == f"❯{fx.NBSP}{line}"


@pytest.mark.parametrize(
    "line",
    ["/compact", "/rename Conformance Probe", "continue with the task"],
    ids=["slash", "slash-with-args", "prose"],
)
def test_line_landed_sees_a_line_the_walker_just_typed(
    live_pane: tuple[str, str], line: str
) -> None:
    """The behaviour the frozen suite claims, against the real thing."""
    sock, pane = live_pane
    _clear(sock, pane)
    captured = _type(sock, pane, line)
    _clear(sock, pane)
    assert wl.line_landed(captured, line), (
        f"walker would abort on: {_composer_line(captured)!r}"
    )


def test_line_landed_false_on_the_live_idle_placeholder(
    live_pane: tuple[str, str],
) -> None:
    """Paired with the positives: the same pane, nothing typed.

    The composer is not empty when idle — the TUI paints a suggestion into it —
    so this is the row that catches a confirm predicate reverting to "is there
    anything here".
    """
    sock, pane = live_pane
    _clear(sock, pane)
    assert not wl.line_landed(_capture(sock, pane), "/compact")


def test_the_idle_placeholder_does_not_read_as_a_user_composing(
    live_pane: tuple[str, str],
) -> None:
    """The pre-send bail, against a real idle pane and a real cursor.

    Load-bearing: a false positive here aborts every line before the walker
    types it, and it would bite hardest right after a transition, where the
    composer is freshest and the placeholder is showing.
    """
    sock, pane = live_pane
    _clear(sock, pane)
    full = _tmux(sock, "capture-pane", "-p", "-t", pane)
    x, y = _cursor(sock, pane)
    assert not wl.composer_has_user_text(full, x, y), (
        f"idle composer read as a user mid-prompt: cursor=({x},{y}) "
        f"line={_composer_line(full)!r}"
    )


def test_a_typed_line_does_read_as_content_in_the_composer(
    live_pane: tuple[str, str],
) -> None:
    """Paired with the row above, over the same pane: the bail must still fire.

    Without this, widening the bail into always-False would pass unnoticed and
    the walker would type over a half-composed prompt.
    """
    sock, pane = live_pane
    _clear(sock, pane)
    _type(sock, pane, "half a prompt")
    full = _tmux(sock, "capture-pane", "-p", "-t", pane)
    x, y = _cursor(sock, pane)
    _clear(sock, pane)
    assert wl.composer_has_user_text(full, x, y), (
        f"typed text did not read as composing: cursor=({x},{y})"
    )


def test_is_unknown_command_still_matches_the_rejection_text(
    live_pane: tuple[str, str],
) -> None:
    """``is_unknown_command`` greps a bare substring, so it is exposed too.

    A gap the TUI repaints inside this sentence would break it exactly the way
    the composer gap broke is_typing, and nothing else would notice.
    """
    sock, pane = live_pane
    _clear(sock, pane)
    captured = _type(sock, pane, "/compzzz-no-such-command")
    # Poll past VERIFY_DELAY: "never painted" and "painted too late for the
    # walker to see it" are different defects and want different fixes.
    seen_at: float | None = None
    waited = wl._env_float("HANDOFF_WATCHER_VERIFY_DELAY", 0.5)
    for target in (0.5, 1.0, 2.0, 4.0, 8.0):
        if target > waited:
            time.sleep(target - waited)
            waited = target
            captured = _capture(sock, pane)
        if wl.is_unknown_command(captured):
            seen_at = waited
            break
    _clear(sock, pane)
    window = wl._env_float("HANDOFF_WATCHER_RECOGNITION_DELAY", 3.0)
    assert seen_at is not None, (
        "the TUI never painted 'No commands match' within 8s — the walker "
        f"would Enter a command it has already rejected.\nPane:\n{captured}"
    )
    assert seen_at <= window, (
        f"'No commands match' took until {seen_at}s, past the walker's "
        f"{window}s recognition window, so the check gives up before the "
        "rejection is painted and the command goes through to Enter"
    )


@pytest.fixture
def shell_hosted_pane() -> Iterator[tuple[str, str, int]]:
    """Boot a TUI *inside a shell*; yield (sock, pane, claude_pid).

    ``live_pane`` runs ``claude`` as the pane command itself, which can only
    ever answer half of the question below: with no shell underneath, there is
    nothing for the foreground to revert to. A real user's pane hosts the TUI
    in their shell, and that is the arrangement the restart gate reads.
    """
    for tool in ("tmux", "claude", "script", "ps"):
        if not shutil.which(tool):
            pytest.skip(f"{tool} not on PATH — conformance probe needs a real TUI")

    sock = f"handoff-foreground-{os.getpid()}"
    conf = Path(tempfile.gettempdir()) / f"{sock}.conf"
    conf.write_text("set -g focus-events on\nset -g status off\n", encoding="utf-8")

    client: subprocess.Popen[bytes] | None = None
    try:
        _tmux(
            sock, "-f", str(conf), "new-session", "-d",
            "-x", "200", "-y", "50", "-c", str(PROBE_CWD), "/bin/sh",
        )  # fmt: skip
        pane = _tmux(sock, "list-panes", "-t", "0", "-F", "#{pane_id}").split("\n")[0]
        if not pane:
            pytest.fail("tmux reported no pane — the probe server never started")

        client = subprocess.Popen(
            [
                "script",
                "-q",
                "-c",
                f"stty rows 50 cols 200; tmux -L {sock} attach -t 0",
                "/dev/null",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(1)
        _tmux(sock, "send-keys", "-t", pane, "-l", "claude")
        _tmux(sock, "send-keys", "-t", pane, "Enter")

        deadline = time.monotonic() + BOOT_TIMEOUT
        while time.monotonic() < deadline:
            time.sleep(0.5)
            if "❯" in _capture(sock, pane):
                break
        else:
            pytest.fail(f"the TUI never booted within {BOOT_TIMEOUT}s")

        time.sleep(SETTLE)
        shell_pid = _tmux(sock, "display-message", "-p", "-t", pane, "#{pane_pid}")
        children = subprocess.run(
            ["ps", "-o", "pid=", "--ppid", shell_pid.strip()],
            capture_output=True, text=True, check=False,
        )  # fmt: skip
        pids = [int(p) for p in children.stdout.split()]
        if not pids:
            pytest.skip("could not identify the claude child of the pane's shell")
        yield sock, pane, pids[0]
    finally:
        if client is not None:
            client.kill()
        _tmux(sock, "kill-server")
        conf.unlink(missing_ok=True)


def test_foreground_command_distinguishes_the_tui_from_the_shell(
    shell_hosted_pane: tuple[str, str, int],
) -> None:
    """The premise wait_for_foreground_change is built on.

    The stub answers ``#{pane_current_command}`` with whatever a test staged,
    so every offline test of that gate passes on an assumption: that tmux
    reports one thing while Claude Code holds the terminal and another once it
    lets go. If those two readings were equal the gate could never fire and
    every driven restart would fail closed, and no offline suite could tell —
    the stub is the thing asserting the premise.

    Observed 2026-08-13 on tmux 3.5a: ``claude`` while running, ``sh`` 0.75s
    after release. This is a format string's behaviour, not a documented
    contract, which is why it is pinned against a real server rather than
    assumed.

    The release is triggered with a signal rather than ``/exit``: what the gate
    polls is the foreground reverting, and ``submit_exited`` already owns
    whether ``/exit`` itself lands.
    """
    sock, pane, claude_pid = shell_hosted_pane

    assert _foreground(sock, pane) == "claude"

    os.kill(claude_pid, signal.SIGTERM)
    deadline = time.monotonic() + 10.0
    released = _foreground(sock, pane)
    while time.monotonic() < deadline and released == "claude":
        time.sleep(0.25)
        released = _foreground(sock, pane)

    assert released != "claude", (
        "the pane's foreground still reads `claude` 10s after the process was "
        "terminated, so wait_for_foreground_change can never fire and every "
        "driven restart fails closed. The #{pane_pid} alternative recorded in "
        "docs/design/rejected-alternatives.md is the fallback."
    )
    assert released == "sh"


# The continuation line of the 2026-09-20 restart that lost its keystrokes,
# verbatim. Longer than the 80-column pane below, so it wraps for real — the
# one residual the offline wrap fixture cannot close, since that one is a
# capture split by hand rather than a capture of a wrap.
LONG_LINE = (
    "re-check whether the masking bind mounts are gone and remove the "
    "leftover phantom files if so"
)

# Typed repeatedly from the first glyph on. Nothing the TUI paints by itself
# contains it, so a landing reading cannot come from the idle placeholder.
PROBE_MARKER = "zqxjv"

# A resume large enough to exercise the boot the walker races, small enough
# not to OOM a 2GB box next to the session running the probe.
MAX_RESUME_BYTES = 3_000_000

RESUME_TIMEOUT = 120.0


def _resumable_session_id() -> str:
    """Pick a past session of this project to resume: the largest stale one.

    Stale by an hour and never the session running the probe: resuming a live
    conversation would have two processes writing one transcript.
    """
    project = Path.home() / ".claude" / "projects" / str(PROBE_CWD).replace("/", "-")
    live = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    cutoff = time.time() - 3600
    candidates = [
        path
        for path in project.glob("*.jsonl")
        if path.stem != live
        and path.stat().st_mtime < cutoff
        and path.stat().st_size <= MAX_RESUME_BYTES
    ]
    if not candidates:
        pytest.skip(f"no stale session transcript under {project} to resume")
    return max(candidates, key=lambda path: path.stat().st_size).stem


# What the pane already holds when the relaunch line is typed into it. The
# default stages a literal ``❯`` above the shell's cursor — the arrangement the
# glyph-presence gate was fooled by. Overridden per row through `indirect`,
# because what a real ``/exit`` leaves behind is a question with an answer:
# Claude Code runs on the alternate screen (`#{alternate_on}` flips to 1 part
# way through boot), so the exited session's frame is discarded and the restored
# normal screen carries no ``❯`` at all — measured 2026-09-21 on CC 2.1.278.
PREVIOUS_SCREEN = "❯ /exit"
EXITED_SCREEN = "session exited"


@pytest.fixture
def resuming_pane(request: pytest.FixtureRequest) -> Iterator[tuple[str, str, float]]:
    """Launch ``claude --resume`` in a shell pane; yield (sock, pane, t_zero).

    The arrangement a driven restart leaves behind, reproduced: a shell pane
    whose screen already carries the line the parametrizing row asked for, with
    the relaunch line typed into it. Yields at once, before anything has
    rendered — the measurement below starts from ``t_zero`` and the boot is the
    thing under observation.

    80 columns, not the 200 the other fixtures use, so ``LONG_LINE`` wraps.
    """
    previous: str = getattr(request, "param", PREVIOUS_SCREEN)
    for tool in ("tmux", "claude", "script"):
        if not shutil.which(tool):
            pytest.skip(f"{tool} not on PATH — conformance probe needs a real TUI")
    session = _resumable_session_id()

    sock = f"handoff-resume-{os.getpid()}"
    conf = Path(tempfile.gettempdir()) / f"{sock}.conf"
    conf.write_text("set -g focus-events on\nset -g status off\n", encoding="utf-8")

    client: subprocess.Popen[bytes] | None = None
    try:
        _tmux(
            sock, "-f", str(conf), "new-session", "-d",
            "-x", "80", "-y", "50", "-c", str(PROBE_CWD), "/bin/sh",
        )  # fmt: skip
        pane = _tmux(sock, "list-panes", "-t", "0", "-F", "#{pane_id}").split("\n")[0]
        if not pane:
            pytest.fail("tmux reported no pane — the probe server never started")

        client = subprocess.Popen(
            [
                "script",
                "-q",
                "-c",
                f"stty rows 50 cols 80; tmux -L {sock} attach -t 0",
                "/dev/null",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(1)
        # The screen the relaunch is typed over, per PREVIOUS_SCREEN.
        _tmux(sock, "send-keys", "-t", pane, "-l", f"printf '%s\\n' '{previous}'")
        _tmux(sock, "send-keys", "-t", pane, "Enter")
        time.sleep(0.5)
        _tmux(sock, "send-keys", "-t", pane, "-l", f"claude --resume {session}")
        _tmux(sock, "send-keys", "-t", pane, "Enter")
        yield sock, pane, time.monotonic()
    finally:
        if client is not None:
            client.kill()
        _tmux(sock, "kill-server")
        conf.unlink(missing_ok=True)


def test_the_first_composer_glyph_is_not_yet_accepting_input(
    resuming_pane: tuple[str, str, float],
) -> None:
    """Measure the gap the boot gate has to cover, and print it.

    ``wait_for_composer`` used to open on the glyph's mere presence anywhere in
    the pane, and a restart's continuation was lost through that gate on
    2026-09-20: the glyph was there, the keystrokes were not read by anything.
    This is the only place the two moments can be told apart — the first glyph
    on screen, and the first keystroke a resuming process actually keeps.

    It asserts the ordering and prints the interval rather than pinning a
    threshold: the number sizes BOOT_LANDING_DELAY on this box, and a pinned
    one would red on a faster or slower machine without anything being wrong.
    The marker count beside it is what says the gap is a paint and not a loss —
    a session that buffers shows every marker sent since the cursor opened.
    """
    sock, pane, t_zero = resuming_pane

    deadline = time.monotonic() + RESUME_TIMEOUT
    t_glyph: float | None = None
    while time.monotonic() < deadline:
        if "❯" in _capture(sock, pane):
            t_glyph = time.monotonic() - t_zero
            break
        time.sleep(0.05)
    assert t_glyph is not None, (
        f"no ❯ on the pane within {RESUME_TIMEOUT}s of the relaunch line"
    )

    t_input: float | None = None
    cursor_open: float | None = None
    sent = 0
    while time.monotonic() < deadline:
        full = _tmux(sock, "capture-pane", "-p", "-t", pane)
        x, y = _cursor(sock, pane)
        if cursor_open is None and wl.cursor_in_composer(full, x, y):
            cursor_open = time.monotonic() - t_zero
        _tmux(sock, "send-keys", "-t", pane, "-l", PROBE_MARKER)
        sent += 1
        time.sleep(0.25)
        if wl.line_landed(_capture(sock, pane), PROBE_MARKER):
            t_input = time.monotonic() - t_zero
            break
    assert t_input is not None, (
        f"nothing typed in the {RESUME_TIMEOUT}s after the relaunch ever "
        f"landed in the composer.\nPane:\n{_capture(sock, pane)}"
    )

    # Buffered or discarded is read off the count, not the delay: a session
    # that buffers shows every marker sent since the glyph at once, one that
    # discards shows only the last.
    time.sleep(1.0)
    shown = wl._squash(_capture(sock, pane)).count(wl._squash(PROBE_MARKER))
    print(
        f"\nmarkers sent after the glyph: {sent}, in the composer: {shown}"
        f"\nresume boot on this box: first ❯ at {t_glyph:.2f}s, "
        f"cursor in composer at "
        f"{'never' if cursor_open is None else f'{cursor_open:.2f}s'}, "
        f"first keystroke kept at {t_input:.2f}s "
        f"(glyph → input {t_input - t_glyph:.2f}s)"
    )
    assert t_input >= t_glyph


def test_line_landed_survives_a_real_wrap_of_a_long_line(
    resuming_pane: tuple[str, str, float],
) -> None:
    """The wrap fixture offline is a capture split by hand; this is a wrap.

    If today's composer wrapped inside a bordered box, or right-padded each row
    with a border glyph, ``_squash`` would stop matching and every driven
    continuation longer than the pane would abort having been delivered.

    Retried to the deadline rather than sent once, because a resuming session
    keeps a keystroke and then drops the next one — a boot repaint takes the
    composer back. That intermittency is the subject of the row above and is
    not what this row is measuring, and a retry cannot make this assertion
    vacuous: a send that concatenates onto an earlier one still contains the
    line, so a wrap that broke ``_squash`` would red either way.
    """
    sock, pane, _ = resuming_pane
    assert len(LONG_LINE) > 80, "the line must exceed the pane width to wrap"

    deadline = time.monotonic() + RESUME_TIMEOUT
    captured = _capture(sock, pane)
    while time.monotonic() < deadline and not wl.line_landed(captured, LONG_LINE):
        _tmux(sock, "send-keys", "-t", pane, "C-u")
        captured = _type(sock, pane, LONG_LINE)
    _clear(sock, pane)
    assert wl.line_landed(captured, LONG_LINE), (
        f"a {len(LONG_LINE)}-character line did not read as landed once "
        f"wrapped.\nPane:\n{captured}"
    )


class _Send(NamedTuple):
    """One marker keystroke, and what the pane read like at the moment of it."""

    marker: str
    at: float
    in_composer: bool
    gated: bool


def _marker(index: int) -> str:
    """Spell the ``index``-th marker: distinct, ordered, self-delimiting.

    One send per marker, each carrying its own ordinal, so the composer says
    *which* sends survived rather than how many. Concatenated they stay
    parseable — ``zq007v`` cannot abut into a neighbour's spelling — and
    ``_squash`` rejoins a row wrap, so an 80-column pane cannot hide one.
    """
    return f"zq{index:03d}v"


# Sent every MARKER_PERIOD plus the three tmux reads that precede each one,
# from before the relaunch has painted anything until the resumed session is
# demonstrably reading and painting. LIMIT bounds a boot that never gets there.
MARKER_PERIOD = 0.3
MARKER_LIMIT = 200
POST_READING_WINDOW = 4.0

# The keystrokes are painted seconds after they are kept, so the composer is
# polled to stillness rather than read after a guessed sleep.
PAINT_SETTLE_STABLE = 6
PAINT_SETTLE_POLL = 0.5
PAINT_SETTLE_TIMEOUT = 30.0


def _composer_text(sock: str, pane: str) -> str:
    """Squash the composer's rows — where a marker either is or is not."""
    return _squash_composer(_tmux(sock, "capture-pane", "-p", "-t", pane))


def _squash_composer(full: str) -> str:
    return wl._squash(wl._composer_region(full))


def _pane_state(sock: str, pane: str) -> tuple[int, int, bool]:
    """Read the cursor and whether the pane is on the alternate screen.

    One display-message for all three: the alternate-screen flag is the
    terminal's own account of the switch, which is where the hand test's lost
    characters went — onto the normal screen the TUI was about to replace. The
    shell's echo of the relaunch line is the alternative and a worse one, since
    the resumed conversation can paint the phrase straight back.
    """
    out = _tmux(
        sock,
        "display-message",
        "-p",
        "-t",
        pane,
        "#{cursor_x},#{cursor_y},#{alternate_on}",
    )
    x, y, alt = [*out.strip().split(","), "", "", ""][:3]
    return int(x or -1), int(y or -1), alt == "1"


def _at(moment: float | None) -> str:
    return "never" if moment is None else f"{moment:.2f}s"


class _Boot(NamedTuple):
    """The five moments of a resume boot, each relative to the relaunch."""

    switch: float | None
    painted: float | None
    cursor: float | None
    gate: float | None
    reading: float | None


def _stream_markers(sock: str, pane: str, t_zero: float) -> tuple[list[_Send], _Boot]:
    """Type ordered markers across the boot, recording the pane at each send.

    Runs from before anything has rendered until POST_READING_WINDOW past the
    first proof that the resumed session is reading and painting — a marker
    sent *after* the screen switch showing up in the composer. Anchored there
    rather than on the gate, which is the thing under observation and can open
    early: a stop condition derived from it would end the run inside the very
    window the row exists to straddle.
    """
    deadline = time.monotonic() + RESUME_TIMEOUT
    switch: float | None = None
    painted: float | None = None
    cursor: float | None = None
    gate: float | None = None
    reading: float | None = None
    sends: list[_Send] = []
    post_switch: list[str] = []
    previous_in = False
    stop_at: float | None = None

    while len(sends) < MARKER_LIMIT and time.monotonic() < deadline:
        full = _tmux(sock, "capture-pane", "-p", "-t", pane)
        x, y, alternate = _pane_state(sock, pane)
        now = time.monotonic() - t_zero
        if switch is None and alternate:
            switch = now
        if switch is not None and painted is None and wl.PROMPT_GLYPH in wl.strip(full):
            painted = now
        if reading is None and post_switch:
            composer = _squash_composer(full)
            if any(marker in composer for marker in post_switch):
                reading = now
                stop_at = time.monotonic() + POST_READING_WINDOW

        in_composer = wl.cursor_in_composer(full, x, y)
        # Two consecutive readings is wait_for_composer's own rule: the first
        # keystroke it lets through is the one after the second of them.
        gated = in_composer and previous_in
        if in_composer and cursor is None:
            cursor = now
        if gated and gate is None:
            gate = now
        previous_in = in_composer

        marker = _marker(len(sends))
        _tmux(sock, "send-keys", "-t", pane, "-l", marker)
        sends.append(_Send(marker, now, in_composer, gated))
        if switch is not None:
            post_switch.append(marker)

        if stop_at is not None and time.monotonic() >= stop_at:
            break
        time.sleep(MARKER_PERIOD)
    return sends, _Boot(switch, painted, cursor, gate, reading)


def _settled_composer(sock: str, pane: str) -> str:
    """Poll the composer to stillness and return it, squashed.

    The keystrokes are kept well before they are painted, so a single read after
    the last send would report a loss the pane is merely late about.
    """
    landed = _composer_text(sock, pane)
    deadline = time.monotonic() + PAINT_SETTLE_TIMEOUT
    stable = 0
    while time.monotonic() < deadline and stable < PAINT_SETTLE_STABLE:
        time.sleep(PAINT_SETTLE_POLL)
        current = _composer_text(sock, pane)
        stable = stable + 1 if current == landed else 0
        landed = current
    return landed


def _report_sends(sends: list[_Send], landed: str, boot: _Boot) -> None:
    """Print where the loss window fell on this run — the row's measurement."""
    lost = [send for send in sends if send.marker not in landed]
    switch_at = next(
        (i for i, send in enumerate(sends) if send.at >= (boot.switch or float("inf"))),
        None,
    )
    gate_at = next((i for i, send in enumerate(sends) if send.gated), None)
    trace = ""
    for index, send in enumerate(sends):
        trace += "/" if index == switch_at else ""
        trace += "|" if index == gate_at else ""
        trace += "+" if send.marker in landed else "-"
    cadence = (sends[-1].at - sends[0].at) / (len(sends) - 1) if len(sends) > 1 else 0
    window = (
        "nothing lost on this run"
        if not lost
        else f"{lost[0].at:.2f}s → {lost[-1].at:.2f}s"
    )
    detail = (
        "none"
        if not lost
        else ", ".join(
            f"{send.marker}@{send.at:.2f}s{'*' if send.in_composer else ''}"
            for send in lost
        )
        + "   (* cursor read as in the composer at send time)"
    )
    print(
        f"\nresume boot: screen switch at {_at(boot.switch)}, composer painted "
        f"at {_at(boot.painted)}, cursor in composer at {_at(boot.cursor)}, "
        f"gate open at {_at(boot.gate)}, session reading at {_at(boot.reading)}"
        f"\n{len(sends)} markers sent every {cadence:.2f}s on average: "
        f"{len(sends) - len(lost)} in the composer, {len(lost)} lost"
        f"\nloss window: {window}"
        f"\n{trace}   (+ kept, - lost, / screen switch, | gate opens)"
        f"\nlost: {detail}"
    )


@pytest.mark.parametrize(
    "resuming_pane", [EXITED_SCREEN], indirect=True, ids=["post-exit-screen"]
)
def test_only_keystrokes_ahead_of_the_boot_gate_are_lost(
    resuming_pane: tuple[str, str, float],
) -> None:
    """The loss window, reproduced, and the gate's promise asserted over it.

    Typed by hand across a resume boot, ``aoeuidhtnsaoe`` arrived as
    ``aoeunsaoe``: the characters sent partway through the boot were echoed onto
    the terminal's own screen and reached no composer, while those either side
    of that window all arrived. That window is the whole reason
    ``wait_for_composer`` exists, and since ``BOOT_SETTLE`` was removed the gate
    is the only thing standing between it and a driven restart's continuation —
    nothing sleeps behind it any more.

    So one claim is asserted: every marker sent while the gate's own condition
    held — the cursor in the composer on this reading and the one before it —
    is in the composer afterwards, in order. Everything else is printed. Where
    the loss window falls, and how much of it a given boot loses, is a property
    of this box's load on the day; pinning it would red on a faster or slower
    one without anything being wrong, and a run that loses nothing at all is
    not a failure either.

    Runs over ``EXITED_SCREEN`` rather than the fixture's default, and the
    difference is the whole assertion. A screen carrying a ``❯`` above the
    shell's cursor satisfies ``cursor_in_composer`` outright — the glyph row is
    found, the cursor is below it — so the gate opens within half a second of
    the relaunch, before the resumed process has rendered anything, and the
    loss window then falls *behind* an open gate (measured 2026-09-21: gate at
    0.43s, keystrokes lost 3.83s → 6.07s). That is a real residual of the
    predicate, and it is not what a restart meets: Claude Code runs on the
    alternate screen, so ``/exit`` restores a normal screen with no ``❯`` on it
    at all. Asserting the gate's promise over the staged glyph would be
    asserting it over an arrangement the platform does not produce.

    Nothing is ever submitted: no Enter is sent after the relaunch line, so
    whatever the markers land in — the composer, or the shell's line while it
    still owns the tty — dies with the pane in teardown.
    """
    sock, pane, t_zero = resuming_pane

    sends, boot = _stream_markers(sock, pane, t_zero)
    landed = _settled_composer(sock, pane)
    _report_sends(sends, landed, boot)

    gated_sends = [send for send in sends if send.gated]
    assert gated_sends, (
        "the boot gate never opened in the "
        f"{sends[-1].at if sends else 0:.0f}s of this run, so the row asserts "
        "nothing. Either the resume never finished booting or "
        "cursor_in_composer has stopped recognising a live composer."
    )
    positions = [landed.find(send.marker) for send in gated_sends]
    missing = [
        send.marker
        for send, index in zip(gated_sends, positions, strict=True)
        if index < 0
    ]
    assert not missing, (
        f"{len(missing)} of {len(gated_sends)} markers sent with the walker's "
        f"boot gate open never reached the composer: {', '.join(missing)}. "
        "The gate is what keeps a driven restart's continuation out of the "
        "loss window, and nothing waits behind it since BOOT_SETTLE was "
        f"removed.\nComposer:\n{landed}"
    )
    assert positions == sorted(positions), (
        "markers sent behind the open gate reached the composer out of "
        f"order: {list(zip([s.marker for s in gated_sends], positions, strict=True))}"
        f"\nComposer:\n{landed}"
    )
