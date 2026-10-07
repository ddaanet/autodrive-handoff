# claude-plugin-dev

Shared development tooling for Claude Code plugins. Vendored into each consumer
plugin via `git subtree` so the release infra is versioned with the repo (CI,
fresh clones, and old tags all reproduce without depending on contributor-side
dotfiles).

## Contents

- **`release.just`** — the recipes imported into the consumer's `justfile`:
  `release`, `resume-release`, `check-version`, `update-plugin-dev` and
  `dogfood`. All are one-line wrappers: `release` and `resume-release` around
  `release.sh`, `update-plugin-dev` around `update.sh`, `dogfood` around
  `dogfood.sh sync`.
- **`update.sh`** — pulls a newer toolkit version into the consumer. With no ref
  it resolves the newest `dist-` tag from the remote. After the pull it prints
  the migration notes for every version crossed — guidance to apply by hand; an
  update never edits files outside `plugin-dev/`.
- **`release.sh`** — the release flow itself. Validates state, bumps
  `.claude-plugin/plugin.json`, commits, tags, pushes, creates a GitHub release,
  and bumps (or creates) the plugin's entry in `marketplace.json`. Its
  `--resume` mode completes a release that landed only partially — a rejected
  push, a failed `gh` call — by probing what already happened and doing only
  what is missing. It is a no-op that says so when everything already landed.
- **`check-version.sh`** — compares `plugin.json`'s version against the plugin's
  `marketplace.json` entry. Exposed as `just check-version` and run as a
  `release` pre-flight, so a release refuses to start on top of a previous one
  that never finished.
- **`version-guard.sh`** — `PreToolUse(Write|Edit)` hook. Refuses agent edits
  that change `.claude-plugin/plugin.json`'s `.version`. Once a plugin has
  released, the release recipe owns version bumps; a manual edit desyncs the
  manifest from the `vX.Y.Z` tag and only gets caught at release time. A first
  release is the exception the Conventions below spell out, and the hook refuses
  an agent's edit there too.
- **`dogfood.sh`** — the dogfood launcher's script, with three subcommands.
  `sync` mirrors the plugin tree, minus git-ignored paths and `.git`, into
  `dist/plugin/`. `pre-tool` is the `PreToolUse` hook that refuses edits into
  that copy, and `session-start` the `SessionStart` hook that warns when a
  session does not load it. See [Dogfooding](#dogfooding).
- **`bin/claude`** — the dogfood shim. First on PATH, it points
  `CLAUDE_CODE_PLUGIN_DIRS` at `dist/plugin/` and execs the next `claude` on
  PATH. It never syncs; while the copy is missing it warns and launches without
  it.
- **`install.sh`** — one-shot install script: vendors the toolkit (resolving the
  newest `dist-` tag when no ref is given), inserts the justfile import line,
  and wires the version-guard hook and the two dogfood hooks into
  `.claude/settings.json`. Idempotent.

## Versioning

Each release cuts **two** tags. `vX.Y.Z` is the source tag; `dist-vX.Y.Z` is
what consumers vendor — a `git subtree split --prefix=toolkit` of the same
commit, so its root tree is only the consumer-facing files. Vendoring a source
tag would copy this repo's whole working environment (its `memory` submodule,
`.claude/`, `CLAUDE.md`, its own justfile) into the plugin, so both `install.sh`
and `update-plugin-dev` refuse a `vX.Y.Z` ref and name the `dist-` one instead.

**Always pin to a tag.** Tracking `main` defeats reproducibility — a consumer
plugin's old git tags should still resolve to the exact toolkit content that was
vendored at the time.

## Installing in a plugin

Resolve the newest **dist** tag, fetch that tag's `install.sh`, and run it from
the plugin's root directory:

```sh
repo=ddaanet/claude-plugin-dev
cd /path/to/your/plugin
tag=$(git ls-remote --tags --refs --sort=-v:refname \
        "https://github.com/$repo.git" 'dist-v*' | head -1 | sed 's|.*/||')
curl -fsSL "https://raw.githubusercontent.com/$repo/$tag/install.sh" \
    | bash -s -- "$tag"
```

A `dist-` tag's root tree *is* `toolkit/`, so that URL serves the same
`install.sh` the plugin is about to vendor, at the same ref. Handing the
resolved tag to the script keeps the two in lockstep and saves it a second
`ls-remote`.

This block never names a version, so it cannot go stale. To pin an older
version, substitute its dist tag in both places. The first install needs `curl`;
nothing else here does.

`install.sh` does three things:

1. `git subtree add --prefix=plugin-dev … dist-vX.Y.Z --squash` (vendors the
   toolkit at the resolved or given dist tag).
