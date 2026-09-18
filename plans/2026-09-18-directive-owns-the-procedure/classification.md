# Classification — directive owns the procedure

Composite: five items, classified individually (implicit bundling — the items
came out of one design conversation).

## Items A (skill bodies) and E (design doc, changelog, CLAUDE.md)

- **Classification:** Simple
- **Implementation certainty:** High — is approach known? Yes, prose edits.
- **Requirement stability:** High — are FRs mechanism-specified? Yes.
- **Behavioral code check:** Does this task add functions, change logic paths,
  or add conditional branches? No
- **Work type:** Production
- **Artifact destination:** agentic-prose (A), investigation (E)
- **Evidence:** pure prose. A cannot ship ahead of B–D: a skill body that
  stops stating the procedure before the checkpoint prints it has no
  procedure at all, so both ride the same runbook as inline phases.

## Items B (directive composition), C (hold rule), D (`handoff-approved` closing line)

- **Classification:** Moderate
- **Implementation certainty:** High — `memory_directive`, `arming_directive`
  and the FR9 composition are direct prior art; `handoff-approved` already
  parses the sentinel through `handoff_drive_read` and already prints a line.
- **Requirement stability:** Moderate-to-high — two forks settled on stated
  defaults (the hold widens to the commit act; the checkpoint owns the closing
  line), one scoping question carried into the outline.
- **Behavioral code check:** Does this task add functions, change logic paths,
  or add conditional branches? Yes → Moderate minimum
- **Work type:** Production
- **Artifact destination:** production
- **Evidence:** C changes the mutation-checked held/armed pair in
  `tests/test_checkpoint.py`; B changes the 24 rows there that assert empty
  stdout. Triage recall selected no memory entry; `craft:directive-writing`
  and `craft:test-discipline` own the domain and load at the point of use.

## Routing

One outline, non-prose Moderate path: `outline.md` → `/proof` → `/runbook`.
