# claude-plugin-dev

Shared development tooling for Claude Code plugins. Vendored into each consumer
plugin via `git subtree` so the release infra is versioned with the repo (CI,
fresh clones, and old tags all reproduce without depending on contributor-side
dotfiles).

## Contents

- **`release.just`** — the recipes imported into the consumer's `justfile`:
  `release`, `resume-release`, `check-version`, `check-refs`,
  `update-plugin-dev` and `dogfood`. All are one-line wrappers: `release` and
  `resume-release` around `release.sh`, `check-refs` around `check-refs.sh`,
  `update-plugin-dev` around `update.sh`, `dogfood` around `dogfood.sh sync`.
- **`update.sh`** — pulls a newer toolkit version into the consumer. With no ref
  it resolves the newest `dist-` tag from the remote. After the pull it prints
  the migration notes for every version crossed — guidance to apply by hand; an
  update never edits files outside `plugin-dev/`.
- **`release.sh`** — the release flow itself. Validates state, bumps
  `.claude-plugin/plugin.json`, commits, tags, pushes, creates a GitHub release,
  and bumps (or creates) the plugin's entry in `marketplace.json`. A plugin with
  a `dist.include` also publishes its `dist` branch. Its
  `--resume` mode completes a release that landed only partially — a rejected
  push, a failed `gh` call — by probing what already happened and doing only
  what is missing. It is a no-op that says so when everything already landed.
  Its steps live in four `release-*.sh` files beside it, which it sources;
  they are not run on their own.
