# tests/mod/fixtures.ts is generated from tests/mod/fixtures/*.json; the mod
# tests read only the generated copy, so a drifted copy tests the wrong plan.
import re
from pathlib import Path

from continuation import continuation
from gen_mod_fixtures import render

MOD_TESTS = Path(__file__).resolve().parent / "mod"
MOD = Path(__file__).resolve().parent.parent / "hooks" / "handoff.ts"


def test_fixtures_ts_matches_the_json_fixtures() -> None:
    committed = (MOD_TESTS / "fixtures.ts").read_text(encoding="utf-8")
    assert render(MOD_TESTS / "fixtures") == committed, (
        "regenerate with: python3 tests/gen_mod_fixtures.py"
    )


def test_the_mods_continuation_literal_is_the_libraries_constant() -> None:
    # The mod holds the one prompt it submits as a literal and reads none from
    # disk; HANDOFF_CONTINUATION is what the sweep renders. Same pin, in
    # spirit, as tests/bin-commands.bats holds handoff-approved to
    # closing_directive().
    source = MOD.read_text(encoding="utf-8")
    found = re.findall(r"^const CONTINUATION = '([^']*)'$", source, re.MULTILINE)
    assert found == [continuation()]


def test_the_continuation_is_one_line_that_is_not_a_command() -> None:
    text = continuation()
    assert text
    assert text.strip() == text
    assert len(text.splitlines()) == 1
    assert not text.startswith("/")
