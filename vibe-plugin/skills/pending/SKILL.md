---
name: pending
description: List pending tasks from the session's already-loaded context — no tool calls while the first-prompt read holds. Reports the current task frame's "Open decisions" and "Remaining" items as read at session start. Use when the user asks "what's pending", "list pending tasks", "show pending", "pending", or asks what is left to do.
---

# pending — List Pending Tasks From Context

Report the pending work already visible in context: the `## Open decisions`
and `## Remaining` sections of the task frame, which under Vibe is the first
read of `TASK.md` and `TODO.md` the AGENTS.md loader line orders at the
session's first prompt. Make **no tool calls** — this is a read of what is
already in context, not of the files on disk — except when the read did not
happen or the lists moved since (step 2).

## Protocol

1. Find the task state already in context: the `TASK.md`/`TODO.md` content
   read at the session's first prompt, or any checkpoint output since.
2. If the first prompt's read is missing (an older session, a repo without
   the loader line yet), the session ran long, or the lists were edited
   after that read, read `TODO.md` at the project root and take the open
   decisions and remaining items from it. Absent both a read and edits, what
   context holds is current however short it looks.
3. List the open decisions and remaining items, grouped as they appear
   ("Open decisions" / "Remaining"). Trim for brevity; do not re-derive
   or editorialize beyond that.
4. If nothing is in context and neither file is in play, say so plainly
   rather than guessing.

## Anti-patterns

- Reading `TASK.md` or `TODO.md` to double-check what the first prompt's
  read already delivered whole. The point is a zero-cost
  report of what is already loaded; a stale answer here is corrected by
  editing `TODO.md` directly (open decisions, remaining items) or at the
  next checkpoint (the current task), not by a file read now.
- Treating this as a task-management action. It reports only — it never
  edits `TASK.md`, `TODO.md`, or memory.
