#!/usr/bin/env bats
# Contract rows for scripts/drive-cancel.sh: the mod's cancel, for a prompt sent
# after the arming turn's Stop, of the clear or compact the window's own take
# left `pending` (docs/design/queued-prompts.md). Each row seeds a real
# .claude/autodrive and runs the real script. A cancel prints the fixture JSON
# under tests/mod/fixtures/ (@ROOT@ unused: the plan carries no path); every
# other case prints nothing and leaves the sentinel byte for byte as it was.
#
# Usage: bats tests/drive-cancel.bats   (run from plugin root)

setup() {
    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    cd "$repo_root" || return 1

    fixtures="$repo_root/tests/mod/fixtures"
    tmp="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$tmp/.claude"
    export CLAUDE_PROJECT_DIR="$tmp"
    load lock-helpers
}

seed() {
    printf '%s\n' "$@" > "$tmp/.claude/autodrive"
}

# $1 is the kind the window's take returned, $2 the session whose prompt
# arrived, as the mod passes them.
cancel() {
    run bash scripts/drive-cancel.sh "$tmp" "${2-sess-hook-test}" "${1-clear}"
}

# A case that cancels nothing: exit 0, empty stdout, sentinel unchanged.
assert_untouched() {
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

seed_and_keep() {
    seed "$@"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
}

# A cancel: the plan is the fixture, the sentinel is gone, one record line.
assert_cancelled() {
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "$fixtures/$1")" ]
    [ ! -e "$tmp/.claude/autodrive" ]
    [ "$(wc -l < "$tmp/.claude/autodrive.swept")" -eq 1 ]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate='"$2"$'\t'*$'\tkind='"$3"$'\t'* ]]
}

@test "drive-cancel (no sentinel: nothing printed)" {
    cancel
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

# pending is ownerless: the mod's window is what says it is this session's.
@test "drive-cancel (a pending clear: cancelled, recorded as pending)" {
    seed "pending" "clear continue" "A Title"
    cancel clear
    assert_cancelled cancel-clear.json pending clear
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\towner=-\t'* ]]
}

@test "drive-cancel (a pending compact: cancelled, recorded as pending)" {
    seed "pending" "compact continue" "keep the parser work"
    cancel compact
    assert_cancelled cancel-compact.json pending compact
}

# The take left nothing armed to cancel: an armed file is not this window's.
@test "drive-cancel (an armed clear, even this session's: nothing printed, file untouched)" {
    seed_and_keep "armed sess-hook-test" "clear continue" "A Title"
    cancel clear
    assert_untouched
}

@test "drive-cancel (a pending file of another kind than the take's: nothing printed, file untouched)" {
    seed_and_keep "pending" "compact continue" "keep the parser work"
    cancel clear
    assert_untouched
}

@test "drive-cancel (FR-G, a pending prepare marker: nothing printed, file untouched)" {
    seed_and_keep "pending" prepare
    cancel compact
    assert_untouched
}

@test "drive-cancel (a kind other than clear or compact: nothing printed, file untouched)" {
    seed_and_keep "pending" prepare
    cancel prepare
    assert_untouched
}

@test "drive-cancel (held: nothing printed, file untouched)" {
    seed_and_keep "held sess-hook-test" "clear continue" "A Title"
    cancel clear
    assert_untouched
}

@test "drive-cancel (an empty session id: nothing printed, file untouched)" {
    seed_and_keep "pending" "clear continue" "A Title"
    cancel clear ""
    assert_untouched
}

@test "drive-cancel (a malformed file: nothing printed, file untouched)" {
    seed_and_keep "pending" bogus-kind
    cancel clear
    assert_untouched
}

@test "drive-cancel (a link at the sentinel: nothing printed, left for the sweep)" {
    : > "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$tmp/.claude/autodrive"
    cancel clear
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ -L "$tmp/.claude/autodrive" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "drive-cancel (an unresolved root: nothing printed)" {
    run bash scripts/drive-cancel.sh "" sess-hook-test clear
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# Fails closed, as the take does: a lock held past the wait cancels nothing.
@test "drive-cancel (the lock is held past the wait: nothing printed, file untouched)" {
    seed_and_keep "pending" "clear continue" "A Title"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=0.05 cancel clear
    release_drive_lock
    assert_untouched
}

# The cancel judges the file it finds once the lock is free (sentinel-lock.md).
# The pending file passes the first test, another actor holds the lock, and the
# file changes under it: an unlocked read has already seen `pending` and would
# remove what is there now.
# <seed lines...> — the replacement written while the cancel waits; none removes
# the file, as a loader consuming it would.
cancel_while_file_changes() {
    seed "pending" "clear continue" "A Title"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=30 bash scripts/drive-cancel.sh "$tmp" sess-hook-test clear \
        > "$BATS_TEST_TMPDIR/cancel.out" 2>&1 3>&- &
    cancel_pid=$!
    wait_until_blocked
    if (( $# )); then seed "$@"; else rm -f "$tmp/.claude/autodrive"; fi
    release_drive_lock
    wait "$cancel_pid"
}

@test "drive-cancel (a checkpoint replaced the pending file while the cancel waited: the new file is left alone)" {
    cancel_while_file_changes "armed sess-hook-test" "clear continue" "New Title"
    [ ! -s "$BATS_TEST_TMPDIR/cancel.out" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed sess-hook-test" ]
    [ "$(sed -n 3p "$tmp/.claude/autodrive")" = "New Title" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "drive-cancel (a loader removed the pending file while the cancel waited: nothing printed, nothing recorded)" {
    cancel_while_file_changes
    [ ! -s "$BATS_TEST_TMPDIR/cancel.out" ]
    [ ! -e "$tmp/.claude/autodrive" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}
