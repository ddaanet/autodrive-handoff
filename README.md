# handoff

A task snapshot that survives a context reset in Claude Code — whether
that reset is a `/clear` or a `/compact`. Designed as a narrow
complement to Claude Code's auto-memory: memory holds durable facts
(preferences, feedback, project context); this plugin holds the
*ephemeral task frame* memory avoids — what you were doing right now,
what decisions are still open.

Two skills sit on that seam, one per boundary:

| | skill |
|---|---|
| **before `/clear`** | `/handoff:handoff` |
| **before `/compact`** | `/handoff:precompact` |

Each one either prepares and stops — putting the open work on disk and
leaving you to run the command — or carries the transition out for you: the plugin's mod
runs the command and submits a one-line prompt that resumes the work on the
far side, once your turn ends. Which one you get is decided by what you ask
for. `/handoff:autoname` is a third skill: the rename alone, for a session
worth a title while the main thread stays live.
`/handoff:pending` is a fourth: it lists the pending items — open decisions
and remaining todos — from the task frame injected at session start or
after a compact, with no tool calls.

What they write is two plain files in your project root, `TASK.md` and
`TODO.md`; a `SessionStart` hook injects them back, verbatim, into whatever
comes next.

## Setup

Install the plugin:

```
/plugin marketplace add ddaanet/claude-plugins
/plugin install handoff@ddaanet
```

That's it. No per-project setup step. A `SessionStart(startup|clear)`
hook assembles the handoff frame in memory at session start — stamping
a header onto `./TASK.md` and `./TODO.md`, whichever has content — and
injects the result into the fresh agent's context. When there is nothing to
inject it says so (`No task frame or todo.`) rather than staying silent. No
generated file is involved, and the transcript is never touched: the live
working set is the harness's own git status.

**Upgrading from 0.15 or earlier**: the two files used to live under
`.claude/`, and the plugin moves them for you. When the root file has no body,
the loader reads `.claude/handoff-task.md` or `.claude/handoff-todo.md` instead
and says so at session start, and the next checkpoint moves the todo onto
`TODO.md` and replaces the task with the new `TASK.md`, removing the old file.
A root file that has a body wins: the old file is left as it is, and every
session start reports it as ignored until you delete it. Under a wrap-up that
asked for a commit, the checkpoint also prints a `git rm --cached
--ignore-unmatch -q -- …` line, run through `git -C <root>` so it works from any
directory, over the old paths it moved or removed, so git records a rename. A
wrap-up that asked for no commit prints nothing, and the deletion stays
unstaged in `git status`.

To move them yourself, once per project that has them:

```
git mv .claude/handoff-task.md TASK.md
git mv .claude/handoff-todo.md TODO.md
```

If your project already has a `TODO.md`, the plugin shares it: that is the
same list, and the agent keeps the shape it finds.

**Migrating from v0.2.x**: if your project's `CLAUDE.md` contains a
`## Handoff` section with `@.claude/handoff.md` (added by the old
`/handoff:setup` skill, removed in v0.3.0), delete it. Leaving it in
place is harmless but causes the content to load twice (once via the
SessionStart hook, once via the `@`-ref).

## Usage

Before `/clear`, ask the agent to save a handoff:

- "save handoff"
- "before I clear"
- "prepare handoff"
- "wrap up"
- "I'm done"

Or invoke explicitly with `/handoff:handoff`. That prepares and stops —
it saves the frame and tells you what the boundary is ready for, and you
type `/clear` yourself.

To have the reset carried out instead, ask for the continuation:

- "continue after clear"
- "continue in a new session"
- "clear and continue"

It does everything the prepare-only path does, then names the session,
clears it, and submits a one-line prompt into the fresh one. No
summarisation cost — the task frame is what crosses.

