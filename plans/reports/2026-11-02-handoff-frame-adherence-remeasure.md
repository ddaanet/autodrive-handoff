# Handoff frame adherence, re-measured under FR13

2026-11-02. The re-run that `2026-10-12-handoff-frame-adherence.md` §7 and §8
asked for, to replace its estimate of what FR13 leaves with a measurement.
Input to a decision my human partner has not taken: whether the residual
warrants a gate. This report measures and recommends; it decides nothing.

Legend: **[M]** counted by script, **[H]** hand-verified by reading,
**[S]** a Sonnet reader judging whole frames, **[P]** a Haiku reader labelling
sentences with the 2026-10-11 rubric, **[J]** my own reading of a sample,
blind to [S].

## Summary

- The threshold was 100 versions under 0.16.1 or later across five
  repositories. 93 versions are since the tag, in 15 repositories. 88 of them
  are at `TASK.md`, the path the checkpoint writes, and a legacy-path version
  cannot have been written by that checkpoint, so the qualifying count is at
  most 88, at least 12 short. The rates below are over those 88; the [J] sample
  is drawn from the 93, with 2 of its 20 outside them. My human partner asked
  for the run expecting 100; I ran it short, judging that the missing versions
  would not change what it can show.
- FR13 holds mechanically: no version of the 88 is over 1000 characters or has
  a list item. Median body 683, longest 997.
- The share of characters on the task in hand rose to 42% [P], from 25% in e4
  and the "one character in five" across e3 and e4 that justified FR13.
- The judgement classes did not go away. On the same reader as the estimate,
  done-logs (26%) and plans (11%) came in at the estimate (28%, 14%).
  Conventions came in above it, on a reading that is noisy.
- The classes depend heavily on the reader and the unit judged. [S] and [J]
  agree on 85 to 95% of 20 versions. [S] and [P] agree on 47 to 80% of 88.
- Pending commit status reappeared: 8 to 10 of 88, against 3 of 298 in e4,
  though the two counts come from different methods.
- Recommendation in one line: no refusing gate; if the residual is worth acting
  on, change the template first. Section 5 argues it.
- The content did not move to `TODO.md` (section 6): todo files shrank, and
  almost no item there is finished work or a standing rule.

## 1. The set

Sources [M]: `collect.py` and `frames.py` over `~/code`, unchanged, then a
filter: plugin-authored task versions whose earliest author date is at or after
the `v0.16.1` tag, 2026-10-15T09:14:49+02:00.

| | versions |
|---|---|
| plugin-authored, dated 2026-10-15 or later | 95 |
| of those, authored before the tag | 2 |
| **since the tag** | **93** |
| of those, at the legacy path, all on 2026-10-15 | 5 |
| **at `TASK.md`, the rates below** | **88** |

- The 88 fall on 44 repository-days in 15 repositories, 18 of them versions in
  private or no-remote repositories, which this report only counts. Five
  repositories hold 69%.
- The rates count only `TASK.md` versions because a legacy-path version cannot
  have been written by the 0.16.1 checkpoint: those are install lag. Both versions
  over 1000 characters since 2026-10-15 are among the 5.
- Which plugin version wrote a version remains unknown (§2 and §6 of the
  earlier report). Release dates stand in, so some of the 88 may be older code.

## 2. Mechanical classes [M]

Over the 88: `#` heading 0, section outside the template 0, `###` sub-heading
0, no `## Current task` 0, `## Open decisions` in the task 0, list item 0, over
1000 characters 0. The checkpoint's validation is doing what it was built to
do.

Character share by [P] label: task in hand 42%, already done 27%, plan and
decisions 16%, conventions 16% (rounded). The same shares in e4, on the 215
versions the re-join resolves: 25%, 32%, 17%, 26%.

## 3. Judgement classes

