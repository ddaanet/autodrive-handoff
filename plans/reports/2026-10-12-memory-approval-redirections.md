# Memory approval rounds: how often the destination is redirected

Date: 2026-10-12. Scope: every Claude Code session transcript under
`~/.claude/projects/`, 2026-06-22 to 2026-10-12, in the repositories that use
gitlore. Question: how often does my human partner, at the memory approval
round, send a fact somewhere other than where the agent put it, and how many of
those redirections would a reviewer agent holding only the written rules have
made first?

This report carries counts, dates, class labels, round ids and repository
names. The proposals, the replies, the reviewer's verdicts and each round's
session id are in the evidence file, outside the repository (last section).

## Short answer

- 243 approval rounds were found. In 33 of them (14%) my human partner
  redirected a destination. In 14 more (6%) they rejected a fact as not worth a
  memory. 172 (71%) were approved as is.
- The redirections are not spread evenly. 24 of the 33 fall between 2026-09-15
  and 2026-09-30, in the weeks after two sibling skill plugins were first
  committed (2026-09-03 and 2026-09-07). October so far: 2 in 20 rounds.
- A blind reviewer (one Sonnet run, written rules only) reached the same
  destination for 20 of the 46 redirected facts (43%) and flagged 25 of them
  at all (54%). Counted by round, it matched at least one fact in 16 of 33.
- It is good at one move and poor at the others. Fact to skill: 17 of 26 same.
  Fact to the tool, hook or template that owns the behaviour: 0 of 10 same.
- It reproduced almost none of the rejections: "nowhere" for 1 of 24 rejected
  facts, and for none of the 14 rejected rounds.
- False alarms depend on the era. On approvals from September and October, 2 of
  18 sampled rounds were flagged (1 with high confidence). On approvals from
  June to August, 13 of 18.
- Recall is inflated by hindsight in three ways given below. One factor pulls
  the other way: the reviewer could not open the repository.

## How the rounds were found

The anchor is the artefact, not the gate's wording. An approved round ends in a
tool call that writes the approved summary: a `Write` or `Edit` of
`.claude/gitlore-memory-message`, of its earlier name `gitlore-commit-msg`
(inside the submodule gitdir, until 2026-07-16), a Bash redirect into either,
or a `commit-memory.sh -m`/`-F` call carrying the summary. Heredoc bodies are
stripped before matching, so a plan or a checkpoint payload that mentions the
names does not count.

A round starts at a proposal: an assistant message carrying a blockquote, in a
turn where a gate instruction fired (seven wordings, in tool results and hook
output), or whose text matches a later write. It runs to the first successful
write. Every genuine human turn in between is collected: typed prompts,
accepted suggestions, queued prompts, messages absorbed mid-turn, and the text
of a rejected tool call. A proposal with no write after it is kept as an
unfinished round, which is where rejected and withdrawn facts are.

A genuine human turn is a `type:"user"` entry with string content, none of
`isMeta`, `isSidechain`, `isCompactSummary`, an `origin.kind` of `human`, and
no command or notification wrapper.

| Step | Count |
|---|---|
| Main-session transcripts naming an anchor | 504 |
| Excluded, eval and probe projects under `/tmp` | 10 |
| Scanned | 494 |
| Episodes cut (231 reached the write, 25 did not) | 256 |
| Not approval rounds, detector artefacts | 2 |
| Summary written with no human turn before the write | 16 |
| Later proposals split out of a merged episode | +5 |
| Rounds | 243 |

The 243 rounds come from 187 sessions in 17 repositories. 218 reached the
write. 137 were labelled approved-as-is mechanically: one reply, a bare
affirmative, one proposal, no memory edit in between. The other 106 were read
and classified by hand. Missed or ambiguous:

- 11 artefact writes matched no proposal. 4 are test or script noise in the
  gitlore repository. 5 are summaries written with no approval turn. 1 belongs
  to a round split by hand. 1 is a real approved round whose proposal the
  detector did not find (session `99494f13`).
- 4 rounds are ambiguous: three approvals are implicit or sit outside the
  episode window (R025, R068, R250), and the outcome of one deferred
  redirection is not visible (R221).
