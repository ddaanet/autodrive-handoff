# Task-file length survey

Scope: every committed version of `.claude/handoff-task.md` across all branches
of every git repo directly under `~/code/`. Read-only; scratch data
under `/tmp/claude/survey/` (`collect.py`, `an.py`, `an2.py`, `an3.py`,
`versions.tsv`, `blobs/<repo>_<sha8>.md`). Nothing in any repo was touched.

Legend: **[M]** = measured by script, **[J]** = my judgement from reading blobs,
**[I]** = inferred / extrapolated.

## 0. Coverage [M]

36 directories under `~/code/` have a `.git`. 22 have history for the
path (commits touching it, `git log --all`): handoff 100, gitlore 198, edify 57,
private-B 60, claude-plugin-dev 41, private-A 37, candidature 26, private-C 27,
private-D 20, cwd-safety 12, prohibitions 13, craft 11, sandbox-lies 11,
shell-gotchas 7, pytest-md 7, private-E 5, plugin-craft 5, private-F 5,
private-G 4, claude-plugins 3, gitmoji 2, onekeys 1. No history: the other 14.

652 commits touch the path; after skipping deletions and deduplicating identical
consecutive blobs per repo (ordered by commit time): **597 versions**. Dedup is consecutive-only as specified, so identical blobs on different
branches that are not adjacent in time survive (e.g. sandbox-lies c156a967 and
7c4f8114, both 2298 chars on 2026-09-26): 306 era-3 versions are not 306
distinct contents.

Eras (by commit date) [M]:

| era | window | versions | repos |
|---|---|---|---|
| 1 | < 2026-07-22 (no todo file) | 156 | 15 |
| 2 | 2026-07-22 .. 2026-08-11 (todo exists; task still carries `## Open decisions`) | 135 | 10 |
| 3 | >= 2026-08-12 (current contract) | 306 | 16 |

Era 3 versions per repo (after dedup): gitlore 87, edify 42, handoff 35,
claude-plugin-dev 34, private-A 29, sandbox-lies 11, craft 10, prohibitions 10,
private-B 11, candidature 9, cwd-safety 7, private-C 6, private-D 5,
plugin-craft 4, shell-gotchas 5, onekeys 1. Five repos hold about 73% of the
sample.

The full per-version table (repo, date, sha, bytes, chars, words, lines,
body_lines, list_lines, checkbox_lines, `##` titles, todo-present flag) is in
`/tmp/claude/survey/versions.tsv` (597 rows). `todo` is whether
`handoff-todo.md` existed in the tree at that commit: 0 of 156 in era 1, 80 of
135 in era 2, 301 of 306 in era 3. No version contains a `- [ ]` checkbox (0
across all eras).

Caveats on the sample [M/I]:
- Versions are successive checkpoints, not independent tasks: one session often
  produces 3-8 near-identical versions (e.g. claude-plugin-dev 2026-09-17 has
  five, all 3.7-4.3 kB with lists). The effective number of independent tasks is
  well below 306. **[I]**
- 24 of the 306 era-3 versions still carry an `## Open decisions` heading; 21
  of them are dated 2026-08-12..14 (the transition days) and the other three
  are single versions on 2026-08-26, 08-27 and 08-28. I base the numbers on the **282 versions without
  it**, from 15 repos, and show all 306 for comparison.
- Two versions are 18 and 20 characters (handoff 51e2b083 2026-08-14,
  prohibitions 397b5978 2026-08-26): test or placeholder strings, harmless to
  the statistics.
- "chars" counts the whole file; "body" excludes ATX heading lines. The
  difference is 13 to 150 characters (an old `# Task — <date>` H1 plus the
  `## Current task` line). A limit applied to the `task` payload should say
  which it counts; the numbers below differ by ~15 chars either way.

## 1. Size distribution in the current-contract era [M]

Era 3, versions without `## Open decisions` (**n = 282, 15 repos**):

| unit | min | median | p75 | p90 | p95 | max |
|---|---|---|---|---|---|---|
| characters (whole file) | 18 | 730 | 1077 | 1771 | 2637 | 4573 |
| characters (body, no headings) | 18 | 713 | 1060 | 1754 | 2620 | 4448 |
| words (whole file) | 3 | 103 | 157 | 269 | 332 | 594 |
| non-blank body lines | 1 | 2 | 5 | 13 | 17 | 57 |

All 306 era-3 versions (16 repos): chars 18 / 750 / 1207 / 1908 / 2848 / 4573;
words 3 / 106 / 169 / 294 / 406 / 594; body lines 1 / 2 / 6 / 15 / 26 / 57.

Context, whole file, earlier eras:

