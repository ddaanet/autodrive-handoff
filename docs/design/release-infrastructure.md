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
  scripts, and runs the handoff-specific hook + pytest suites; its
  `prerelease` is exactly `precommit`. The indirection exists so a
  plugin whose release gate is wider than its commit gate — slow or
  paid checks — can widen `prerelease` without slowing every commit.
- The release recipe also bumps the plugin's entry in the sibling
  `claude-plugins` marketplace repo (path from `$MARKETPLACE_DIR`,
  set in `.envrc`) and pushes that repo. A tag without a marketplace
  bump is invisible to end-users, so the recipe treats both pushes as
  one atomic release.

Updates: `just update-plugin-dev vX.Y.Z` (recipe imported from
`release.just`).
