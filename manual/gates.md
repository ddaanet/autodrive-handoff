# Gate sentinels and the quiet bats runner

Part of the claude-plugin-dev manual; [README.md](../README.md) is the rest.

Two opt-in pieces for a plugin's own `precommit`: sentinels that let a gate skip
itself when nothing it reads has changed, and a bats runner that prints failures
and a count instead of the whole TAP stream. A plugin that imports neither is
unaffected, and `release.just`, `precommit` and `prerelease` keep their
contract: `release` still depends on `prerelease`, which is still yours.

To convert an existing plugin, follow
[`plugin-dev/migrations/v0.11.0.md`](../migrations/v0.11.0.md). This chapter is
the reference behind it.

## The sentinel

A gate is a pure function of its inputs, so running it again over a tree it just
passed only reprints the verdict. A gate recipe opens with `sentinel-guard`,
which hashes the files it names and, when the hash equals the one recorded by
the last pass, prints `<gate>: cached (inputs unchanged)` and ends the recipe
with status 0. It ends with `record-sentinel`, which records the hash.

Import the prolog, then make the gate a shebang recipe that interpolates it:

```just
import 'plugin-dev/release.just'
import 'plugin-dev/gates.just'

precommit:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard precommit .claude-plugin hooks scripts tests
    shellcheck scripts/*.sh
    plugin-dev/run-bats.sh tests/*.bats
    record-sentinel

prerelease: precommit
```

A shebang recipe is one bash script run with `set -euo pipefail`, not a line per
command, and just still interpolates `{{ }}` in it. Dependencies
(`precommit: format-docs`) run first, as for any recipe, and every time; a
formatter moves into the body instead, as below.

The sentinel is a file under the gitdir (`git rev-parse --git-path
plugin-dev/gates/<gate>`), so it never shows in `git status` or in its own hash,
and each clone and worktree has its own. The hash covers the names, contents and
execute bits of every non-ignored file matching the pathspecs, tracked or not,
so a rename, a deletion, a `chmod +x` and a brand-new file each count; ignored
files do not. A symlink counts by where it points as well as by what it points
at: the target path joins the hash, and the execute bit and contents of a file
target are followed. Two inputs are always hashed beside the pathspecs you give:
the justfile, since the commands of the gate are part of what it checks, and the
vendored `plugin-dev` tree, so that a toolkit update invalidates every pass.
They are listed apart from your pathspecs, by the absolute paths just reports,
so an exclude of yours never subtracts from them, and a justfile named
`Justfile`, a recipe that runs under `[working-directory]` and a gate in a
module all hash the same two inputs. That needs `gates.just` inside the
repository, as `plugin-dev/` is. A pathspec of yours that matches no file is
refused, so a typo cannot cache forever; an exclude (`:!…`, `:^…`, their `:/`
forms, or `exclude` among the magic words of `:(…)`) has no files of its own and
is not held to it. Pathspecs resolve against the directory the recipe runs in,
as git resolves them: a list of excludes alone subtracts from that directory's
files, so under `[working-directory]` or in a module `':!docs'` lists only the
files below it, and so does `':(top,exclude)docs'`, which anchors the exclude
and not the listing. A gate over the whole repository minus `docs` lists
`:/` beside the exclude: `:/ ':(top,exclude)docs'`, or `:/ ':/!docs'`.

### A formatter in the gate

A formatter that rewrites inputs, run as a dependency, runs on every call,
cached or not. Moved after the guard, it is skipped on a cached run, but its
edits move the inputs away from the hash the guard took, and the pass is not
recorded until a second run finds nothing to format. `hash-sentinel` closes
that: placed after the formatter and before the checks, it re-takes the hash, so
`record-sentinel` records the formatted tree in the same run.

```just
precommit:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard precommit .claude-plugin hooks scripts tests
    just format
    hash-sentinel
    shellcheck scripts/*.sh
    plugin-dev/run-bats.sh tests/*.bats
    record-sentinel
```

The checks still read the tree that is recorded: they start after the re-hash,
and only the formatter saw the tree before it. Nothing but a formatter belongs
between the guard and `hash-sentinel`, since whatever runs there is not vouched
for by the hash recorded. It is refused with no guard before it, and a re-hash
that fails leaves `record-sentinel` refusing the pass as for any hash that
cannot be computed. A cached run skips the formatter too, so list its version
in `PLUGIN_DEV_GATE_TOOLS`: a new release that wraps differently then reruns
the gate instead of leaving the tree as the old one formatted it.

### What is never recorded

`record-sentinel` records the hash taken before the checks ran, by the guard or
by `hash-sentinel`, and records nothing when it cannot vouch for it:

- **The inputs moved during the run** (another session edited one): the recipe
  prints `inputs changed while the checks ran; the pass was NOT recorded` and
  keeps the checks' own verdict, exiting 0 when they passed. Only the sentinel is
  withheld, so the next run does the work again.
- **The hash could not be computed** (a listed tool is missing, an input file
  cannot be read): the checks run,
  the recipe passes, and `could not hash inputs; the pass was NOT recorded` goes
  to stderr. A gate that never caches is slow, not wrong, but the message is how
  you hear that it stopped caching.
- **A check failed**: the recipe ends at the failure, before `record-sentinel`.

### One gate per recipe body

`sentinel-guard` leaves shell variables behind for `record-sentinel`, so a
second guard in the same body would overwrite the first's. The prolog refuses
it (`each gate needs its own recipe`), and `record-sentinel` or `hash-sentinel`
with no guard before it. Split gates into recipes, each with its own guard and its own
pathspecs, and have `precommit` depend on them:

```just
precommit: check-distribution lint
```

### Environment

