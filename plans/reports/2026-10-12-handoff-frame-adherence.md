# Handoff frame adherence

2026-10-12. Input to a decision my human partner has not taken: whether to
add validation to the checkpoint, or a reviewer agent, for handoff text. This
report measures and recommends; it decides nothing.

Legend: **[M]** counted by script, **[H]** hand-verified by reading every
candidate, **[J]** my judgement from reading a sample, **[P]** the Haiku
labelling of 2026-10-11 reused (`plans/2026-10-11-task-and-todo-move-to-root/
reports/overflow/labels.tsv`), **[D]** read in Claude Code's documentation.

## Summary

- The sample is large for a survey and small per cell: 612 task versions and
  437 todo versions the plugin's skills wrote, from 23 repositories, 2026-05-21
  to 2026-10-12. Five repositories hold 71% of the task versions.
- What a regex can decide exactly is close to absent. No todo version has a
  checked box, a `done:` prefix or a struck item (0 of 437). Heading-shape
  faults sit at 1 to 3% each.
- Commit status is the one mechanical class with volume, and a regex cannot
  decide it. The tightest filter I could write fires on 54 of the 629 versions
  of the current-template era and is right on 9.
- The judgement classes are where frames deviate: about four task versions in
  ten carry a done-log and as many carry standing conventions, by two readers
  who agree on 72 to 80% of versions.
- No frame in the sample was demonstrably written under FR13. Every rate here
  describes the rules before it, and FR13 would have refused 34% of the
  versions of the era it replaces.
- Recommendation in one line: no new validation beside FR13, no reviewer yet,
  and one re-run of these scripts once FR13 has produced frames. Section 7
  argues it per class.

## 1. Inventory and sample sizes

Sources [M]. 36 directories under `~/code/` have a `.git`; 25 hold one of the
paths in history or in a working copy. Paths surveyed:
`.claude/handoff-task.md`, `.claude/handoff-todo.md`, `TASK.md`, `TODO.md`, and
`.claude/handoff.md`, the generated artifact retired on 2026-06-05 (31 blobs,
excluded: a script wrote it, not an agent).

| source | task | todo |
|---|---|---|
| commit sides touching the path, all refs | 649 | 593 |
| distinct blobs in history, per repository | 620 | 561 |
| working-copy files found (4 untracked) | 13 | 17 |
| of those, content not in any commit | 8 | 7 |
| distinct versions, history and working copy | 628 | 568 |
| hand-kept `TODO.md`, not the plugin's | 0 | 119 |
| placeholder bodies under 30 characters | 4 | 0 |
| copies of one blob in a second repository | 12 | 12 |
| **plugin-authored versions counted** | **612** | **437** |

- A version is a distinct blob per repository and kind. A blob found in several
  repositories is one version: three frames of `claude-plugin-dev` also sit,
  byte-identical, in seven repositories that vendor its toolkit.
- Plugin-authored means the legacy path, or a root file dated from the move
  that carries a template heading (`TASK.md` as found). The 119 hand-kept
  versions are the root `TODO.md` of `tuick` (73), `candidature` (24) and
  `emojipack` (22): all predate the move or lack `## Remaining`.
- Commit granularity undercounts wrap-ups: a frame rewritten twice between two
  commits is one version, and a session that never committed left none.
  Fifteen versions exist only in a working copy.
- Versions are not independent. They fall on 299 (task) and 206 (todo)
  repository-days, and successive versions of one session are near-copies.
- Task versions per repository: gitlore 191, handoff 91, micro 57, edify 53,
  claude-plugin-dev 41, Emploi 36, candidature 23, devddaanet 22, home 17,
  then fourteen repositories with 13 or fewer.
- Visibility, read from each remote with `gh repo view`: `Emploi` is private.
  `ddaanet`, `devddaanet`, `general`, `home`, `micro`, `super-sdd-cached`,
  `tuick` and `emojipack` have no remote and are treated as private. They hold
  141 task and 71 todo versions; this report carries their counts and nothing
  else.

## 2. The rules and when each came into force

Dated from `git log -p -- skills/handoff/SKILL.md` and the release that first
carried each commit. A rule counts as in force from its release date, since
sibling repositories run the released plugin.

