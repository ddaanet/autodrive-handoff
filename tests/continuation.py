"""The continuation prompt, read from its one definition.

`HANDOFF_CONTINUATION` in scripts/_lib_drive.sh is the string the sweep offers
and the one the mod's own literal (hooks/handoff.ts) must equal. Nothing in
Python composes it any more, so the tests read it from the source the way
tests/shared-helpers.bash's `continuation_line` does.
"""

import re
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"


def continuation() -> str:
    """Return HANDOFF_CONTINUATION's value from scripts/_lib_drive.sh."""
    source = (SCRIPTS / "_lib_drive.sh").read_text(encoding="utf-8")
    match = re.search(r"^HANDOFF_CONTINUATION='([^']*)'$", source, re.MULTILINE)
    assert match, "HANDOFF_CONTINUATION not found in scripts/_lib_drive.sh"
    return match.group(1)