To name the session *without* a handoff — a `/btw` side conversation, or
any session worth a title while the main thread stays live — invoke
`/handoff:autoname`. It derives a title from the conversation and renames
the session (the plugin's mod runs `/rename` when your turn ends); it
writes no task file and touches no memory.

## Compact and continue

The compact boundary is the other half: not a wrap-up, but a way to keep
going. Long sessions eventually have to compact, and compaction paraphrases
the conversation — anything that has to survive *exactly* should be on disk
first. Both skills capture durable learnings in auto-memory, commit them if
your repo is gitlore-managed, and put the open work in `TODO.md`.

Ask for the compaction to be prepared — "precompact", "before I compact" —
and you run `/compact` yourself; `TODO.md` is still re-injected when it
finishes, because the skill marked the compaction as expected. Ask for it to
be carried out — "compact and continue" — and the plugin's mod runs
`/compact` once your turn ends, and once it finishes, `TODO.md` is
re-injected and a one-line continuation prompt is submitted. You do not run
`/compact` yourself, and you do not have to type anything to resume.

The two boundaries differ in one thing. Before a `/clear`, the skill writes
`TASK.md`: the task in hand and where it stands, as prose, at most 1000
characters and with no list in it — a longer one is refused with a message
saying where the rest goes. Before a `/compact` there is no task file, and an
existing one is removed: the compaction's own summary carries the task, and a
second account on disk would only be there to contradict it. Whatever must
survive a compaction word for word goes in `TODO.md` or in the focus
directive given to `/compact`.

`TODO.md` holds the **open decisions** and the **remainder** of the task list
— the still-open items, never the finished ones — and is injected alongside
the task file. That file is the ledger; a todo panel in the UI, when there is
one, is a cache of it. Finished items are dropped rather than ticked off:
`git log` already records what landed, and a done item still listed reads as
outstanding and gets redone.

Carrying a transition out is done by a Claude Code mod that ships in this
plugin (`hooks/handoff.ts`), so it **requires Claude Code 2.1.287 or newer**;
the plugin manifest has no field to pin a minimum version, so an older
install loads the rest of the plugin and silently skips the mod. The mod
runs the lines when your turn ends, in order, and stops rather than
running anything over text you have in the prompt. If a line is rejected, the mod
records why, and you and the agent are told at your next prompt rather than
being left to wonder whether the transition happened. A rejected line stops
the sequence, so a rename that never took costs you a wrong title and
nothing more.

When the mod is not loaded — `--safe-mode`, or a Claude Code older than
2.1.287 — nothing runs. The next prompt discards the stale transition, says
so, and prints the lines for you to run yourself, in order. `/restart` is
Claude Code's own command; this plugin has no restart skill.

Use a compact-boundary skill when the work continues past a long session,
and a clear-boundary one when the thread itself should restart. Compacting
right before `/clear` throws away what the compaction just paid for.

The agent updates auto-memory with any durable learnings, then in a single
turn decides the task snapshot (if anything is outstanding), the todo
remainder (if a task list is in flight), and a session title, and pipes all
three to one `handoff-checkpoint` call as a JSON payload. The checkpoint
writes `TASK.md` and writes or edits `TODO.md`, moves or removes a file left
at an old `.claude/handoff-*.md` path, and writes `.claude/autodrive` when
there is something to run at the end of the turn. It stages nothing:
both are ordinary tracked files, and when your request called for a commit
the agent makes it with both in it. Anything to be run waits for the turn to
end — and, when the transition is held, for the `handoff-approved` call that
releases it: when the turn completes, the mod takes the sentinel through
`scripts/drive-take.sh` and runs each line through Claude Code's own command
and prompt entry points. The agent may edit `TASK.md` and `TODO.md` directly
at any time, like any file; a guard denies a direct write to
`.claude/autodrive` alone. After `/clear` (or in a fresh session), the
`SessionStart` hook assembles and injects the handoff frame into the new
agent's context automatically. Auto-memory restores independently. The
agent's own shell cannot see the project root, so a `PreToolUse(Bash)` hook
resolves it and injects it into each `handoff-checkpoint` call as it runs,
rather than sampling it once at session start. And if the session's working
directory ever leaves the repo it was launched in, the next prompt says so,
once per episode.

In a gitlore-managed repository, handoff also offers to commit your memory:
when the memory submodule has uncommitted changes, it drafts a commit message
for them, asks you to approve (or edit) it, and commits via gitlore — so durable
learnings land instead of waiting for your next commit. When a commit is going
to land the change that memory documents — the one you are about to make, or a
later one — the memory rides *that* commit instead of committing separately
first, which saves a step, and it is written as if the change has already
happened, because it has. When that same turn also has a transition to carry
out, the commands wait for your answer — clearing or compacting first would
take away the conversation the question belongs to.

## Staleness and cleanup

The injected frame carries a timestamp in its first heading, and the note
you see at session start gives its age. When the task is finished, invoke the
skill again with nothing outstanding — the agent clears both files, so the
next session starts clean and says `No task frame or todo.`

`TASK.md` and `TODO.md` are tracked like any other file and ride whichever
commit you make next; together they are the durable task trail. Nothing
commits or stages them for you, so a wrap-up that was not asked to commit
leaves them modified in your working tree. gitlore auto-memory is the
complement for durable context that outlives tasks.

## Scope

| Concern | Handled by |
|---|---|
| Durable facts, preferences, feedback | auto-memory |
| Conversation transcript, resume | session JSONL + `claude -c` |
| Summarising the conversation | Claude Code `/compact`, Session Memory |
| **Compacting without losing the thread** | **this plugin** (`precompact`) |
| Code state | the repo |
| **Current task + open decisions across `/clear`** | **this plugin** |

See [`docs/design.md`](docs/design.md) for the research and analysis behind
this split.

### Choosing a handoff provider

The two differ in what crosses the boundary. This plugin keeps a local task
frame and re-injects it verbatim into the next session. A separate plugin,
`ddaa-handoff` (and its French `ddaa-passation`), writes a full
end-of-session *summary*, delivered to Notion when available. They share
the same trigger phrases on purpose, so the same words work whichever you
pick — therefore **enable exactly one handoff provider per project**.
Enabling both reloads the collision this split was made to remove.

## Requirements

- Claude Code 2.1.287 or newer (the transition is run by a mod)
- `python3` in `$PATH`
- `jq` in `$PATH`

## Files touched on your system

Per project, two tracked files in the project root:

- `TASK.md` — the task in hand, written by the checkpoint before a `/clear`
  and removed by it before a `/compact`.
- `TODO.md` — open decisions and the remainder of an in-flight task list,
  kept by the agent all session. Shared with any `TODO.md` the project
  already has.

And under `./.claude/`, two transient files:

- `autodrive` — transient file describing the transition to carry out:
  first line its state, second the kind (`rename`, `compact` or `clear`),
  then the lines to run. Written by the checkpoint and by nothing else — a
  direct agent write is denied. It starts out `held` when running it now would
  cost you something: it would run at the end of a turn that is still asking
  an unanswered memory question, or it would carry out a transition while a commit your
  request called for has not been made yet. `handoff-approved` is the one
  command that releases it to `armed`, and the agent runs it once you have
  approved the memory summary, or once the commit has landed; otherwise the
  file starts out `armed` and nothing is waited on. When it goes into
  flight at the end of your turn its state becomes `pending`, and it is
  consumed once the transition completes. At most one exists at a time — one
  prompt, one transition.
- `autodrive.failed` — written only when a line was rejected, and consumed
  when you are told about it at your next prompt.
- `autodrive.swept` — one line for each transition file the prompt-time sweep
  removed (when, which session, its state, owner and age), newest first, the
  last 50 kept. Never consumed; a diagnostic for a sentinel that went missing.

Nothing outside the current project is modified.

## Uninstall

```
/plugin uninstall handoff@ddaanet
```

## Further reading

- [`docs/design.md`](docs/design.md) — research, SOTA analysis, decisions;
  the hub for the nodes under [`docs/design/`](docs/design/).
- [`docs/changelog.md`](docs/changelog.md) — one line per design change,
  linking the dated write-time record of each under `docs/changelog/`.
- [`plans/`](plans) — prospective content: specs, design proposals,
  implementation plans.
- [`CLAUDE.md`](CLAUDE.md) — agent instructions for working on the
  plugin itself.
- [`skills/handoff/SKILL.md`](skills/handoff/SKILL.md) — the skill
  that the agent follows when you ask for a handoff.
- [`skills/precompact/SKILL.md`](skills/precompact/SKILL.md) — the
  compact-boundary protocol.

## License

MIT
