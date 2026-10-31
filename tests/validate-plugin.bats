#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=checkpoint-helpers.bash
source "$BATS_TEST_DIRNAME/checkpoint-helpers.bash"

# Tests for the justfile's `validate-plugin` recipe: the two exceptions to
# `claude plugin validate --strict` and the scoping of each to the entry it
# names. The rest of the bash-side neighbors of the checkpoint channel are in
# tests/inject-checkpoint-root.bats and tests/bin-commands.bats; the helpers
# they share are in tests/checkpoint-helpers.bash.
#
# Run with: bats tests/validate-plugin.bats   (from plugin root)

# ==========================================================================
# justfile validate-plugin — the two exceptions to `claude plugin validate
# --strict` are scoped to the entry (file) they name. `claude` is a stub on
# PATH that prints a fixture and ignores its arguments, so the recipe's jq
# gate is the only thing under test; the fixture's `file` paths are absolute
# under the root the recipe runs in, as the real validator's are.
# ==========================================================================

# validate_entry <file> <path> <message> [errors|warnings]: one validator
# entry carrying one finding, in the list named by the last argument.
validate_entry() {
    jq -nc --arg file "$1" --arg path "$2" --arg msg "$3" --arg list "${4:-errors}" \
        '{file:$file, type:"x", errors:[], warnings:[], notes:[], gatingHooks:[]}
         | .[$list] = [{path:$path, message:$msg, code:null}]'
}

# The validator's own wording for the two findings.
mcp_syntax_entry() {
    validate_entry "$1" json 'Invalid JSON syntax: JSON Parse error: Unexpected EOF. The plugin loader logs this at debug level and loads no servers from the file.'
}
claude_md_entry() {
    validate_entry "$1" root 'CLAUDE.md at the plugin root is not loaded as project context. To ship context with your plugin, use a skill (skills/<name>/SKILL.md) instead.' warnings
}

# physical_dir <path> — make the directory and print its physical path. The
# validator's entries carry physical paths (checked against the real one: `claude
# plugin validate .` reports the realpath of the directory it runs in), and
# $BATS_TEST_TMPDIR is not one where /var is a link, as on macOS.
physical_dir() {
    mkdir -p "$1" && (cd "$1" && pwd -P)
}

# validate_run <root> <entry>...: a stub `claude` printing the fixture (an
# empty manifest plus the entries), then the real recipe with <root> as its
# working directory (or $VALIDATE_CWD, a path that reaches it). Sets $status and
# $output.
validate_run() {
    local root="$1" entries; shift
    entries="$(IFS=,; echo "$*")"
    mkdir -p "$root" "$BATS_TEST_TMPDIR/stubbin"
    jq -nc --arg root "$root" --argjson entries "[$entries]" \
        '{manifest:{file:($root + "/.claude-plugin/plugin.json"), type:"manifest", errors:[], warnings:[], notes:[], gatingHooks:[]}, contents:$entries}' \
        > "$BATS_TEST_TMPDIR/fixture.json"
    cat > "$BATS_TEST_TMPDIR/stubbin/claude" <<'STUB'
#!/bin/sh
cat "$FIXTURE"
STUB
    chmod +x "$BATS_TEST_TMPDIR/stubbin/claude"
    FIXTURE="$BATS_TEST_TMPDIR/fixture.json" PATH="$BATS_TEST_TMPDIR/stubbin:$PATH" \
        PWD="${VALIDATE_CWD:-$root}" run just --justfile "$repo_root/justfile" --working-directory "${VALIDATE_CWD:-$root}" validate-plugin
}

@test "validate-plugin: an empty .mcp.json's syntax error and the CLAUDE.md warning pass" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -eq 0 ]
}

@test "validate-plugin: a root path holding a space passes the same fixture" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/my plugin dir")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -eq 0 ]
}

# The recipe runs the validator on `.`, which reports the physical path of the
# directory, so a working directory reached through a link still matches. The
# recipe's shell inherits the link as its $PWD, as it does from a user who cd'd
# through one, so a plain `pwd` there would name the link.
@test "validate-plugin: a working directory reached through a symlink passes with the validator's physical paths" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    ln -s "$root" "$BATS_TEST_TMPDIR/plugin-link"
    VALIDATE_CWD="$BATS_TEST_TMPDIR/plugin-link" \
        validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -eq 0 ]
}

@test "validate-plugin: the same syntax error on hooks.json fails beside an empty .mcp.json" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" \
        "$(mcp_syntax_entry "$root/hooks/hooks.json")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: the syntax error on a non-empty .mcp.json fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; echo '{' > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: the syntax error with no .mcp.json at all fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: the CLAUDE.md warning on another entry's file fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/skills/x/SKILL.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: an unrelated finding on an exempt file still fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" \
        "$(validate_entry "$root/.mcp.json" servers 'bad server')"
    [ "$status" -ne 0 ]
}
