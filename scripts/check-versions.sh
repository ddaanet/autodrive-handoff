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

main() {
    local root="${1:-.}"
    local claude_manifest="$root/.claude-plugin/plugin.json"
    local vibe_manifest="$root/vibe-plugin/plugin.json"
    local claude_version vibe_version

    # A failing read_version runs in the command substitution, where fail's
    # exit ends only the subshell; the failed assignment then aborts the
    # script under set -e, after fail has printed the refusal.
    claude_version="$(read_version "$claude_manifest")"
    vibe_version="$(read_version "$vibe_manifest")"

    if [[ "$claude_version" == "$vibe_version" ]]; then
        printf 'check-versions: %s == %s == %s\n' "$claude_manifest" "$vibe_manifest" "$claude_version"
        exit 0
    fi
    fail "manifest versions disagree: $claude_manifest $claude_version, $vibe_manifest $vibe_version — bump the Vibe manifest in the post-release sync commit"
}

# Prints the manifest's .version; fails on a missing file, a parse error or an
# empty .version. jq's stderr is dropped and its status routed through fail:
# otherwise its raw parse error (exit 5) would abort first and this script's
# own refusal message would never print.
read_version() {
    local manifest="$1" version status=0
    [[ -f "$manifest" ]] || fail "missing $manifest (run from the repo root)"
    version="$(jq -er '.version // empty' "$manifest" 2>/dev/null)" || status=$?
    if [[ "$status" -eq 5 ]]; then
        fail "unparseable .version in $manifest"
    elif [[ "$status" -ne 0 ]]; then
        fail "empty .version in $manifest"
    fi
    printf '%s\n' "$version"
}

fail() {
    printf 'check-versions: %s\n' "$1" >&2
    exit 1
}

main "$@"
