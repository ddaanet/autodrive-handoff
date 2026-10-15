---
name: handoff
description: Snapshot the in-progress task and still-open decisions before a `/clear` or new session, so the next one resumes where this left off — and, when asked, carry the reset out: name the session, `/clear`, and submit a continuation prompt into the fresh one. A local task frame, not a conversation summary. Use when the user asks to "save handoff", "save context", "prepare handoff", "prepare clear", "write handoff", "before /clear", "before I clear", "clear handoff", "discard handoff", "clean handoff", "finalize", "wrap up", "I'm done", "/handoff", "handoff", "conversation too long", "end", "goodbye", "continue after clear", "continue in a new session", "clear and continue", "pick this up in a new chat", or otherwise signals an imminent `/clear` or end of task. To compact rather than clear, use the precompact skill.
---

# handoff — Task Snapshot at the Clear Boundary

Preserve the irreducible residual across `/clear`: what was in progress
and what's still undecided. When the user wants the reset carried out
rather than prepared, this skill drives it too — the rename, the `/clear`,
and the prompt that resumes the work on the far side.

`handoff-checkpoint` handles the writes and the transition file, and prints
what is left to do after the call — this skill's job is deciding what goes in
them, then following what it prints.

## Protocol

### Step 1: Write durable learnings to memory

If durable learnings surfaced this session, write them to auto-memory now.
Skip if nothing durable surfaced — do not force. These writes are the only
tool calls allowed before `handoff-checkpoint`.

### Step 2: Decide, then checkpoint

**Make no tool call between deciding and `handoff-checkpoint`.**

Decide the following from the request and the state of the work. None of
them has a default: considering the question is the whole contribution.

**Is the transition driven?** `clear: true` when the user asked for the
reset to be carried out — "clear and continue", "continue in a new
session", "pick this up in a new chat". `clear: false` when they are
preparing one they will run themselves — "save handoff", "before I clear",
"wrap up". A request that asks for the clear **is** the authorization to
clear; do not ask whether to proceed.

**Does the session continue after the clear?** `continue` is `true` when
the user's ask has the fresh session carry on, `false` when it stops at the
clear. It is `true` only alongside `clear: true`.

**Does the ask imply a commit?** Two answers of equal weight:

- **`with-commit`** — the request this call serves implies a commit.
  "handoff and commit" does; so do "handoff and amend" and "handoff and
  ci", which contain neither the word nor a substring of it. The test is
  interpretation, not a keyword.
- **`without-commit`** — it does not. What the session learned stands on
  its own.

The ask stops at the transition. A commit named on the far side of it is not
evidence of `with-commit`: no live session owes it.

Then decide the content:

- **Session title** — a concise, specific title (≤ ~50 characters, Title
  Case, no surrounding quotes, no trailing punctuation) for the work done
  this session.
- **Task snapshot** — whether there's an active task whose state is worth
  preserving; if so, draft the content using the template below.
- **Todo content** — whether there are open decisions still to make, or a
  task list with open items in play; if so, draft the todo content using
  the template below (open decisions first, then remaining items).

Then run `handoff-checkpoint` (Bash), piping the whole wrap-up as JSON on
stdin via a heredoc:

```
handoff-checkpoint <<'JSON'
{
  "skill": "handoff",
  "commit": "<with-commit|without-commit>",
  "rename": "<session title>",
  "clear": <true|false>,
  "continue": <true|false>,
  "task": <"task content"|{"action": "clear"}>,
  "todo": <"todo content"|{"action": "clear"}|{"action": "keep"}|{"action": "edit", "old_string": "…", "new_string": "…"}>
}
JSON
```

`task` and `todo` are both required, each carrying content as a string or an
object naming an action. `{"action": "clear"}` removes that file — for
`task`, this is how a boundary with nothing to carry says so; for `todo`, it
says every item landed. When the call has nothing to say about the list, send
`{"action": "keep"}`, which leaves it untouched: a scratch list must survive a
call that is silent about it, so `keep` is the default and `clear` is a
deliberate stand-down.
`{"action": "edit", …}` strikes a finished item without regenerating it.
`keep` and `edit` apply to `todo` only; `edit` needs the file to exist and
`old_string` to appear in it exactly once. `null` is an error on both, as
is omitting a key, or adding one inside an action object.

### Step 3: Follow what it prints, in order

`handoff-checkpoint` prints what is left to do at this boundary. Carry out
each part in the order printed; each one waits for everything above it, and
whatever you run may print the next part. The checkpoint owns the decision —
do not re-derive or verify it. A non-zero exit names the offending field on
stderr — fix the payload and retry.

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
- It is a remainder plus the open questions blocking it, not a plan of
  record — but it is versioned like the task file, so write it as
  something that reads well in history.
- A `TODO.md` that is already there in another shape keeps its shape: add to
  it and strike from it with `edit` rather than rewriting it into this
  template.

## The seam: files vs. continuation

Both files are re-injected verbatim on the far side of the transition, and
they are the only carrier. The continuation is a fixed prompt that points at
them and says nothing of its own, so a fact left out of the files is gone.

- **Task file** — current task state alone: in-flight threads, what needs
  to resume.
- **Todo file** — the open items of an active task list, plus open
  decisions: identifiers, commit ranges, paths a decision hinges on, the
  exact shape of an open question — everything that must survive verbatim
  for a choice still to be made.

## Anti-patterns

- Reading `TASK.md`, `TODO.md`, or any other file "to
  check" before deciding what to write in Step 2. The decision
  comes from the conversation already in context — re-reading duplicates
  what `handoff-checkpoint` does internally, against state that may be
  stale by the time it writes.
- Padding "Current task" to look thorough. Length should track how many
  threads are genuinely in flight, not effort.
- A task list in `## Current task`. Steps go to `TODO.md`; the
  task file says what is in progress, not the checklist to get there.
- A done-log or working conventions in `## Current task`. What landed is in
  `git log`, and how to work is memory.
- Completion state in `TODO.md` — `- [x]` lines, "done:" prefixes,
  a resolved decision left in place, a struck-through item. The file
  holds only what's still open — decisions and remainder alike.
- Durable lessons in `## Open decisions`. Those go to feedback memory.
- Extra sections in either file. Both templates are fixed.
- Asking whether to clear, or telling the user to run `/clear`, under a
  driven transition. Both are settled by the request and the armed file.
- Printing the `/clear` line, or the continuation prompt, as something for
  the user to run. When the drive does not run, the
  plugin prints the lines itself.
- Writing `.claude/autodrive` directly. The checkpoint composes it from
  the payload; a hand-written one is a second writer of the same channel.

## Additional resources

- **`references/design.md`** — design rationale: what the residual is
  and why the agent-authored task file plus read-time assembly split.
