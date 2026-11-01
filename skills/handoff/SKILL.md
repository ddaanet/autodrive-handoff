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
Skip if nothing durable surfaced — do not force. These writes and Step 2's
read of the files reference are the only tool calls allowed before
`handoff-checkpoint`.

### Step 2: Decide, then checkpoint

Read `references/files.md`, beside this skill, before deciding: the task and
todo templates, their rules, and the seam between the files and the
continuation. It ships with the plugin, so it cannot go stale.

**Make no tool call between deciding and `handoff-checkpoint`.**

Decide the following from the request and the state of the work. None of
them has a default: considering the question is the whole contribution.

**Is the transition driven?** `clear: true` when the user asked for the
reset to be carried out — "clear and continue", "continue in a new
session", "pick this up in a new chat", and a bare "continue" after the
handoff ("handoff and continue", "handoff, commit, continue"): there is no
continuing this side of a clear. `clear: false` when they are
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
  preserving; if so, draft the content using the task template.
- **Todo content** — whether there are open decisions still to make, or a
  task list with open items in play; if so, draft the todo content using
  the todo template (open decisions first, then remaining items).

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

The templates, their rules and the seam between the files and the
continuation are in `references/files.md`.

## Anti-patterns

- Reading `TASK.md`, `TODO.md`, or any other project file "to
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

- **`references/files.md`** — the task and todo templates, their rules, and
  the seam between the files and the continuation; read in Step 2.
- **`references/design.md`** — design rationale: what the residual is
  and why the agent-authored task file plus read-time assembly split.