- `PLUGIN_DEV_GATE_FORCE=1 just precommit` runs the checks whatever the
  sentinels say, and records the result. Use it before a release if you do not
  trust the declared inputs. Any non-empty value forces, `0` included; unset it
  to turn it off.
- `PLUGIN_DEV_GATE_DIR=/some/dir` keeps sentinels there instead of in the
  gitdir. Set it when you run a recipe without meaning its verdict, for example
  a test that drives the real recipe with its checks stubbed: a pass recorded
  from that would overwrite the real one.
- `PLUGIN_DEV_GATE_TOOLS` lists tool versions to fold into the hash; see below.

## Choosing the inputs

The pathspecs are an allow-list you declare. The cache is correct exactly while
**every check in the recipe reads only inside it**. A check that reads a path
the hash ignores can go red because of a file the hash never saw: the commit
that adds the file reports a cached pass, and the failure surfaces days later,
on an unrelated edit that finally moves the hash. Nothing warns about it.

For each check in the recipe, list what it reads, and reconcile that with the
pathspecs:

- **Narrow the check** to the hashed paths, by giving it a path argument or an
  exclude, when it reads a tree you do not mean it to cover. A linter that takes
  no path argument lints the whole project.
- **Widen the pathspecs** when the check exists to read that tree: a bats suite
  over `hooks/` means `hooks` is an input.
- **Split the recipe** when one cheap check reads outside the set of an
  expensive gate. Give it its own recipe and pathspecs, and have the expensive
  one's recipe depend on it. Declare everything *its* check reads, not only the
  paths the other gate misses.

The justfile and `plugin-dev` are inputs of every gate already. A module's own
file is not the justfile: list it. Besides the paths
your checks name, a plugin almost always needs:

- Any justfile the root `justfile` `import`s; the root one is already an input.
- Lockfiles and tool configuration the checks read: `uv.lock`, `pyproject.toml`,
  `package-lock.json`, `.shellcheckrc`, `.gitignore`. `.gitignore` decides which
  untracked files the hash enumerates.
- `.claude-plugin`, and `.claude/settings.json` if a check reads it.
- Test helpers and fixtures, which sit beside the suites that load them.

The hash reads the files on disk, tracked or not, so a check must pick its files
the same way: `git ls-files -co --exclude-standard`, and execute bits from disk
with `[ -x ]`. A check that lists the index (`git ls-files` alone, or `-s`
modes) starts reading a file when it is added, which does not move the hash: a
pass recorded while the file was untracked stays cached, and the file commits
unchecked.

Name the paths; do not hash the whole tree. Naming keeps the sandbox's phantom
home dotfiles, scratch directories and build output out of the hash. The
pathspecs are shell words in the recipe, so a path with whitespace in it needs
quoting, and a pathspec with magic such as `':(exclude)tests/slow/*'` goes in
single quotes so the shell does not glob it first. Written into a just
variable and interpolated, they are split on whitespace instead.

### A gitlink cannot be hashed

A submodule path, such as a gitlore `memory/` mount, is hashed by name only.
`git ls-files` lists the one path and there is nothing to read: neither an edit
inside it nor a new commit of it moves the hash. A check that reads a gitlink,
a memory-hygiene checker for one, would be skipped on exactly the commit that
changes what it reads. Run that check **uncached, ahead of the guard**, in the
same recipe body:

```just
precommit:
    #!{{ plugin_dev_gate_prolog }}
    scripts/check-memory-hygiene.sh
    sentinel-guard precommit .claude-plugin scripts tests
    ...
    record-sentinel
```

The same goes for a check over a tree you left out of the pathspecs on purpose,
`docs/` for a docs-link checker: placed before the guard it runs every time, and
a docs-only commit does not skip it.

### Prove the coverage

Reasoning about the hash is the claim that fails. After wiring a gate:

1. Run it twice and see `<gate>: cached (inputs unchanged)` the second time.
2. Append a throwaway line to a file in each tree the checks read and confirm
   the next run does real work. Remove the line and confirm `git diff` on that
   file is empty.
3. Edit a file in a tree you left out and confirm the gate stays cached.

## Tool versions

A gate is also a function of the tools that run it. A plugin that pins them
(through a lockfile in the pathspecs) needs nothing here. One that does not,
bats and shellcheck installed from the system, folds their versions into the
hash by exporting `PLUGIN_DEV_GATE_TOOLS` from its justfile: one shell command
per line, each printing a version.

```just
export PLUGIN_DEV_GATE_TOOLS := "bats --version\nshellcheck --version\njq --version"
```

Empty by default, so nothing is hashed unless you list it. A listed command
that fails leaves the hash uncomputable, which the run reports as above. List
the tools your checks use and that no lockfile in the pathspecs pins.

## The quiet bats runner

`plugin-dev/run-bats.sh` takes the arguments `bats` takes, except any that
change the output format or print something other than test results, such as
`-p`, `-F` with a formatter other than `tap` or `tap13`, `-c`, `-v` and `-h`: it
reads the TAP stream, and a run with no `ok` or `not ok` line counts as a run of
no test. It runs bats into a log under `$TMPDIR`, prints only the `not ok`
blocks (the whole log when bats failed without one, as when it died before a
plan or a `teardown_file` crashed), then one line, and exits with bats' own
status. A run that exits 0 having run no test, from a `--filter` that matches
nothing or an empty `.bats` file, is a failure: it prints `bats: no tests ran`
and the log, and exits 1. A green run is that line alone and leaves no log:

```text
bats: 412 passed, 0 failed
```

A red run is the failing tests with their diagnostics, and the same line naming
the log it kept:

```text
bats: 411 passed, 1 failed — full log: /tmp/plugin-dev-bats.Ab3dEf
```

Replace direct `bats …` calls in the gate with it. It is independent of the
sentinels: use either alone.
