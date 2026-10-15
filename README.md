# autodrive-handoff

A task snapshot that survives a context reset in Claude Code — whether
that reset is a `/clear` or a `/compact`. Designed as a narrow
complement to Claude Code's auto-memory: memory holds durable facts
(preferences, feedback, project context); this plugin holds the
*ephemeral task frame* memory avoids — what you were doing right now,
what decisions are still open.

| skill | use it |
|---|---|
| `/autodrive-handoff:handoff` | before a `/clear` |
| `/autodrive-handoff:precompact` | before a `/compact` |
| `/autodrive-handoff:autoname` | to name the session, and nothing else |
| `/autodrive-handoff:pending` | to list the open decisions and remaining todos already loaded, with no tool calls |

The two boundary skills either prepare and stop — putting the open work on
disk and leaving you to run the command — or carry the transition out for
you: the plugin's mod runs the command and submits a fixed prompt that
resumes the work from the files on the far side, once your turn ends. Which
one you get is decided by what you ask for.

What they write is two plain files in your project root, `TASK.md` and
`TODO.md`; a `SessionStart` hook injects them back, verbatim, into whatever
comes next.

## Setup

Install the plugin:

```
/plugin marketplace add ddaanet/claude-plugins
/plugin install autodrive-handoff@ddaanet
```

This plugin was called `handoff` before; if you installed it under that name,
run `/plugin uninstall handoff@ddaanet` first, then install the new name.

At every session start and after every `/clear`, a hook injects `TASK.md`
and `TODO.md`, whichever has content, into the agent's context under a
timestamp header. When neither has, it says so: `No task frame or todo.`

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

Or invoke explicitly with `/autodrive-handoff:handoff`. That prepares and stops —
it saves the frame and tells you what the boundary is ready for, and you
type `/clear` yourself.

To have the reset carried out instead, ask for the continuation:

- "continue after clear"
- "continue in a new session"
- "clear and continue"

It does everything the prepare-only path does, then names the session,
clears it, and submits a fixed continuation prompt into the fresh one. No
summarisation cost — the task frame is what crosses.

To name the session *without* a handoff — a `/btw` side conversation, or
any session worth a title while the main thread stays live — invoke
`/autodrive-handoff:autoname`. It derives a title from the conversation and renames
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
re-injected and a fixed continuation prompt is submitted. You do not run
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
plugin (`handoff.ts` in its `hooks` directory), so it **requires Claude Code 2.1.287 or newer**;
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

In a gitlore-managed repository, this plugin also offers to commit your memory:
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