2. Adds `import 'plugin-dev/release.just'` to the plugin's `justfile` (creating
   one if absent).
3. Wires the version-guard hook and the two dogfood hooks, the `PreToolUse` copy
   guard and the `SessionStart` check, into `.claude/settings.json`.

It's idempotent — re-running with everything already in place is a no-op. The
vendored copy at `plugin-dev/install.sh` can be re-run after clone or after
wiring drift to repair the wiring without re-vendoring.

Then define two project-specific recipes in `justfile`: `precommit`, your commit
gate, and `prerelease`, the gate `release` depends on.

```just
import 'plugin-dev/release.just'

precommit:
    jq . .claude-plugin/plugin.json > /dev/null
    bash -n scripts/*.sh
    # ...whatever else your plugin needs...

prerelease: precommit
```

For most plugins the two gates are the same and `prerelease: precommit` is the
whole recipe. If your release gate is bigger — slow or paid checks you don't
want on every commit — widen it there:

```just
evals:
    make evals      # slow, paid; not part of precommit

prerelease: precommit evals
```

`prerelease` is mandatory. just rejects a justfile whose dependency names a
recipe that doesn't exist, so omitting it fails every recipe immediately with
`unknown dependency prerelease` — not silently at release time.

Commit:

```sh
git add plugin-dev justfile .claude/settings.json
git commit -m "add claude-plugin-dev toolkit"
```

