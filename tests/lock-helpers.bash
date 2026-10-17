#!/usr/bin/env bash
# Shared by the bats files that test the sentinel's lock (docs/design/
# sentinel-lock.md): a stand-in for another actor that holds
# `.claude/autodrive.lock` while a row mutates the sentinel the way a writer or
# a taker would, and then lets go. The holder is tests/lock_holder.py, which
# takes the lock through the code under test's own `_drive_lock.locked`.
#
# Nothing here sleeps or polls: the holder reports through a FIFO the row reads
# with a bounded blocking `read`, and it lets go by being killed.
#
# An ordering row starts the actor under test in the background, calls
# `wait_until_blocked <pid>`, and only then changes the sentinel. The actor
# reports that it is waiting through $HANDOFF_LOCK_BLOCKED_FILE, a FIFO that
# hold_drive_lock exports, opens read-write on fd 7 and every actor started
# after it inherits; the wait writes a byte to it (`_signal_blocked`), and the
# row's `read` returns. An actor that never calls for the lock never writes, so
# the row fails when its bound passes, whatever the speed of the box (a fixed
# sleep would pass with the lock call removed).
#
# A contention row needs no signal at all: the holder holds for the whole run,
# the actor starts with HANDOFF_LOCK_WAIT_SECS tiny, and its wait cannot
# succeed.

# hold_drive_lock <root> — take the lock from a background process and return
# once it holds it. The holder ends after a minute if a row forgets to release
# (its own alarm). Its fds are cut off from bats' (3>&-) so the runner is not
# kept waiting. Fails when it does not say `held` within 30 s.
hold_drive_lock() {
    local root="$1" held="$BATS_TEST_TMPDIR/lock-held" line=""
    local holder="$BATS_TEST_DIRNAME/lock_holder.py"
    export HANDOFF_LOCK_BLOCKED_FILE="$BATS_TEST_TMPDIR/lock-blocked"
    rm -f "$held" "$HANDOFF_LOCK_BLOCKED_FILE"
    mkfifo "$held" "$HANDOFF_LOCK_BLOCKED_FILE"
    exec 7<>"$HANDOFF_LOCK_BLOCKED_FILE" 8<>"$held"
    python3 -I "$holder" "$root/.claude/autodrive.lock" >"$held" 2>&1 3>&- 7>&- 8>&- &
    LOCK_HOLDER=$!
    read -r -t 30 -u 8 line || true
    exec 8>&-
    [ "$line" = held ]
}

# wait_until_blocked — return once a background actor has found the lock held
# and is waiting for it. Fails when 30 s pass without the report: the
# actor never waited, whether it ended or not.
wait_until_blocked() {
    local byte=""
    read -r -n 1 -t 30 -u 7 byte || true
    [ -n "$byte" ]
}

# release_drive_lock — let go of what hold_drive_lock took.
release_drive_lock() {
    kill "$LOCK_HOLDER" 2>/dev/null || true
    wait "$LOCK_HOLDER" 2>/dev/null || true
    exec 7>&-
}