- **`dist.sh`** — the dist branch's script, used by `release.sh` and
  `dogfood.sh`. It reads `dist.include` and builds, checks, validates and
  commits the tree holding only the listed paths. Not opted in, it does
  nothing. See [The dist branch](#the-dist-branch).
- **`check-refs.sh`** — refuses a Markdown link whose target is missing, and,
  with a `dist.include`, one from a shipped file to an unshipped one. Run from
  `precommit`; the dist build runs it again on the tree it builds. Its parser
  lives in `check-refs-parse.sh` beside it, which it sources. See
  [Reference check](#reference-check).
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
  `sync` mirrors the plugin tree (only the `dist.include` paths, where the
  plugin has one), minus git-ignored paths (a submodule's own ignores included)
  and `.git`, into `dist/plugin/`. `pre-tool` is the
  `PreToolUse` hook that refuses edits into that copy, and `session-start` the
  `SessionStart` hook that warns when a session does not load it. See
  [Dogfooding](#dogfooding).
- **`bin/claude`** — the dogfood shim. First on PATH, it points
  `CLAUDE_CODE_PLUGIN_DIRS` at `dist/plugin/`, appends the copy's `bin/` to
  PATH, and execs the next `claude` on PATH. It never syncs, and sets both
  whether or not the copy exists yet: `/reload-plugins` loads one made later.
  It never warns about a missing copy; the `SessionStart` check does.
- **`gates.just`** — opt-in, imported beside `release.just`. Defines the prolog
  that turns a gate recipe into one that skips itself while the files it reads
  are unchanged. See [Gate sentinels](#gate-sentinels).
- **`run-bats.sh`** — opt-in quiet runner for `bats`: failures and a pass count
  instead of the TAP stream.
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

The hook commands double-quote `${CLAUDE_PROJECT_DIR}`, so a plugin checked out
under a path with a space still runs them. Earlier releases wrote the
version-guard command unquoted, and Claude Code treats the failure of that
command as a non-blocking error: the guard failed open, silently. A re-run
rewrites that entry to the quoted form in place, under whatever matcher you gave
it, and reports `version-guard hook requoted`. `update-plugin-dev` does not
re-run the installer, so a plugin vendored before the change gets the fix by
running `bash plugin-dev/install.sh` once, from your own shell.

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

Then follow [Dogfooding](#dogfooding) → [Setup](manual/dogfood.md#setup), which
ends with a first `just dogfood`. The `SessionStart` hook the install wired
warns on every session until the shim is on PATH, the sync refuses to run until
git ignores the copy, and a launch before `just dogfood` has created it starts
without the plugin and says so.

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

## The dist branch

A plugin that lists its shipped paths in a `dist.include` at its root has each
release publish a `dist` branch holding only those paths, plus a `dist-vX.Y.Z`
tag, and its marketplace entry follows that branch. Nothing changes for a
plugin without one. How to opt in, and what each check refuses or warns about,
is in [manual/dist-branch.md](manual/dist-branch.md).

## Reference check

`just check-refs` refuses a broken Markdown reference: a link, image or
reference definition, `[text](target)`, `![alt](target)` or `[label]: target`,
whose relative target, resolved beside the file that holds it, is not a file
git lists (tracked, or untracked and not ignored) or a directory holding one.
An ignored target is refused, a target above the repository root too, and the
match is exact-case even on a case-insensitive disk. Links with a scheme, pure
`#anchors`, root `/paths`, fenced code, inline code spans and HTML comments are
not checked, and neither are backticked paths. It reads every Markdown file on
disk that git does not ignore, tracked or not, apart from `plugin-dev/` and
submodules. Wire it into the commit gate as a dependency, so it runs on every
call, ahead of any gate guard:

```just
precommit: check-refs
```

Files under `docs/changelog/` and `plans/` are exempt, since a dated record's
link to a file deleted later is still true. A `refs.exempt` at the root, one
path per line with `#` comments, replaces that list; an empty one exempts
nothing.

With a `dist.include`, a link from a shipped file must also reach a shipped file
that exists, exempt or not: the `dist` tree holds only the listed paths, and
anything else dangles there. List the target in `dist.include`, or drop the
link. `dist.sh` checks the tree it builds from the release commit as well, and
the two differ in one case: a link to an untracked file passes `precommit`,
which lets you link a file before adding it, and the release refuses it until
it is committed. `plugin-dev/check-refs.sh --shipped
<path>...` checks against the given paths instead of `dist.include`.

Each broken reference is one line on stderr, `docs/a.md:12: target — reason`,
and the exit is 1. A pass prints one line with the counts.

## Gate sentinels

Optional. A gate recipe that opens with the prolog from `gates.just` skips
itself when the files it reads are unchanged, and `run-bats.sh` prints a bats
run as failures and a count. A plugin that imports neither is unaffected, and
the `precommit` and `prerelease` contract does not change. How to choose the
inputs so a cached pass stays true, and how to convert an existing `precommit`,
is in [manual/gates.md](manual/gates.md) and
`plugin-dev/migrations/v0.11.0.md`.

## Dogfooding

A session that loads the plugin from its own working tree asks before each agent
edit to it, so the dogfood launcher loads the plugin from a copy at
`dist/plugin/` instead: agents edit the source, and the copy changes only when
you run `just dogfood`. Setting up the shim and the copy, launching, what each
kind of change needs to go live, and the two dogfood hooks are in
[manual/dogfood.md](manual/dogfood.md), whose [Setup](manual/dogfood.md#setup) is the
first step after an install. A plugin that vendored the toolkit before the
launcher shipped takes the steps in `plugin-dev/migrations/v0.9.0.md`.

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
  — the clean-tree check refuses a dirty manifest. That edit is the
  maintainer's to make, and the one the version-guard hook refuses from an
  agent. Passing a bump on a first release is refused. Afterwards the
  last-released rule above applies as normal.
- An agent issues `just release` and `just resume-release` **bare**: alone in
  the Bash call, with no `cd … &&` prefix and no trailing `; echo`. Both write
  the marketplace checkout and push, which the command sandbox blocks, so list
  `"just release *"` and `"just resume-release *"` in `sandbox.excludedCommands`.
  A compound call is not covered by the entry and stays sandboxed, and under
  auto mode the `dangerouslyDisableSandbox` flag gets the call denied.
- Default branch is auto-detected from `origin/HEAD`; recipes don't hardcode
  `main`.
- The version-guard hook fires on Write/Edit events targeting
  `.claude-plugin/plugin.json` and is a no-op outside plugin repositories (no
  manifest, no fire).

## Requirements

`bash`, `jq`, `git`, `gh`, `rsync`; `claude` on PATH for a plugin that publishes a `dist` branch.

## License

MIT
