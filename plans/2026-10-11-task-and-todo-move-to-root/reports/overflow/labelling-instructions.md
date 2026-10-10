# Labelling task-file units

You are given a batch number NN. Label every unit in one text file with a
single letter. Read-only analysis: you write exactly one output file and touch
nothing else.

- Input: `/tmp/claude/survey/overflow/batch-NN.txt`
- Output: `/tmp/claude/survey/overflow/batch-NN.labels.tsv`

The input holds many versions of a "task file": a short note an AI coding agent
leaves for the next session, saying what it was working on. Each version starts
with a line `=== vNNN <repo> <date>`. Lines starting with `#` are headings
(context only, never labelled). Every other non-blank line is a unit:
`<unit-id><TAB><text>`; unit ids look like `v021.04`. Some versions are in
French. Successive versions of one repo are often near-copies of each other:
label the same sentence the same way each time it recurs.

Give each unit exactly one label:

- **A** — the task in hand and its immediate continuity: what is being worked
  on right now, where it stands, what is in flight or half-done, the single
  next action, and the pointers needed to pick it up (the plan file, the
  branch, the file being edited, the baseline commit).
- **B** — plan to execute: remaining steps beyond the single next action, an
  ordered queue of work, phases or items still to do, follow-ups, deferred
  work, other threads running alongside, open decisions and open questions,
  things waiting on someone.
- **C** — standing rules and conventions: how to work in general — dispatch or
  orchestration protocol, which model to use for what, environment constraints
  and gotchas, tool quirks, lessons learned, settled design decisions "not to
  re-litigate", anything that would stay true after this task is finished.
- **D** — already done: what was completed, landed or committed, commit lists,
  verdicts already reached, what a finished item changed, the history of how
  the session got here.
- **E** — none of the above, or unreadable.

Rules for choosing:

- Judge each unit on its own text, using the heading above it and the
  neighbouring units only as context. A unit under `## Open decisions` is B. A
  unit under a heading like "Next step" or "Remaining" that lists several steps
  is B. A unit under "Conventions…", "Environment constraints…" or "…already
  settled" is C. A unit under "…already done…" or "…as landed" is D.
- A unit that only introduces what follows ("Verdicts so far:", "Conventions
  this run settled on:") takes the label of what it introduces.
- A unit that mixes kinds gets the label of the kind that takes most of its
  characters.
- A statement of the current state ("X is half-migrated", "tests are red on
  Y") is A. A statement that something finished ("X landed in abc123", "step 3
  is committed") is D.
- A rule about how to do the work ("dispatch one subagent per item", "never use
  tool Z here") is C even when it sits inside the task description.

Write the output file with the Write tool: one line per unit,
`<unit-id><TAB><label>`, in input order, nothing else — no header, no comments,
no blank lines. Every unit id in the input must appear exactly once.

Read the whole input file before labelling. Do not run scripts to guess labels;
read and judge. Before finishing, count the unit lines in the input (lines
beginning with `v`, digits, a dot, digits and a tab) and the lines in your
output, and make them equal.

Reply with one line: the output path and the number of units labelled.
