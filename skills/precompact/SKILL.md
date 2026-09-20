---
name: precompact
description: Commit durable memory and snapshot the in-progress task before a `/compact`, so the compaction has nothing left to lose — and, when asked, carry the compaction out: run `/compact` and submit a continuation prompt into the compacted context. Use when the user asks to "precompact", "prepare compaction", "prepare compact", "before compact", "before I compact", "about to compact", "flush memory before compact", "compact and continue", "compact then continue", "do this after compact", "compact and pick up", or otherwise signals an imminent `/compact`. For an imminent `/clear` or end of task, use the handoff skill.
---

# precompact — Task Snapshot at the Compact Boundary

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
them has a default: a default is the answer given by an agent that never
considered the question, and considering it is the whole contribution.

**Is the transition typed?** `compact: true` when the user asked for the
compaction to be carried out — "compact and continue", "compact then
continue" — or the focus directive itself (`compact: "keep the parser
work"`) when one would help the summariser keep the right material.
`compact: false` when they are preparing one they will run themselves —
"precompact", "before I compact". A request that asks for the compaction
**is** the authorization to compact; do not ask whether to proceed.

Even under `compact: false` the checkpoint writes the transition file.
Nothing is typed; what it records is that a compaction is *expected*,
which is what the frame's re-injection is gated on. Without it the
compaction re-injects nothing and the summariser's paraphrase is all that
survives of the files just written.

**Is there a continuation prompt?** `continue` is one line of prose,
submitted into the compacted context, or `null` when nothing follows it.
It is only meaningful alongside a typed transition — nothing would type it
otherwise, and the checkpoint rejects the combination. Author it
**silently**: it is typed visibly into the composer and lands in
scrollback, so reprinting it in the reply shows the same text twice with
no veto value.

**Does the ask imply a commit?** Two answers of equal weight:
**`with-commit`** — the request this call serves implies a commit, a test
of interpretation rather than of keywords — and **`without-commit`** — it
does not. The ask stops at the transition: a commit named in a
continuation prompt is on the far side of it, so it is not evidence of
`with-commit`.

Then decide the task snapshot and, when open decisions or a task list with
open items are in play, the todo content — one `## Current task` section
for the task file; `## Open decisions`, when any remain, plus
`## Remaining`, open items only, for the todo file. Both lists live in the
context the compaction is about to paraphrase; deciding them now is what
spares your post-compaction self from inferring which are still open — an
inference that fails silently by redoing finished work or re-litigating a
settled decision.

The `handoff` skill holds the full templates, the rules behind them, and
the seam between what belongs in a file and what belongs in a prompt, in
the `SKILL.md` beside this one — `../handoff/SKILL.md`, relative to this
skill's own directory. Read that file when the rules matter.

Then run `handoff-checkpoint` (Bash) with `"skill": "precompact"` (no
`rename` field — precompact never renames), the three answers above, and
`task`/`todo` each carrying the drafted content or naming an action:

```
handoff-checkpoint <<'JSON'
{
  "skill": "precompact",
  "commit": "<with-commit|without-commit>",
  "compact": <true|false|"focus directive">,
  "continue": <"one line of prose"|null>,
  "task": <"task content"|{"action": "clear"}>,
  "todo": <"todo content"|{"action": "clear"}|{"action": "keep"}|{"action": "edit", "old_string": "…", "new_string": "…"}>
}
JSON
```

Both keys are required. `{"action": "clear"}` removes that file — for
`task`, this is how a boundary with nothing to carry says so; for `todo`,
it says every item landed. Content that is empty once headings and blank
lines are stripped removes the file too, on either key — a `## Remaining`
with no items stands the list down as surely as `clear` does. When the
call has nothing to say about the list, send `{"action": "keep"}`, which
leaves it untouched: a scratch list must survive a call that is silent
about it, so `keep` is the default and `clear` is a deliberate stand-down.
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

The normal case — nothing durable, clean memory, no commit — is one
checkpoint call, and its output is one part, naming the line to end on.

## Anti-patterns

- Running `/compact` yourself, or telling the user to run it under a driven
  transition. Both are settled by the request and the armed file.
- Reprinting the continuation prompt, or printing the `/compact` line, as
  something for the user to run. There is one producer of that pasteable
  form and it is the hook — which is also what covers a session outside
  tmux, where there is no composer to type into.
- Authoring a continuation prompt for a prepared compaction. Nothing types
  it, and the checkpoint rejects it.
- Writing `.claude/autodrive` directly. The checkpoint composes it from the
  payload; a hand-written one is a second writer of the same channel.
- A `rename` field in the checkpoint payload. A rename is
  `/handoff:autoname`'s job when wanted, and the checkpoint rejects it here.
- Forcing a memory write to have something to show. An empty flush is the
  normal case.
- Padding the line the checkpoint tells you to end on into a summary of the
  session. The compaction is about to produce one.
