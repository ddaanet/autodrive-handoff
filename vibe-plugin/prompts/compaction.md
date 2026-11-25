CRITICAL: Respond with text only. Do NOT call any tools. Any tool call will be rejected.

You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume this task. A handoff boundary may or may not have run just before this compaction (a plain /compact or an auto-compaction uses the same prompt). Either way TASK.md and TODO.md survive on disk, untouched by the compaction, and are the task frame; the next model sees this summary of the conversation in place of the conversation itself.

The summary comes in two layers, in this order.

## Layer 1: the task and the open work

- `## Current task` — the task in hand and its concrete next action, as the conversation now stands: the latest state of the work, not a copy of any TASK.md read earlier in the session (that read may be stale, and its "first action" may be done). Prose, not a recap.
- The frame on disk — TASK.md and TODO.md survive the compaction, and any copy of them in this conversation may be stale (rewritten since, or edited by hand). Do not reproduce either. Say that the next turn's first act is to read TASK.md and TODO.md from disk and treat those files as the frame. You may list the open decisions and remaining items you know of for orientation, flagged as not the file.

Add nothing of your own inside any fenced block you do quote: no note, parenthetical, marker or status remark, not even after the last line. Anything inside a block reads as the file's content. A comment on a file goes in Layer 2, outside every fence.

## Layer 2: what the files do not carry

After Layer 1, and briefly:

- Key decisions made this session and their rationale, if not already on disk
- Files touched and their state of in-progress work (paths + one-line status)
- What remains to be done that neither file lists
- Any data, identifiers, or references the next LLM needs that are in neither file

Do not repeat what Layer 1 already carries. Do not include a "Final Answer" section — the entire summary IS the handoff.

Wrap the ENTIRE summary in <summary></summary> tags and output nothing outside them:

<summary>
...your handoff summary here...
</summary>