| era | n | chars min/med/p75/p90/p95/max | words med/p90 | body lines med/p90 |
|---|---|---|---|---|
| 1 | 156 | 133 / 661 / 905 / 1214 / 1542 / 3039 | 99 / 173 | 3 / 11 |
| 2 | 135 | 284 / 1579 / 2242 / 3175 / 4182 / 6907 | 229 / 475 | 18 / 43 |

Restricting to the `## Current task` section alone (so that the Open decisions
lists of eras 1-2 do not count): era 1 median 238 chars (p90 366, max 1483),
era 2 median 660 (p90 1722, max 4645), era 3 median 714 (p90 1764, max 4534).
So the task section grew about 3x between era 1 and era 2 and has been flat
since; the growth is not mainly bullet lists (see section 5).

Per-repo medians of era-3 chars (clean set): private-D 297, prohibitions 426,
shell-gotchas 528, handoff 535, craft 549, private-C 574, private-B 686, gitlore
696, plugin-craft 714, cwd-safety 708, candidature 731, claude-plugin-dev 839,
edify 865, sandbox-lies 932, private-A 1442. By month (medians): Aug 590,
Sep 747, Oct 729. The tail (>1500 chars) is concentrated: private-A 11 of its
28 versions, gitlore 11, claude-plugin-dev 6, edify 3, handoff 3,
sandbox-lies 3, private-B 1.

Sample sufficiency: 282 versions from 15 repos supports distribution
statements. It does not support per-repo claims for the small repos, and the
tail (above ~2000 chars, 22 versions) is dominated by a handful of long
orchestration sessions. **[I]**

## 2. Classification: description only vs list content [M + J]

### 2a. First cut, measured

Markdown list-item lines (`-`, `*`, `+`, `1.`, `1)`; no checkboxes occur) in the
282 clean era-3 versions: **15 versions have any, and every one of those has
>= 3** (none has 1 or 2). Adding "has an `###` sub-heading" gives 16 "structural"
versions (the extra one, edify 5f4487bf, 1446 chars, has an `###` and no
list items). Smallest structural version: **1342 chars** (plugin-craft
fd263230, 3 list lines). 266 of 282 (94%) have no list items and no `###`.

Era 1 to 3 contrast (list-item lines inside the `## Current task` section only):
era 1: 2 of 156 versions have any (1 has >= 3); era 2: 14 of 135 (11 with >= 3);
era 3: 17 of 306 (17 with >= 3, 15 of them in the clean set). Markdown lists in
the task section were already rare before the todo file existed.

### 2b. Judgement, 15 blobs read (the largest and borderline cases, not a random sample)

| blob (repo, date, chars) | markdown lists | what it holds | judged class |
|---|---|---|---|
| claude-plugin-dev df2c4c05, 2026-09-17, 4302 | 8 + 5 `###` | "Phase 1, as landed" item list, dispatch protocol, lessons | carries list/ledger content |
| edify fb542dc2, 2026-09-17, 4573 | 6 + 4 `###` | commits landed, what items did, `### Next step` with 3 numbered review groups | carries (steps + done-log) |
| handoff a8abf8b6, 2026-09-19, 4303 | 9 | done/in-flight/`Next:` chain of ~10 dispatches, conventions, deviations | carries (steps + conventions) |
| gitlore ae54c1b9, 2026-09-10, 3642 | 0 | prose "Phase 4 remainder: Item 1.3 slice 2, then 4.1+4.2 ..., then 4.3", dispatch shape | carries steps in prose |
| gitlore 914fec13, 2026-09-14, 3445 | 10 | defect analysis, "design to produce" 1-3 | carries (a spec/step list) |
| private-A 25a137c3, 2026-09-19, 3062 | 0 | ordered queue of 3 work items, plus a long standing working-method block | carries queue + standing conventions, as one paragraph |
| private-A a0a9b4f7, 2655 | 0 | same, 4 queued work items | same |
| edify 06a431ec, 2026-09-01, 2853 | 0 | 8 committed commit-ids, "Task 8 in progress" sweep leftovers, "Still to run" | carries steps + done-log in prose |
| edify b5b1b30c, 2026-09-27, 2736 | 3 | "Verdicts so far" per proof item | carries a decision log |
| sandbox-lies 7c4f8114, 2026-09-26, 2298 | 0 | orchestration protocol, "standing decisions carried into every brief" | mostly standing conventions; mild |
| claude-plugin-dev 0b7ef2e2, 2026-09-30, 1449 | 6 | one short state paragraph with Next, plus "Conventions this run settled" bullets | carries conventions as a list; no remaining-step list |
| private-A 3ef9c9c0, 1704 | 0 | one work item's state plus a paragraph following other threads | borderline; mostly state, legitimately multi-thread |
| gitlore a61e788d, 2026-09-08, 1793 | 0 | orchestration state, two decided deviations, model rules | borderline-legitimate prose; no steps |
| edify 926e372d, 1071 | 0 | merge complete, next thread named in one paragraph, 2 loose ends | task description only |
| gitlore 4c10e5e4, 1028 | 0 | memory review in progress, 3 short paragraphs | task description only |