See [`docs/design.md`](https://github.com/ddaanet/autodrive-handoff/blob/main/docs/design.md) for the research and analysis behind
this split.

### Choosing a handoff provider

The two differ in what crosses the boundary. This plugin keeps a local task
frame and re-injects it verbatim into the next session. A separate plugin,
`ddaa-handoff` (and its French `ddaa-passation`), writes a full
end-of-session *summary*, delivered to Notion when available. They share
the same trigger phrases on purpose, so the same words work whichever you
pick — therefore **enable exactly one handoff provider per project**.
Enabling both reloads the collision this split was made to remove.

## Limitations

One session per project root at a time. Sessions sharing a root share
`TASK.md`, `TODO.md` and `.claude/autodrive`, and nothing locks them:

- When two sessions checkpoint in one root, the later checkpoint replaces the
  earlier one's transition, which is then lost without a word.
- `TASK.md` and `TODO.md` are last-writer-wins: a second session's wrap-up
  replaces the first's.
- Taking a transition at turn end reads the file and then rewrites it, not in
  one step; a checkpoint landing in between is overwritten.
- A `.claude/` shared between roots (a symlink from one worktree to another's,
  or any other sharing) is unsupported: a transition in flight names no
  session, since the one after a `/clear` has a new id, so the other root can
  consume it.

To run sessions in parallel, give each its own git worktree: the root is the
enclosing worktree, so each one has its own `.claude/`, `TASK.md` and
`TODO.md`.

## Requirements

- Claude Code 2.1.287 or newer (the transition is run by a mod)
- `python3` in `$PATH`
- `jq` in `$PATH`

## What the plugin runs and writes

This is everything the plugin starts, submits and writes, checked against its
code. There is no network code in it, and nothing it runs leaves your machine.
The only thing that goes anywhere is what any file or tool output in your
session goes to: text that reaches the conversation (the injected `TASK.md`
and `TODO.md`, a hook's note) is part of the context Claude Code sends to the
model, like anything else in it.

### Programs it starts

The plugin ships no binary. Every program is `bash`, `python3` or `jq`, over
scripts in the plugin's own `scripts/` and `bin/`, plus the usual
coreutils (`date`, `stat`, `find`, `mktemp`, `mkdir`, `rm`, `tr`, `awk`,
`head`) and, read-only, `git` (see below).

Hooks, each declared in the plugin's hooks manifest and run as
`bash <plugin>/scripts/<name>`:

| Event | Script | What it does |
|---|---|---|
| `SessionStart` (every source) | `session-pointer.sh` | creates `/tmp/claude` (mode 0700) and deletes `handoff-root-*` and `handoff-drift-*` files there older than 7 days |
| `SessionStart` (`startup`, `clear`) | `load-handoff.sh` | injects `TASK.md` and `TODO.md`; clears a finished `clear` transition |
| `SessionStart` (`compact`) | `load-compact.sh` | injects `TODO.md`; clears a finished `compact` transition |
| `UserPromptSubmit` | `report-drive-failure.sh` | reports a failed or stale transition, sweeps a stale one, notes session-root drift |
| `PreToolUse` (`Write`, `Edit`) | `write-guard.sh` | denies a write to `.claude/autodrive`; allows or ignores everything else |
| `PreToolUse` (`Bash`) | `inject-checkpoint-root.sh` | see below |

The mod, `handoff.ts` in the plugin's `hooks` directory, runs one program: at
the end of a turn it runs `bash <plugin>/scripts/drive-take.sh <cwd>
<session-id>`. It skips even that when the session's directory is the project
root and no `.claude/autodrive` file exists, so a turn with nothing armed
starts nothing. It also reads the prompt box, to see whether you have typed
anything, shows toasts, and writes `.claude/autodrive.failed` (below). It does
no network or git work, and it never reads `.claude/autodrive` itself:
`drive-take.sh` does, and hands it the plan.

The agent itself runs two commands from the plugin's `bin/`, from its Bash
tool and under your normal permission rules:

- `handoff-checkpoint` reads a JSON payload on stdin and writes the files
  below. It starts `python3` and, to re-read the file it just composed, `bash`.
- `handoff-approved` takes no input and moves a held transition to armed.

`git` is run by `handoff-checkpoint` in three read-only forms, and only to
find out whether a gitlore memory submodule has uncommitted changes:
`git config --file .gitmodules submodule.gitlore-memory.path` on each
`handoff` or `precompact` wrap-up (not for `autoname`), and, only when that
submodule exists, `git -C <memory> status --porcelain` and, if it has
changes, `git -C <root> config --get gitlore.memoryApprovalClauseFile`. None
changes a repository. The file list `status` prints is shown to the agent in
the checkpoint's output, so it can draft the memory commit message. Nothing
else the plugin ships starts `git`.

### What the mod submits

The mod runs only what `.claude/autodrive` holds, and only when the turn that
just ended belongs to the session whose id that file names as its owner.
`handoff-checkpoint` composes the file in the agent's call, from a payload it
validates, and the guard above refuses a direct `Write` or `Edit` to it. The
lines it can hold are:

- `/rename <title>`, the session title the agent chose;
- `/clear`;
- `/compact`, or `/compact <focus>` with the focus directive the agent chose,
  one line;
- one resume prompt, which is exactly this, from the `CONTINUATION` constant
  in `scripts/checkpoint.py`:

  ```
  Continue where the previous context stopped.
  ```

That resume prompt is the only prompt the plugin ever submits, and the
checkpoint writes it only when the request was to continue after the reset.
The mod runs the lines in order and checks the prompt box before each one: if
you have typed anything it stops and runs nothing more. A line the host
rejects stops the sequence and is recorded, and you are told at your next
prompt. The file's reader also pins each command to its place and refuses a
prose line that begins with `/`, so a file the checkpoint did not write still
cannot make the mod run any other slash command.

### The `PreToolUse(Bash)` hook

`inject-checkpoint-root.sh` looks at every Bash call the agent makes with one
`jq` parse and a substring test. When the command contains `handoff-checkpoint`
or `handoff-approved`, it rewrites it to `export HANDOFF_ROOT=<root>; <the
original command>`, where `<root>` is the project root it resolved, shell-quoted.
Those two commands cannot find the root from inside the agent's shell. The hook
returns the rewritten command and nothing else: it makes no permission decision,
so the rewritten command goes through your usual permission rules, the same as
if the agent had typed it. (An earlier version also returned `allow`, which
skips that check for any command that merely contained one of the two names; it
no longer does.) Any other command is left alone and the hook prints nothing.

### Files it writes

Per project, two tracked files in the project root:

- `TASK.md` — the task in hand, written by the checkpoint before a `/clear`
  and removed by it before a `/compact`. Read by `load-handoff.sh`.
- `TODO.md` — open decisions and the remainder of an in-flight task list,
  kept by the agent all session. Shared with any `TODO.md` the project
  already has. Read by both loaders.

Both are plain files that nothing stages or commits. A file left by 0.15 or
earlier at `.claude/handoff-task.md` or `.claude/handoff-todo.md` is moved onto
`TODO.md`, or removed, by the checkpoint (see Setup).

And under `./.claude/`, three files:

- `autodrive` — transient file describing the transition to carry out: first
  line its state (with the owning session's id while it waits to run), second
  the kind (`rename`, `compact` or `clear`), then the lines to run. Only the
  owning session's turn end runs it. Another session's prompt leaves an
  `armed` one alone while the owning session is active, and a `held` one alone
  always: it waits on your approval for as long as that takes. Written by the
  checkpoint and by nothing else — a direct agent write is denied. It starts
  out `held` when running it now would cost you something: it would run at the
  end of a turn that is still asking an unanswered memory question, or it
  would carry out a transition while a commit your request called for has not
  been made yet. `handoff-approved` is the one command that releases it to
  `armed`, and the agent runs it once you have approved the memory summary, or
  once the commit has landed; otherwise the file starts out `armed` and
  nothing is waited on. When it goes into flight at the end of your turn its
  state becomes `pending`, and it is consumed once the transition completes.
  At most one exists at a time — one prompt, one transition. Read by
  `drive-take.sh`, both loaders and the prompt hook.
- `autodrive.failed` — written by the mod only when a line was rejected, and
  consumed by the prompt hook when you are told about it at your next prompt.
- `autodrive.swept` — one line for each transition file the prompt-time sweep
  removed (when, which session, its state, owner and age), newest first, the
  last 50 kept. Never consumed; a diagnostic for a sentinel that went missing.

Outside the project, in `/tmp/claude/`:

- `handoff-drift-<session id>` — a marker the prompt hook writes when the
  session's working directory has left the repository it was launched in, so
  the note appears once and not every prompt. It holds that directory and is
  deleted by `session-pointer.sh` when over 7 days old.

When a gitlore memory submodule has uncommitted changes, the checkpoint prints
instructions for the agent to summarise them, get your approval and write a
message file under `.claude/` for gitlore to use; the agent writes it, not the
plugin, and gitlore reads it. Likewise, when your request called for a commit,
the checkpoint prints a line telling the agent to make it, with `TASK.md` and
`TODO.md` included. These are instructions the agent may follow, printed on
the checkpoint's output, and the commit is the agent's, made under your
permission rules. The plugin itself never runs `git commit`, `git push` or any
other git command that changes anything.

Nothing outside the current project is modified except those markers. The
plugin reads one file it does not write: the modification time (never the
content) of the owning session's transcript, to tell a live session from a dead
one.

### What it does not do

- It makes no network call: no script or the mod fetches, posts or opens a
  connection, and it sends nothing anywhere.
- It runs no git command that changes anything, and never commits or pushes
  (the checkpoint's printed instructions above are the one place a commit
  comes up).
- It submits no prompt other than the one above, and runs no slash command
  other than `/rename`, `/clear` and `/compact`.

## Uninstall

```
/plugin uninstall autodrive-handoff@ddaanet
```

## Further reading

- [`docs/design.md`](https://github.com/ddaanet/autodrive-handoff/blob/main/docs/design.md) — research, SOTA analysis,
  decisions; the hub for the nodes under
  [`docs/design/`](https://github.com/ddaanet/autodrive-handoff/tree/main/docs/design).
- [`docs/changelog.md`](https://github.com/ddaanet/autodrive-handoff/blob/main/docs/changelog.md) — one line per design
  change, linking the dated write-time record of each under
  [`docs/changelog/`](https://github.com/ddaanet/autodrive-handoff/tree/main/docs/changelog).
- [`plans/`](https://github.com/ddaanet/autodrive-handoff/tree/main/plans) — prospective content: specs, design
  proposals, implementation plans.
- [`CLAUDE.md`](https://github.com/ddaanet/autodrive-handoff/blob/main/CLAUDE.md) — agent instructions for working on
  the plugin itself.
- [`skills/handoff/SKILL.md`](skills/handoff/SKILL.md) — the skill
  that the agent follows when you ask for a handoff.
- [`skills/precompact/SKILL.md`](skills/precompact/SKILL.md) — the
  compact-boundary protocol.

## License

MIT
