#!/usr/bin/env bats

# --- check-versions (precommit, uncached) ---
#
# The two manifests carry the same version; see
# docs/design/release-infrastructure.md for the coupling and the sync commit.

setup() {
    ROOT="$(mktemp -d)"
}

teardown() {
    rm -rf "$ROOT"
}

write_manifests() {
    local claude="$1" vibe="$2"
    mkdir -p "$ROOT/.claude-plugin" "$ROOT/vibe-plugin"
    printf '{"version": "%s"}\n' "$claude" > "$ROOT/.claude-plugin/plugin.json"
    printf '{"version": "%s"}\n' "$vibe" > "$ROOT/vibe-plugin/plugin.json"
}

@test "equal manifests pass, printing the shared version" {
    write_manifests 1.2.3 1.2.3
    run bash scripts/check-versions.sh "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.2.3"* ]]
}

@test "a release alone (claude bumped, vibe lagging) is refused, naming both versions" {
    write_manifests 1.3.0 1.2.3
    run bash scripts/check-versions.sh "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"disagree"* ]]
    [[ "$output" == *"$ROOT/.claude-plugin/plugin.json 1.3.0, $ROOT/vibe-plugin/plugin.json 1.2.3"* ]]
}

@test "a missing vibe manifest is refused, not skipped" {
    mkdir -p "$ROOT/.claude-plugin"
    printf '{"version": "1.2.3"}\n' > "$ROOT/.claude-plugin/plugin.json"
    run bash scripts/check-versions.sh "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing $ROOT/vibe-plugin/plugin.json"* ]]
}

@test "an empty .version is refused" {
    write_manifests 1.2.3 1.2.3
    printf '{}\n' > "$ROOT/.claude-plugin/plugin.json"
    run bash scripts/check-versions.sh "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty .version"* ]]
}

@test "an unparseable manifest is refused with the friendly message" {
    write_manifests 1.2.3 1.2.3
    printf '{not json}\n' > "$ROOT/.claude-plugin/plugin.json"
    run bash scripts/check-versions.sh "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"check-versions: unparseable .version in"* ]]
}