- 3 rounds have no human reply at all (the session ended).
- A round whose summary was presented in a form the detector does not
  recognise and never written is invisible. No estimate.

One observation outside the question: 21 writes had no human turn between the
summary and the write (the 16 above plus the 5 unmatched). 20 are from July,
one from 2026-10-11.

## Classes

Destination labels: PM project memory, ST shared tier, AL an always-loaded
file (`CLAUDE.md` or the shared conventions file), SK a skill or agent
definition, TOOL the hook, tool, template or code that owns the behaviour, DOC
a design doc, NONE nowhere.

| Class | Meaning | Rounds | Share |
|---|---|---|---|
| A | approved as is | 172 | 71% |
| D | destination redirected, fact moved or removed | 25 | 10% |
| D+ | fact kept, and also sent to an owner | 5 | 2% |
| Dd | redirected, move deferred to a todo | 3 | 1% |
| X | rejected as not worth a memory | 14 | 6% |
| C | content corrected, the fact was wrong | 9 | 4% |
| W | wording edited | 6 | 2% |
| S | split or merged | 1 | 0% |
| O | other: a question, an added fact, a confused store | 5 | 2% |
| N | no human reply | 3 | 1% |

Redirected means D, D+ and Dd together: 33 rounds, 46 facts. Content corrected
is not in the task's list of classes. It is kept apart from wording because
the reply changed what the fact claims.

16 rounds carry a rejection of at least one fact (24 facts): the 14 X rounds
and two D rounds where some facts were moved and others dropped.

Where the 46 redirected facts went: 25 ST→SK, 7 ST→TOOL, 2 each of PM→TOOL,
ST→AL, PM→AL and ST→PM, and 1 each of PM→SK, PM→ST, PM→DOC, ST→DOC, ST→NONE
and AL→TOOL.

Per month:

| Month | Rounds | Redirected | Rejected | Approved as is |
|---|---|---|---|---|
| 2026-06 | 14 | 1 (7%) | 0 | 12 (86%) |
| 2026-07 | 122 | 4 (3%) | 1 | 102 (84%) |
| 2026-08 | 20 | 2 (10%) | 5 | 9 (45%) |
| 2026-09 | 67 | 24 (36%) | 8 | 31 (46%) |
| 2026-10 | 20 | 2 (10%) | 0 | 18 (90%) |

Inside September the split is 1 redirection in 10 rounds through the 15th and
23 in 57 after it.

Per source repository:

| Repository | Rounds | Redirected | Rejected | Approved as is |
|---|---|---|---|---|
| gitlore | 50 | 8 | 2 | 35 |
| micro | 50 | 3 | 0 | 41 |
| handoff | 39 | 2 | 2 | 31 |
| edify | 30 | 7 | 8 | 14 |
| claude-plugin-dev | 12 | 6 | 0 | 6 |
| home | 12 | 1 | 1 | 10 |
| devddaanet | 11 | 0 | 0 | 9 |
| sandbox-lies | 10 | 4 | 0 | 4 |
| Emploi | 8 | 0 | 0 | 7 |
| 8 others | 21 | 2 | 1 | 15 |

The eight others have five rounds or fewer each: general, craft, cwd-safety,
prohibitions, candidature, onekeys, plugin-craft and claude-plugins. They hold
one redirection each in craft and claude-plugins, and one rejection in craft.

## The blind test

**Material.** 84 proposal records: all 33 redirected rounds, the 14 rejected
rounds, the one merged round, and 36 of the 172 approved-as-is rounds, sampled
by month (3, 11, 4, 12, 6 for June to October, seed 20261012), shuffled, with
opaque ids. Each record holds the repository name, which stores existed at the
time, the gate's file list, the first proposal of the round, and excerpts of
the memory edits the session made before it. Re-proposals are excluded because
they already encode the reply. The human replies sat in a separate file the
reviewer was told not to read. The labels were frozen (hash recorded) before
dispatch.

**Reviewer.** One fresh Sonnet subagent, told to judge destination only and to
return "no objection" or, per fact, a destination, the rule it rests on and a
high or low confidence.

