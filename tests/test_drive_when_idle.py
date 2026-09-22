"""End-to-end tests for drive_when_idle.py against the tmux stub.

Port of the walker sections of tests/watcher-test.bats — see
docs/changelog/2026-08-10-python-split.md.
"""

from __future__ import annotations

import json
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from conftest import TmuxStub

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "drive_when_idle.py"

TITLE = "Driven Transitions Design"
# The composer's own gap after the glyph — see _watcher_lib.COMPOSER_GAP.
# Every staged pane below that stands for a real composer carries it; a bare
# shell prompt's ❯ (see the resume-line tests) stays ASCII-padded on purpose.
NBSP = "\N{NO-BREAK SPACE}"


def walk(
    tmux_stub: TmuxStub,
    *lines: str,
    env: dict[str, str] | None = None,
    timeout: float = 5,
    consume: float = 1,
) -> subprocess.CompletedProcess[str]:
    full_env = {
        "PATH": tmux_stub.path_env(),
        "HANDOFF_WATCHER_TIMEOUT": str(timeout),
        "HANDOFF_WATCHER_POLL": "0.01",
        "HANDOFF_WATCHER_VERIFY_DELAY": "0.01",
        "HANDOFF_WATCHER_CONSUME_POLL": "0.05",
        "HANDOFF_WATCHER_CONSUME_TIMEOUT": str(consume),
        "HANDOFF_WATCHER_RECOGNITION_DELAY": "0.05",
        "HANDOFF_WATCHER_LANDING_DELAY": "0.5",
        "HANDOFF_WATCHER_BOOT_LANDING_DELAY": "0.5",
    }
    if env:
        full_env.update(env)
    return subprocess.run(
        [sys.executable, str(SCRIPT), "%9", *lines],
        env=full_env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_slash_line_typed_then_recognition_read_back_then_entered(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(
        f"/compact  Compact the conversation\n❯{NBSP}/compact keep the parser work\n"
    )
    result = walk(
        tmux_stub,
        "/compact keep the parser work",
        env={"HANDOFF_PENDING_FILE": str(tmp_path / "absent")},
    )
    assert result.returncode == 0
    sent = tmux_stub.sent_text()
    assert "-l|/compact keep the parser work|" in sent
    assert "Enter|" in sent
    lines = sent.splitlines()
    l_line = next(i for i, line in enumerate(lines) if "-l|" in line)
    e_line = next(i for i, line in enumerate(lines) if "Enter|" in line)
    assert l_line < e_line


def test_unrecognized_command_cleared_with_ctrl_u_never_entered(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(
        f'No commands match "/compzzz"\n❯{NBSP}/compzzz\n'
    )
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        "/compzzz",
        "a continuation that must never be typed",
        env={"HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    sent = tmux_stub.sent_text()
    assert "C-u|" in sent
    assert "Enter|" not in sent
    assert "continuation" not in sent
    assert "recognize" in fail_file.read_text().lower()
    assert len(fail_file.read_text().splitlines()) == 1


def test_a_composer_that_repaints_late_is_waited_for_not_failed(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """The pane does not always paint within VERIFY_DELAY.

    Read once, a late repaint is indistinguishable from a swallowed keystroke
    and the walker aborts a line it typed successfully. Mutation check: revert
    wait_for_landing to a single read and this row alone goes red.
    """
    pane_file = tmux_stub.stubdir / "pane_after_l.txt"
    pane_file.write_text(f"──── x ──\n❯{NBSP}\n")

    def repaint_late() -> None:
        # Anchored to the send, not to wall-clock from here: interpreter
        # startup is ~0.4s and would swallow a fixed delay, leaving even a
        # single read landing after the repaint — a green that proves nothing.
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and "-l|" not in tmux_stub.sent_text():
            time.sleep(0.01)
        time.sleep(0.4)
        pane_file.write_text(f"──── x ──\n❯{NBSP}continue the parser work\n")

    threading.Thread(target=repaint_late, daemon=True).start()
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    submitted = {
        "type": "user",
        "message": {"role": "user", "content": "continue the parser work"},
    }
    tmux_stub.on_enter(f"printf '{json.dumps(submitted)}\\n' >> '{tr}'")
    result = walk(
        tmux_stub,
        "continue the parser work",
        env={"HANDOFF_WATCHER_LANDING_DELAY": "3", "HANDOFF_TRANSCRIPT": str(tr)},
    )
    assert result.returncode == 0
    assert "-l|continue the parser work|" in tmux_stub.sent_text()


def test_nothing_sent_while_user_is_composing(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_idle.txt").write_text(
        f"──── x ──\n❯{NBSP}half-typed thought\n"
    )
    # The cursor, not the text, is what says a person typed it: the TUI paints
    # its own suggestion into an idle composer and leaves the cursor at the
    # start column. The gap is one character either way, so the length here
    # is unaffected by the ASCII-space-to-NBSP swap above.
    tmux_stub.compose(len("❯ half-typed thought"))
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        "/clear",
        "should not send",
        env={"HANDOFF_FAIL_FILE": str(fail_file)},
        timeout=1,
    )
    assert result.returncode != 0
    assert tmux_stub.sent_text() == ""
    assert "composing" in fail_file.read_text().lower()


def test_non_delivery_with_no_fail_file_still_stops_walker(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    result = walk(
        tmux_stub,
        "a prose line nothing will accept",
        env={"HANDOFF_TRANSCRIPT": str(tmp_path / "absent.jsonl")},
    )
    assert result.returncode != 0


def test_line_swallowed_by_pane_fails_fast_before_enter(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(f"──── x ──\n❯{NBSP}\n")
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        "/compact keep the parser work",
        env={"HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    sent = tmux_stub.sent_text()
    assert "-l|/compact keep the parser work|" in sent
    assert "Enter|" not in sent
    text = fail_file.read_text().lower()
    assert "did not land" in text
    assert "was typed and entered" not in text


def test_swallowed_prose_line_fails_fast_before_enter(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(f"──── x ──\n❯{NBSP}\n")
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub, "continue with task 3", env={"HANDOFF_FAIL_FILE": str(fail_file)}
    )
    assert result.returncode != 0
    sent = tmux_stub.sent_text()
    assert "-l|continue with task 3|" in sent
    assert "Enter|" not in sent
    assert "did not land" in fail_file.read_text().lower()


def test_rename_line_confirms_by_custom_title_entry(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    tmux_stub.on_enter(
        f'printf \'{{"type":"custom-title","customTitle":"{TITLE}"}}\\n\' >> \'{tr}\''
    )
    result = walk(tmux_stub, f"/rename {TITLE}", env={"HANDOFF_TRANSCRIPT": str(tr)})
    assert result.returncode == 0
    assert f"-l|/rename {TITLE}|" in tmux_stub.sent_text()


def test_rename_line_not_confirmed_by_title_merely_on_pane(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(
        f"──── {TITLE} ──\n❯{NBSP}/rename {TITLE}\nf"
    )
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        f"/rename {TITLE}",
        env={"HANDOFF_TRANSCRIPT": str(tr), "HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    assert "title never changed" in fail_file.read_text().lower()


def test_rename_line_not_confirmed_by_preexisting_entry(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    tr = tmp_path / "t.jsonl"
    tr.write_text(f'{{"type":"custom-title","customTitle":"{TITLE}"}}\n')
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        f"/rename {TITLE}",
        env={"HANDOFF_TRANSCRIPT": str(tr), "HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    assert "title never changed" in fail_file.read_text().lower()


def test_compact_line_confirms_by_pending_file_consumed(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(
        f"/compact  Compact the conversation\n❯{NBSP}/compact keep the parser work\n"
    )
    pending = tmp_path / "autodrive"
    pending.write_text("")
    fail_file = tmp_path / "autodrive.failed"

    def consume_soon() -> None:
        time.sleep(0.3)
        pending.unlink(missing_ok=True)

    threading.Thread(target=consume_soon, daemon=True).start()
    result = walk(
        tmux_stub,
        "/compact keep the parser work",
        env={"HANDOFF_PENDING_FILE": str(pending), "HANDOFF_FAIL_FILE": str(fail_file)},
        consume=5,
    )
    assert result.returncode == 0
    assert not fail_file.exists()


def test_compact_line_reported_when_nothing_consumes_it(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(
        f"/compact  Compact the conversation\n❯{NBSP}/compact keep the parser work\n"
    )
    pending = tmp_path / "autodrive"
    pending.write_text("")
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        "/compact keep the parser work",
        env={"HANDOFF_PENDING_FILE": str(pending), "HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    assert "no /compact followed" in fail_file.read_text().lower()


def test_clear_line_with_nothing_to_confirm_not_reported_failed(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(
        f"/clear  Clear the conversation\n❯{NBSP}/clear\n"
    )
    fail_file = tmp_path / "autodrive.failed"
    result = walk(tmux_stub, "/clear", env={"HANDOFF_FAIL_FILE": str(fail_file)})
    assert result.returncode == 0
    assert not fail_file.exists()


def test_prose_confirms_queued_submit_that_shows_no_spinner(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    tr = tmp_path / "t.jsonl"
    stale = {
        "type": "user",
        "message": {"role": "user", "content": "continue with task 3 (stale copy)"},
    }
    tr.write_text(json.dumps(stale) + "\n")
    fresh = {
        "type": "user",
        "message": {"role": "user", "content": "continue with task 3"},
    }
    tmux_stub.on_enter(f"printf '{json.dumps(fresh)}\\n' >> '{tr}'")
    result = walk(
        tmux_stub, "continue with task 3", env={"HANDOFF_TRANSCRIPT": str(tr)}
    )
    assert result.returncode == 0
    sent = tmux_stub.sent_text()
    assert "-l|continue with task 3|" in sent
    assert sent.count("Enter|") == 1


def test_prose_retries_three_times_and_reports_when_enter_absorbed(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        "continue with task 3",
        env={"HANDOFF_TRANSCRIPT": str(tr), "HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    sent = tmux_stub.sent_text()
    assert sent.count("Enter|") == 3
    assert sent.count("-l|") == 1
    assert "continuation prompt" in fail_file.read_text().lower()
    assert len(fail_file.read_text().splitlines()) == 1


def test_prose_confirms_submit_landing_after_fast_retry_window(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    tr = tmp_path / "t.jsonl"
    tr.write_text("")

    entry = {
        "type": "user",
        "message": {"role": "user", "content": "continue with task 3"},
    }

    def land_late() -> None:
        time.sleep(1)
        with Path(tr).open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry) + "\n")

    threading.Thread(target=land_late, daemon=True).start()
    result = walk(
        tmux_stub,
        "continue with task 3",
        env={"HANDOFF_TRANSCRIPT": str(tr)},
        consume=5,
    )
    assert result.returncode == 0
    assert tmux_stub.sent_text().count("Enter|") == 3


def test_multiline_sequence_types_every_line_in_order(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    pending = tmp_path / "autodrive"
    pending.write_text("")
    tmux_stub.on_enter(
        f'printf \'{{"type":"custom-title","customTitle":"{TITLE}"}}\\n\' >> \'{tr}\'; '
        f"rm -f '{pending}'"
    )
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        f"/rename {TITLE}",
        "/clear",
        env={
            "HANDOFF_TRANSCRIPT": str(tr),
            "HANDOFF_PENDING_FILE": str(pending),
            "HANDOFF_FAIL_FILE": str(fail_file),
        },
    )
    assert result.returncode == 0
    assert not fail_file.exists()
    sent_lines = tmux_stub.sent_text().splitlines()
    rename_line = next(i for i, line in enumerate(sent_lines) if "-l|/rename" in line)
    clear_line = next(i for i, line in enumerate(sent_lines) if "-l|/clear" in line)
    assert rename_line < clear_line


def test_line_that_never_confirms_stops_sequence(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    fail_file = tmp_path / "autodrive.failed"
    result = walk(
        tmux_stub,
        f"/rename {TITLE}",
        "/clear",
        "pick up per the task file",
        env={"HANDOFF_TRANSCRIPT": str(tr), "HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    sent = tmux_stub.sent_text()
    assert "/clear" not in sent
    assert "pick up per the task file" not in sent
    contents = fail_file.read_text()
    assert len(contents.splitlines()) == 1
    assert TITLE in contents


def test_exit_line_confirms_by_exit_file_appearing(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(f"/exit\n❯{NBSP}/exit\n")
    exit_file = tmp_path / "autodrive.exited"
    tmux_stub.on_enter(f"touch '{exit_file}'")
    result = walk(tmux_stub, "/exit", env={"HANDOFF_EXIT_FILE": str(exit_file)})
    assert result.returncode == 0
    assert "-l|/exit|" in tmux_stub.sent_text()
    assert not exit_file.exists()


def test_exit_line_reported_when_nothing_confirms_it(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(f"/exit\n❯{NBSP}/exit\n")
    fail_file = tmp_path / "autodrive.failed"
    exit_file = tmp_path / "autodrive.exited"
    result = walk(
        tmux_stub,
        "/exit",
        env={"HANDOFF_EXIT_FILE": str(exit_file), "HANDOFF_FAIL_FILE": str(fail_file)},
    )
    assert result.returncode != 0
    assert "session" in fail_file.read_text().lower()


def test_resume_line_bypasses_composer_checks(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """A `claude --resume` line targets a bare shell, not the TUI composer.

    Pane text that would fail _drive_line's composer bail/delivery checks
    (no ❯ at all — nothing recognizable as a shell prompt either) must not
    stop this line from being sent: the whole point of the shell-line path is
    that it does not read composer chrome.
    """
    for name in ("pane_idle.txt", "pane_after_l.txt", "pane_after_enter.txt"):
        (tmux_stub.stubdir / name).write_text("some-shell$ \n")
    pending = tmp_path / "autodrive"
    pending.write_text("")

    # The foreground answers as the TUI once — the baseline main samples —
    # then as the shell, which is what opens the gate. Enter puts the relaunch
    # in front, which is how the walker knows the line ran.
    tmux_stub.foreground_changes_to("some-shell")
    tmux_stub.on_enter(f"echo claude > '{tmux_stub.foreground}'")

    def consume_soon() -> None:
        time.sleep(0.2)
        pending.unlink(missing_ok=True)

    threading.Thread(target=consume_soon, daemon=True).start()
    result = walk(
        tmux_stub,
        "claude --resume sess-42",
        env={
            "HANDOFF_PENDING_FILE": str(pending),
            "HANDOFF_WATCHER_FOREGROUND_POLL": "0.01",
        },
        consume=2,
    )

    assert result.returncode == 0
    assert "-l|claude --resume sess-42|" in tmux_stub.sent_text()


def test_resume_line_dispatches_on_the_command_not_the_literal_prefix(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """An absolute argv[0] and %q-quoted flags still take the shell path.

    Nothing composes this shape any more — the relaunch is typed as `claude
    --resume <sid>` and resolved through PATH. It is the shape that broke:
    while stop-drive.sh replayed the exiting process's argv, argv[0] was the
    resolved binary, a prefix test on `claude --resume ` missed, and the line
    fell through to _drive_line, which typed it into a bare shell and then
    waited for a TUI composer to hold it — so it was never Entered. This row
    is what keeps the predicate a parse rather than a prefix test, which the
    other rows would not notice losing.
    """
    line = (
        r"/Users/david/.local/bin/claude "
        r"--settings \{\"autoMemoryDirectory\":\"/tmp/m\"\} "
        r"--plugin-dir /Users/david/code/handoff -r --resume sess-42"
    )
    for name in ("pane_idle.txt", "pane_after_l.txt", "pane_after_enter.txt"):
        (tmux_stub.stubdir / name).write_text("some-shell$ \n")
    pending = tmp_path / "autodrive"
    pending.write_text("")

    tmux_stub.foreground_changes_to("some-shell")
    tmux_stub.on_enter(f"echo claude > '{tmux_stub.foreground}'")

    def consume_soon() -> None:
        time.sleep(0.2)
        pending.unlink(missing_ok=True)

    threading.Thread(target=consume_soon, daemon=True).start()
    result = walk(
        tmux_stub,
        line,
        env={
            "HANDOFF_PENDING_FILE": str(pending),
            "HANDOFF_WATCHER_FOREGROUND_POLL": "0.01",
        },
        consume=2,
    )

    assert result.returncode == 0
    assert f"-l|{line}|" in tmux_stub.sent_text()


def test_resume_line_presses_enter_once_when_the_line_runs(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """One Enter, though the resume confirms seconds later.

    The relaunch's own confirmation is the sentinel going, which the resumed
    session's SessionStart does — after a whole Claude Code boot. Retrying
    against that signal is guaranteed to press again before it can arrive, and
    those presses land in a session that is already starting, where an Enter
    answers whatever dialog is on screen rather than costing an empty prompt
    line. The foreground leaving the shell says the line ran, and says it at
    once.
    """
    for name in ("pane_idle.txt", "pane_after_l.txt", "pane_after_enter.txt"):
        (tmux_stub.stubdir / name).write_text("some-shell$ \n")
    pending = tmp_path / "autodrive"
    pending.write_text("")

    tmux_stub.foreground_changes_to("some-shell")
    # The relaunch starts the moment the line runs; the sentinel it will
    # consume outlives that by the length of a boot.
    tmux_stub.on_enter(f"echo claude > '{tmux_stub.foreground}'")

    def consume_late() -> None:
        time.sleep(1.0)
        pending.unlink(missing_ok=True)

    threading.Thread(target=consume_late, daemon=True).start()
    result = walk(
        tmux_stub,
        "claude --resume sess-42",
        env={
            "HANDOFF_PENDING_FILE": str(pending),
            "HANDOFF_WATCHER_FOREGROUND_POLL": "0.01",
            "HANDOFF_WATCHER_CONSUME_POLL": "0.05",
        },
        consume=3,
    )

    assert result.returncode == 0
    assert tmux_stub.sent_text().count("Enter") == 1


def test_resume_line_presses_again_while_the_shell_still_holds_the_pane(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """A line that never runs is pressed again, then failed loudly.

    The shell keeping the foreground is the evidence that the keystroke was not
    taken — the one condition under which pressing again is safe, and the one
    under which it is needed.
    """
    for name in ("pane_idle.txt", "pane_after_l.txt", "pane_after_enter.txt"):
        (tmux_stub.stubdir / name).write_text("some-shell$ \n")
    fail_file = tmp_path / "autodrive.failed"

    tmux_stub.foreground_changes_to("some-shell")

    result = walk(
        tmux_stub,
        "claude --resume sess-42",
        env={
            "HANDOFF_FAIL_FILE": str(fail_file),
            "HANDOFF_WATCHER_FOREGROUND_POLL": "0.01",
            "HANDOFF_WATCHER_EXIT_TIMEOUT": "0.3",
        },
    )

    assert result.returncode != 0
    assert tmux_stub.sent_text().count("Enter") > 1
    assert "some-shell" in fail_file.read_text()
    assert "never ran" in fail_file.read_text()


def test_tui_line_stops_pressing_enter_after_three(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """The composer keeps the old rule: a registered Enter must not resend.

    The pane holds a live turn once it takes the first Enter, and pressing again
    submits a second one. Only the shell-prompt path opted out, so this is the
    negative that keeps the flag from spreading back.
    """
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(
        f"/compact  Compact the conversation\n❯{NBSP}/compact\n"
    )
    pending = tmp_path / "autodrive"
    pending.write_text("")

    def consume_late() -> None:
        time.sleep(1.0)
        pending.unlink(missing_ok=True)

    threading.Thread(target=consume_late, daemon=True).start()
    result = walk(
        tmux_stub,
        "/compact",
        env={
            "HANDOFF_PENDING_FILE": str(pending),
            "HANDOFF_WATCHER_CONSUME_POLL": "0.05",
        },
        consume=3,
    )

    assert result.returncode == 0
    assert tmux_stub.sent_text().count("Enter") == 3


def test_resume_line_settle_is_configurable(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text("some-shell$ \n")
    pending = tmp_path / "autodrive"
    pending.write_text("")

    tmux_stub.foreground_changes_to("some-shell")
    tmux_stub.on_enter(f"echo claude > '{tmux_stub.foreground}'")

    def consume_soon() -> None:
        time.sleep(0.05)
        pending.unlink(missing_ok=True)

    threading.Thread(target=consume_soon, daemon=True).start()
    start = time.monotonic()
    result = walk(
        tmux_stub,
        "claude --resume sess-42",
        env={
            "HANDOFF_PENDING_FILE": str(pending),
            "HANDOFF_WATCHER_FOREGROUND_POLL": "0.01",
            "HANDOFF_WATCHER_SHELL_SETTLE": "0.05",
        },
        consume=2,
    )
    elapsed = time.monotonic() - start
    assert result.returncode == 0
    assert elapsed < 1


def test_resume_line_is_not_typed_while_claude_still_holds_the_pane(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """The relaunch waits for Claude Code to release the terminal.

    /exit confirming means SessionEnd fired, not that the terminal is accepting
    input again. A keystroke sent inside that window is dropped leaving no
    trace, so a gate that gave up and typed anyway would reproduce the defect
    silently — this fails loudly instead, and the fail file is the only channel
    back from a detached walker.
    """
    (tmux_stub.stubdir / "pane_after_l.txt").write_text("some-shell$ \n")
    tmux_stub.set_foreground("claude")
    fail_file = tmp_path / "autodrive.failed"

    start = time.monotonic()
    result = walk(
        tmux_stub,
        "claude --resume sess-42",
        env={
            "HANDOFF_FAIL_FILE": str(fail_file),
            "HANDOFF_WATCHER_EXIT_TIMEOUT": "0.5",
            "HANDOFF_WATCHER_FOREGROUND_POLL": "0.01",
            "HANDOFF_WATCHER_SHELL_SETTLE": "0.01",
        },
    )
    elapsed = time.monotonic() - start

    assert result.returncode != 0
    assert "-l|claude --resume sess-42|" not in tmux_stub.sent_text()
    assert elapsed >= 0.5  # it waited the whole timeout rather than typing
    assert "claude" in fail_file.read_text()


def test_restart_sequence_exit_then_resume_in_order(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_l.txt").write_text(f"/exit\n❯{NBSP}/exit\n")
    exit_file = tmp_path / "autodrive.exited"
    pending = tmp_path / "autodrive"
    pending.write_text("")
    # Claude Code releasing the terminal is what the relaunch waits on, and it
    # happens after /exit — so the flip is staged on Enter, not at setup, or
    # the baseline sampled before the first line would already be the shell.
    foreground = tmux_stub.foreground
    tmux_stub.on_enter(
        f"touch '{exit_file}'; rm -f '{pending}';"
        f" if grep -q -- '-l|claude --resume' '{tmux_stub.sent}';"
        f" then echo claude > '{foreground}';"
        f" else echo some-shell > '{foreground}'; fi"
    )
    result = walk(
        tmux_stub,
        "/exit",
        "claude --resume sess-42",
        env={
            "HANDOFF_EXIT_FILE": str(exit_file),
            "HANDOFF_PENDING_FILE": str(pending),
            "HANDOFF_WATCHER_SHELL_SETTLE": "0.01",
        },
        consume=2,
    )
    assert result.returncode == 0
    sent_lines = tmux_stub.sent_text().splitlines()
    exit_line = next(i for i, line in enumerate(sent_lines) if "-l|/exit|" in line)
    resume_line = next(
        i for i, line in enumerate(sent_lines) if "-l|claude --resume sess-42|" in line
    )
    assert exit_line < resume_line


def test_composer_boot_is_waited_for_not_typed_into_a_screen_with_none(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """A freshly exec'd process has no composer for the first stretch of boot.

    Reproduces the 2026-08-14 driven-restart continuation failure: the walker
    started against a pane that had just exec'd `claude --resume`, found no
    busy chrome (there is none during boot) and typed immediately, before a
    composer existed to receive it. Fixed code waits for the glyph itself,
    not merely the spinner's absence, before typing.
    """
    booting = "╭─ Claude Code ─╮\n│  booting...    │\n╰────────────────╯\n"
    ready = f"──── x ──\n❯{NBSP}\n"
    idle = tmux_stub.stubdir / "pane_idle.txt"
    after_l = tmux_stub.stubdir / "pane_after_l.txt"
    idle.write_text(booting)
    after_l.write_text(booting)

    def boot_completes() -> None:
        time.sleep(0.3)
        idle.write_text(ready)
        after_l.unlink()  # falls back to the stub's normal send-keys echo

    threading.Thread(target=boot_completes, daemon=True).start()
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    submitted = {
        "type": "user",
        "message": {"role": "user", "content": "continue with task 3"},
    }
    tmux_stub.on_enter(f"printf '{json.dumps(submitted)}\\n' >> '{tr}'")

    start = time.monotonic()
    result = walk(
        tmux_stub,
        "continue with task 3",
        env={
            "HANDOFF_TRANSCRIPT": str(tr),
            "HANDOFF_WATCHER_LANDING_DELAY": "0.1",
            "HANDOFF_WATCHER_BOOT_TIMEOUT": "2",
        },
    )
    elapsed = time.monotonic() - start

    assert result.returncode == 0
    assert elapsed >= 0.3
    assert "-l|continue with task 3|" in tmux_stub.sent_text()


def test_a_glyph_that_is_not_a_live_composer_does_not_open_the_boot_gate(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """A ❯ on screen is not the same thing as a composer reading input.

    Reproduces the 2026-09-20 driven-restart continuation failure, which the
    2026-08-15 gate above did not catch: the pane under `claude --resume`
    carries the exited session's last frame and the replayed transcript, so a
    ❯ is on screen from the first moment — here inside replayed text about
    this very module. The gate opened on it, the line was typed into a screen
    nothing was reading, and the keystrokes were lost for good. Fixed code
    asks where the terminal cursor is, which chrome and replayed text never
    answer for.
    """
    booting = "● the glyph is ❯ in _watcher_lib\n╭─ Claude Code ─╮\n│  resuming...  │\n"
    ready = f"──── x ──\n❯{NBSP}\n"
    idle = tmux_stub.stubdir / "pane_idle.txt"
    after_l = tmux_stub.stubdir / "pane_after_l.txt"
    idle.write_text(booting)
    after_l.write_text(booting)
    # Nowhere near the replayed glyph — a repaint parks the cursor at the
    # screen's origin, never inside the conversation it just drew.
    tmux_stub.compose(0, 0)

    def boot_completes() -> None:
        time.sleep(0.3)
        idle.write_text(ready)
        after_l.unlink()  # falls back to the stub's normal send-keys echo
        tmux_stub.compose(2, 1)  # the composer, cursor at its start column

    threading.Thread(target=boot_completes, daemon=True).start()
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    submitted = {
        "type": "user",
        "message": {"role": "user", "content": "continue with task 3"},
    }
    tmux_stub.on_enter(f"printf '{json.dumps(submitted)}\\n' >> '{tr}'")

    result = walk(
        tmux_stub,
        "continue with task 3",
        env={
            "HANDOFF_TRANSCRIPT": str(tr),
            "HANDOFF_WATCHER_LANDING_DELAY": "0.1",
            "HANDOFF_WATCHER_BOOT_TIMEOUT": "2",
        },
    )

    assert result.returncode == 0
    assert "-l|continue with task 3|" in tmux_stub.sent_text()


def test_a_booting_pane_is_typed_into_at_once_and_given_time_to_paint(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """A resuming session buffers the keystrokes and paints them seconds later.

    The gate above is sized on the premise that a resuming session *discards*
    input for a stretch after the cursor reaches the composer, and pays a flat
    settle before typing. Measured, the input is kept — it simply does not show
    for 3-9s, tracking the box's load. So the settle costs that delay on every
    restart and buys nothing, while the mid-session landing window it hands the
    line to is far shorter than the paint it must wait for: the walker abandons
    a line the session already has, and reports a non-delivery that did not
    happen.

    The line is therefore sent as soon as the gate opens, and the window it
    gets afterwards is the boot-sized one. BOOT_SETTLE is set high here on
    purpose: a run that finishes well inside it is the evidence that nothing
    slept.
    """
    idle = tmux_stub.stubdir / "pane_idle.txt"
    after_l = tmux_stub.stubdir / "pane_after_l.txt"
    idle.write_text("╭─ Claude Code ─╮\n│  resuming...  │\n")
    after_l.write_text(f"──── x ──\n❯{NBSP}\n")
    tmux_stub.compose(0, 0)

    def boot_completes() -> None:
        # A full second, not the 0.3s the gate rows use: this row's subject is
        # what happens on the boot branch, so the walker's own ~0.4s of
        # interpreter startup must not be able to swallow the absence that
        # selects it.
        time.sleep(1.0)
        idle.write_text(f"──── x ──\n❯{NBSP}\n")
        tmux_stub.compose(2, 1)

    def paint_late() -> None:
        # Anchored to the send, not to wall-clock from here: the whole subject
        # is how long after the keystroke the composer shows it.
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and "-l|" not in tmux_stub.sent_text():
            time.sleep(0.01)
        time.sleep(0.5)
        after_l.write_text(f"──── x ──\n❯{NBSP}continue with task 3\n")

    threading.Thread(target=boot_completes, daemon=True).start()
    threading.Thread(target=paint_late, daemon=True).start()
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    submitted = {
        "type": "user",
        "message": {"role": "user", "content": "continue with task 3"},
    }
    tmux_stub.on_enter(f"printf '{json.dumps(submitted)}\\n' >> '{tr}'")
    fail_file = tmp_path / "autodrive.failed"

    start = time.monotonic()
    result = walk(
        tmux_stub,
        "continue with task 3",
        env={
            "HANDOFF_TRANSCRIPT": str(tr),
            "HANDOFF_FAIL_FILE": str(fail_file),
            "HANDOFF_WATCHER_LANDING_DELAY": "0.1",
            "HANDOFF_WATCHER_BOOT_LANDING_DELAY": "5",
            "HANDOFF_WATCHER_BOOT_SETTLE": "5",
            "HANDOFF_WATCHER_BOOT_TIMEOUT": "5",
        },
    )
    elapsed = time.monotonic() - start

    assert result.returncode == 0, (
        fail_file.read_text() if fail_file.exists() else result.stderr
    )
    assert not fail_file.exists()
    assert "-l|continue with task 3|" in tmux_stub.sent_text()
    # Typed the moment the gate opened: a 5s settle would dominate the run.
    assert elapsed < 4


def test_a_mid_session_line_keeps_the_short_landing_window(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """Only a boot buys the long window; elsewhere a late paint still fails.

    Green on both sides of the change by design. It is what stops the boot
    window being granted everywhere, which would cost minutes of silence on the
    one report that says a keystroke was swallowed — mid-session the composer
    has been reading for as long as the session has, and a line that does not
    appear in it is not one that will.
    """
    after_l = tmux_stub.stubdir / "pane_after_l.txt"
    after_l.write_text(f"──── x ──\n❯{NBSP}\n")

    def paint_late() -> None:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and "-l|" not in tmux_stub.sent_text():
            time.sleep(0.01)
        time.sleep(0.5)
        after_l.write_text(f"──── x ──\n❯{NBSP}continue with task 3\n")

    threading.Thread(target=paint_late, daemon=True).start()
    fail_file = tmp_path / "autodrive.failed"

    result = walk(
        tmux_stub,
        "continue with task 3",
        env={
            "HANDOFF_FAIL_FILE": str(fail_file),
            "HANDOFF_WATCHER_LANDING_DELAY": "0.1",
            "HANDOFF_WATCHER_BOOT_LANDING_DELAY": "5",
        },
    )

    assert result.returncode != 0
    assert "did not land" in fail_file.read_text().lower()
    assert "Enter|" not in tmux_stub.sent_text()


def test_a_delivered_line_records_its_gate_timings(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    """A delivery leaves its timings behind, since nothing else can say them.

    The walker is detached and its output goes nowhere, so the first dogfood
    of the 2026-09-20 boot gate could only be read off transcript timestamps:
    36s from Stop to the continuation, with no way to split boot from settle.
    The composer is absent for 1s here, so the gate's share is measurable.

    The record carries no `settle`: there is no settle left to report, and a
    key pinned to a tunable that no longer exists would read as a figure the
    next dogfood could act on.
    """
    idle = tmux_stub.stubdir / "pane_idle.txt"
    after_l = tmux_stub.stubdir / "pane_after_l.txt"
    idle.write_text("╭─ Claude Code ─╮\n│  resuming...  │\n")
    after_l.write_text(idle.read_text())
    tmux_stub.compose(0, 0)

    def boot_completes() -> None:
        time.sleep(1.0)
        idle.write_text(f"──── x ──\n❯{NBSP}\n")
        after_l.unlink()
        tmux_stub.compose(2, 1)

    threading.Thread(target=boot_completes, daemon=True).start()
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    submitted = {
        "type": "user",
        "message": {"role": "user", "content": "continue with task 3"},
    }
    tmux_stub.on_enter(f"printf '{json.dumps(submitted)}\\n' >> '{tr}'")
    log = tmp_path / "autodrive.log"
    log.write_text("".join(f'{{"line": "old {n}"}}\n' for n in range(60)))

    result = walk(
        tmux_stub,
        "continue with task 3",
        env={
            "HANDOFF_TRANSCRIPT": str(tr),
            "HANDOFF_LOG_FILE": str(log),
            "HANDOFF_WATCHER_BOOT_TIMEOUT": "5",
        },
    )

    assert result.returncode == 0
    records = [json.loads(row) for row in log.read_text().splitlines()]
    last = records[-1]
    assert last["line"] == "continue with task 3"
    # The 1s clock starts before the walker's interpreter does, so the gate
    # sees less of it than was staged — 0.25-0.45s less unloaded, and a 0.3s
    # staging went under 0.15 at load average ~9. An already-present composer
    # costs 0.03, so the bound is well clear of that either way.
    assert last["gate"] >= 0.5
    assert set(last) == {"at", "line", "gate", "idle", "landed", "confirmed"}
    # Bounded: a file nothing consumes must not grow with every transition.
    assert len(records) == 50
    assert records[0]["line"] == "old 11"


def test_sequence_re_gates_on_idle_between_lines(
    tmux_stub: TmuxStub, tmp_path: Path
) -> None:
    (tmux_stub.stubdir / "pane_after_enter.txt").write_text(
        f"* Flummoxing… (12s · ↓ 1k tokens)\n❯{NBSP}\n"
    )
    tr = tmp_path / "t.jsonl"
    tr.write_text("")
    tmux_stub.on_enter(
        f'printf \'{{"type":"custom-title","customTitle":"{TITLE}"}}\\n\' >> \'{tr}\''
    )

    start = time.monotonic()
    walk(
        tmux_stub,
        f"/rename {TITLE}",
        "the second line",
        env={"HANDOFF_TRANSCRIPT": str(tr)},
        timeout=3,
    )
    elapsed = time.monotonic() - start

    assert "-l|the second line|" in tmux_stub.sent_text()
    assert elapsed >= 2
