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
- `docs/changelog.md` and `docs/changelog/` are a frozen archive of the
  write-time records written up to 2026-10-31. Nothing adds a record or an
  index line, and nothing edits a record; links into the archive stay valid.
- A design change rewrites whatever `docs/design.md` or `docs/design/` prose it
  invalidates, in the same commit. The node keeps the reason the decision
  stands; the commit body carries why it changed now. A rewrite that reverses a
  decision whose node cites an archived record as its argument drops or
  replaces that link.
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
