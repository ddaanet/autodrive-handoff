# Proposal: task template wording

2026-11-02. From `plans/reports/2026-11-02-handoff-frame-adherence-remeasure.md`
§5. A proposal: nothing here is applied. All of it is in
`skills/handoff/SKILL.md`, the one skill that writes a task.

## 1. One action in the slot

The slot asks for "the next concrete action", and a frame can answer with a
chain in one sentence. 44 of the 88 frames are a plan to the whole-frame reader
and not to the sentence-level one; 39 of those hold `then`, `once` or `before`
in a unit, against 13 of the 34 frames neither reader flags. So a chain is the
likely shape of that gap, though the word does not establish one and the 44 are
not a count of chains. The rule that sends remaining steps to the todo is
two lines below the slot and does not name that shape.

Now:

```markdown
<The task in hand and where it stands, in-flight threads named in a sentence,
and the next concrete action: what the fresh session does first, not the
topic. Prose. Not a recap.>
```

```markdown
- **Only the task in hand stays here.** Remaining steps and open decisions go
  to the todo. Standing rules and conventions are memory: write them in Step 1.
  Finished work is one sentence at most.
```

Proposed:

```markdown
<The task in hand and where it stands, in-flight threads named in a sentence,
and the ONE action the fresh session does first, not the topic and not what
follows it. Prose. Not a recap.>
```

```markdown
- **Only the task in hand stays here.** Every step after the first action, in
  order, and open decisions go to the todo, a chain of later steps in one
  sentence included. Standing rules and conventions are memory: write them in
  Step 1. Finished work is one sentence at most.
```

The capitals follow the one precedent: a slot that said "ONE SENTENCE" was
followed on 144 of 152 versions.

Cost: the order of remaining steps moves to a file whose items the template
treats as a list and not a sequence, so "in order" has to be said, as above.
The fresh session reads both files, so nothing is lost across the boundary.

## 2. Commit and push status

About one frame in ten states pending commit or push status under the named
prohibition. Most of the cases read as work whose state matters because a person
must act on it, so this names the push form and where the tree shows, and adds
no new home for them. A push awaiting someone's call is left uncovered, because
the todo rule forbids that item.

Now:

```markdown
- **No commit, push or release status** ("the work is uncommitted", "ready to
  commit", "release is a separate request"): the line is false after the next
  commit. If uncommitted work matters, what matters is *why* (tests red,
  decision pending): write that as an open decision in the todo.
```

Proposed:

```markdown
- **No commit, push or release status** ("the work is uncommitted", "nothing
  pushed", "ready to commit", "release is a separate request"): the line is
  false after the next commit, and `gitStatus` at load time shows the tree. If
  it matters, what matters is *why* (tests red, decision pending): write that
  as an open decision in the todo.
```

## What is not changed

`checkpoint.py`, FR13 and the todo template. No version bump on the file shapes,
since neither path nor shape changes; `docs/design/decisions.md` keeps its
"fixed at the template level" position, which this acts on.

## How it is read afterwards

At a later re-measurement, with the two whole-frame classes the 88 give a base
for: plan 58% and pending status 8 to 10 of 88, on a Sonnet reader. A frame
written before the release that carries this stays out of the count.
