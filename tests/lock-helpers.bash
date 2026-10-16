#!/usr/bin/env bash
# Shared by the bats files that test the sentinel's lock (docs/design/
# driving-the-transition.md, "The sentinel's lock"): a stand-in for another
# actor that holds `.claude/autodrive.lock` while a row mutates the sentinel
# the way a writer or a taker would, and then lets go.

# hold_drive_lock <root> — take the lock from a background process and return
# once it holds it. The holder dies after a minute if a row forgets to release.
# Its fds are cut off from bats' (3>&-) so the runner is not kept waiting.
hold_drive_lock() {
    local lock="$1/.claude/autodrive.lock" ready="$BATS_TEST_TMPDIR/lock-held" i
    rm -f "$ready"
    python3 -I -c '
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(60)
' "$lock" "$ready" >/dev/null 2>&1 3>&- &
    LOCK_HOLDER=$!
    for i in $(seq 200); do
        [ -e "$ready" ] && return 0
        sleep 0.05
    done
    return 1
}

# release_drive_lock — let go of what hold_drive_lock took.
release_drive_lock() {
    kill "$LOCK_HOLDER" 2>/dev/null || true
    wait "$LOCK_HOLDER" 2>/dev/null || true
}
