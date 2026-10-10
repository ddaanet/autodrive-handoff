# Overflow analysis: what is left of a task file once its overflow moves out

2026-10-11. Follows `task-length-survey.md`, whose cap (1500) was fitted to how
often raw task files exceed a length. My human partner reopened it: the
threshold should come from the content that belongs in the task file, measured
after everything else is sent where it belongs.

## The rule being measured

A task file holds the task in hand and its immediate continuity. Everything
else is overflow, and each kind has a home:

| label | content | home |
|---|---|---|
| A | the task in hand: what is being worked on, where it stands, what is in flight, the single next action, the pointers to pick it up | `TASK.md` |
| B | the plan to execute: remaining steps, queues, follow-ups, other threads, open decisions | `TODO.md` |
| C | standing rules and conventions: protocol, environment constraints, lessons, settled designs | memory, through the approval gate |
| D | what was just completed | dropped, beyond one sentence |
| E | none of these | dropped |

## Method

- **Sample.** Every committed version of `.claude/handoff-task.md` dated
  >= 2026-07-22 in the repositories the survey covered: 441 versions (135 in
  era 2, 2026-07-22..08-11, when the task file still held `## Open decisions`;
  306 in era 3). The slice question the survey left open does not arise: the
  residual is measured on both eras and comes out the same.
- **Units, by script** (`overflow/units.py`). Heading lines are context, not
  content. Each list item is one unit; each prose block is unwrapped and split
  into sentences (also at `; `). 3030 units, median 148 characters, p90 329,
  longest 1729.
- **Labels, by a Haiku reader** (`overflow/labelling-instructions.md`), in 13
  batches of about 45 000 characters, successive versions of a repo kept
  together. The reader assigns one letter per unit and counts nothing.
- **Counts, by script** (`overflow/tally.py`). Every unit came back labelled
  exactly once with a valid letter: 3030 of 3030.
- **Residual.** Two readings per version: the A units alone, and the A units
  plus the first D unit (the one sentence of "just completed" the rule allows).
  Units are joined by one character, as they were in the file.

`overflow/labels.tsv` holds one row per unit (unit id, repo, commit, date, era,
characters, label) and no task-file text. `python3 overflow/tally.py` prints
every table below from that file alone. To read a label against its text,
rebuild the units: `collect.py` writes `versions.tsv` and `blobs/` under
`/tmp/claude/survey` from the repositories' history, and `units.py`, run from
there, writes `overflow/units.tsv` with the same unit ids.

## How far to trust the labels

- **Calibration.** Before the full run, the 15 versions the survey judged by
  reading (its section 2b) were labelled alone and I read every label against
  the text. The assignments were defensible throughout; the two the survey
  called "description only" came back about half A, half B, which is the same
  reading at a finer grain (each names a next thread or a deferred edit).
- **Run-to-run agreement.** Those 15 versions were labelled a second time
  inside the full run. 192 of 217 units agree (88%), 89% by characters. Per
  version, the A total moves by a median of about 85 characters between runs.
  One version moved by 2245: a 1729-character verdict list was D in one run and
  A in the other. A single long unit flipping is the failure mode, so the top
  of the tail (p99, max) is not stable; p90 and p95 are.
- **Direction of the error.** Reading the five largest residuals: each is a
  plan, a spec or a defect analysis written inline and labelled A (a gate
  rework with its file-by-file instructions, a proposed fix shape, a design
  brief). Under the rule these are plan matter, so the reader is lenient at the
  top and the residual tail is an overestimate.
  At the bottom, 73 versions have no A unit at all: they open on "X is
  complete" and go straight to open decisions. Their continuity is the one
  done sentence, which is why the second reading is the one to fit a cap to.

## Results

Where the characters go (all 441 versions, 532 111 characters):

| label | share of characters | versions carrying any |
|---|---|---|
| A, task in hand | 20.3% | 368 |
| B, plan and open decisions | 35.7% | 305 |
| C, rules and conventions | 16.9% | 176 |
| D, already done | 27.1% | 357 (166 with more than one unit) |

Era 3 alone: A 25.4%, B 21.8%, C 22.2%, D 30.7%. The todo file took the open
decisions out of the task file (B fell from 53.5% in era 2), and the space was
refilled with conventions and done-logs rather than given back.

422 of 441 versions carry some B, C or D. 58 are already in the target shape
(A units and at most one D unit).

Residual length in characters:

| sample | reading | p50 | p75 | p90 | p95 | p99 | max |
|---|---|---|---|---|---|---|---|
| all 441 | raw body | 867 | 1543 | 2496 | 3263 | 4599 | 6554 |
| all 441 | A only | 156 | 358 | 550 | 696 | 1337 | 4018 |
| all 441 | A + one done sentence | 354 | 524 | 691 | 867 | 1525 | 4058 |
| era 2 (135) | A + one done sentence | 332 | 491 | 727 | 932 | 1299 | 4058 |
| era 3 (306) | A + one done sentence | 365 | 537 | 674 | 843 | 1619 | 2717 |

The two eras differ by a factor of two in raw length and by under 10% in
residual at every percentile up to p95: the task in hand has been the same
size all along, about 350 characters at the median.

Candidate caps, over all 441 versions:

| cap | raw files over it | still over after relocation (A + one done sentence) |
|---|---|---|
| 600 | 317 (72%) | 78 (17.7%) |
| 800 | 247 (56%) | 31 (7.0%) |
| 1000 | 189 (43%) | 16 (3.6%) |
| 1200 | 161 (37%) | 9 (2.0%) |
| 1500 | 117 (27%) | 5 (1.1%) |

The second column is not a false-rejection rate: it is how often a handoff
written the old way would be sent back to move content out, which is the
rule working. The third column is the cost: how often the task in hand, by a
lenient reader's judgement, does not fit. The 16 versions over 1000 are
gitlore 7, edify 3, private-A 4, private-B 2; the largest are the inline plans
and specs described above.

## Proposal

**1000 characters**, with the no-list rule kept.

- It is the first round number above the residual p95 (867), with about 130
  characters of margin, more than the run-to-run noise of the labelling.
- It is nearly three times the median task in hand, so an ordinary task
  description never meets it.
- 1500 does not bind: it sits at the residual p99, so a file could carry 600
  characters of conventions or done-log on top of a p95 task and pass.
- 800 is the tighter choice (residual p94): it would have sent back 7% of
  task descriptions that a lenient reader accepted as task-only.

What the number cannot do: a cap bounds the amount, not the kind. A
900-character file that is all done-log passes. The list rule catches plans
written as lists; plans and conventions written as prose under the cap are
left to the template wording and the error text, which should name the four
homes above.
