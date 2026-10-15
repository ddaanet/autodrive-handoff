# autodrive-handoff

Clear or compact a long Claude Code session without losing the thread.

Before a `/clear` or `/compact`, the plugin has Claude put the work in
progress on disk: the open decisions and remaining to-do items, plus the task
in hand before a `/clear`. After the reset the files are injected back,
verbatim. If you ask, the plugin also runs the reset and resumes the work, so
you type nothing.

## What you get

- **A task frame that survives `/clear`.** `TASK.md` and `TODO.md` in your
  project root, loaded into the next session.
- **A to-do list that survives `/compact`.** The wrap-up saves `TODO.md` before
  the compaction and re-injects it word for word after.
- **Optional hands-off resets.** Ask for "clear and continue" or "compact and
  continue" and the plugin runs the command and resumes from the files.
- **Optional commit.** The wrap-up has Claude commit the two files with your
  work, or amend them into your last commit.
- **Plain files.** You can read and edit them; the plugin has no database and
  no network code.

## Install

```
/plugin marketplace add ddaanet/claude-plugins
/plugin install autodrive-handoff@ddaanet
```

## Use it

Ask in plain words, or invoke a skill:

| skill | use it |
|---|---|
| `/autodrive-handoff:handoff` | before a `/clear` |
| `/autodrive-handoff:precompact` | before a `/compact` |
| `/autodrive-handoff:autoname` | to name the session, and nothing else |
| `/autodrive-handoff:pending` | to list the open decisions and remaining todos already loaded, with no tool calls |

Examples of what to say:

| You say | What happens |
|---|---|
| "save handoff", "wrap up" | Files written and session renamed; you run `/clear` yourself. |
| "handoff and continue" | Files written and session renamed, then cleared and resumed. |
| "handoff, commit" | Files written, then committed together with the session's work. |
| "handoff, amend" | For work already committed: the updated files are folded into that last commit. |
| "handoff, commit, continue" | The commit, then the clear and the resume. |
| "precompact" | Files written; you run `/compact` yourself. |
| "compact and continue" | Files written, then `/compact` runs and the work resumes. |

The commit is recognised by meaning, not by keyword: "handoff and ci" counts.
Commit and amend combine with continuing in the same way.

## What to expect

**Clear.** The wrap-up writes `TASK.md` (the task and where it stands, at most
1000 characters of prose) and `TODO.md` (open decisions and remaining items;
finished items are dropped), and the session is renamed when your turn ends.
With "continue", it is also cleared. The fresh session starts with both files
injected, and the plugin submits one fixed prompt to resume.

**Compact.** The wrap-up writes `TODO.md` only; the compaction summary
carries the task, so an old `TASK.md` is removed. Whatever must survive
word for word goes in `TODO.md`. With "continue", `/compact` runs when your
turn ends, `TODO.md` is re-injected and the work resumes.

