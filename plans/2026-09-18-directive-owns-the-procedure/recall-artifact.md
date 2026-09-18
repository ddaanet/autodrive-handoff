# Recall artifact — directive owns the procedure

Planning-relevant entries only. Execution detail reaches executors through
dispatch prompts.

## Memory

- `memory/ddaanet/subagent-skips-at-import-expansion.md` — a dispatched
  subagent's context omits `CLAUDE.md`'s `@memory/ddaanet/shared-claude.md`
  import, so a rule from the shared tier that an executor must follow is
  stated in its dispatch prompt (bare `pytest`, no `uv run`; entry points
  before definitions; no compat aliases).

## Skills (load at the point of use)

- `craft:directive-writing` — every new agent-facing string: the commit act,
  the closing line, the reworded arming instruction. Phases 1, 3 and 4.
- `craft:test-discipline` — the mutation-checked rows in phases 1–3: a genuine
  red from a failed assertion, and each mutation redding its own row alone.
- `plugin-craft:skill-authoring` — phase 4's two skill bodies.
- `craft:design-doc-writing` — phase 5's `docs/design.md` rewrite and the
  changelog entry.

## Post-explore gate

Exploration surfaced one domain recall had not anticipated — a miscounted
enumeration in the outline (six empty-stdout rows, not 24), corrected in place.
`craft:plan-contracts` → spec hygiene covers it: re-derive an enumerated list
by grep before checking against it. No further memory entry selected.
