The task and todo file templates, their rules, and the seam between the files and the continuation, read by the `handoff` and `precompact` skills before they draft.

## File templates

Neither file takes a `#` heading — the read-time hook prepends one when it
assembles the frame next session. Neither has a location to choose: the
checkpoint writes both in the project root.

**Task file template** (`./TASK.md`):

```markdown
## Current task

<The task in hand and where it stands — what a fresh agent needs in order
to resume it. Prose. Where work spans several concurrent threads, name them
in a sentence. Not a recap.>
```

Task file rules:

- **At most 1000 characters of prose, and no list.** The checkpoint rejects a
  longer body, and any line that opens a list item.
- **Only the task in hand stays here.** Remaining steps and open decisions go
  to `TODO.md`. Standing rules and conventions are memory: write them in
  Step 1, where the user's approval covers them. Finished work is one
  sentence at most; `git log` has the rest.
- No file paths or code beyond what's needed to say what's in progress.
  The working set is reconstructable from `git status` at load time.
- **No commit, push or release status** ("the work is uncommitted", "ready
  to commit", "release is a separate request"). `git status` and `git log`
  have it at load time, and the line is false after the next commit. If
  uncommitted work matters, what matters is *why* (tests red, decision
  pending): write that as an open decision in `TODO.md`.

**Todo file template** (`./TODO.md`):

```markdown
## Open decisions

- <Unmade choice, phrased as a decision still to make, with enough
  context to decide — identifiers, commit ranges, file paths, the exact
  shape of the question, whatever must survive verbatim.>

<Drop the section if there are no open decisions. No filler.>

## Remaining

- <Open item, one line, phrased as work still to do.>
```

Todo file rules:

- **Open items only, in both sections.** A finished item is dropped,
  never checked off, and a resolved decision is dropped too. What
  landed is reconstructable from `git log`; anything still listed reads
  as outstanding and gets redone.
- **A decision the user has left unanswered across several frames is
  declined, not missed.** Drop it, and never annotate one with the number of
  times it has been raised. A listed decision blocks nothing either: work
  that can proceed without the answer is listed as work.
- **No commit or push status here either**, and no item saying "commit the
  work" or "push the branch". A release still owed is an item.
- **A content string replaces the whole file**, so it carries every open
  item still listed. To add or drop an item without the whole list in
  context, use `edit` or `keep`.
- It is a remainder plus the open questions blocking it, not a plan of
  record — but it is versioned like the task file, so write it as
  something that reads well in history.
- A `TODO.md` that is already there in another shape keeps its shape: add to
  it and drop from it with `edit` rather than rewriting it into this
  template.

## The seam: files vs. continuation

At the clear boundary both files are re-injected verbatim on the far side,
and they are the only carrier. The continuation is a fixed prompt that points
at them and says nothing of its own, so a fact left out of the files is gone.
At the compact boundary the checkpoint removes the task file and the summary
carries the task, so in-progress task state stays out of `## Remaining`.

- **Task file** — current task state alone: in-flight threads, what needs
  to resume, and the next concrete action, what the fresh session does first
  (not the topic): the fixed continuation names none.
- **Todo file** — the open items of an active task list, plus open
  decisions: identifiers, commit ranges, paths a decision hinges on, the
  exact shape of an open question — everything that must survive verbatim
  for a choice still to be made.
