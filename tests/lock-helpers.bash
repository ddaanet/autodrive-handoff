#!/usr/bin/env bash
# Shared by the bats files that test the sentinel's lock (docs/design/
# sentinel-lock.md): a stand-in for another actor that holds
# `.claude/autodrive.lock` while a row mutates the sentinel the way a writer or
# a taker would, and then lets go. The holder is tests/lock_holder.py, which
# takes the lock through the code under test's own `_drive_lock.locked`.
#
# A row starts the actor under test in the background, calls
# `wait_until_blocked <pid>`, and only then changes the sentinel. The actor
# reports that it is waiting through the file $HANDOFF_LOCK_BLOCKED_FILE, which
# hold_drive_lock exports and every actor started after it inherits; an actor
# that never calls for the lock never reports, so the row fails whatever the
# speed of the box (a fixed sleep would pass with the lock call removed).

# hold_drive_lock <root> — take the lock from a background process and return
# once it holds it. The holder dies after a minute if a row forgets to release.
# Its fds are cut off from bats' (3>&-) so the runner is not kept waiting.
hold_drive_lock() {
    local root="$1" held="$BATS_TEST_TMPDIR/lock-held"
    local holder="$BATS_TEST_DIRNAME/lock_holder.py"
    export HANDOFF_LOCK_BLOCKED_FILE="$BATS_TEST_TMPDIR/lock-blocked"
    rm -f "$held" "$HANDOFF_LOCK_BLOCKED_FILE"
    python3 -I "$holder" "$root/.claude/autodrive.lock" 60 >"$held" 2>&1 3>&- &
    LOCK_HOLDER=$!
    for _ in $(seq 200); do
        [ "$(cat "$held")" = held ] && return 0
        sleep 0.05
    done
    return 1
}

# wait_until_blocked <pid> — return once the background actor <pid> has found the
# lock held and is waiting for it. Fails when the actor ends without having
# waited, or after a minute.
wait_until_blocked() {
    local pid="$1"
    for _ in $(seq 1200); do
        [ -e "$HANDOFF_LOCK_BLOCKED_FILE" ] && return 0
        if ! kill -0 "$pid" 2>/dev/null; then
            [ -e "$HANDOFF_LOCK_BLOCKED_FILE" ]
            return
        fi
        sleep 0.05
    done
    return 1
}

# release_drive_lock — let go of what hold_drive_lock took.
release_drive_lock() {
    kill "$LOCK_HOLDER" 2>/dev/null || true
    wait "$LOCK_HOLDER" 2>/dev/null || true
}
