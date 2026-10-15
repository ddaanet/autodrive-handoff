# tests/mod/fixtures.ts is generated from tests/mod/fixtures/*.json; the mod
# tests read only the generated copy, so a drifted copy tests the wrong plan.
import json
from pathlib import Path

from checkpoint import CONTINUATION
from gen_mod_fixtures import render

MOD_TESTS = Path(__file__).resolve().parent / "mod"


def test_fixtures_ts_matches_the_json_fixtures() -> None:
    committed = (MOD_TESTS / "fixtures.ts").read_text(encoding="utf-8")
    assert render(MOD_TESTS / "fixtures") == committed, (
        "regenerate with: python3 tests/gen_mod_fixtures.py"
    )


def test_every_prose_line_a_fixture_submits_is_the_checkpoint_constant() -> None:
    prose = [
        (path.name, line)
        for path in sorted((MOD_TESTS / "fixtures").glob("*.json"))
        for line in json.loads(path.read_text(encoding="utf-8"))["after"]
        if not line.startswith("/")
    ]
    assert prose, "no fixture carries a continuation"
    assert [(n, line) for n, line in prose if line != CONTINUATION] == []