Tally of the 15: 11 carry list/step/ledger content, 2 borderline-legitimate
(1704 and 1793 chars), 2 description only (1028 and 1071 chars). Selection
bias: I chose the largest and the 1000-1800 band, so these proportions say
nothing about the whole population. **[J]**

Representative excerpts.

Carries list content (edify fb542dc2):

    ### Next step
    §5 review gate per `plugin/skills/build/references/finishing.md`. Three groups ...
    1. **Skill definitions** -> `plugin-dev:skill-reviewer`, ...
    2. **Agent definitions** -> `edify:corrector`, ...

Carries list content in prose with zero list syntax (gitlore ae54c1b9):

    Phase 4 remainder: Item 1.3 slice 2, then Items 4.1 + 4.2 in **one commit** (...), then 4.3.

Carries list content (claude-plugin-dev 0b7ef2e2):

    Conventions this run settled on:
    - Dispatches leave the Agent `name` unset ...
    - A transient `.git/index.lock` failure has hit twice. ...

Task description only (gitlore 4c10e5e4):

    Reviewing all 100 `memory/ddaanet/` facts against the `memory-writing` rubric,
    ordered by index-line size largest first, one memory at a time with my human
    partner validating each verdict before the next. ...
    Edits to the memory files themselves stay deliberately deferred to the end of
    the pass, so the index and the frontmatter descriptions are rewritten once ...

Task description only (edify 926e372d):

    The /inline + /orchestrate -> /build merge is complete against `plans/build-skill/outline.md`: ...
    Next thread is the /design skill work in the todo, starting with removing its direct-execution path. ...

### 2c. What separates the classes

- Description-only versions sit at about 300-1100 chars, 1-3 paragraphs, no
  list syntax. The legitimate long cases I read top out around 1700-1800 chars.
