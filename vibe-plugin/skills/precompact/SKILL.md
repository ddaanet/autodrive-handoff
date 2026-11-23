---
name: precompact
description: 'Put the open work on disk before a `/compact`, so the compaction has nothing left to lose — under Vibe the task itself crosses only through the custom compaction prompt, and this checkpoint also checks that it is installed. Use when the user asks to "precompact", "prepare compaction", "prepare compact", "before compact", "before I compact", "about to compact", "flush memory before compact", "compact and continue", "compact then continue", "do this after compact", "compact and pick up", or otherwise signals an imminent `/compact`. For an imminent `/clear` or end of task, use the handoff skill.'
---

# precompact — Open Work on Disk at the Compact Boundary

Compaction paraphrases the conversation; disk survives it untouched. So:
put what matters on disk before it runs. Under Vibe the task file is
removed at this boundary and reaches the compacted session only through the
custom compaction prompt — the checkpoint warns when it is not installed.

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

**Does the user run `/compact` at once?** `compact: true` when the user
asked for the compaction to be carried out — "compact and continue",
"compact then continue". `compact: false` when they are preparing one they
will run themselves — "precompact", "before I compact".

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

There is no task snapshot and no `rename` field at this boundary: the summary
carries the task, and the checkpoint removes the task file. The Claude
schema's `compact` focus string does not port — Vibe's `/compact` takes no
argument; whatever the summariser must keep besides what is on disk belongs
in the todo.

Then run `checkpoint.py` (Bash) from the plugin's skill directory — the skill
tool printed its path when this skill loaded, as
`Base directory for this skill: <path>` — piping the whole call as JSON on
stdin via a heredoc, with the project root as the cwd:

````
python3 "<base directory>/checkpoint.py" <<'JSON'
{
  "skill": "precompact",
  "commit": "<with-commit|without-commit>",
  "compact": <true|false>,
  "todo": <"todo content"|{"action": "clear"}|{"action": "keep"}|{"action": "edit", "old_string": "…", "new_string": "…"}>
}
JSON
````

`todo` is required. A content string replaces the whole file, so it carries
every open item still listed. `{"action": "clear"}` removes the file — it says
every item landed. When the call has nothing to say about the
list, send `{"action": "keep"}`, which leaves it untouched: `keep` is the
usual answer and `clear` a deliberate stand-down. `{"action": "edit", …}` replaces
one exact occurrence of `old_string` with `new_string`, so an item is added or
dropped without the whole list in context; it needs the file to exist and
`old_string` to appear in it exactly once. `null` is an error, as is
omitting the key, or adding one inside an action object.

### Step 3: Follow what it prints, in order

`checkpoint.py` prints what is left to do at this boundary. Carry out each
part in the order printed; each one waits for everything above it. The
checkpoint owns the decision — do not re-derive or verify it. A non-zero
exit names the offending field on stderr: fix the payload and retry.

A `root` error means nothing was written: the cwd drifted off the project
root — go back there and run the call again.

When a printed part warns that the custom compaction prompt is not
installed, surface the warning and its setup line to the user before the
closing line: running `/compact` without it loses the task to paraphrase.

The last part is always the closing line. Vibe runs no transition for you:
end the reply on that line, so the user reads what to type — `/compact` —
and types it.

The normal case — nothing durable, clean memory, no commit — is one
checkpoint call, and its output is one part, naming the line to end on.

## Anti-patterns

- Submitting a `continue` field or the Claude schema's focus string. There
  is no driven transition under Vibe, and `/compact` takes no argument.
- A `rename` or `task` field in the checkpoint payload. The summary is the
  task's carrier at this boundary, and the checkpoint rejects both keys.
- Forcing a memory write to have something to show. An empty flush is the
  normal case.
- Padding the line the checkpoint tells you to end on into a summary of the
  session. The compaction is about to produce one.
