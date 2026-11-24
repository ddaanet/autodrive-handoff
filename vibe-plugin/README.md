# autodrive-handoff, for Mistral Vibe

The native Vibe port of the autodrive-handoff plugin. Same boundaries, same
frame files, one narrower mechanism: Vibe has no SessionStart-class hook,
never reads CLAUDE.md, and has no driven continuation, so the transition is
prepared on disk and the user types the `/clear` or `/compact` themselves.

## Install

1. **Copy the plugin into a plugins directory.**

   ```
   mkdir -p ~/.vibe/plugins
   cp -R vibe-plugin ~/.vibe/plugins/autodrive-handoff
   ```

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

3. **Install the compaction prompt** (the compact seam). Without it,
   `/compact` paraphrases the context under the builtin prompt and the task
   file's removal loses the task. Fine to skip when you only ever use
   `/clear`:

   ```
   mkdir -p .vibe/prompts
   cp ~/.vibe/plugins/autodrive-handoff/prompts/compaction.md \
      .vibe/prompts/handoff-compact.md
   printf 'compaction_prompt_id = "handoff-compact"\n' >> .vibe/config.toml
   ```

   Then run `/reload`. The boundary itself reports when the prompt is
   missing — the checkpoint's compaction-prompt guard mirrors Vibe's own
   resolution order — so a skipped step surfaces at the boundary, where it
   is cheap, rather than at the compaction, where it is a lost task.

## Memory

Vibe has no native memory system; durable learnings ride
[gitlore](https://github.com/ddaanet/gitlore), which publishes memory
through git. The boundary's memory directive points at gitlore's
`gitlore:commit` skill when the repo's `gitlore-memory` submodule is
dirty. For that line to be actionable, gitlore must be
installed under Vibe: symlink it into the plugins directory —

```
mkdir -p ~/.vibe/plugins
ln -s ~/.claude/plugins/cache/ddaanet/gitlore/<version> ~/.vibe/plugins/gitlore
```

Vibe's foreign-format adapter imports gitlore's skills and exposes them
under their plugin namespace, so the directive's `gitlore:commit` names the
same skill the session sees. Without the plugin installed, the boundary
still prints its directive and the memory stays dirty until committed by
hand.

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
- **Updates**: reinstalling the directory replaces everything; the frame
  files in your project are kept as they are. The project-local compaction
  prompt is outside the plugin directory: after updating, re-copy
  `prompts/compaction.md` over `.vibe/prompts/handoff-compact.md`, or the
  summary runs under the old wording.
