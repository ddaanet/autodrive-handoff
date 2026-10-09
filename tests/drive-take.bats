#!/usr/bin/env bats
# Contract rows for scripts/drive-take.sh: the plan the mod runs at Stop.
# Each row seeds a real .claude/autodrive, runs the real script, and compares
# stdout to a fixture under tests/mod/fixtures/ (@ROOT@ stands for the session
# root). The same fixtures stub `process.run` in the mod's own tests.
#
# Usage: bats tests/drive-take.bats   (run from plugin root)

setup() {
    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    cd "$repo_root" || return 1

    fixtures="$repo_root/tests/mod/fixtures"
    tmp="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$tmp/.claude"
    export CLAUDE_PROJECT_DIR="$tmp"
}

# Linked-worktree layout, as in hook-test.bats: .git is a file pointing under
# the project's .git/worktrees. Echoes the worktree path.
make_worktree() {
    local name="$1" wt="$BATS_TEST_TMPDIR/$1"
    mkdir -p "$wt/.claude" "$tmp/.git/worktrees/$name"
    printf 'gitdir: %s\n' "$tmp/.git/worktrees/$name" > "$wt/.git"
    printf '%s\n' "$wt"
}

# seed_state <dir> <state-line> <lines...>
seed() {
    local dir="$1"; shift
    printf '%s\n' "$@" > "$dir/.claude/autodrive"
}

# The fixture $2 with @ROOT@ replaced by $1, as the script must print it.
expected() {
    local body
    body="$(cat "$fixtures/$2")"
    printf '%s' "${body//@ROOT@/$1}"
}

take() {
    run bash scripts/drive-take.sh "$1"
}

@test "drive-take (no autodrive: empty stdout, exit 0)" {
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "drive-take (armed compact: prints the plan, file becomes pending)" {
    seed "$tmp" armed compact "/compact keep the parser work" "continue with task 3"
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "$(expected "$tmp" armed-compact.json)" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
}

@test "drive-take (armed clear: before and after in order, file becomes pending)" {
    seed "$tmp" armed clear "/rename A Title" "/clear" "pick up per the task file"
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "$(expected "$tmp" armed-clear.json)" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    # Only line 1 changes: the loader still parses the rest.
    [ "$(tail -n +2 "$tmp/.claude/autodrive")" = "$(printf '%s\n' clear "/rename A Title" "/clear" "pick up per the task file")" ]
}

# `rename` has no loader, so nothing would ever clear a pending armed for it.
@test "drive-take (armed rename: prints the plan, sentinel removed)" {
    seed "$tmp" armed rename "/rename Driven Transitions"
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "$(expected "$tmp" armed-rename.json)" ]
    [ ! -e "$tmp/.claude/autodrive" ]
}

# FR-G: the prepare-only marker. Nothing to run; the pending file alone is what
# SessionStart(compact) gates the frame re-injection on.
@test "drive-take (FR-G, compact kind line alone: empty plan, stays pending)" {
    seed "$tmp" armed compact
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "$(expected "$tmp" prepare-only-compact.json)" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
}

@test "drive-take (pending: empty stdout, file untouched)" {
    seed "$tmp" pending compact "/compact" "continue with task 3"
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$(printf '%s\n' pending compact "/compact" "continue with task 3")" ]
}

@test "drive-take (held: empty stdout, file untouched)" {
    seed "$tmp" "held sess-hook-test" clear "/rename A Title" "/clear"
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$(printf '%s\n' "held sess-hook-test" clear "/rename A Title" "/clear")" ]
}

@test "drive-take (arms once only: second take is empty)" {
    seed "$tmp" armed compact "/compact" "continue with task 3"
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" != "" ]
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "drive-take (malformed: discarded, kind null, message names the constraint)" {
    seed "$tmp" armed clear "/rename A Title"
    take "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "$(expected "$tmp" malformed.json)" ]
    [ ! -e "$tmp/.claude/autodrive" ]
}

@test "drive-take (worktree cwd: takes the worktree file, failFile under the worktree)" {
    wt="$(make_worktree wtS)"
    seed "$wt" armed compact "/compact keep the parser work" "continue with task 3"
    take "$wt"
    [ "$status" -eq 0 ]
    [ "$output" = "$(expected "$wt" armed-compact.json)" ]
    [ "$(head -n1 "$wt/.claude/autodrive")" = "pending" ]
}

@test "drive-take (worktree cwd: the project's own sentinel is not touched)" {
    wt="$(make_worktree wtT)"
    seed "$tmp" armed compact "/compact" "continue with task 3"
    take "$wt"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed" ]
}
