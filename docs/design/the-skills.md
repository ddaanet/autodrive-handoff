# The skills

Part of [handoff — Design](../design.md).

The dated records named here are in the `changelog-archive` tag's
`docs/changelog/`.

One skill per boundary, plus the rename:

| boundary | skill | transition field |
|---|---|---|
| compaction | `/autodrive-handoff:precompact` | `compact`: `false` \| `true` \| `"<directive>"` |
| clear | `/autodrive-handoff:handoff` | `clear`: `false` \| `true` |

The two differ in one content field. `handoff` carries a `task`, because a
`/clear` leaves nothing else to say what was in hand. `precompact` takes none
and removes the task file, because the compaction's summary says it
([The compact boundary carries no task](decisions.md)). Both carry `todo`.

The templates of the two files, their rules and the seam between what the
files carry and the continuation are inline in `skills/handoff/SKILL.md`.
`skills/precompact/SKILL.md` repeats the todo template and the todo rules it
needs, so neither skill reads anything to draft; an edit to the todo template
or rules changes both. Memory writes are the only tool calls ahead of the
checkpoint
([Between deciding and the checkpoint, no tool call](decisions.md)).

There is no restart skill: Claude Code's own `/restart` relaunches with
`--resume`, which carries the conversation over whole, so there is no
boundary for this plugin to cross and no frame to carry.

`/autodrive-handoff:pending` has no design surface at all: it reports
the `## Open decisions` and `## Remaining` sections of the
frame already injected into context, making no tool call and writing no file.
It appears nowhere else in the design because there is nothing else to say
about it.

The judgment is per-boundary, not per-drive-mode: commit awareness, memory
capture, the drafting rules and the seam between the files and the
continuation are identical whether or not the plugin runs the command afterwards. So whether
the transition is driven (the code's `typed`) is a **field of the payload**, decided the way
`commit` already is — one fact the agent supplies, everything downstream
deterministic — rather than a skill of its own.

A separate driven skill per boundary was the earlier shape, and it cost
routing (six trigger phrases each, every one naming the sibling it was not,
so "compact and continue" reaching `precompact` produced a prepared
compaction nobody ran), duplication (the arming discipline and the sentinel's
line shapes stated twice in prose), and expressiveness: driving a transition
*without* a continuation prompt was unreachable, because the driven skills
treated the prompt as intrinsic. The fields cover the cross product:

```
handoff     clear:false          continue:false  prepare only
handoff     clear:true           continue:false  clear, then stop
handoff     clear:true           continue:true   clear and continue
precompact  compact:false        continue:false  prepare only
precompact  compact:true|"…"     continue:false  compact, then stop
precompact  compact:true|"…"     continue:true   compact and continue
```

`continue` is a boolean, and `true` is a schema error against a transition that
is not carried out, since nothing would submit the prompt, and at the clear
boundary also when neither file would have a body once the plans are applied
(checked before any write, the legacy fallback counted; after a compaction the
summary carries the task, so `precompact` is exempt). The prompt it asks
for is one fixed line, `CONTINUATION` in `checkpoint.py`, that points the fresh
context at the task and todo files. It was once a line of prose the agent
wrote, and the agent used it to carry the task: a description of the next step,
or the facts it hinged on, that no file held and that the next `/clear` lost.
With the line fixed, `TASK.md` and `TODO.md` are the only carrier at a clear
(at a compact the summary and the focus directive carry too), and the
skills ask one yes-or-no question of the user's request where they once asked
for a sentence.
2026-10-15 The continuation is a constant

The transition field is named after the command it runs, and its value is
that command's argument: `/clear` takes none, so it is a bool; `/compact`
takes an optional focus directive, so it is a bool or the directive itself.
`false` does not mean "no sentinel" — it means the command is not run.

What the separate skills bought, and what this gives up, is that the
transition was settled by *which name the description matched* rather than
by reading the request: a misread now drives a transition where only
preparation was asked for. The fields are required and have no default, so
the question is at least always asked; and the prepare-only wording is the
larger half of both descriptions, since that is the reading a bare
"handoff" or "precompact" should get.

- **`/autodrive-handoff:autoname`** — rename only, neither boundary. Decides a title
  and calls the checkpoint with `{"skill": "autoname", "rename": …}`, the
  whole payload. Every other field is a schema error under it, and no
  directive is composed — its description promises no memory write, and a
  memory directive is an instruction to make one. For `/btw` side
  conversations and any session worth a name while the main thread stays
  live. It is a skill rather than a mod command because the host refuses a
  command run from inside a command handler: the rename would land one
  ordinary turn late, and never under `-p`. The checkpoint call composes a
  `rename` sentinel and the mod runs it when the turn ends, like any other
  kind ([Driving the transition](driving-the-transition.md)).

## Rejected alternatives

**A reviewer agent for the handoff task, or for memory destinations, for now**
— rejected on measurements; the memory reading reopens on a number, and the
handoff reading has none set. For the handoff frame, the re-measurement
(`plans/reports/2026-11-02-handoff-frame-adherence-remeasure.md`, 88 task
versions at `TASK.md` since the `v0.16.1` tag) finds FR13 at zero faults and a
residual of done-logs in 26 to 42% of versions and plans in 11 to 58%, depending
on the reader; the content did not move to `TODO.md`. The gap between the
readers, which comes with the definition and the unit judged, is the size of the
rate: a Haiku sentence reader and a Sonnet whole-frame reader agree on 47 to 80%
of versions per class. Sonnet and a hand reading agree on 85 to 95% of 20
versions, about plus or minus 15 points, a first sign that Sonnet tracks a
stronger reader and not a measured error rate. After FR13 a miss is at most 1000 characters of redundant text per
session start, plus a convention that reaches no approval gate; the history
shows no session acting on a bad frame. The report recommends no refusing
gate and names no further threshold. Should a gate be wanted, the shape the data support
is narrow: a prompt-type `PreToolUse` hook on the `handoff-checkpoint` call
with `continueOnBlock` (the default deny ends the turn, against the
single-turn wrap-up), judging `task` alone, on a Sonnet-class model, scored
offline first (313 of the 441 labelled versions resolve today) so its
false-refusal rate is a number before it can refuse anything. Not verified: timeout behaviour, whether
the `if` filter parses a heredoc command, any limit on the input size.

For memory destinations, a blind reviewer's yield was concentrated in one
transient wave and one kind of move. Of the 26 redirected rounds in the 87
rounds it would have run in (from 2026-08-28), 24 fall in one fortnight of
September, after two sibling skill plugins arrived. Across all redirected
facts, fact to skill matched 17 of 26 and fact to the tool, hook or template
that owns the behaviour 0 of 10. It reproduced almost none of the rejections
("nowhere" for 1 of 24 rejected facts, none of the 14 rejected rounds) and
raised a spurious objection on about 1 approved round in 9.
The levers belong to gitlore and were sent there as a brief: an inventory of
the owners a fact can go to, and a per-fact existence answer in the approval
summary. The reading changes with a second wave of redirections after the next
growth of the skill library, measured the same way, or a rerun of the blind
test with repository access that lifts recall on tool-bound facts above zero.
2026-10-15 The mechanical principle is narrowed; a reviewer waits for a measurement
