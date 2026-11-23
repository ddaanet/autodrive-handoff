CRITICAL: Respond with text only. Do NOT call any tools. Any tool call will be rejected.

You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume this task. A handoff boundary ran just before this compaction: TASK.md and TODO.md in the project root are the sources of truth, and TASK.md no longer exists in context the next time the model looks — this summary is its only carrier.

The summary comes in two layers, in this order.

## Layer 1: the files, verbatim

Reproduce the on-disk frames byte for byte, headings and blank lines included, inside fenced markdown blocks:

- `## Current task` — the exact content of TASK.md. If TASK.md was absent or empty, write one line saying so.
- `## Open decisions` and `## Remaining` — the exact content of TODO.md, the file reproduced in full.

Do not trim, reword, reorder, or "summarize" these blocks. They exist so the next session keeps the exact identifiers, decisions and steps that were chosen to survive; a paraphrase defeats the boundary that wrote them.

## Layer 2: what the files do not carry

After the verbatim blocks, and briefly:

- Key decisions made this session and their rationale, if not already on disk
- Files touched and their state of in-progress work (paths + one-line status), where this is not inferable from the frames
- What remains to be done that neither file lists
- Any data, identifiers, or references the next LLM needs that are in neither file

Do not repeat what Layer 1 already carries. Do not include a "Final Answer" section — the entire summary IS the handoff.

Wrap the ENTIRE summary in <summary></summary> tags and output nothing outside them:

<summary>
...your handoff summary here...
</summary>
