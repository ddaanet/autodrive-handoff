#!/usr/bin/env bats

# --- check-versions (precommit, uncached) ---
#
# The Vibe manifest equals the Claude one or is one patch/minor/major bump
# ahead; see docs/design/release-infrastructure.md for the coupling.

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

expect_relation() {
    write_manifests "$1" "$2"
    run bash scripts/check-versions.sh "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == "check-versions: $3 (claude $1, vibe $2)" ]]
}

expect_refused() {
    write_manifests "$1" "$2"
    run bash scripts/check-versions.sh "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$ROOT/.claude-plugin/plugin.json $1, $ROOT/vibe-plugin/plugin.json $2"* ]]
}

@test "equal manifests pass, naming the relation and both versions" {
    expect_relation 1.2.3 1.2.3 equal
}

@test "vibe one patch ahead passes" {
    expect_relation 1.2.3 1.2.4 "vibe one patch ahead"
}

@test "vibe one minor ahead passes" {
    expect_relation 1.2.3 1.3.0 "vibe one minor ahead"
}

@test "vibe one major ahead passes" {
    expect_relation 1.2.3 2.0.0 "vibe one major ahead"
}

@test "vibe behind is refused, naming both versions" {
    expect_refused 1.3.0 1.2.3
}

@test "claude ahead by a minor (a release alone) is refused" {
    expect_refused 1.3.0 1.2.9
}

@test "vibe two bumps ahead is refused" {
    expect_refused 1.2.3 1.2.5
    expect_refused 1.2.3 1.4.0
    expect_refused 1.2.3 3.0.0
}

@test "a minor bump without the patch reset is refused" {
    expect_refused 0.23.1 0.24.1
}

@test "a non-semver version is refused" {
    expect_refused 1.2.3 1.2.4-rc1
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
