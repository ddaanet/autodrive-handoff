"""Tests for `fit_frame` in scripts/_checkpoint_lib.py — what counts as a
TODO.md item, the counting unit and the cost of the cut.

The loaders' rows over the same function, through `handoff_frame_fit`, are in
tests/load-handoff.bats and tests/load-compact.bats.
"""

import time

import _checkpoint_lib as lib
import pytest

HEAD = "header\n\n## Current task\n\ntask"
POINTER_TAIL = "than shown here: read it before acting on either list."


@pytest.mark.parametrize("marker", ["- ", "* ", "+ ", "1. ", "12) "])
def test_every_list_marker_starts_an_item(marker: str) -> None:
    # Breaks if `marker` is not an item: the over-long item it follows is then
    # its continuation, both go, and the pointer counts one item.
    todo = f"## Remaining\n\n{marker}keep\n{marker}" + "z" * lib.FRAME_LIMIT + "\n"
    out = lib.fit_frame(HEAD, todo, "")
    assert f"\n{marker}keep" in out
    assert out.endswith(f"TODO.md holds 1 more remaining item {POINTER_TAIL}")


@pytest.mark.parametrize(
    "heading", ["## Open decisions", "## Open decisions:", "## OPEN DECISIONS :"]
)
def test_the_decisions_heading_marks_its_tier(heading: str) -> None:
    # Breaks if `heading` is not read as the decisions tier: its item, last in
    # the file, is then a remaining one and the first to go.
    big = "z" * lib.FRAME_LIMIT
    todo = f"## Remaining\n\n- {big}\n\n{heading}\n\n- decide\n"
    out = lib.fit_frame(HEAD, todo, "")
    assert "- decide" in out
    assert out.endswith(f"TODO.md holds 1 more remaining item {POINTER_TAIL}")


@pytest.mark.parametrize("fence", ["```", "~~~~"])
def test_a_fence_never_starts_an_item(fence: str) -> None:
    # Breaks if a `- ` line inside the fence starts an item: the cut then drops
    # it alone and leaves the fence's opening line behind, unclosed.
    big = "z" * lib.FRAME_LIMIT
    todo = (
        f"## Remaining\n\n- keep\n- code\n{fence}\n- {big}\n## not a heading\n{fence}\n"
    )
    out = lib.fit_frame(HEAD, todo, "")
    assert out.endswith(
        f"\n\n- keep\n\nTODO.md holds 1 more remaining item {POINTER_TAIL}"
    )


def test_a_tilde_line_does_not_close_a_backtick_fence() -> None:
    big = "z" * lib.FRAME_LIMIT
    todo = f"## Remaining\n\n- keep\n- code\n```\n~~~\n- {big}\n```\n"
    out = lib.fit_frame(HEAD, todo, "")
    assert "```" not in out
    assert out.endswith(f"TODO.md holds 1 more remaining item {POINTER_TAIL}")


def test_an_astral_character_counts_two_units() -> None:
    # 6000 emoji: 6000 code points, 12000 UTF-16 units. A code-point count
    # leaves the frame whole, over the host's limit.
    todo = "## Remaining\n\n- keep\n- " + "\U0001f600" * 6000 + "\n"
    whole = HEAD + "\n\n" + todo
    assert len(whole) + 1 <= lib.FRAME_LIMIT
    out = lib.fit_frame(HEAD, todo, "")
    assert "\U0001f600" not in out
    assert out.endswith(f"TODO.md holds 1 more remaining item {POINTER_TAIL}")


def test_a_frame_exactly_at_the_limit_in_units_stays_whole() -> None:
    # One emoji is two units: the frame plus the closing newline is exactly
    # FRAME_LIMIT units, and one more x puts it over.
    base = HEAD + "\n\n## Remaining\n\n- keep\n- \U0001f600"
    pad = lib.FRAME_LIMIT - (len(base) + 1) - 1 - 1
    todo = "## Remaining\n\n- keep\n- \U0001f600" + "x" * pad + "\n"
    assert lib.fit_frame(HEAD, todo, "") == HEAD + "\n\n" + todo
    todo = "## Remaining\n\n- keep\n- \U0001f600" + "x" * (pad + 1) + "\n"
    assert "TODO.md holds 1 more" in lib.fit_frame(HEAD, todo, "")


def test_ten_thousand_items_fit_well_under_a_second() -> None:
    # Breaks if each dropped item re-renders the file: 10000 items then take
    # tens of seconds, past the loaders' 10 s hook timeout.
    todo = "## Remaining\n\n" + "".join(f"- item {n}\n" for n in range(10000))
    started = time.monotonic()
    out = lib.fit_frame(HEAD, todo, "")
    elapsed = time.monotonic() - started
    assert elapsed < 0.5
    assert len(out) + 1 <= lib.FRAME_LIMIT
    # the smallest cut: one item fewer would be over
    shown = out.count("\n- item ")
    kept = (
        HEAD
        + "\n\n"
        + "## Remaining\n\n"
        + "".join(f"- item {n}\n" for n in range(shown + 1))
    )
    pointer = f"TODO.md holds {10000 - shown - 1} more remaining items {POINTER_TAIL}"
    assert len(kept.rstrip() + "\n\n" + pointer) + 1 > lib.FRAME_LIMIT
