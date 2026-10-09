# tests/mod/fixtures.ts is generated from tests/mod/fixtures/*.json; the mod
# tests read only the generated copy, so a drifted copy tests the wrong plan.
from pathlib import Path

from gen_mod_fixtures import render

MOD_TESTS = Path(__file__).resolve().parent / "mod"


def test_fixtures_ts_matches_the_json_fixtures() -> None:
    committed = (MOD_TESTS / "fixtures.ts").read_text(encoding="utf-8")
    assert render(MOD_TESTS / "fixtures") == committed, (
        "regenerate with: python3 scripts/gen_mod_fixtures.py"
    )