**Memory.** If your repository uses
[gitlore](https://github.com/ddaanet/gitlore), the wrap-up also offers to
commit uncommitted memory: it drafts the message and waits for your approval
before any clear or compact.

**When it does not run.** If the transition could not run, you are told at
your next prompt, with the commands to run by hand. That happens on Claude
Code older than 2.1.287 or under `--safe-mode`.

**Finishing.** Run the handoff again with nothing outstanding to clear both
files. They are ordinary tracked files and ride your next commit.

Use compact when the work continues past a long session, and clear when the
thread itself should restart. Compacting right before `/clear` wastes the
compaction.

## Limitations

- One session per project root at a time. Sessions sharing a root share
  `TASK.md`, `TODO.md` and `.claude/autodrive`, unlocked, and the later
  wrap-up wins. Give parallel sessions a git worktree each.
- Do not share one `.claude/` between roots.
- Another handoff plugin (`ddaa-handoff`, `ddaa-passation`) answers the same
  phrases. Enable one handoff provider per project.

## Requirements

- Claude Code 2.1.287 or newer (the plugin's mod runs the transition)
- `python3` and `jq` in `$PATH`

## What the plugin runs and writes

Everything the plugin starts, submits and writes, checked against its code.
It has no network code. Text that reaches the conversation, such as the
injected `TASK.md` and `TODO.md`, is sent to the model like any other context.

### Programs it starts

No binary is shipped. Every program is `bash`, `python3` or `jq` over the
plugin's own `scripts/` and `bin/`, plus coreutils and read-only `git`.

| Where | Program | Purpose |
|---|---|---|
| `SessionStart` hooks | `bash scripts/session-pointer.sh`, `load-handoff.sh`, `load-compact.sh` | inject the files, clean up |
| `UserPromptSubmit` hook | `bash scripts/report-drive-failure.sh` | report a failed or stale transition, note session-root drift |
| `PreToolUse(Write\|Edit)` hook | `bash scripts/write-guard.sh` | deny writes to `.claude/autodrive` |
| `PreToolUse(Bash)` hook | `bash scripts/inject-checkpoint-root.sh` | see below |
| Mod, at turn end | `bash <plugin>/scripts/drive-take.sh <cwd> <session-id>` | take the armed transition |
| Agent's Bash tool | `handoff-checkpoint`, `handoff-approved` | write the files; release a held transition |

The mod skips `drive-take.sh` only when the turn ended in the session root
and `.claude/autodrive` does not exist. Otherwise it runs it, and it prints
nothing when no transition is armed for this session. The mod runs no git or
network code.

`git` is read-only and runs only inside `handoff-checkpoint`, to learn whether
a gitlore memory submodule has uncommitted changes:
`git config --file .gitmodules submodule.gitlore-memory.path`, then
`git -C <memory> status --porcelain` and
`git -C <root> config --get gitlore.memoryApprovalClauseFile`.

### What the mod submits

The mod runs only what `.claude/autodrive` holds, and only for the session
that file names as its owner. The lines it can hold:

- `/rename <title>`
- `/clear`
- `/compact`, or `/compact <focus>` with a one-line focus directive
- the one prompt the plugin ever submits:

  ```
  Continue where the previous context stopped.
  ```

The mod checks the prompt box before each line and stops if you typed
anything. A rejected line stops the sequence and is reported at your next
prompt. The file's reader refuses any other slash command.

### The `PreToolUse(Bash)` rewrite

When a Bash command contains `handoff-checkpoint` or `handoff-approved`, the
hook rewrites it to `export HANDOFF_ROOT=<root>; <original command>`. It makes
no permission decision: your usual permission rules apply. Other commands are
left alone.

Because the rewritten command starts with `export`, a prefix rule for the
command name alone does not match it, and you are prompted (a headless `-p`
run is denied). To run the checkpoint without a prompt, allow all three in
`.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(handoff-checkpoint:*)",
      "Bash(handoff-approved:*)",
      "Bash(export HANDOFF_ROOT=*)"
    ]
  }
}
```

### Files it writes

| File | Purpose |
|---|---|
| `TASK.md`, `TODO.md` (project root) | the task frame; plain tracked files |
| `.claude/` | created by `handoff-checkpoint` when absent |
| `.claude/autodrive` | the transition to carry out; written only by `handoff-checkpoint`, direct writes denied by the `PreToolUse(Write\|Edit)` guard |
| `.claude/autodrive.failed` | written by the mod when a line is rejected; consumed at your next prompt |
| `.claude/autodrive.swept` | one line per stale transition file removed; last 50 kept |
| `.claude/handoff-todo.md`, `.claude/handoff-task.md` | files from an earlier version of the plugin; `handoff-checkpoint` moves the todo to `TODO.md` or removes either, and nothing else touches them |
| `/tmp/claude/handoff-drift-<session id>` | marker so a session-root drift note appears once; `/tmp/claude` is created mode 0700 and markers older than 7 days are deleted |

`TASK.md`, `TODO.md`, `.claude/autodrive` and `.claude/autodrive.swept` are
each written through a temporary sibling file renamed over the name.

It also reads, never writes, the modification time of the owning session's
transcript, to tell a live session from a dead one.

### What it does not do

- No network call.
- No `git commit`, `git push` or any git command that changes anything. When
  you ask for a commit, the agent makes it under your permission rules.
- No prompt other than the one above, and no slash command other than
  `/rename`, `/clear` and `/compact`.

## Uninstall

```
/plugin uninstall autodrive-handoff@ddaanet
```

## Further reading

- [Design hub](https://github.com/ddaanet/autodrive-handoff/blob/main/docs/design.md)
  with the nodes under
  [`docs/design/`](https://github.com/ddaanet/autodrive-handoff/tree/main/docs/design)
- [Driving the transition](https://github.com/ddaanet/autodrive-handoff/blob/main/docs/design/driving-the-transition.md):
  the mod, the sentinel, stale-file handling and sessions sharing a root
- [The checkpoint directive](https://github.com/ddaanet/autodrive-handoff/blob/main/docs/design/the-checkpoint-directive.md):
  memory commits, held and armed transitions
- [`skills/handoff/SKILL.md`](skills/handoff/SKILL.md) and
  [`skills/precompact/SKILL.md`](skills/precompact/SKILL.md): the protocols the
  agent follows

## License

MIT
