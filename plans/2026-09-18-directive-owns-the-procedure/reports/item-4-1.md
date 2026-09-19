# Item 4.1 — handoff skill follows what the checkpoint prints

File: `skills/handoff/SKILL.md`. Word count 1932 → 1791 (`wc -w`).
`just precommit` green (261 passed, 11 deselected; lint stages ok).

## Shape

- Step 1: Write durable learnings to memory — the only tool calls allowed
  before `handoff-checkpoint`; skip if nothing durable surfaced.
- Step 2: Decide, then checkpoint — "Make no tool call between deciding and
  `handoff-checkpoint`", the three decisions, content, heredoc, key semantics.
- Step 3: Follow what it prints, in order — each part waits for everything
  above it, and a run command may print the next part (covers
  `handoff-approved` printing the closing line on the held path).

## Removed

- Tense clause inside **Capture memory** ("Under `with-commit`, memory
  bodies state present-tense truth …") — removed; the rest of Capture memory
  became Step 1.
- Step 2's commit-placement paragraph ("When the ask includes a commit, make
  it **after** the checkpoint …") — removed.
- Step 3 "Say what the boundary is ready for" and its prepared/driven
  matrix — removed.
- "`handoff-checkpoint` prints nothing when there is nothing further to
  do" — rewritten as "prints what is left to do at this boundary. Carry out
  each part in the order printed …".
- Not on the item's list, removed as mechanism under
  `craft:directive-writing`: "A driven transition whose directive needs an
  answer is written but not armed, and the directive says how to release
  it." The printed arming instruction now carries that act. Flag if it
  should be restored.

## Kept

- The three decisions step 1 owned (typed transition, continuation, commit
  awareness), verbatim, now in Step 2, including "The ask stops at the
  transition".
- "The checkpoint owns the decision — do not re-derive or verify it" — in
  Step 3.
- Non-zero-exit instruction (names the offending field on stderr; fix the
  payload and retry) — in Step 3.
- File templates, task/todo rules — unchanged.
- The seam section — unchanged, heading intact for precompact.
- Every anti-pattern — kept; the first one's "Step 1" reference updated to
  "Step 2", where deciding now lives.
