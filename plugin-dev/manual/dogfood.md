# Dogfooding

Part of the claude-plugin-dev manual; [README.md](../README.md) is the rest.

Claude Code treats every file under a loaded plugin root as sensitive, so a
session that loads the plugin from its own working tree asks before each agent
edit to it, and runs a half-edited hook script in the session editing it. The
dogfood launcher loads the plugin from a copy at `dist/plugin/` instead. Agents
edit the source; the copy changes only when you promote it.

A plugin that vendored the toolkit before the launcher shipped takes the steps
in `plugin-dev/migrations/v0.9.0.md`. They include re-running `install.sh`,
which `update-plugin-dev` does not do. From 0.9.1 a launch no longer syncs, so a
plugin coming from before 0.9.1 runs `just dogfood` before its next launch.

#### Setup

Put the shim on PATH as the last `PATH_add` in `.envrc`, after gitlore's
`PATH_add .gitlore/bin`, so it is the `claude` found first:

```sh
PATH_add plugin-dev/bin
```

Then run `direnv allow`. Ignore the copy in `.gitignore`; the sync refuses to
run until git ignores it:

```gitignore
/dist/plugin/
```

If a `clean` recipe deletes `dist/`, make it spare `dist/plugin/`: a live
session loads its skills and hooks from there.

Create the copy before the first launch:

```sh
just dogfood
```

#### Launching

Launch `claude` from the repo root. The shim execs the next `claude` on PATH
with its arguments unchanged and `CLAUDE_CODE_PLUGIN_DIRS` set to
`<root>/dist/plugin`, replacing any inherited value. It never syncs: a launch, a
`claude -c` relaunch or any other `claude` you run in the repo loads the copy as
it stands. With no other `claude` on PATH the shim exits 127.

The shim also appends `<root>/dist/plugin/bin` to PATH, after your entries,
whether or not the copy or its `bin/` exists yet. A marketplace install puts a
plugin's `bin/` on the Bash tool's PATH and a `CLAUDE_CODE_PLUGIN_DIRS` load
does not, so without this a command your plugin ships for agents' Bash would
work only after a release. It is appended, not prepended, because a released
plugin's `bin/` cannot shadow system commands either. The entry is not
deduplicated: a repeat on PATH is harmless.

One divergence from the release: the shim sets PATH on the `claude` process, so
hooks, MCP servers and plugin agents inherit the directory too, while a
marketplace install is only known to put `bin/` on the Bash tool's PATH. A hook
that calls a bare `bin/` command works in dogfood and may fail once released.
Hooks should find their scripts by `${CLAUDE_PLUGIN_ROOT}` or `$0`, never
through `bin/`.

With no copy the shim sets the same variable and launches silently: Claude Code
starts with a plugin directory that does not exist yet, and the `SessionStart`
check says so. Run `just dogfood` in that session, then `/reload-plugins`; no
relaunch is needed. That was verified headless; the interactive command was not
run. Until then `/plugin` lists the missing directory under Errors, and
`/reload-plugins` reports one load error.

From a subdirectory the session still loads the copy, but no project hook fires:
Claude Code reads `.claude/settings.json` from the launch directory only. That
session runs without the copy guard, the `SessionStart` check and the
version-guard, and nothing reports their absence.

#### Promoting changes

The copy lags the source by design. A session runs what was last promoted, not
the working tree, and a Read of a path under `dist/plugin/` returns the promoted
content. Only `just dogfood` promotes; a launch or relaunch does not:

```sh
just dogfood
```

It syncs and nothing else: it starts no `claude` and runs no gate. What goes
live then depends on what changed:

- **Hook scripts and `bin/` files** — at once, in every live session in the
  repo, since Claude Code reads them on each call.
- **Skill bodies** — after `/reload-plugins` in the session.
- **Agent definitions and hook events** — only in a new session. After
  `just dogfood`, exit and relaunch `claude`; `claude -c` keeps the
  conversation.
- **Commands, `.mcp.json` and output styles** — after `/reload-plugins` in the
  session, like skill bodies: a changed or new command, the plugin's MCP
  servers and a style's body (from the next turn) all go live. A relaunch after
  `just dogfood` does too, since it re-reads everything Claude Code reads at
  start.

The sync copies everything git does not ignore, tracked or not, minus every
`.git` and `dist/plugin/` itself, and deletes from the copy what left the
source. What an initialised submodule ignores through its own rules stays out
too. It refuses to run without `.claude-plugin/plugin.json` at the root, when
git does not ignore `dist/plugin/`, and when an ignored path's name holds `*`,
`?`, `[`, `]` or a backslash, naming that path, and without `rsync` on PATH;
each refusal leaves `dist/` untouched. A git error listing the root or an
initialised submodule stops the sync with git's own message, `dist/` untouched.
rsync's own errors are shown as they come, and a failure exits non-zero. A file
vanishing mid-sync, or two syncs colliding, fails the same way; a re-run
repairs it.

Run `just dogfood` from your own shell, not through an agent's Bash tool,
whether or not your plugin ships a `.mcp.json`. The command sandbox masks a set
of dotfiles in the project root, `.mcp.json` among them, and a sandboxed sync
does not skip the masks. A character-device mask makes rsync warn
`skipping non-regular file` and keep the copy's old `.mcp.json`, so a changed
MCP config goes stale. A zero-byte mask is copied as an empty file, which puts
an empty `.mcp.json` into the copy of a plugin that ships none; it stays until
the next sync from your shell deletes it. Claude Code loads the plugin
regardless, ignores the file and reports nothing in the session, though
`claude plugin validate` on the copy fails on it. The shim never syncs, so a
launch is unaffected.

#### Hooks

`install.sh` wires two dogfood hooks into `.claude/settings.json`, beside the
version-guard:

- **Copy guard** — `PreToolUse` on `Write|Edit|NotebookEdit`. Refuses an edit
  into `dist/plugin/`, a spelling through a symlink included, and gives the
  agent the source path to edit instead. A Bash write into the copy passes it,
  and the next sync overwrites or deletes that write.
- **Session check** — `SessionStart`. Silent when the session loads the copy and
  the copy is a directory; otherwise it prints one of four warnings:

  ```text
  dogfood: no copy at <root>/dist/plugin yet; run just dogfood to create it, then /reload-plugins, no relaunch needed
  dogfood: no copy at <root>/dist/plugin, so this session does not load it; run just dogfood to create it, then direnv allow in <root> and relaunch claude from a shell there
  dogfood: this session does not load <root>/dist/plugin; run direnv allow in <root>, then relaunch claude from a shell there
  dogfood: jq is not on PATH, so the copy guard and this check are off until it is installed
  ```

  The first means the session was launched through the shim before any
  `just dogfood`, or a regular file sits where the copy belongs. It names the
  copy, so `/reload-plugins` loads it once made. The second means there is no
  copy and the session started past the shim. The third means the copy exists
  but the session started past the shim (no direnv, an IDE or the desktop app,
  an absolute path to `claude`), or inherited another repo's
  `CLAUDE_CODE_PLUGIN_DIRS`, as a `claude` started from another plugin's
  dogfood session does. `direnv allow` loads the `.envrc` that puts the shim
  first on PATH. The agent never sees these lines: it gets the finding as a
  fact with no command to run, and nothing for the fourth. After the fourth,
  Claude Code's
  own sensitive-file prompt still stops a copy edit.
