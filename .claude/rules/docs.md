---
paths:
  - "docs/**"
  - "plans/**"
  - "inbox/**"
---

# Document conventions

- `docs/design.md` is the hub: Problem, Research, Analysis, Requirements, a
  routing table, one index line per decision and per rejected alternative,
  Non-goals. `docs/design/` holds one node per mechanism; read the node
  before making a claim about its mechanism.
- `docs/changelog.md` is the index: one line per design change, newest
  first, `- [<date> — Title](changelog/<file>.md) — hook (vX.Y.Z)`, the
  version only when the entry maps onto one release.
- `docs/changelog/` holds one dated file per design change with the full
  write-time reasoning, never edited after the fact. A later change that
  reverses one heads the affected section with a
  `> **Superseded <date>** (see [<title>](<sibling>.md))` blockquote scoped
  to what changed.
- A design change adds its changelog file and index line and rewrites
  whatever `docs/design.md` or `docs/design/` prose it invalidates, all in the
  same pass.
- `plans/` holds prospective content (specs, proposals, implementation plans)
  and its reports, write-time records like changelog entries. A claim wrong
  at the time it was written is corrected in place with a
  `> **Corrected at review, <date>.**` blockquote that quotes the original
  wording, names what was wrong, shows the evidence and says what still
  stands.
- `inbox/` holds what arrives from a session in another repository: a brief,
  note or finding. Never the repo root, never `plans/`. Triage means acting
  on it and deleting it, or promoting it into `plans/`; a brief's
  recommendation is input, not a decision. See `inbox/README.md`.