| task file | e4, all [P] n=296 | e4 passing FR13 [P] n=197, the estimate | now [P] n=88 | now [S] n=88 |
|---|---|---|---|---|
| done-log: more than one sentence of what finished | 36% | 28% | 26% | 42% |
| conventions: any unit of standing rules | 40% | 26% | 52% | 23% |
| conventions: two or more units | 27%* | 13%* | 17% | |
| plan: two or more units of remaining steps | 25% | 14% | 11% | 58% |
| none of the three | 32% | 46% | 26% | 11% |

\* From a re-join of the prior labels that resolved 215 of the 296 e4 versions
and 142 of the 197 passing ones (the other columns are the earlier report's).

- **The [P] column is the like-for-like one.** Same rubric, same sentence
  splitter (`units.py`), same tier, though not necessarily the same Haiku model.
  One version per repository-day (n=44, seeded) moves it little: done-log 30%,
  conventions 55%, plan 14%, none 23%.
- **Done-logs and plans came in near the estimate; the rest of its picture did
  not.** On [P], done-log is 26% against 28% and plan 11% against 14%. Frames
  are not shorter than the estimate's population: median body 683 against 565
  for the e4 versions passing FR13 (737 for all e4) [M]. None of the three is
  26% against 46%. Section 6 finds no relocation to `TODO.md`, so the matching
  rates do not confirm the relocation the estimate assumed.
- **Conventions at "any unit" rose, and I do not read that as a real rise.**
  [P] alone flags 26 of the 88 where [S] does not, and [S] alone flags none.
  At two or more units [P] is 17%, near the estimate, and [S] is 23%. The
  earlier report's 12% self-disagreement of this reader applies too. By
  repository, [P] finds a conventions version in 11 of 15, [S] in 5.
- **The [S] plan rate may count something [P] cannot.** A single sentence that
  chains steps ("run X, then Y, then Z") is one unit for [P] and can be a plan
  for [S]. Of the 44 frames only [S] flags, 39 have a unit holding `then`,
  `once` or `before`, matched case-sensitively [M], against 13 of the 34 frames
  neither reader flags, and every one has at most one unit [P] calls a plan.
  That fits a chain and does not establish one. It may be the shape FR13 pushes
  toward, prose and no list; no [S] reading of pre-FR13 frames exists to show
  it. The skill's slot asks for "the next
  concrete action", and its rule sends remaining steps to the todo.

### Reader agreement

| class | [S] and [J], n=20 | [S] and [P], n=88 |
|---|---|---|
| done-log | 95% | 80% |
| conventions | 85% | 70% |
| plan | 95% | 47% |

[J] is a seeded sample of 20 of the 46 repository-days of the 93, 2 of its
versions outside the 88, labelled before [S] was read. It
differs from [S] on one version for done-log and one for plan. On conventions
all three differences are [J] flagging what [S] did not: a restated review
protocol, a sandbox gotcha and a settled decision. Twenty versions leave wide
intervals, about plus or minus 15 points, so
this is the first sign a Sonnet reader tracks a stronger one and not a measured
error rate.

## 4. Commit status [S], [H]

- [S] marks 10 of the 88 as stating pending commit or push status. Reading the
  10: 8 state it plainly and 2 are weaker, one an untracked script and one a
  pending memory-commit approval.
- Earlier rates: 3 of 298 in e4, 6 of 13 in e5 before 0.16.1. The e4 figure
  comes from hand-reading a regex's candidates and this one from a whole-frame
  reader, so the comparison is only of order: 1% then, about 10% now.
- By period [S]: 6 of 31 up to 2026-10-25, 4 of 57 after.
- The rule stands in the skill ("No commit, push or release status"), so these
  are deviations under a named prohibition. [S]'s `commit_done` class agrees
  with [J] on only 16 of 20, so no done-statement rate is reported.

## 5. Recommendation

Section 8's first question was what residual would justify a refusing reviewer.
Items 1 to 3 below are the earlier report's reasons 1 to 3, against this data.
Its reason 4, that every mechanism crosses a standing position, was corrected
at its own review into design costs a gate would have to meet. Item 4 comes
from its section on validation in `checkpoint.py`, where the cost was argued for
a mechanical check's false positive.

1. **The rate is no longer an estimate**, so reason 1 is spent. What remains is
   about one frame in four with a done-log on [P], and about two in three with
   a plan or a convention on [S] (61 of 88; plan alone is 58%).
2. **Reader error is still the same size as the rate.** Two readers applying
   one definition differ on 42 versus 26 and 58 versus 11. A gate needs a
   definition first, and these data show the definition is what moves the
   number. Sonnet tracking a stronger reader on 20 versions lowers the concern
   about the tier and leaves that one.
3. **The cost of a miss is bounded only in size**: at most 1000 characters,
   median 683, plus a convention that reaches no approval gate, which the
   earlier report calls the real cost. Conventions are in 23 to 52% of these
   frames by reader, and what a session does with one is not measured (§7).
   The share on the task in hand rose by 17 points over e4 without a gate.
4. **A false refusal still costs a second full payload** at the moment context
   is shortest.

So: no refusing gate now. The levers the data point at are in the template,
which is where the one rule followed 95% of the time lived.

- The "next concrete action" slot admits a chain of steps in one sentence. A
  slot that asks for one action, as "ONE SENTENCE" once asked for one sentence,
  is a wording change the largest class on the stricter reader can test:
  `plans/2026-11-02-frame-template-wording.md` §1 proposes it.
- Commit status is a named prohibition being crossed in about one frame in ten.
  The same proposal's §2 rewords the rule, and the rate can be reread at the
  next re-measurement after any template change.

A wording change is a design decision and is not made here. Should a gate be
wanted anyway, its offline scoring has lost part of its ground truth: the 441
[P] versions survive in the repository, holding no text, and 313 of them
resolve on today's re-join, while the 90 hand-read versions and the 480 commit
verdicts were in scratch and did not survive a reboot.

## 6. Did the content move to the todo?

The earlier report's estimate assumed agents answer a refusal by relocating.
Under the cap, finished work and standing rules did not relocate to `TODO.md`.

| todo file | e4 | since the tag |
|---|---|---|
| versions [M] | 327 | 211 at `TODO.md` |
| median body, characters [M] | 2045 | 1529 |
| the same, the 10 repositories in both | 2202 | 1642 |
| median items [M] | 7 | 6 |
| sample read [S], one per repository-day | 30 files, 307 items | 30 files, 180 items |
| work | 64% | 83% |
| open decisions | 34% | 10% |
| finished work | 0 | 1 item |
| standing rule or convention | 0 | 0 |
| other fact, naming no work | 1% | 5% |
| commit or release status | 0 | 2 items |
| files whose items carry a done-log | 0 | 1 |

- [S] read the 60 files shuffled, with their era hidden. Sentences carrying a
  past-tense completion marker, by regex, are 4% then and 3% now [M].
- [S] may under-call: in the earlier report a stronger reader found a fact or
  caveat item in 7 of 26 e4 files, and here [S] finds one in 3 of 30. Both eras
  share that reader, so the comparison holds better than either level.
- The samples differ in spread: 9 repositories in e4 and 14 now.
- This does not exclude a move to memory, which was not read. Nor does it say
  why open decisions fell; the 2026-09-17 rule dropping unanswered decisions is
  inside e4, so it can explain only part.

## 7. What the data cannot show

- Whether the next session did anything differently because of a frame.
- The plugin version behind any given frame.
- Independence: successive versions of a session remain near-copies, which the
  repository-day row corrects only in part.

## Method and files

Scripts: `plans/2026-10-12-deviation-measurement/frames/` (`collect.py`,
`frames.py`, `join_labels.py`) and the `units.py` splitter and
`labelling-instructions.md` under
`plans/2026-10-11-task-and-todo-move-to-root/reports/overflow/`. The filter and
tallies were run inline; §1's definition reproduces the set.

Data: `/tmp/claude/handoff-measure/frames/`, which holds private text, belongs
in no repository and does not survive a reboot: `remeasure-index.tsv`,
`remeasure-task.txt`, `labels-sonnet.tsv` ([S]), `labels-mine.tsv` ([J]),
`units-remeasure.labels.tsv` ([P]).
