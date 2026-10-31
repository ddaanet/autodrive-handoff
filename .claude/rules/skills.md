---
paths:
  - "skills/**"
---

# Skill conventions

Behaviour lives in `docs/design/the-skills.md`; read it first.

- A `SKILL.md` body stays at or under 2000 words (NFR3: bodies get shorter,
  not longer). Detailed rationale goes to `references/` or `docs/design.md`.
- The markdown templates of `TASK.md` and `TODO.md`, and the seam between
  what the files carry and the fixed continuation, live only in
  `skills/handoff/SKILL.md`. `precompact` defers to it, and neither loader
  restates them: each file carries its own `##` headings and is inlined
  verbatim under the one `#` header the frame prepends.
- A skill states none of what the checkpoint prints (the memory directive,
  the commit act, the `handoff-approved` instruction, the closing line): it
  follows the printed text. The check is that
  `grep -n 'gitlore:commit\|handoff-approved' skills/*/SKILL.md` stays empty.
- At a boundary skill, the memory writes are the only tool calls ahead of the
  one `handoff-checkpoint` call. `precompact` carries no `rename` and no
  `task`; the schema forbids both there.
- `autoname` decides a title with no tool call, and its payload is exactly
  `{"skill": "autoname", "rename": "<title>"}`. `pending` makes no tool call
  and writes nothing.
