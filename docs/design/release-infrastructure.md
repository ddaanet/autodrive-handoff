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

The native Vibe tree (`vibe-plugin/`) is part of the same plugin and
ships under the same version. The coupling is one-way enforced where it
can be: the toolkit's `release` recipe bumps only the Claude manifest,
so the release sequence is `just release <tier>` with tier one of
`patch|minor|major` (commits, tags, pushes),
then a `vibe-plugin/plugin.json` sync commit bumping it to the version
`just release <tier>` wrote —
plain tree state, no recipe to widen. Between the two commits the
manifests legitimately disagree, and `check-versions` (uncached, in
`precommit`) refuses any commit outside that window whose manifests
disagree: with both files present and equal at the sync commit, the gate
is green, and a hand edit of one manifest alone cannot pass any other
commit. The release acts stay decoupled — and the tag + GH release +
marketplace bump run for the Claude surface only, since Vibe has no
marketplace; its install is the documented per-consumer copy.

There is no Vibe-side version guard hook: the toolkit's
`version-guard.sh` is a Claude `PreToolUse` hook the toolkit ships and
guards the Claude manifest; Vibe exposes `pre_tool`/`post_tool` — a real
surface the port leaves unused until something needs it — and a mirror
guard there would refuse the coupled bump the policy requires. The
coupling is enforced where both agents meet: the gate.

Updates: `just update-plugin-dev dist-vX.Y.Z` (recipe imported from
`release.just`; it refuses the bare `vX.Y.Z` source tag).