**Rules given.** The body of the `gitlore:memory-writing` skill; the opening
section of the shared conventions file; and the tier text. The root
`memory/MEMORY.md` has no header and its history never had one, so the tier
text is the header of the shared tier's own index plus the tier guidance
gitlore injects at session start.

**What the reviewer had beyond that**, unavoidably: the list of skills
installed today, and this repository's `CLAUDE.md`, which imports the whole
shared conventions file and not only its opening. The prompt said it could use
the skill list to name an owner.

**One label changed after dispatch**, before any verdict was read: R180, from
"destination questioned, kept" to D. The reviewer turned out to match it, at
low confidence. Without it: 19 of 45 facts, 15 of 32 rounds.

### Recall

Per fact, which is the unit of what my human partner had to type:

| Human-redirected facts | n | Same destination | Flagged at all |
|---|---|---|---|
| All | 46 | 20 (43%) | 25 (54%) |
| High-confidence verdicts only | 46 | 14 (30%) | 18 (39%) |
| Before 2026-08-28 | 7 | 2 | 5 |
| From 2026-08-28 | 39 | 18 (46%) | 20 (51%) |
| To a skill | 26 | 17 (65%) | 18 |
| To an always-loaded file | 4 | 2 | 2 |
| To a tool, hook or template | 10 | 0 | 3 |
| To project memory, tier, doc, nowhere | 6 | 1 | 2 |

Per round, counting a round as matched when one of its facts is: 16 of 33 same
destination (48%), 21 flagged at all (64%); with high-confidence verdicts only,
13 and 17. By class: D 14 and 18 of 25, D+ 1 and 2 of 5, Dd 1 and 1 of 3. Of
the 26 rounds from 2026-08-28 on, 13 had every redirected fact flagged.

### Rejections

Of the 24 facts my human partner rejected, the reviewer said "nowhere" for 1,
sent 8 to another destination and raised nothing on 15.

By round, it objected to the rejected fact in 5 of the 14 X rounds,
and in none did it say the fact should not exist. It cited the owner question
(§1 Q2) 37 times, the moment question (Q5) 8 times, the reads-as-common-sense
question (Q3) 3 times and the incident question (Q1) never.

### False alarms

Reviewer redirections on rounds my human partner approved as is:

| Month of the round | Sampled | Flagged | Flagged, high confidence |
|---|---|---|---|
| 2026-06 | 3 | 2 | 2 |
| 2026-07 | 11 | 8 | 7 |
| 2026-08 | 4 | 3 | 1 |
| 2026-09 | 12 | 1 | 0 |
| 2026-10 | 6 | 1 | 1 |

These are two populations. 13 of 18 before September, 2 of 18 after. Most of
the early ones send a project-status memory to a design doc under Q2: today's
rule applied to approvals given before the rule was written. They measure how
far the standard moved, not reviewer noise. The figure that bears on building
anything is the later one: 2 of 18, which is 5 or 6 of the 49 approved rounds
of that period if the sample holds. The 95% interval on 2 of 18 runs from
about 3% to 33%.

Inside the other sampled rounds the reviewer also redirected 8 facts my human
partner kept (6 before September, 2 after). For rounds from 2026-08-28 on, the
reviewer's redirections in the sample landed 20 times on a fact my human
partner also redirected, 6 times on one they rejected, 4 times on one they
kept.

### The date split

The rule the reviewer cited was a skill section in all but two verdicts, so
the split is by what was written when the round happened.

| Period | What existed in writing | Rounds | Same | Flagged |
|---|---|---|---|---|
| Before 2026-07-26 | no owner rule anywhere | 5 | 2 | 4 |
| 07-26 to 08-27 | rule facts in the shared tier | 2 | 0 | 1 |
| From 2026-08-28 | the skill, run by the gate | 26 | 14 | 16 |

- The first written owner rule is a shared-tier fact added on 2026-07-26,
  after a correction by my human partner. A tier-routing fact follows on 07-27
  and a memory-writing fact on 07-30, all fetched on recall, not always loaded.
