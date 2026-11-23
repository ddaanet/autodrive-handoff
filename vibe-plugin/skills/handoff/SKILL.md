---
name: handoff
description: 'Snapshot the in-progress task and still-open decisions before a `/clear` or new session, so the next one resumes where this left off — the fresh session reads TASK.md and TODO.md before its first reply. Use when the user asks to "save handoff", "save context", "prepare handoff", "prepare clear", "write handoff", "before /clear", "before I clear", "finalize", "wrap up", "I''m done", "/handoff", "handoff", "conversation too long", "continue after clear", "continue in a new session", "clear and continue", "pick this up in a new chat", or otherwise signals an imminent `/clear` or end of task. To compact rather than clear, use the precompact skill.'
---

# handoff — Task Snapshot at the Clear Boundary

Preserve the irreducible residual across `/clear`: what was in progress and
what's still undecided. The fresh session opens on the two files through the
AGENTS.md loader line — they are the only carrier, and a fact left out of
them is gone.

`checkpoint.py` does the writes and prints what is left to do. This skill
decides what goes in them, then follows what it prints. Nothing under Vibe
runs a `/clear` for you: when the user asked for the reset, this skill
prepares it and its closing line names the command back to the user.

## Protocol

### Step 1: Write durable learnings to memory

If durable learnings surfaced this session, write them to memory now — under
Vibe memory is gitlore (its `gitlore:memory-writing` flow); when no store is
mounted, skip silently. Skip if nothing durable surfaced — do not force.
These writes are the only tool calls allowed before `checkpoint.py`.

### Step 2: Decide, then checkpoint

**Make no tool call between deciding and `checkpoint.py`.**

Decide the following from the request and the state of the work. None of
them has a default: considering the question is the whole contribution.

**Does the user run `/clear` at once?** `clear: true` when the user asked
for the reset to happen now — "clear and continue", "continue in a new
session", "pick this up in a new chat", and a bare "continue" after the
handoff: there is no continuing this side of a clear. `clear: false` when
they are preparing one they will run themselves — "save handoff",
"before I clear", "wrap up".

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
  this session. It reaches the user as a `/rename` suggestion.
- **Task snapshot** — whether there's an active task whose state is worth
  preserving; if so, draft it from the task template below.
- **Todo content** — whether there are open decisions still to make, steps
  after the first action, or a task list with open items in play; if so,
  draft it from the todo template below.

The fresh session reads the two files whole (the AGENTS.md loader line), so
whatever is in them arrives verbatim — and whatever is not in them is lost.
There is no continuation prompt and no driven transition under Vibe: do not
carry the Claude payload's `continue` field; this schema rejects it.

**Task template:**

```markdown
## Current task

<The task in hand and where it stands, in-flight threads named in a sentence,
and the ONE action the fresh session does first, not the topic and not what
follows it. Prose. Not a recap.>
```

- **At most 1000 characters of prose, and no list.** The checkpoint rejects a
  longer body, and any line that opens a list item.
- **Only the task in hand stays here.** Every step after the first action, in
  order, and open decisions go to the todo, a chain of later steps in one
  sentence included. Standing rules and conventions are memory: write them in
  Step 1. Finished work is one sentence at most.
- No file paths or code beyond what's needed to say what's in progress.
- **No commit, push or release status** ("the work is uncommitted", "nothing
  pushed", "ready to commit", "release is a separate request"): the line is
  false after the next commit. If uncommitted work matters, what matters is
  *why* (tests red, decision pending): write that as an open decision in the
  todo.

**Todo template:**

```markdown
## Open decisions

- <Unmade choice, phrased as a decision still to make, with enough context to
  decide — identifiers, commit ranges, file paths, the exact shape of the
  question, whatever must survive verbatim.>

<Drop the section if there are no open decisions. No filler.>

## Remaining

- <Open item, one line, phrased as work still to do.>
```

- **Open items only, in both sections.** A finished item or a resolved decision
  is dropped, never checked off, prefixed "done:" or struck through: anything
  still listed reads as outstanding and gets redone.
- **A decision the user has left unanswered across several frames is declined,
  not missed.** Drop it, and never annotate one with the number of times it has
  been raised. A listed decision blocks nothing either: work that can proceed
  without the answer is listed as work.
- **No commit or push status here either**, and no item saying "commit the
  work" or "push the branch". A release still owed is an item.
- Durable lessons go to memory, not to `## Open decisions`.
- A `TODO.md` that is already there in another shape keeps its shape: add to it
  and drop from it with `edit` rather than rewriting it into this template.

Neither file takes a `#` heading or extra sections.

Then run `checkpoint.py` (Bash) from the plugin's skill directory — the skill
tool printed its path when this skill loaded, as
`Base directory for this skill: <path>` — piping the whole wrap-up as JSON on
stdin via a heredoc, with the project root as the cwd:

````
python3 "<base directory>/checkpoint.py" <<'JSON'
{
  "skill": "handoff",
  "commit": "<with-commit|without-commit>",
  "rename": "<session title>",
  "clear": <true|false>,
  "task": <"task content"|{"action": "clear"}>,
  "todo": <"todo content"|{"action": "clear"}|{"action": "keep"}|{"action": "edit", "old_string": "…", "new_string": "…"}>
}
JSON
````

`task` and `todo` are both required, each carrying content as a string or an
object naming an action. A content string replaces the whole file, so a `todo`
string carries every open item still listed. `{"action": "clear"}` removes
that file — for `task`, this is how a boundary with nothing to carry says so;
for `todo`, it says every item landed. When the call has nothing to say about
the list, send `{"action": "keep"}`, which leaves it untouched: `keep` is the
usual answer and `clear` a deliberate stand-down.
`{"action": "edit", …}` replaces one exact occurrence of `old_string` in the
file with `new_string`, so an item is added or dropped without the whole list
in context. `keep` and `edit` apply to `todo` only; `edit` needs the file to
exist and `old_string` to appear in it exactly once. `null` is an error on
both, as is omitting a key, or adding one inside an action object.

### Step 3: Follow what it prints, in order

`checkpoint.py` prints what is left to do at this boundary. Carry out each
part in the order printed; each one waits for everything above it. The
checkpoint owns the decision — do not re-derive or verify it. A non-zero
exit names the offending field on stderr: fix the payload and retry.

A `root` error means nothing was written: the cwd drifted off the project
root — go back there and run the call again.

The last part is always the closing line. Vibe runs no transition for you:
end the reply on that line, so the user reads what to type — `/clear` (and
`/rename <title>` under `clear: true`, from the rename line) — and types it.

## Anti-patterns

- Reading `TASK.md`, `TODO.md`, or any other project file "to
  check" before deciding what to write in Step 2. The decision
  comes from the conversation already in context — re-reading duplicates
  what `checkpoint.py` does internally, against state that may be
  stale by the time it writes.
- Padding "Current task" to look thorough. Length should track how many
  threads are genuinely in flight, not effort.
- Submitting a `continue` field, or any other Claude-only payload key. The
  schema rejects them: there is no driven transition under Vibe.
- Paraphrasing the closing line into prose. The user acts on the line
  verbatim: `/clear` is a slash command no agent can type.