Then follow [Dogfooding](#dogfooding) → [Setup](#setup), which ends with a
first `just dogfood`. The `SessionStart` hook the install wired warns on every
session until the shim is on PATH, the sync refuses to run until git ignores the
copy, and a launch before `just dogfood` has created it starts without the
plugin and says so.

## Updating in a plugin

```sh
just update-plugin-dev                 # newest dist tag on the remote
just update-plugin-dev dist-vX.Y.Z     # or pin one
```

To see what is available:

```sh
git ls-remote --tags --refs --sort=-v:refname \
    git@github.com:ddaanet/claude-plugin-dev.git 'dist-v*'
```

This wraps `git subtree pull` with the prefix and URL baked in. It rejects a
dirty tree, refuses a source (`vX.Y.Z`) ref naming the `dist-` one to use
instead, and refuses anything else — a branch, a sha, `main` — since only the
dist lineage carries the consumer-facing files.

A release that needs a consumer-side step (say, a new required justfile recipe)
ships a note at `plugin-dev/migrations/vX.Y.Z.md`. After the pull, every note in
the crossed version range is printed. Apply them by hand: the update itself
never edits files outside `plugin-dev/`.

**Then run `just --list` before considering the pull done.** A toolkit version
that requires a consumer-side change — the `prerelease` recipe was one — makes
`just` refuse to compile *any* recipe, so nothing in your justfile works and
nothing announces it. The breakage surfaces at the next unrelated recipe run,
which may be days later and will look unrelated to the update. A note is
optional per release, so this check stands whether or not one was printed.

Land the consumer-side fix as its own commit, separate from the subtree-pull
merge commit. The merge is toolkit content; the fix is your plugin's own.

A plugin vendored before dist refs existed carries the toolkit's leaked working
environment under `plugin-dev/` — most visibly a `plugin-dev/memory` gitlink
that makes a bare `git submodule status` fail for the whole repo. No manual
cleanup is needed: the first pull of a `dist-` tag deletes all of it in the same
commit.

## Dogfooding

Claude Code treats every file under a loaded plugin root as sensitive, so a
session that loads the plugin from its own working tree asks before each agent
edit to it, and runs a half-edited hook script in the session editing it. The
dogfood launcher loads the plugin from a copy at `dist/plugin/` instead. Agents
edit the source; the copy changes only when you promote it.

A plugin that vendored the toolkit before the launcher shipped takes the steps
in `plugin-dev/migrations/v0.9.0.md`. They include re-running `install.sh`,
which `update-plugin-dev` does not do. From 0.9.1 a launch no longer syncs, so a
plugin coming from before 0.9.1 runs `just dogfood` before its next launch.

### Setup

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

### Launching

Launch `claude` from the repo root. The shim execs the next `claude` on PATH
with its arguments unchanged and `CLAUDE_CODE_PLUGIN_DIRS` set to
`<root>/dist/plugin`, replacing any inherited value. It never syncs: a launch, a
`claude -c` relaunch or any other `claude` you run in the repo loads the copy as
it stands. With no other `claude` on PATH the shim exits 127.

With no copy, the shim says so on one line, leaves `CLAUDE_CODE_PLUGIN_DIRS` as
it found it, and launches anyway:

```text
dogfood: no copy at <root>/dist/plugin, so claude starts without it; run just dogfood to create it
```

That session does not load the copy, and the `SessionStart` check says so. Run
`just dogfood`, then relaunch.

From a subdirectory the session still loads the copy, but no project hook fires:
Claude Code reads `.claude/settings.json` from the launch directory only. That
session runs without the copy guard, the `SessionStart` check and the
version-guard, and nothing reports their absence.

### Promoting changes

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
  `just dogfood`, exit and relaunch through the shim; `claude -c` keeps the
  conversation.
- **Commands** — read at session start, so a relaunch after `just dogfood` makes
  them live. Whether `/reload-plugins` does too is unverified.
- **`.mcp.json` and output styles** — whether `/reload-plugins` picks them up is
  unverified. A relaunch after `just dogfood` does, since it re-reads everything
  Claude Code reads at start.

The sync copies everything git does not ignore, tracked or not, minus every
`.git` and `dist/plugin/` itself, and deletes from the copy what left the
source. It refuses to run without `.claude-plugin/plugin.json` at the root, when
git does not ignore `dist/plugin/`, and when an ignored path's name holds `*`,
`?`, `[`, `]` or a backslash, naming that path, and without `rsync` on PATH;
each refusal leaves `dist/` untouched. rsync's own errors are shown as they
come, and a failure exits non-zero. A file vanishing mid-sync, or two syncs
colliding, fails the same way; a re-run repairs it.

Run `just dogfood` from your own shell, not through an agent's Bash tool,
whether or not your plugin ships a `.mcp.json`. The command sandbox masks a set
of dotfiles in the project root, `.mcp.json` among them, and a sandboxed sync
does not skip the masks. A character-device mask makes rsync warn
`skipping non-regular file` and keep the copy's old `.mcp.json`, so a changed
MCP config goes stale. A zero-byte mask is copied as an empty file, which puts
an empty `.mcp.json` into the copy of a plugin that ships none; it stays until
the next sync from your shell deletes it, and how Claude Code reads an empty
`.mcp.json` is unverified. The shim never syncs, so a launch is unaffected.

### Hooks

`install.sh` wires two dogfood hooks into `.claude/settings.json`, beside the
version-guard:

- **Copy guard** — `PreToolUse` on `Write|Edit|NotebookEdit`. Refuses an edit
  into `dist/plugin/`, a spelling through a symlink included, and gives the
  agent the source path to edit instead. A Bash write into the copy passes it,
  and the next sync overwrites or deletes that write.
- **Session check** — `SessionStart`. Silent when all is well; otherwise it
  prints one of two warnings:

  ```text
  dogfood: this session does not load <root>/dist/plugin — launch claude through plugin-dev/bin/claude from the repo root
  dogfood: jq is not on PATH, so the copy guard and this check are off until it is installed
  ```

  The first means the session started through the shim with no copy, or past
  the shim (no direnv, an IDE or the desktop app, an absolute path to
  `claude`), or inherited another repo's `CLAUDE_CODE_PLUGIN_DIRS`, as a
  `claude` started from another plugin's dogfood session does. The agent is
  told the same, as a fact. After the second, Claude Code's own sensitive-file
  prompt still stops a copy edit.

## Conventions

- Release commit message: `release: X.Y.Z` (the gitmoji hook maps it to
  `🔖 X.Y.Z`).
- Plugin manifest holds the **last released** version. `just release` bumps from
  there. Manual edits are blocked by the version-guard hook and the release
  recipe's own pre-flight check.
- A plugin that has never been released has nothing to bump from, so its
  **first** `just release` — with no bump argument — publishes the version
  `plugin.json` already holds. That state is detected by tag alone: no `vX.Y.Z`
  tag exists here or on origin. The marketplace entry plays no part, so a plugin
  already listed there can still take its first release. The version published
  is usually whatever `/plugin-dev:create-plugin` seeded into the manifest; to
  ship a different one, set `.version` and **commit** that edit before releasing
  — `.claude-plugin/` is not exempt from the clean-tree check. That edit is the
  maintainer's to make, and the one the version-guard hook refuses from an
  agent. Passing a bump on a first release is refused. Afterwards the
  last-released rule above applies as normal.
- Default branch is auto-detected from `origin/HEAD`; recipes don't hardcode
  `main`.
- The version-guard hook fires on Write/Edit events targeting
  `.claude-plugin/plugin.json` and is a no-op outside plugin repositories (no
  manifest, no fire).

## Requirements

`bash`, `jq`, `git`, `gh`, `rsync`.

## License

MIT
