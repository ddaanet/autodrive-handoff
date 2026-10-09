"""Live smoke test: does the plugin's mod drive an armed transition?

Boots a real ``claude -p`` (cheap model, one trivial turn) with this repo as
``--plugin-dir`` in a throwaway git repo whose ``.claude/autodrive`` is
already ``armed``, then reads what the transition left in the session
transcripts. Nothing is read from a pane and no tmux is involved: the mod
drives the session through the mods API, and the transcript is the record.

Excluded from ``just precommit`` by the ``live`` marker: it needs a real
``claude`` on PATH, which the agent's sandbox excludes, and it spends a few
model turns. Run it with ``just mod-smoke``.

The four facts the spike settled are in
``plans/2026-10-08-plugin-becomes-a-mod/reports/step1-mod-live-smoke.md``.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest

pytestmark = pytest.mark.live

REPO = Path(__file__).resolve().parent.parent

MODEL = os.environ.get("HANDOFF_MOD_SMOKE_MODEL", "haiku")
RUN_TIMEOUT = 240.0
FIRST_PROMPT = "Reply with the single word ok. Use no tools."
TITLE = "mod-smoke-title"
CONTINUATION = "Reply with exactly the word CONTINUED"
FOCUS = "keep the word PINEAPPLE"


def test_rename_row(smoke_repo: Path) -> None:
    arm(smoke_repo, f"rename\n/rename {TITLE}\n")

    run_claude(smoke_repo)

    assert TITLE in custom_titles(smoke_repo)


def test_clear_row_continues_in_the_fresh_session(smoke_repo: Path) -> None:
    arm(smoke_repo, f"clear\n/rename {TITLE}\n/clear\n{CONTINUATION}\n")

    run_claude(smoke_repo)

    sessions = user_prompts_by_session(smoke_repo)
    first = [s for s, texts in sessions.items() if FIRST_PROMPT in texts]
    fresh = [s for s, texts in sessions.items() if texts[:1] == [CONTINUATION]]
    assert len(first) == 1, sessions
    assert len(fresh) == 1, sessions
    assert first != fresh, sessions


def test_compact_row_carries_the_focus_and_continues(smoke_repo: Path) -> None:
    arm(smoke_repo, f"compact\n/compact {FOCUS}\n{CONTINUATION}\n")

    run_claude(smoke_repo)

    entries = [e for _, e in transcript_entries(smoke_repo)]
    assert any(e.get("isCompactSummary") for e in entries), "no compaction"
    focus_run = [e for e in entries if FOCUS in entry_text(e)]
    assert focus_run, "the /compact focus never reached the session"
    assert any(entry_text(e) == CONTINUATION for e in entries), "no continuation"


@pytest.fixture
def smoke_repo(tmp_path: Path) -> Iterator[Path]:
    repo = tmp_path.resolve() / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    (repo / ".claude").mkdir()
    yield repo
    shutil.rmtree(transcript_dir(repo), ignore_errors=True)


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True)


def arm(repo: Path, body: str) -> None:
    (repo / ".claude" / "autodrive").write_text(f"armed\n{body}")


def run_claude(repo: Path) -> None:
    env = allowed_env()
    proc = subprocess.run(
        [
            "claude",
            "-p",
            "--model",
            MODEL,
            "--plugin-dir",
            str(REPO),
            "--permission-mode",
            "default",
            # `=` form: the flag is variadic and would swallow the prompt.
            "--disallowedTools=Bash,Edit,Write,NotebookEdit",
            FIRST_PROMPT,
        ],
        cwd=repo,
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=RUN_TIMEOUT,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr


def allowed_env() -> dict[str, str]:
    # Not the developer's whole environment: the process runs a model turn
    # and a plugin's hooks. TMUX is absent by construction, so the plugin's
    # classic hooks can never type into the pane of whoever runs the suite.
    names = {"PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "USER", "CLAUDE_CONFIG_DIR"}
    return {
        k: v
        for k, v in os.environ.items()
        if k in names or k.startswith("ANTHROPIC_") or k == "CLAUDE_CODE_OAUTH_TOKEN"
    }


def custom_titles(repo: Path) -> list[str]:
    return [
        e["customTitle"]
        for _, e in transcript_entries(repo)
        if e.get("type") == "custom-title"
    ]


def user_prompts_by_session(repo: Path) -> dict[str, list[str]]:
    sessions: dict[str, list[str]] = {}
    for session, entry in transcript_entries(repo):
        if entry.get("type") != "user" or entry.get("isMeta"):
            continue
        text = entry_text(entry)
        if text and not text.startswith("<"):
            sessions.setdefault(session, []).append(text)
    return sessions


def entry_text(entry: dict[str, Any]) -> str:
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""


def transcript_entries(repo: Path) -> list[tuple[str, dict[str, Any]]]:
    out: list[tuple[str, dict[str, Any]]] = []
    for path in sorted(transcript_dir(repo).glob("*.jsonl")):
        lines = (ln for ln in path.read_text().splitlines() if ln.strip())
        out.extend((path.stem, json.loads(ln)) for ln in lines)
    return out


def transcript_dir(repo: Path) -> Path:
    encoded = re.sub(r"[^A-Za-z0-9]", "-", str(repo))
    return Path.home() / ".claude" / "projects" / encoded
