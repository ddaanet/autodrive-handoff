#!/usr/bin/env bats
# Contract rows for scripts/drive-cancel.sh: the mod's answer to a prompt sent
# after the arming turn's Stop (docs/design/queued-prompts.md). Each row seeds a
# real .claude/autodrive and runs the real script. A cancel prints the fixture
# JSON under tests/mod/fixtures/ (@ROOT@ unused: the plan carries no path);
# every other case prints nothing and leaves the sentinel byte for byte as it
# was.
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

    CONTINUATION="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from checkpoint import CONTINUATION; print(CONTINUATION)' "$repo_root/scripts")"
    [ -n "$CONTINUATION" ]
}

seed() {
    printf '%s\n' "$@" > "$tmp/.claude/autodrive"
}

# $1 is the session whose prompt arrived, as the mod passes it.
cancel() {
    run bash scripts/drive-cancel.sh "$tmp" "${1-sess-hook-test}"
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

@test "drive-cancel (an owned armed clear: cancelled, recorded as armed)" {
    seed "armed sess-hook-test" clear "/rename A Title" "/clear" "$CONTINUATION"
    cancel
    assert_cancelled cancel-clear.json armed clear
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\towner=sess-hook-test\t'* ]]
}

@test "drive-cancel (an owned armed compact: cancelled, recorded as armed)" {
    seed "armed sess-hook-test" compact "/compact keep the parser work" "$CONTINUATION"
    cancel
    assert_cancelled cancel-compact.json armed compact
}

# pending is ownerless: the mod's window is what says it is this session's.
@test "drive-cancel (a pending clear: cancelled, recorded as pending)" {
    seed "pending" clear "/rename A Title" "/clear" "$CONTINUATION"
    cancel
    assert_cancelled cancel-clear.json pending clear
}

@test "drive-cancel (a pending compact: cancelled, recorded as pending)" {
    seed "pending" compact "/compact keep the parser work" "$CONTINUATION"
    cancel
    assert_cancelled cancel-compact.json pending compact
}

# A rename is not cancelled: the prompt's turn runs it. The window may have
# the sweep read the file first, so the script takes it as the take would and
# prints the take's plan; nothing is recorded, as nothing was cancelled.
@test "drive-cancel (an owned armed rename: taken, the take's plan printed, no record)" {
    seed "armed sess-hook-test" rename "/rename Driven Transitions"
    cancel
    [ "$status" -eq 0 ]
    [ "$output" = "$(sed "s|@ROOT@|$tmp|g" "$fixtures/armed-rename.json")" ]
    [ ! -e "$tmp/.claude/autodrive" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "drive-cancel (another session's armed rename: nothing printed, file untouched)" {
    seed_and_keep "armed sess-other" rename "/rename Driven Transitions"
    cancel
    assert_untouched
}

@test "drive-cancel (a pending rename: nothing printed, file untouched)" {
    seed_and_keep "pending" rename "/rename Driven Transitions"
    cancel
    assert_untouched
}

@test "drive-cancel (FR-G, a prepare-only compact, armed: nothing printed, file untouched)" {
    seed_and_keep "armed sess-hook-test" compact
    cancel
    assert_untouched
}

@test "drive-cancel (FR-G, a prepare-only compact, pending: nothing printed, file untouched)" {
    seed_and_keep "pending" compact
    cancel
    assert_untouched
}

@test "drive-cancel (held: nothing printed, file untouched)" {
    seed_and_keep "held sess-hook-test" clear "/rename A Title" "/clear" "$CONTINUATION"
    cancel
    assert_untouched
}

@test "drive-cancel (another session's armed file: nothing printed, file untouched)" {
    seed_and_keep "armed sess-other" clear "/rename A Title" "/clear" "$CONTINUATION"
    cancel
    assert_untouched
}

@test "drive-cancel (an empty session id: nothing printed, file untouched)" {
    seed_and_keep "armed sess-hook-test" clear "/rename A Title" "/clear" "$CONTINUATION"
    cancel ""
    assert_untouched
}

@test "drive-cancel (a malformed file: nothing printed, file untouched)" {
    seed_and_keep "armed sess-hook-test" bogus-kind
    cancel
    assert_untouched
}

@test "drive-cancel (a link at the sentinel: nothing printed, left for the sweep)" {
    : > "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$tmp/.claude/autodrive"
    cancel
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ -L "$tmp/.claude/autodrive" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "drive-cancel (an unresolved root: nothing printed)" {
    run bash scripts/drive-cancel.sh "" sess-hook-test
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# Fails closed, as the take does: a lock held past the wait cancels nothing.
@test "drive-cancel (the lock is held past the wait: nothing printed, file untouched)" {
    seed_and_keep "armed sess-hook-test" clear "/rename A Title" "/clear" "$CONTINUATION"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=0.05 cancel
    release_drive_lock
    assert_untouched
}

# The take and the cancel serialise on the lock: the cancel that waited sees the
# file the take left behind.
@test "drive-cancel (the take moved the file to pending while the cancel waited: it cancels the pending file)" {
    seed "armed sess-hook-test" clear "/rename A Title" "/clear" "$CONTINUATION"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=30 bash scripts/drive-cancel.sh "$tmp" sess-hook-test \
        > "$BATS_TEST_TMPDIR/cancel.out" 2>&1 3>&- &
    cancel_pid=$!
    wait_until_blocked
    sed -i.bak '1s/.*/pending/' "$tmp/.claude/autodrive"
    release_drive_lock
    wait "$cancel_pid"
    [ "$(cat "$BATS_TEST_TMPDIR/cancel.out")" = "$(cat "$fixtures/cancel-clear.json")" ]
    [ ! -e "$tmp/.claude/autodrive" ]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=pending\t'* ]]
}