| rule | commit | release | until |
|---|---|---|---|
| fixed template, no `#` heading, no extra section | 04-26 | 0.2.0 | now |
| `## Current task` is one sentence | 04-26 | 0.2.0 | 07-21 |
| no filler under `## Open decisions` | 04-26 | 0.2.0 | now |
| durable lessons go to memory, "not a recap" | 04-26 | 0.2.0 | now |
| no commit or push status in the task | 06-24 | 0.8.3 | now |
| "usually one sentence", threads may be listed | 07-20 | 0.10.0 | 10-11 |
| todo file: open items only, `## Remaining` alone | 07-22 | 0.11.0 | 08-13 |
| no list of steps in the task | 07-22 | 0.11.0 | now |
| no commit status or commit item in the todo | 07-27 | 0.11.4 | now |
| the seam: no facts in the continuation prompt | 07-30 | 0.11.7 | now |
| open decisions move to the todo file | 08-12 | 0.13.0 | now |
| an unanswered decision is dropped, never counted | 09-17 | 0.14.0 | now |
| FR13: 1000 characters, no list at all | 10-11 | 0.16.0 | now |
| done-log and conventions named as anti-patterns | 10-11 | 0.16.0 | now |
| no release status | uncommitted | none | |

Eras used below: **e1** to 06-23, **e2** 06-24 to 07-20, **e3** 07-21 to
08-12, **e4** 08-13 to 10-10, **e5** from 10-11. Two caveats on e5. 0.16.0
was pulled from the marketplace the day it shipped, so siblings kept running
0.15.0: 8 of the 13 e5 task versions are at the legacy path. The other 5 are
`TASK.md` in this repository, where 0.15.0 is the installed version too, so
nothing shows they went through the checkpoint that enforces FR13.

## 3. Mechanical classes

Deviations over versions of the era; a dash means the rule was not in force.

| task file [M] | e1 | e2 | e3 | e4 | e5 |
|---|---|---|---|---|---|
| versions | 93 | 59 | 149 | 298 | 13 |
| more than one sentence | 5 | 3 | - | - | - |
| `#` heading | 0 | 0 | 7 | 5 | 0 |
| `##` section outside the template | 1 | 0 | 8 | 1 | 0 |
| `###` sub-heading | 0 | 0 | 4 | 7 | 0 |
| no `## Current task` | 0 | 0 | 4 | 10 | 2 |
| `## Open decisions` after its move | - | - | - | 19 | 0 |
| list item under `## Current task` | - | - | 15 | 15 | 0 |
| "none" filler, or a commit item | 0 | 0 | 2 | 0 | 0 |
| commit status, pending [H] | - | 2 | 25 | 3 | 6 |
| commit status, done-statement [H] | - | 4 | 22 | 26 | 1 |
| any of the above | 5 | 9 | 45 | 65 | 7 |
| any, done-statements aside | 5 | 5 | 34 | 46 | 7 |

| todo file [M] | e3 | e4 | e5 |
|---|---|---|---|
| versions | 91 | 331 | 15 |
| `- [x]`, `done:` prefix, struck item | 0 | 0 | 0 |
| `#` heading | 0 | 4 | 0 |
| `###` sub-heading | 0 | 4 | 0 |
| extra `##` section, or sections out of order | 0 | 0 | 2 |
| "none" filler under `## Open decisions` | 0 | 3 | 0 |
| "raised N times" on a decision | - | 2 | 0 |
| commit or push item [H] | 1 | 5 | 1 |
| commit status, pending or done [H] | 0 | 7 | 2 |
| any of the above | 1 | 22 | 4 |

- **One sentence held while the template said so.** 144 of 152 versions in e1
  and e2 have a one-sentence `## Current task`. The release that relaxed it to
  "usually one sentence" is followed by a median of 4 sentences (e3, e4), and
  17 of 298 e4 versions keep to one. The same release let `precompact` write
  the file, so the wording is not the only change.
- **Open decisions left in the task**: 16 of the 19 are dated within three days
  of the release that moved them, which is installation lag, not deviation.
  Three remain in eight weeks.
- **The `#` heading** is a `# Task — …` header in the shape the loader
  prepends, 9 of the 12 dated like it: 12 versions in 5 repositories.
- **A list under `## Current task`** is an upper bound: the rule then forbade a
  list of steps and allowed threads to be named.
- **"Raised N times"**: five more versions carry it before the rule, in this
  repository's todo, counting from two sessions to five. That chain is what the
  rule was written for.
- **Pending commit status** is 2 of 59 versions in e2, 25 of 149 in e3, 3 of
  298 in e4 (22 of 67 repository-days, then 3 of 145). I cannot attribute the
  fall. e3 is when `precompact` wrote the task file mid-task, with a dirty
  tree as the normal state; the todo file also took the open decisions at the
  e4 boundary. The six in e5 are two repository-days, five of them one day in
  this repository: "The work is uncommitted in the tree. [...] Release is a
  separate request."
