---
paths:
  - "skills/**"
---

# Skill conventions

Behaviour lives in `docs/design/the-skills.md`; read it first.

- A `SKILL.md` body stays at or under 2000 words (NFR3: bodies get shorter,
  not longer). Detailed rationale goes to `references/` or `docs/design.md`.
- The markdown templates of `TASK.md` and `TODO.md`, and the seam between
  what the files carry and the fixed continuation, live in
  `skills/handoff/SKILL.md`. `skills/precompact/SKILL.md` repeats the todo
  template and the todo rules it needs, so an edit to the todo template or
  rules changes both skills. Neither loader restates them: each file carries
  its own `##` headings and is inlined verbatim under the one `#` header the
  frame prepends.
- A skill states none of what the checkpoint prints (the memory directive,
  the commit act, the `handoff-approved` instruction, the closing line): it
  follows the printed text. The check is that
  `grep -n 'gitlore:commit\|handoff-approved' skills/*/SKILL.md` stays empty.
- At a boundary skill, only the memory writes may precede the one
  `handoff-checkpoint` call. Nothing is read: no project state, `TASK.md`
  and `TODO.md` included. A reference file read on every call is not an
  option; the templates are inline. `precompact` carries no `rename` and no
  `task`; the schema forbids both there.
- `autoname` decides a title with no tool call, and its payload is exactly
  `{"skill": "autoname", "rename": "<title>"}`. `pending` makes no tool call
  and writes nothing.
