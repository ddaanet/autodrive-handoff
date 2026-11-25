#!/usr/bin/env bash
# Uncached precommit check: the Vibe manifest's version equals the Claude
# manifest's, or is exactly one patch, minor or major bump ahead of it.
#
# The Claude manifest (.claude-plugin/plugin.json) is bumped by the toolkit's
# `release` recipe, which knows only that manifest. The Vibe manifest
# (vibe-plugin/plugin.json) is bumped in its own commit before `just release`,
# so between that commit and the release the Vibe version leads by one bump;
# the release's own bump commit is where they meet again, and that commit is
# what gets tagged. The two surfaces are interdependent but separate — see
# docs/design/release-infrastructure.md and docs/design/decisions.md. Anything
# else (Vibe behind, Claude ahead, two bumps, a skipped component, a
# non-semver version) is refused, naming both versions.
#
# Both manifests are required. The check is repo-local (unlike the toolkit's
# guards), so a missing file is an error, not a benign absence: this plugin
# ships both surfaces.
set -euo pipefail

main() {
    local root="${1:-.}"
    local claude_manifest="$root/.claude-plugin/plugin.json"
    local vibe_manifest="$root/vibe-plugin/plugin.json"
    local claude_version vibe_version relation

    # A failing read_version runs in the command substitution, where fail's
    # exit ends only the subshell; the failed assignment then aborts the
    # script under set -e, after fail has printed the refusal.
    claude_version="$(read_version "$claude_manifest")"
    vibe_version="$(read_version "$vibe_manifest")"

    if relation="$(relation_of "$claude_version" "$vibe_version")"; then
        printf 'check-versions: %s (claude %s, vibe %s)\n' "$relation" "$claude_version" "$vibe_version"
        exit 0
    fi
    fail "vibe must equal claude or be one patch, minor or major bump ahead: $claude_manifest $claude_version, $vibe_manifest $vibe_version"
}

# Prints "equal" or "vibe one <tier> ahead" and succeeds when the Vibe version
# stands in an accepted relation to the Claude one; fails otherwise, including
# when either is not X.Y.Z.
relation_of() {
    local c="$1" v="$2"
    local semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    [[ "$c" =~ $semver ]] || return 1
    local cx="${BASH_REMATCH[1]}" cy="${BASH_REMATCH[2]}" cz="${BASH_REMATCH[3]}"
    [[ "$v" =~ $semver ]] || return 1
    if [[ "$v" == "$c" ]]; then
        echo equal
    elif [[ "$v" == "$cx.$cy.$((cz + 1))" ]]; then
        echo "vibe one patch ahead"
    elif [[ "$v" == "$cx.$((cy + 1)).0" ]]; then
        echo "vibe one minor ahead"
    elif [[ "$v" == "$((cx + 1)).0.0" ]]; then
        echo "vibe one major ahead"
    else
        return 1
    fi
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
