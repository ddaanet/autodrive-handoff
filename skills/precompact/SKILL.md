---
name: precompact
description: Commit durable memory and put the open work on disk before a `/compact`, so the compaction has nothing left to lose — and, when asked, carry the compaction out: run `/compact` and submit a continuation prompt into the compacted context. Use when the user asks to "precompact", "prepare compaction", "prepare compact", "before compact", "before I compact", "about to compact", "flush memory before compact", "compact and continue", "compact then continue", "do this after compact", "compact and pick up", or otherwise signals an imminent `/compact`. For an imminent `/clear` or end of task, use the handoff skill.
---

# precompact — Open Work on Disk at the Compact Boundary

Compaction paraphrases the conversation; disk survives it untouched. So:
put what matters on disk before it runs. When the user wants the compaction
carried out rather than prepared, this skill drives it too — the `/compact`
itself, and the prompt that resumes the work on the far side.

## Protocol

### Step 1: Write durable learnings to memory

If durable learnings surfaced this session, write them to auto-memory now.
Skip if nothing durable surfaced — do not force. These writes are the only
tool calls allowed before `handoff-checkpoint`.

### Step 2: Decide, then checkpoint

**Make no tool call between deciding and `handoff-checkpoint`.**

Decide the following from the request and the state of the work. None of
them has a default: considering the question is the whole contribution.

**Is the transition driven?** `compact: true` when the user asked for the
compaction to be carried out — "compact and continue", "compact then
continue" — or the focus directive itself (`compact: "keep the parser
work"`) when one would help the summariser keep the right material.
`compact: false` when they are preparing one they will run themselves —
"precompact", "before I compact". A request that asks for the compaction
**is** the authorization to compact; do not ask whether to proceed.

**Does the session continue after the compaction?** `continue` is `true`
when the user's ask has the compacted session carry on, `false` when it
stops at the compaction. It is `true` only alongside a driven transition.

**Does the ask imply a commit?** Two answers of equal weight:
**`with-commit`** — the request this call serves implies a commit, a test
of interpretation rather than of keywords — and **`without-commit`** — it
does not. The ask stops at the transition: a commit named on the far side
of it is not evidence of `with-commit`.

Then decide the todo content, when open decisions or a task list with
open items are in play. Both lists live in the context the compaction is
about to paraphrase; deciding them now is what spares your post-compaction
self from inferring which are still open — an inference that fails silently
by redoing finished work or re-litigating a settled decision.

```markdown
## Open decisions

- <Unmade choice, phrased as a decision still to make, with the identifiers,
  paths and exact question that must survive verbatim.>

<Drop the section if there are no open decisions. No filler.>

## Remaining

- <Open item, one line, phrased as work still to do.>
```

- **Open items only, in both sections.** A finished item or a resolved decision
  is dropped, never checked off: anything still listed reads as outstanding and
  gets redone.
- **A decision the user has left unanswered across several frames is declined,
  not missed.** Drop it, and never annotate one with the number of times it has
  been raised. Work that can proceed without an answer is listed as work.
- **No commit or push status**, and no item saying "commit the work" or "push
  the branch". A release still owed is an item.
- A `TODO.md` that is already there in another shape keeps its shape: add to it
  and drop from it with `edit`.
- No `#` heading and no extra sections.

There is no task snapshot at this boundary: the summary carries the task,
and the checkpoint removes the task file. Whatever must survive verbatim goes
in the todo file or in the `compact` focus directive.

Then run `handoff-checkpoint` (Bash):

```
handoff-checkpoint <<'JSON'
{
  "skill": "precompact",
  "commit": "<with-commit|without-commit>",
  "compact": <true|false|"focus directive">,
  "continue": <true|false>,
  "todo": <"todo content"|{"action": "clear"}|{"action": "keep"}|{"action": "edit", "old_string": "…", "new_string": "…"}>
}
JSON
```

`todo` is required. A content string replaces the whole file, so it carries
every open item still listed. `{"action": "clear"}` removes the file — it says
every item landed. When the call has nothing to say about the
list, send `{"action": "keep"}`, which leaves it untouched: `keep` is the
default and `clear` is a deliberate stand-down. `{"action": "edit", …}` replaces
one exact occurrence of `old_string` with `new_string`, so an item is added or
dropped without the whole list in context; it needs the file to exist and
`old_string` to appear in it exactly once. `null` is an error, as is
omitting the key, or adding one inside an action object.

### Step 3: Follow what it prints, in order

`handoff-checkpoint` prints what is left to do at this boundary. Carry out
each part in the order printed; each one waits for everything above it, and
whatever you run may print the next part. The checkpoint owns the decision —
do not re-derive or verify it. A non-zero exit names the offending field on
stderr — fix the payload and retry.

The normal case — nothing durable, clean memory, no commit — is one checkpoint
call, and its output is one part, naming the line to end on.

## Anti-patterns

- Running `/compact` directly, or telling the user to run it under a driven
  transition. The request settled both.
- Printing the `/compact` line, or the continuation prompt, as something for
  the user to run. When the drive does not run, the plugin
  prints the lines itself.
- `"continue": true` for a prepared compaction. Nothing submits it, and the
  checkpoint rejects it.
- A `rename` field in the checkpoint payload. A rename is
  `/autodrive-handoff:autoname`'s job when wanted, and the checkpoint rejects it here.
- A `task` field in the checkpoint payload. The summary is the task's
  carrier at this boundary, and the checkpoint rejects the key.
- Forcing a memory write to have something to show. An empty flush is the
  normal case.
- Padding the line the checkpoint tells you to end on into a summary of the
  session. The compaction is about to produce one.
