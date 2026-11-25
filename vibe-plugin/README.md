# autodrive-handoff, for Mistral Vibe

The native Vibe port of the autodrive-handoff plugin. Same boundaries, same
frame files, one narrower mechanism: Vibe has no SessionStart-class hook,
never reads CLAUDE.md, and has no driven continuation, so the transition is
prepared on disk and the user types the `/clear` or `/compact` themselves.

## Install

1. **Copy the plugin into a plugins directory.**

   ```
   rm -rf ~/.vibe/plugins/autodrive-handoff
   mkdir -p ~/.vibe/plugins
   cp -R vibe-plugin ~/.vibe/plugins/autodrive-handoff
   ```

   The `rm -rf` makes the same three lines the update: without it, a
   second `cp -R` nests `vibe-plugin/` inside the old install.

   (`.vibe/plugins/` in a trusted project works too; there it wins over the
   user scope on name collisions.) Run `/reload-plugins` in a running
   session, or restart.

2. **Add the loader line to the project's `AGENTS.md`.** Vibe splices
   AGENTS.md verbatim and reads no CLAUDE.md, and the line is what
   injects the frame into the fresh session:

   ```
   Before answering the first prompt of a session, read TASK.md and TODO.md
   in the project root; they are the current task frame and the only thing
   that survives the /clear.
   ```

   A headless run (`vibe -p`) in a folder Vibe does not trust ignores the
   project's AGENTS.md, so there the line, and with it the frame, is
   skipped without a word. Trust the folder before driving it headless —
   an interactive session, or `--trust` on the headless invocation (it
   trusts the working directory for that run only).

3. **Install the compaction prompt** (optional). It has the summary state
   the current task and next action from the conversation, and sends the
   next turn to re-read `TASK.md` and `TODO.md` from disk. Fine to skip
   when you only ever use `/clear`:

   ```
   mkdir -p .vibe/prompts
   cp ~/.vibe/plugins/autodrive-handoff/prompts/compaction.md \
      .vibe/prompts/handoff-compact.md
   ```

   Then set the key `compaction_prompt_id = "handoff-compact"` in
   `.vibe/config.toml` as a top-level key, above the file's first `[table]`
   header: below a header it belongs to that table, and Vibe ignores it.
   When the file is absent, create it holding just that line; when the key
   already exists, change its value rather than adding a second one, which
   is invalid TOML.

   Then run `/reload`.

## Memory

Vibe has no native memory system; durable learnings ride
[gitlore](https://github.com/ddaanet/gitlore), which publishes memory
through git. When the repo's `gitlore-memory` submodule is dirty, the boundary's
memory directive tells the agent to report it to you as uncommitted, since
Vibe has no `gitlore:commit` skill; under with-commit the commit leaves the
memory pointer out. gitlore installs for Claude Code; it has no Vibe-native install of
its own, and bridging one through a symlink into Claude Code's plugin
cache is ruled out — the port deliberately waits for gitlore to ship
natively. Until then the boundary still prints its directive and the
memory stays dirty until committed by hand. (For the record: Vibe's
foreign-format adapter does import Claude-format trees and expose their
skills under `{namespace}:{name}` — the coupling, not the capability, is
what was refused.)

## Skills

| skill | use it |
|---|---|
| `/autodrive-handoff:handoff` | before a `/clear` |
| `/autodrive-handoff:precompact` | before a `/compact` |
| `/autodrive-handoff:autoname` | to decide a session title — the user runs `/rename` with it |
| `/autodrive-handoff:pending` | to list the open decisions and remaining todos already loaded |

## What differs from the Claude plugin

- **No driven transitions.** Vibe cannot type `/clear`, and its hook
  surface (`post_agent`/`pre_tool`/`post_tool`) has no SessionStart and no
  Stop — so the mod, the sentinel in `.claude/autodrive`, the write guard
  and the hold predicate have no counterpart, and the checkout drops the
  `continue` payload field. The skills' closing lines name the command for
  the user instead.
- **The frame is read, not injected.** The AGENTS.md line above replaces
  the SessionStart loader; the files arrive whole, never cut.
- **One manifest, one write path.** `checkpoint.py` and its three modules
  live in `scripts/` of the installed plugin and a copy ships inside each
  caller skill directory, invoked through the base directory the skill
  tool prints. `TASK.md` and `TODO.md` keep the Claude plugin's templates
  and cap (1000 characters of prose).
- **Updates**: rerun step 1, whose `rm -rf` replaces everything; the frame
  files in your project are kept as they are. The project-local compaction
  prompt is outside the plugin directory: after updating, re-copy
  `prompts/compaction.md` over `.vibe/prompts/handoff-compact.md`, or the
  summary runs under the old wording.
- **Nothing drives the compaction.** `precompact` flushes memory and
  writes `TASK.md` and `TODO.md`, as `handoff` does, then names
  `/compact` for you to type. Both files survive the compaction; the
  prompt has the summary state the current task and next action from the
  conversation, and tells the next turn to re-read both files from disk
  instead of reproducing them.
- **`autoname` runs from any directory**; it needs no project root.