- List/step/ledger-carrying versions appear from about 1340-1450 chars and are
  nearly all >= 2200 chars. In the reads, the signature is a section after the
  opening paragraph that enumerates done items, next steps, conventions or
  verdicts ("Done and committed", "In flight", "Next", "Conventions this run
  settled", "Verdicts so far", "### Next step").
- The markdown list count is a poor detector of the second class: of the 11
  judged carriers, 5 had zero list lines (they carry steps as prose or as
  semicolon-chained queues). Line count is also unreliable: gitlore hard-wraps
  at 80 columns (a 1028-char prose file has 15 lines), private-A writes one
  2000-3000 char line.
- A keyword proxy (`next|remaining|conventions|in flight|...`) matched 156 of
  282 versions, including most short ones; useless as a classifier.

## 3. Recommended length limit

Unit: **characters**. Reasons **[M/I]**:
- Words track characters closely (about 7 chars per word in this data;
  1500 chars is roughly 215 words), so they add nothing.
- Lines are the worst unit: they depend on the author's wrapping (see above).
  A 15-line cap would reject wrapped legitimate prose and pass a single
  3000-char paragraph.
- Characters alone separates the structural class cleanly at the low end
  (smallest list-bearing file 1342 chars) and counts the prose-carried queues
  that no line or list rule sees.

Value: **1500 characters** of task body (counting the `## Current task` heading
or not moves each count by under 15 characters).

Measured rejections on the 282 clean era-3 versions. "Structural" = the 16
versions with >= 3 list lines or an `###`; "other" = the remaining 266. The
second column of the judged counts is from the 15 blobs only (**[J]**, biased
sample):

| limit (chars) | would reject | of which structural (of 16) | structural let through | other rejected | judged in 15 reads: carriers caught (of 11) | judged legit/borderline rejected (of 4) |
|---|---|---|---|---|---|---|
| 1200 (tighter) | 62 (22%) | 16 | 0 | 46 | 11 of 11 (a 1449 carrier now caught) | 2 of 4 (1704, 1793) |
| **1500 (recommended)** | 38 (13.5%) | 13 | 3 (1342, 1446, 1449) | 25 | 10 of 11 | 2 of 4 (1704, 1793, both borderline) |
| 2000 (looser) | 22 (7.8%) | 12 | 4 (adds 1912) | 10 | 10 of 11 | 0 of 4 |

Also measured at other values: >1000 rejects 84; >2500 rejects 15; >3000
rejects 11 (8 structural). In words: >200 rejects 46 (14 structural, 2
structural pass), >250 rejects 31 (13), >300 rejects 20 (12); in non-blank body
lines: >8 rejects 48 (10 structural, 6 pass), >15 rejects 17 (5 structural, 11
pass).

How to read the "other rejected" column. Those 25 (at 1500) are versions with
no markdown list that exceed the limit: by repo, private-A 11, gitlore 7,
handoff 2, sandbox-lies 3, private-B 1, edify 1. I read 7 of them (see the
table above); 5 carry steps or a standing-conventions block in prose, 2 are
borderline legitimate. Extrapolating that 2:5 split would put roughly 7 of the
25 as false rejections of acceptable descriptions, i.e. about 2.5% of all clean
versions, but that is an extrapolation from 7 hand-read, size-selected blobs,
**[I]**, and I did not read the other 18. The 1200 limit adds 24 more
rejections of versions in the 1200-1500 band that I have not read except for
the 1449 carrier.

Why 1500 and not a neighbour: there is no gap in the distribution, so the
choice is a tradeoff, not a threshold the data dictates. 1500 sits above the
p75 (1077) with margin, below the p90 (1771), above every legitimate
description I read except two borderline ones, and below all but three of the
structural list versions. Choose 1200 if letting any list through is the worse
error (it catches all 16 structural versions but rejects about 1 in 5
historical files); choose 2000 if false rejections are the worse error (rejects
about 1 in 13, and lets 4 of 16 list-bearing versions through, plus anything
carried as prose below 2000).

## 4. Structural rule vs length rule [M, with J on the 15 reads]

Rule "no list items and no `###` in the task file": rejects 16 of 282 (15 list
lines + 1 `###`). The smallest rejected version is 1342 chars; none under
1200. It lets through every prose-carried queue.

| rule | rejects | structural rejected | judged carriers caught (of 11) | judged legit/borderline rejected (of 4) |
|---|---|---|---|---|
| no list items, no `###` | 16 (5.7%) | 16 of 16 | 6 of 11 (5 carriers have zero list lines) | 0 of 4 |
| <= 1500 chars | 38 (13.5%) | 13 of 16 | 10 of 11 | 2 of 4 |
| both (reject if either) | 41 (14.5%) | 16 of 16 | 11 of 11 | 2 of 4 |
| paragraphs > 3 | 33 (11.7%) | 12 | not computed | not computed |

(The "structural" column is circular for the structural rule by construction;
only the judged columns are independent evidence, and they rest on 15 blobs.)

Observations:
- The structural rule has no false rejections among versions I read, but
  catches only 6 of 11 judged carriers. In the private-A files and in
  gitlore ae54c1b9 / edify 06a431ec the "list" is a prose paragraph or a
  semicolon-chained queue, which no syntax rule sees.
- The length rule catches those, at the cost of two borderline-legitimate
  files and a policy that must live with an arbitrary number.
- The union (length >= 1500 or any list syntax) adds 3 catches over the length
  rule alone (1342, 1446, 1449 chars) for no measured false rejection, since
  no list-bearing version in the clean set is shorter than 1342 chars. The
  one list-bearing version I judged as not a step list (0b7ef2e2: "Conventions
  this run settled" bullets, 1449 chars) would be rejected by the structural
  half; it still carries a list that does not belong in a one-sentence-to-
  few-paragraph pointer.
- Paragraph count is a weaker separator: >2 paragraphs rejects 68 including 54
  non-structural versions of 554+ chars.
- This data is consistent with the length cap as the primary rule, with a
  list-syntax rule as an optional second rule giving three more catches; it
  does not show the structural rule to be better on its own.

## 5. Findings that contradict or qualify the premise [M / J]

1. **Markdown lists in the task file were rare in the first place.** In the
   current contract 15 of 282 versions (5%) contain any list item; in era 1
   (no todo file) the `## Current task` section had a median of 238 chars and
   only 2 of 156 versions had a list item in it (era 1's lists lived in
   `## Open decisions`, which was a separate section of the same file). The
   premise holds for a few long orchestration sessions, not for the typical
   file.
2. **The problem is mostly prose, not bullets.** Of the 11 judged carriers, 5
   used no list syntax: steps appear as "Phase 4 remainder: ... then ...",
   "Next: A -> B -> C", or semicolon-joined ordered queues. A limit has to
   count length for this, not list items.
3. **Long legitimate prose exists and is a repo style.** private-A's task
   file is one 1000-3000 char paragraph per version (median 1442; 11 of its 28
   versions exceed 1500). It mixes state, an ordered queue of work items and a
   long standing working-method block. Part of that is standing conventions,
   which belong neither in the todo file nor really in a task pointer. A 1500
   cap would reject 11 of 28 private-A versions (39%); a 2000 cap, 5 of 28
   (versions of 2138 to 3152). Whether those are "legitimate" is a judgement:
   they are not step lists but they are not a one-sentence pointer either.
   Excluding private-A, a 1500 cap rejects 27 of 254 clean versions (11%), 13
   of them structural.
4. **Most overlong files are orchestration frames**, i.e. `/orchestrate` or
   `/build` runs: "done and committed", "in flight", dispatch conventions,
   deviations. They carry standing conventions and a done-log as much as a
   todo list. Moving content to `handoff-todo.md` would be right only for the
   remaining steps; the conventions and done-log would have no home (the
   todo file template is open items only). A hard length cap will therefore
   force an agent to drop or relocate material the plugin currently has no
   slot for. **[I]**
5. **The current template already says "Usually one sentence ... Threads, not
   steps"** (`skills/handoff/SKILL.md`, task template). Observed median is 730
   chars and p90 1771; the guidance is not being followed as written even in
   the median case, so a limit as tight as one sentence would reject most of
   them: chars >500 rejects 211 of 282 (75%), >600 rejects 172 (61%). A one-sentence reading is not supported by how
   the file is used.
6. **Same-day churn inflates the tail.** Six of the 22 clean versions above
   2000 chars come from two sessions on 2026-09-17 (claude-plugin-dev: five
   successive versions of 3.7-4.3 kB; edify: one of 4.6 kB). Distinct long tasks
   in the sample are fewer than the version count suggests. **[M for the dates, I
   for the conclusion]**
7. Era boundary caveat: the first days after 2026-08-12 still show `Open
   decisions` in the task file (21 versions), i.e. the contract change took
   2-3 days to land in consumers. The late stragglers (2026-08-26/27/28, 3
   versions) may be sessions on an un-upgraded plugin install **[I]**. Excluded from the main
   statistics.
8. The distribution is very repo-dependent (medians from 297 chars in private-D
   to 1442 in private-A), so any one limit binds unevenly across repos.

## 6. Summary of the recommendation

- Measured: era-3 median 730 chars, p90 1771, p95 2637 (n=282, 15 repos). No
  version with markdown list items is shorter than 1342 chars. All 15
  list-bearing versions are in orchestration-style long frames.
- Recommended: cap the task body at **1500 characters**; it rejects 13.5% of
  historical versions, 13 of 16 structurally list-bearing ones, and (judged on
  7 hand-read non-list versions) probably includes a minority of
  borderline-legitimate long state descriptions.
- Alternatives: 1200 (catches all 16 structural, rejects 22%); 2000 (rejects
  7.8%, lets 4 of 16 through, 0 judged false rejections in the read sample).
- A list-syntax rule alone misses the prose-carried queues; as a complement to
  the length cap it adds three catches at no measured cost.
- Not decided by the data: where standing conventions and done-logs go when the
  cap bites (the todo template has no place for them).

## 7. Recomputation over everything since the todo file existed [M]

Added at promotion (2026-10-11), because the scratch data under
`/tmp/claude/survey` will not survive. Sample: every version dated
>= 2026-07-22 (eras 2 and 3), 441 versions. Body is the content minus ATX
heading lines, stripped; a list item is a line matching
`^\s*([-*+]|\d+[.)])\s`, the rule the plan's `validate_task_shape` uses.

| sample | versions | median chars | p90 chars | > 1500 chars | list item or > 1500 |
|---|---|---|---|---|---|
| all since 07-22 | 441 | 872 | 2529 | 117 (26.5%) | 189 (42.9%) |
| era 2 (07-22..08-11, task still held `## Open decisions`) | 135 | 1543 | 3139 | 68 (50.4%) | 126 (93.3%) |
| era 3 without `## Open decisions` (section 1's sample) | 282 | 712 | 1753 | 37 (13.1%) | 39 (13.8%) |

In the all-since-07-22 sample, 163 versions (37.0%) carry a list item, 72 of
them at or under 1500 characters (what the list rule catches beyond the cap).

The figures the plan quotes (median 716, p90 1754, 14.5% rejected) are section
1's and section 4's: the 282 current-contract versions, not the 441. Era 2 is
the era before the todo file took the step lists, which is why it fails the
rule nearly every time; the cap's target is era 3's behaviour, and the 13-14%
rejection there is the cost of the rule once the todo file exists.