- **Done-statements** ("Steps 1 to 4 are committed", "released and pushed to
  both targets") fall under the rule as written, since `git log` has them, and
  are not falsified by the next commit. I count them apart.

**The commit-status filter cannot be a check [H].** A broad candidate regex
matched 480 distinct sentences. Read one by one: 66 pending status, 13 commit
or push items, 78 done-statements, 29 open decisions about a commit (the form
the skill sanctions), 7 ambiguous, 287 unrelated. A narrow regex (`uncommitted`,
`unpushed`, `not yet committed`, `ready to commit`, `nothing is committed`,
`about to commit` and French forms) matches 102 of them: 47 true, 11 sanctioned
decisions, 44 unrelated or ambiguous, and it misses 32 of the 79 true ones.
Run over the e4 versions it fires on 15 task versions and is right on 2, and on
39 todo versions and is right on 7. The misfires are sentences whose subject is
commits: "merge/push report uncommitted changes", "it diffs `merge-base HEAD
main`, so reviewing work already committed on `main` returns an empty
inventory". They concentrate in gitlore and handoff, the two heaviest users.

**FR13 against the era it replaces [M].** Of the 298 e4 task versions, 96 are
over 1000 characters, 34 hold a list item, 100 fail one or the other (34%).
The five root `TASK.md` versions all pass. Of the 37 e4 versions with a
heading-shape fault, FR13 would already refuse 30.

## 4. Judgement classes

Two readers. [P] labelled every sentence of 441 task versions (A task in hand,
B plan and decisions, C rules and conventions, D already done); I joined its
labels to this inventory by commit and blob, all 441 resolved. [J] is my own
reading of a stratified, seeded sample of 50 task and 40 todo versions, at
most one per repository-day (`sample.py`); the labels and a note per version
are in `my-labels.tsv`.

Wording judged against: "not a recap" and "overflow belongs in memory or git"
from 04-26; "threads, not steps" from 07-22; "a snapshot of what was in
progress, nothing else" from 08-13. The explicit anti-pattern naming a done-log
and working conventions shipped on 10-11, so before e5 these are deviations
from the template's intent, not from a named prohibition.

| task file, e4 | [P] n=296 | [J] n=20 |
|---|---|---|
| done-log: more than one sentence of what finished | 107 (36%) | 9 (45%) |
| standing rules, conventions, dispatch protocol | 118 (40%) | 7 (35%) |
| plan: two or more units of remaining steps | 75 (25%) | 3 (15%) |
| none of the three | 94 (32%) | 6 (30%) |

- Other eras [J]: e1 and e2, 12 of 14 clean, the other two listing to-do items
  as open decisions (there was no todo file). e3, 2 of 10 clean. e5, 1 of 6.
- Spread [P]: a done-log version in 14 of the 16 e4 repositories, a conventions
  version in 12. Not one repository's habit.
- Agreement on the 29 versions both readers saw: 72% on done-log, 79% on
  conventions, 80% on plan, with disagreements in both directions. [P] flagged
  a done-log on 4 of the 16 versions I judged free of one, and conventions on
  5 of 17. A 20-version cell has a 95% interval of roughly plus or minus 20
  points.
- What the conventions are [J]: mostly dispatch and environment rules for an
  orchestrated run ("launch delegates without an Agent `name`", "one test
  process at a time"). Two of the seven e4 cases and one of the three in e5
  cite the memory that already holds the rule: the task restates it.
- **What FR13 would leave [P].** Among the 197 e4 versions that pass FR13 as
  written: done-log 55 (28%), conventions 51 (26%), plan 27 (14%), none 91
  (46%). Among the 99 it refuses: 53%, 68%, 48%, and 3 clean. The cap removes
  the worst and leaves about half the passing frames carrying something, if
  agents answer a refusal by relocating and not by compressing.

| todo file [J] | e3 n=9 | e4 n=26 | e5 n=5 |
|---|---|---|---|
| nothing forbidden | 9 | 16 | 1 |
| an item that is a fact or caveat and names no work | 0 | 7 | 2 |
| memory candidates queued as items | 0 | 3 | 1 |
| a settled or declined decision left in place | 0 | 2 | 1 |
| an "open decision" that is not a choice | 0 | 2 | 0 |
| a finished item | 0 | 1 | 0 |
| a decision under `## Remaining`, or a push item | 0 | 0 | 2 |

- The queued memory candidates have a cause outside the skill: "Queued memory
  writes, all blocked on the index cap above". The memory index was over its
  loader budget, the fact had nowhere to go, and the list kept it as work
  owed. A reviewer would flag it and the agent could not comply.
- "One line" per item is not what is written: 338 of 437 todo versions hold an
  item over 300 characters [M]. The template also asks decisions to carry
  "whatever must survive verbatim", so I do not count length as a deviation.
- The seam's prompt half is invisible here (section 6). Its file half is the
  open decisions left in the task (3 past the lag) and the plan rows above.

## 5. What the history shows about a miss

- **Pending commit status is falsified by its own commit [M].** Of the 57
  committed versions carrying a pending-status sentence, 42 were first
  committed together with other files. That is the 2026-06-24 mechanism, still
  occurring where the class occurs.
- **It is not copied forward [M].** One of the 66 pending-status sentences
  appears in a second version. The stale line lives for one session start.
- **Standing content is hand-carried [M].** 20 of 298 e4 task versions hold a
  sentence unchanged through three or more versions on two or more days.
- **An unanswered decision was re-raised five times** before the 09-17 rule.
- **Nothing in git shows a session acting on a bad frame**: redoing finished
  work, trusting a stale status, obeying a parked convention. The changelog
  records a stale status (2026-06-24) and a stale frame (2026-09-07) loaded
  into a session, each seen live, neither recoverable from frame history.
- **Size is the cost git does show**, and FR13 now bounds it: at most 1000
  characters of task re-injected per session start, whatever they hold.

## 6. What the data cannot show

- Adherence under FR13 and under the two anti-patterns added with it. Zero
  frames.
- The continuation prompt. It lives in `.claude/autodrive` for one turn and in
  session transcripts, neither surveyed. The seam rule is unmeasured.
- Whether a version came from `handoff` or `precompact` (which wrote the task
  file from 07-20 to 10-11), or from a direct edit, which the todo file allows
  all session. Todo versions are not all wrap-ups.
- Which plugin version a session ran. Release dates stand in for it.
- What the next session did with a frame.
- Independence. Rates per version overweight long orchestrated runs; the
  repository-day counts in section 3 are the correction available.
- Language bias. French frames are in every count; no class was checked for
  one.

## 7. Recommendation

### Whether a hook can run an LLM check on the checkpoint call [D]

Yes, per `https://code.claude.com/docs/en/hooks` as fetched on 2026-10-12.
`PreToolUse` is among the events that accept `type: "prompt"` and `type:
"agent"` handlers, and a plugin's `hooks/hooks.json` takes the same schema. A
prompt hook sends its prompt plus the hook input (`$ARGUMENTS`, here the Bash
command, which is the whole heredoc payload) to a model for one turn and reads
back `{"ok": true}` or `{"ok": false, "reason": ...}`. What the same page says
that bears on the design:

- On `PreToolUse`, `ok: false` denies the call and **ends the turn** by
  default. `continueOnBlock: true` returns the reason to the agent as the tool
  error instead.
- Default timeout 30 seconds; default model the one used for background
  functionality; `model` overrides it.
- An `if` filter such as `Bash(handoff-checkpoint *)` narrows the handler, but
  is "best-effort": when the command cannot be parsed the hook runs anyway, so
  the prompt must pass every command that is not a checkpoint call.
- The model is sent the prompt and the hook input; no conversation is named.
- `SessionStart` accepts neither `prompt` nor `agent` handlers, so no LLM
  check can run at load time. Agent hooks are marked experimental.

Not verified, since nothing was run: behaviour on timeout, whether the `if`
filter parses a heredoc command, any size limit on the input.

### Validation in `checkpoint.py`

The position to test was that mechanical checks belong beside FR13. The place
is right and there is nothing to put there.

- **Todo completion state** (`- [x]`, `done:`, struck): 0 of 437. A check
  would catch nothing, and it would refuse a project's own list: 16 of the 119
  hand-kept `TODO.md` versions have a checked box and 118 have a heading
  outside the template. The write path's "written as given" and the rejected
  "protecting a foreign `TODO.md`" already say this file keeps its shape.
- **Heading shape of the task**: a zero-false-positive check, since the task
  is authored whole. It would have refused 7 versions in eight weeks that FR13
  does not already refuse, all of them a missing `## Current task`, which
  loads fine. The non-goal "validating the markdown templates" was reversed
  for FR13 on a measured failure of advice (one character in five described
  the task in hand); 2% of versions does not meet that bar.
- **Commit status**: the one class with a rate worth acting on in its bad
  era, and the one a regex gets wrong five times in six. A false positive is
  a refused wrap-up with no legitimate rewrite available, in the repositories
  that use the plugin most. The standing decision is that this is fixed "at
  the template level", and the data agree with it in direction: the uncommitted
  edit that moves the rule from the anti-patterns into the file rules is that
  lever, and 3 of 298 is the rate it starts from.
- **"Raised N times"**: 2 of 331 since the rule. No check.

What a miss costs here is small and bounded: a stale status line for one
session start, a duplicate header, a section FR13 mostly catches. What a false
positive costs is a second full payload, generated at the main model's output
rate at the moment context is shortest, on top of the refusals FR13 will
already produce for about a third of old-style frames.

### A reviewer for the judgement classes

The position to test was that a judgement check waits for a measured base
rate. The base rate is now measured and it is high: a done-log in 36 to 45% of
task versions, conventions in 35 to 40%. It does not settle the question, for
four reasons.

1. **It is the rate before FR13.** The best estimate of what FR13 leaves is
   26 to 28% per class among frames that already fit, and that assumes
   relocation. The first hundred frames written under 0.16.1 replace the
   estimate with a measurement, at no cost: the scripts exist.
2. **The reviewer's own error is measured too, and it is large.** A Haiku
   reader disagreed with my reading on 20 to 28% of versions per class, and
   with itself on 12% of sentences between runs. On these small cells, a
   blocking check that wrong refuses about one compliant frame in four. Shared
   conventions put a reviewer's floor at Sonnet; no Sonnet reading exists.
3. **The miss it would prevent is, after FR13, at most 1000 characters** of
   redundant text per session start, plus a convention that reaches no
   approval gate. The second is the real cost, and section 4 found some of
   those conventions already in memory.
4. **Every mechanism crosses a standing position.**
   - A prompt hook is judgement in a hook, against "hooks are mechanical;
     anything requiring judgment is in a skill". That decision's stated ground,
     that a hook cannot run an agent turn, no longer holds for `PreToolUse`.
   - Its default deny ends the turn, against "the wrap-up completes in a
     single turn"; `continueOnBlock` is mandatory.
   - A reviewer the skill dispatches before the checkpoint breaks "deciding
     makes no tool call" and NFR3.
   - A note the checkpoint prints after writing lands too late to change the
     file ("a directive is correct only where in the turn it lands").
   - A reviewer that edits the file is a second writer.

So: not now. If the re-measurement shows a residual my human partner judges
worth a gate, the shape the data support is narrow: a prompt hook on the
checkpoint call with `continueOnBlock`, judging the `task` string alone (the
todo's classes are softer and its shape is not the plugin's to police), on a
Sonnet-class model, and scored offline first against the 441 labelled versions
and the 90 read here, so that its false-refusal rate is a number before it can
refuse anything. On keeping the handoff reviewer apart from a memory reviewer:
this data covers the handoff half only and gives no reason to merge them.

The cheaper lever the data point at is the template. The one rule that was
ever followed 95% of the time was a slot that said "ONE SENTENCE".

## 8. Open questions

1. What residual rate, per class, would justify a refusing reviewer? Default:
   none stated; decide after the re-measurement.
2. When to re-measure. Default: at 100 task versions written under 0.16.1 or
   later, across at least five repositories, with the scripts below.
3. Whether session transcripts may be read for the continuation prompt and for
   what the next session did (outside this task's sources). Default: no.
4. Whether done-statements ("is committed") are meant to be covered by the
   commit-status rule. The text covers them; the rationale (falsified by the
   next commit) does not. Default: leave the rule as written.

## Method and files

Scripts: `plans/2026-10-12-deviation-measurement/frames/`, moved there from
the scratch directory after this report was written, so the paths inside them
still name it. Read-only on every repository: `collect.py` (inventory,
streamed), `frames.py` (dedup, authorship, each regex check with its in-force
date), `join_labels.py` ([P]), `sample.py` ([J]), `tally.py` (every number
here), `evidence.py`.

Data: `/tmp/claude/handoff-measure/frames/`, which holds private text, belongs
in no repository and does not survive a reboot: `commit-verdicts.tsv` (the 480
hand verdicts), `my-labels.tsv` ([J]), `tally.out`, and `evidence.md`, which
lists each counted deviation with repository, path, commit, date, class and
excerpt.
