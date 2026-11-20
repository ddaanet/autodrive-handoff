---
name: pending
description: List pending tasks from the session's already-injected context — no tool calls unless that context was cut short. Reports the current task frame's "Open decisions" and "Remaining" items as loaded. Use when the user asks "what's pending", "list pending tasks", "show pending", "pending", or "/autodrive-handoff:pending".
---

# pending — List Pending Tasks From Context

Report the pending work already visible in context: the `## Open decisions`
and `## Remaining` sections of the task frame injected at session start (or
after a compact), which follow the `## Current task` when there is one. Make
**no tool calls** — this is a read of what is already in context, not of
the files on disk — except when the frame arrived cut (step 2).

## Protocol

1. Find the most recent task frame already in context.
2. If the frame sits inside a `<persisted-output>` block that says
   `Output too large`, context holds only a preview of it; if it holds a
   line saying `TODO.md` holds more items than shown, the loader cut items to
   fit. Either way, read `TODO.md` at the root of the git worktree the session
   was launched in, and take the open decisions and remaining items from it.
   Absent both, the frame is complete however short it looks.
3. List its open decisions and remaining items, grouped as they appear
   ("Open decisions" / "Remaining"). Trim for brevity; do not re-derive
   or editorialize beyond that.
4. If no frame was injected this session, or it has nothing pending,
   say so plainly rather than guessing.

## Anti-patterns

- Reading `TASK.md` or `TODO.md` to double-check a frame that arrived
  whole. The point is a zero-cost
  report of what is already loaded; a stale answer here is corrected by
  editing `TODO.md` directly (open decisions, remaining items) or at the
  next checkpoint (the current task), not by a file read now.
- Treating this as a task-management action. It reports only — it never
  edits `TASK.md`, `TODO.md`, or memory.