- The skill shipped on 2026-08-28 with questions 1 to 8 and the tier section;
  the hook-or-tool owner and the literal-not-activity test came on 2026-09-02.
  From 2026-08-28 the gate also tells the proposing agent to hold its pending
  changes against that skill before drafting the summary.
- The first redirected round after that is 2026-09-15, so every section cited
  for the third row existed at the time.

The seven early rounds are hindsight by construction: the reviewer applied
rules that the corrections of that period went on to produce. One of its early
verdicts names a skill that did not exist at the round's date.

The third row has its own hindsight. The reviewer read today's skill list. At
least one of its matches rests on wording in a skill description that was
added on 2026-09-25, eight days after the round, by the very brief the
redirection produced (R190). How many of the 17 skill matches lean on later
wording was not checked one by one.

The third row is also not a test of rules against no rules. The proposing
agent had been told to run the same skill, so these 26 rounds are what an
author holding the rules still got wrong. A fresh reader with the same rules
caught about half of that residue.

### The rounds

Brackets give facts matched out of facts redirected.

- **Same destination, 16 rounds.** PM→DOC: R007. PM→SK: R063. PM→AL: R201.
  ST→AL: R180. ST→SK: R185, R187, R190, R192, R208, R213, R215, R219, R243,
  R181 (1 of 2, the other ST→NONE), R189 (3 of 6), R195 (3 of 6, one of them
  ST→AL).
- **Flagged, other destination, 5 rounds.** PM→TOOL: R052. PM→ST: R146.
  ST→TOOL: R156, R183. ST→SK: R178.
- **Missed, 12 rounds.** PM→TOOL: R081. ST→TOOL: R161, R222, R223b, R226,
  R184 (with one ST→DOC). AL→TOOL: R234. ST→PM: R204 (2 facts). PM→AL: R214.
  ST→SK: R194, R221, R237.

R063, R183, R223b, R234 and R237 are class D+; R007, R194 and R221 are Dd; the
rest are D. The rejected rounds are R015, R154, R156b, R162, R168, R169b, R186,
R191, R198, R210, R211, R223, R228 and R230. The evidence file gives each
round's date, repository and session id.

## What the missed redirections had in common

17 redirected rounds were not matched to the same destination: 12 where the
reviewer raised nothing on the fact, 5 where it sent the fact elsewhere. They
sort into what my human partner knew and the three rule sources do not carry.

**That a fix at the source beats a note, and where the source is.** R052,
R081, R161, R184, R222, R223b, R226, R234 and, with a skill as the owner, R237.
The reply names a hook, a template, a tool's own prompt or a plugin that should
change, and the vehicle: a brief dropped in the owning repository's inbox. The
skill does list "a hook or tool that prints the diagnosis" as an owner. It
does not say which tools exist, that my human partner owns them and will fix
them, that a fix is already under way (R081), or that a brief is the route.
The reviewer scored 0 of 10 on this destination.

**Which repositories actually meet a mechanism.** R204 moved two facts down
from the shared tier to one project. The tier section says to name the other
member that will meet the symptom. Only someone who knows the other
repositories can.

**What exists in sibling repositories to carry a rule.** R194, R221 and R214:
an agent definition or a skill elsewhere that should hold the fact, with a
pointer left behind. The reviewer saw skill names and descriptions, not agent
definitions and not skill bodies.

**The same owner question, answered differently.** The five other-place
rounds (R052, counted above, is one). In R156 and R178 both sides sent the
fact out of memory to its owner and differ only on skill against tool. In
R183 my human partner kept the fact and also briefed the owner; the reviewer
said drop it. R146 runs the other way: my human partner promoted a fact to the
shared tier, the reviewer said a skill already owns it, and two months later
(R185, R189) they were moving facts into that same skill themselves.

**Whether a fact is worth keeping at all.** The 14 rejections rest on
questions the skill does ask (is there an incident, would the reader reach it
unaided). The reviewer almost never answered them with "discard". Six replies
in the corpus name the memory-writing rules outright (R162, R164, R168, R169b,
R201, R216), which was enough for the agent in the session to withdraw or
rework the fact. Four of the six are in the sample; the reviewer, holding the
same text, matched one. The rule text alone does not produce the verdict. The
prompt to apply it to a named fact, from someone who already doubts the fact,
does.

