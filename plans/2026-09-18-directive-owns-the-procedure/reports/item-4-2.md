# Item 4.2 — precompact skill follows what the checkpoint prints

File: `skills/precompact/SKILL.md`. Word count 1289 → 1128 (`wc -w`).
`just precommit` green (261 passed, 11 deselected; lint stages ok).

## Shape

Mirrors `skills/handoff/SKILL.md` (Item 4.1): `## Protocol` with three
`###` steps.

- Step 1: Write durable learnings to memory — moved ahead of deciding, as in
  4.1; the only tool calls allowed before `handoff-checkpoint`.
- Step 2: Decide, then checkpoint — "Make no tool call between deciding and
  `handoff-checkpoint`", the three decisions, task/todo content, deferral to
  `../handoff/SKILL.md`, heredoc, key semantics.
- Step 3: Follow what it prints, in order — handoff's Step 3 paragraph
  verbatim, then the rewritten normal-case sentence.

## Removed (against the item)

- Step 1's tense paragraph ("Under `with-commit`, memory bodies state
  present-tense truth …") — removed.
- Step 2's tense clause ("in the tense the commit answer sets") — removed.
- Step 3's closing commit-placement paragraph ("When the ask includes a
  commit, make it **after** this call …") — removed.
- Step 5 and its prepared/driven × commit matrix — removed.
- "Nothing printed → nothing further to do" — rewritten as Step 3's "prints
  what is left to do at this boundary. Carry out each part in the order
  printed …".
- "The normal case — nothing durable, clean memory, no directive — is one
  silent checkpoint call and one line of reply" — rewritten as "The normal
  case — nothing durable, clean memory, no commit — is one checkpoint call,
  and its output is the one line you end on." "no commit" added because
  `with-commit` prints the commit act ahead of the closing line.
- Not on the item's list, removed as mechanism per the dispatch (same
  treatment as 4.1): step 4's second paragraph ("A driven compaction whose
  directive needs an answer is written but not armed …"). The printed
  arming instruction carries that act.

## Kept

- Step 4's do-not-re-derive prohibition and non-zero-exit instruction — in
  Step 3.
- Deferral to `handoff/SKILL.md` for templates and the seam — in Step 2.
- The `compact` focus directive; the reason `compact: false` still writes
  the transition file (moved next to the `compact` decision it explains);
  silent authoring of the continuation (folded into the `continue`
  decision, as in 4.1); the task/todo guidance.
- "None of them has a default" with its reason, and "The ask stops at the
  transition".
- Every anti-pattern, unchanged — including padding the closing line into a
  summary, which now guards text the checkpoint supplies.

## Handoff skill

No inconsistency found in `skills/handoff/SKILL.md`.

## Commit

Blocked: `git commit` failed with `cannot lock ref 'HEAD'` —
`.git/refs/heads/main.lock` exists (0 bytes). Not removed. The skill and
this report are left staged; commit with subject
`docs: Item 4.2 — precompact skill follows what the checkpoint prints`.
