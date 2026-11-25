#!/usr/bin/env bash
# Uncached precommit check: the two manifests carry the same version.
#
# The Claude manifest (.claude-plugin/plugin.json) is bumped by the toolkit's
# `release` recipe; the Vibe manifest (vibe-plugin/plugin.json) is bumped by a
# sync commit right after the release (the recipe knows only the Claude
# manifest, and the release policy couples the versions — see
# docs/design/release-infrastructure.md and docs/design/decisions.md). This
# check enforces that coupling on every commit: it refuses when the manifests
# disagree, which is exactly the state between a release and its sync commit —
# and green again on the sync commit itself, since the gate reads the tree the
# commit is about to make.
#
# Both manifests are required. The check is repo-local (unlike the toolkit's
# guards), so a missing file is an error, not a benign absence: this plugin
# ships both surfaces.
set -euo pipefail

root="${1:-.}"

read_version() {
    jq -r '.version // empty' "$1"
}

fail() {
    printf 'check-versions: %s\n' "$1" >&2
    exit 1
}

claude_manifest="$root/.claude-plugin/plugin.json"
vibe_manifest="$root/vibe-plugin/plugin.json"

[[ -f "$claude_manifest" ]] || fail "missing $claude_manifest (run from the repo root)"
[[ -f "$vibe_manifest" ]] || fail "missing $vibe_manifest (run from the repo root)"

claude_version="$(read_version "$claude_manifest")"
[[ -n "$claude_version" ]] || fail "unparseable or empty .version in $claude_manifest"
vibe_version="$(read_version "$vibe_manifest")"
[[ -n "$vibe_version" ]] || fail "unparseable or empty .version in $vibe_manifest"

if [[ "$claude_version" == "$vibe_version" ]]; then
    printf 'check-versions: %s == %s == %s\n' "$claude_manifest" "$vibe_manifest" "$claude_version"
    exit 0
fi
fail "manifest versions disagree: $claude_manifest $claude_version, $vibe_manifest $vibe_version — bump the Vibe manifest in the post-release sync commit"