## What the data cannot show

- **Redirections outside the approval round.** A destination settled when the
  fact was written, or changed after the commit, is not counted. One was seen
  in the two turns after a write (R131's session) and reversed a turn later.
- **Whether "approved as is" was right.** An approval is not ground truth.
  Facts approved in July were retired or relocated in bulk later, which the
  early false alarms partly anticipate.
- **Variance and agreement.** One reviewer run, one model, one prompt, 18
  approved rounds per era. One reader classified the 106 hand-labelled rounds;
  D+ and Dd are a judgement, and class D alone gives 14 of 25 rounds matched.
- **A reviewer with the repository.** This one saw 520-character excerpts and
  could not open the owner it named. The skill says to grep the owner first. A
  deployed reviewer could, which would move both hits and false alarms.
- **Time saved.** A caught redirection still needs my human partner's consent
  (a brief into another repository is their call), so the saving per catch is
  one correction typed, not one approval round.
- **Whether the September wave recurs.** It followed the arrival of new homes
  for facts, and the corpus has one such event.

## Recommendation

Input to my human partner's decision, not a decision. The arithmetic for the
period a reviewer would have run in (2026-08-28 on, 87 rounds): 26 redirected
rounds carrying 39 facts, 8 rejected rounds, 49 approved. The blind reviewer
would have pre-empted 18 of the 39 redirected facts, fully covered 13 of the 26
rounds, raised a spurious objection on about 1 approved round in 9, and made
none of the 8 rejections. Of those 26 rounds, 24 fall in one fortnight and 2
since.

1. **A general memory reviewer is not worth building on this evidence.** Its
   yield is concentrated in one transient wave and one kind of move, it misses
   the two things that cost the most typing after that move (fix-at-source
   redirections and outright rejections), and its recall is an upper bound.
2. **The cheaper baseline is the step the gate already has.** The proposing
   agent is told to run the memory-writing skill before drafting. What it and
   the blind reviewer both lacked is inventory, not principle: which sibling
   plugins, hooks and agents exist as owners, and that a brief in the owner's
   inbox is a destination. Writing that down where the skill pass reads it is
   aimed at the ten tool-bound facts, which neither reader of the rules caught.
3. **If a reviewer is built anyway, narrow it** to the one question it answers
   well, "does an installed skill own this", with access to the skill bodies,
   and keep its low-confidence verdicts out of the approval prompt. That is the
   16-of-25 case since the skill shipped, at that period's false-alarm rate.
4. **The rejections need a different lever.** They came from my human partner
   asking the existence question of a named fact. A gate that makes the agent
   answer that question in the summary, per new fact, is a smaller change than
   a second agent, and is untested here.

What would change this reading: a second wave of redirections after the next
growth of the skill library, measured the same way; or a rerun of the blind
test with repository access that lifts recall on tool-bound facts above zero.

## Evidence and scripts

Scripts, in `plans/2026-10-12-deviation-measurement/memory/`, moved there from
the scratch directory after this report was written, so the paths inside them
still name it: `rounds.py` (extraction), `worksheet.py` (auto-labelling),
`blind.py` (records, rules, sampling), `compare.py`, `stats.py`, `evidence.py`;
`reviewer-prompt.md`; and the exploration helpers.

Under `/tmp/claude/handoff-measure/memory/`, not in the repository and gone at
the next reboot:

- `evidence.md`: every round with session id, project, date, class, the
  proposal, the human replies and the blind verdict.
- `labels.py`: the hand classification, which `blind.py`, `compare.py` and
  `report_tables.py` import. It is data and stays out: it names memory facts
  and quotes proposal text from sessions in repositories with no public
  remote.
- `blind/` (what the reviewer read), `withheld/` (key and replies),
  `blind-verdicts.jsonl` (its raw output), `comparison.json`, `fact-map.json`
  (four hand joins), `frozen.sha256`.
