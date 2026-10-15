# The mechanical principle is narrowed; a reviewer waits for a measurement

2026-10-15.

## What was believed

The standing decision "Hooks are mechanical; anything requiring judgment is in
a skill" was read as a bar: no hook may judge. Two things rested on that
reading. The rejection of a `PreCompact` hook for the memory flush gave it as
its first ground ("hooks are mechanical and the flush is judgment",
[Session compaction](2026-07-12-session-compaction.md)), and the report on
handoff frame adherence
(`plans/reports/2026-10-12-handoff-frame-adherence.md`, section 7) counted a
prompt-type hook that reviews the checkpoint payload as crossing the decision.

## What the principle is

My human partner's statement of it: a design principle to move mechanical logic
out of skills. Its typical consequence is a skill conditional removed. A script
probes the environment and then produces the agent's instructions, where the
skill would state the condition in prose and leave the agent to evaluate it.
It is not a bar on judgement in a hook, and a standing decision should not
stand in the way of facts.

So the headline now says what the decision does: the deterministic part
(detection, branching, decisions) lives in a script or hook that emits a
structured result or the agent's instructions, and the skill body holds
judgement only. Whether a hook may judge is weighed on the event. Per Claude
Code's hook documentation as read on 2026-10-12 (nothing run), `PreToolUse`
accepts `type: "prompt"` and `type: "agent"` handlers and `SessionStart`
accepts neither. Nothing was read about `PreCompact` handler types, so nothing
is claimed. The old body's other two facts stay, because they still serve the
headline: a probe cannot see the agent's task list, and detection that would
need a transcript scrape is asked of the agent or not at all.

"A `PreCompact` hook cannot run an agent turn" was the old ground for "judgement
only in skills". It moves to the rejected alternative, where it is a fact about
an event and not a consequence of a rule.

## The `PreCompact` rejection

The first ground goes. The factual one stays: `PreCompact(manual)` can annotate
or block a compaction but cannot run an agent turn, and the flush is a
summarize, approve, write sequence that needs one. What else stood is kept:
the flush is a skill run before compacting, and the commit can ride any later
commit because compaction threatens conversation state only. The entry in
[Session compaction](2026-07-12-session-compaction.md) carries a superseding
note scoped to the withdrawn ground, the one edit made to that file. The
decision was recorded in the design hub before the changelog files existed, so
no changelog entry introduced it and none is annotated for that.

## A reviewer agent, rejected for now

Two reports measured whether a reviewer agent would pay for itself, and both
recommended against building one yet. The reasons below are the measurements,
not a standing position: the first-drafted reason that a handoff gate "crosses
the hooks-are-mechanical decision" was withdrawn at review on 2026-10-15 for
the reason above, and the report carries the correction. The design costs a
gate would still have to meet stay costs: a `PreToolUse` deny ends the turn
unless `continueOnBlock` is set, against the single-turn wrap-up, and a
reviewer dispatched by the skill before the checkpoint breaks "deciding makes
no tool call".

- **Handoff task.** The measured rates (a done-log in 36 to 45% of task
  versions, conventions in 35 to 40%) are the rates before FR13, which would
  have refused 34% of the versions of the era it replaces. No frame in the
  sample was demonstrably written under it. The reviewer's own error is
  measured: 20 to 28% disagreement with the hand reading per class, 12% with
  itself. A miss after FR13 is at most 1000 characters per session start.
  Re-measure at 100 task versions written under 0.16.1 or later across at
  least five repositories; the scripts exist. The narrow shape, if a gate is
  then warranted, is a prompt-type `PreToolUse` hook on the
  `handoff-checkpoint` call with `continueOnBlock`, judging `task` alone, on a
  Sonnet-class model, scored offline first. Unverified: timeout behaviour,
  whether the `if` filter parses a heredoc command, any input size limit.
- **Memory destinations**
  (`plans/reports/2026-10-12-memory-approval-redirections.md`). Of the 26
  redirected rounds among the 87 a reviewer would have run in, 24 fall in one
  fortnight. Across all redirected facts the blind reviewer matched fact to
  skill 17 of 26 and fact to tool, hook or template 0 of 10, and it made none
  of the rejections. The cheaper levers are gitlore's (an owner inventory, a
  per-fact existence answer in the approval summary) and went there as a
  brief. A second wave after the skill library next grows, or a rerun with
  repository access that lifts tool-bound recall above zero, would change the
  reading.

The design doc carries both as one rejected alternative; the handoff and
memory reviewers are not merged, since the handoff data gives no reason to.
