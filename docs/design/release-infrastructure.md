# Release infrastructure delegated to claude-plugin-dev

Part of [handoff — Design](../design.md).

The `release` recipe and the `version-guard.sh` PreToolUse hook live
in the [claude-plugin-dev](https://github.com/ddaanet/claude-plugin-dev)
toolkit, vendored at `plugin-dev/` via `git subtree`. Rationale:

- The release dance — clean-tree check, version bump, tag, push, GH
  release, marketplace bump, plus a guard that refuses agent-driven
  version edits — is identical across every plugin we ship. Inlining
  it in each consumer's justfile produces drift; vendoring the source
  of truth keeps the contract one file.
- `git subtree --squash` rather than a submodule keeps the toolkit
  files visible in this repo's tree (no extra clone, no fragile
  pointer), and pinning to a tag makes upgrades explicit — the pinned
  version is `plugin-dev/VERSION`, which is the vendored tree's own record
  of it rather than a copy here that would rot at the next update.
- The toolkit's `release.just` requires consumers to define two
  recipes: `precommit`, the per-plugin checks that must pass before
  every commit, and `prerelease`, the gate `release` actually depends
  on. handoff's `precommit` lints its own manifests, syntax-checks
  scripts, and runs the handoff-specific hook + pytest suites, then the
  toolkit's `check-refs`, `check-size` and `check-frontmatter`, the second
  reading the root `size.exempt` for the files kept over its byte caps and the
  third refusing a skill whose frontmatter is not YAML; its
  `prerelease` is exactly `precommit`. The indirection exists so a
  plugin whose release gate is wider than its commit gate — slow or
  paid checks — can widen `prerelease` without slowing every commit.
- The release recipe also bumps the plugin's entry in the sibling
  `claude-plugins` marketplace repo (path from `$MARKETPLACE_DIR`,
  set in `~/code/.envrc`, which this repo's `.envrc` pulls in with
  `source_up_if_exists`) and pushes that repo. A tag without a marketplace
  bump is invisible to end-users, so the recipe treats both pushes as
  one atomic release.

## The Vibe surface and the coupled version

The native Vibe tree (`vibe-plugin/`) is part of the same plugin, but the
two surfaces are interdependent and separate: each has its own manifest, and
the tag must carry both at one version. The toolkit's `release` recipe bumps
and tags only the Claude manifest, so the Vibe manifest is bumped in its own
commit *before* the release: `vibe-plugin/plugin.json` moves to the version
the coming `just release <tier>` (tier one of `patch|minor|major`) will
write, then the release runs. Its bump commit brings the Claude manifest to
the Vibe one, and that commit is what gets tagged, so the tag carries both
manifests at one version and nothing lags behind a release.

`check-versions` (uncached, in `precommit`) accepts the Vibe version equal
to the Claude one, or exactly one patch (X.Y.Z to X.Y.(Z+1)), minor
(X.(Y+1).0) or major ((X+1).0.0) bump ahead of it, and prints which relation
held with both versions. It refuses everything else, naming both versions:
Vibe behind, Claude ahead, two bumps, a skipped component such as 0.23.1 to
0.24.1, a non-semver version. The release's own gate (`prerelease` is
`precommit`) runs before the bump, with Vibe one bump ahead, and passes. The
release does not re-run the gate on its bump commit, so a Vibe bump of a
different tier than the release's goes untested: the tag would carry
mismatched manifests. The release acts stay decoupled: the tag + GH release +
marketplace bump run for the Claude surface only, since Vibe has no
marketplace; its install is the documented per-consumer copy.

There is no Vibe-side version guard hook: the toolkit's
`version-guard.sh` is a Claude `PreToolUse` hook the toolkit ships and
guards the Claude manifest; Vibe exposes `pre_tool`/`post_tool` — a real
surface the port leaves unused until something needs it — and a mirror
guard there would refuse the early Vibe bump the policy requires. The
coupling is enforced where both agents meet: the gate.

Updates: `just update-plugin-dev dist-vX.Y.Z` (recipe imported from
`release.just`; it refuses the bare `vX.Y.Z` source tag).
