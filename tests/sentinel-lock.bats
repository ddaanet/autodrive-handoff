#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"
load lock-helpers

# --- the sentinel's lock: the sweep and a writer or the take ---
#
# Another actor holds .claude/autodrive.lock, a sweep starts and has to wait,
# and the sentinel becomes `pending` under the lock, as the take leaves it. The
# sweep must then find `pending` and say nothing: a sweep that has already read
# `armed` removes the file the take armed, and tells the user the mod did not
# run a transition that is about to run.

# <outfile> — run_report_failure's input and script, in the background.
start_report_failure() {
    (
        jq -nc --arg cwd "$tmp" --arg sid "$SESSION_ID" --arg pid "${PROMPT_ID-}" \
          '{cwd:$cwd, session_id:$sid, prompt:"anything"}
           + (if $pid == "" then {} else {prompt_id:$pid} end)' \
        | HANDOFF_LOCK_WAIT_SECS=30 bash scripts/report-drive-failure.sh
    ) > "$1" 2>&1 3>&- &
    SWEEP_PID=$!
}

# <kind> — the sentinel as the take leaves it, under the lock.
become_pending() {
    printf '%s\n' pending "$1" "/rename Queued Title" "/clear" "pick up the queued task" \
        > "$tmp/.claude/autodrive"
}

# The sweep ended with nothing said or recorded and the file `pending`.
assert_sweep_left_pending() {
    wait "$SWEEP_PID"
    [ ! -s "$BATS_TEST_TMPDIR/sweep.out" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
}

@test "report-drive-failure (the sentinel becomes pending while a stale sweep waits on the lock: left alone, nothing said)" {
    seed_armed_kind clear
    hold_drive_lock "$tmp"
    start_report_failure "$BATS_TEST_TMPDIR/sweep.out"
    wait_until_blocked
    become_pending clear
    release_drive_lock
    assert_sweep_left_pending
}

@test "report-drive-failure (the sentinel becomes pending while a queued-prompt cancel waits on the lock: left alone, nothing said)" {
    seed_queued clear
    hold_drive_lock "$tmp"
    PROMPT_ID=arming-prompt start_report_failure "$BATS_TEST_TMPDIR/sweep.out"
    wait_until_blocked
    become_pending clear
    release_drive_lock
    assert_sweep_left_pending
}

# The bound fails closed: a lock that is not let go does not wedge the hook, and
# after the wait (HANDOFF_LOCK_WAIT_SECS) the sweep leaves the file untouched and
# says on both channels that it did not judge it. The holder holds for the whole
# run, so the wait cannot succeed, and is killed afterwards: no sleep.
@test "report-drive-failure (the lock is held past the wait: the sweep judges nothing, the file is untouched, both channels say so)" {
    seed_armed_kind clear
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    make_pointer_dir
    hold_drive_lock "$tmp"
    PROMPT_ID=idle-prompt HANDOFF_LOCK_WAIT_SECS=0.05 run_report_failure "$tmp"
    release_drive_lock
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    [ ! -e "$tmp/.claude/autodrive.swept" ]
    split_output "$output"
    [ "$MSG" = $'\033[0m'"handoff: autodrive not judged — the sentinel's lock was busy; left in place." ]
    [[ "$CTX" == *"the sentinel's lock was busy"* && "$CTX" == *"left in place and not judged"* ]]
    # Not judged means no lines offered and no stale-file verdict.
    [[ "$output" != *"Type in order"* && "$output" != *"discarded"* ]]
}

# A failure record is read with the sentinel it may explain: a pending file is
# cleared only with the report, so with the lock busy the record stays for the
# next prompt, which can judge both, and is not reported twice.
@test "report-drive-failure (the lock is held past the wait: a failure record is left for the next prompt)" {
    seed_pending "$tmp" clear "/rename A Title" "/clear" "pick up the task"
    printf '%s\n' "/clear rejected" > "$tmp/.claude/autodrive.failed"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=0.05 run_report_failure "$tmp"
    release_drive_lock
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    [ "$(cat "$tmp/.claude/autodrive.failed")" = "/clear rejected" ]
    [[ "$output" != *"did not deliver"* ]]
    [[ "$output" == *"not judged"* ]]
}

@test "report-drive-failure (a link at the lock: the sweep judges nothing and says the lock could not be set up)" {
    seed_armed_kind clear
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    : > "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$tmp/.claude/autodrive.lock"
    PROMPT_ID=idle-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    split_output "$output"
    [ "$MSG" = $'\033[0m'"handoff: autodrive not judged — the sentinel's lock could not be set up; left in place." ]
}

# A sentinel that does not parse — here, a `clear` with only one of its four
# command/prose lines — describes no transition this session can complete.
# handoff_drive_read returns 1, drive_state is recorded as "malformed", and
# the sweep (any state other than "pending" or "held") discards it, but offers
# no lines to type: there is nothing it could say they were.
@test "report-drive-failure (malformed sentinel: discarded and reported)" {
    seed_drive "$tmp" "clear" "/rename A Title"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("discarded")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("Type in order") | not' >/dev/null
}

# --- the sentinel's lock: the loaders ---
#
# A loader reads `pending` and removes it. A checkpoint may replace the sentinel
# in between (it replaces whatever is there), so the read and the removal are
# one step under the lock. Another actor holds it, a loader starts and has to
# wait, and the sentinel becomes a freshly armed one. The loader must then
# judge that file, which is not a pending transition of its kind, and leave it:
# an unlocked loader has already read `pending` and removes the new file.

# <script> <source> <outfile> — a loader started in the background.
start_loader() {
    (
        jq -nc --arg cwd "$tmp" --arg s "$2" \
          '{cwd:$cwd, hook_event_name:"SessionStart", source:$s}' \
        | HANDOFF_LOCK_WAIT_SECS=30 bash "scripts/$1"
    ) > "$3" 2>&1 3>&- &
    LOADER_PID=$!
}

# <kind> — what a checkpoint writes over the pending file.
become_armed() {
    if [ "$1" = compact ]; then
        printf '%s\n' "armed $SESSION_ID" compact "/compact keep it" "next task"
    else
        printf '%s\n' "armed $SESSION_ID" clear "/rename Next Title" "/clear" "next task"
    fi > "$tmp/.claude/autodrive"
}

@test "load-handoff (the pending clear is replaced while the loader waits on the lock: the new file is left alone)" {
    seed_pending "$tmp" clear "/rename A Title" "/clear" "pick up per the task file"
    hold_drive_lock "$tmp"
    start_loader load-handoff.sh clear "$BATS_TEST_TMPDIR/loader.out"
    wait_until_blocked
    become_armed clear
    release_drive_lock
    wait "$LOADER_PID"
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed $SESSION_ID" ]
}

@test "load-compact (the pending compact is replaced while the loader waits on the lock: the new file is left alone)" {
    seed_pending "$tmp" compact "/compact" "continue"
    hold_drive_lock "$tmp"
    start_loader load-compact.sh compact "$BATS_TEST_TMPDIR/loader.out"
    wait_until_blocked
    become_armed compact
    release_drive_lock
    wait "$LOADER_PID"
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed $SESSION_ID" ]
}

# The bound fails closed. The holder holds for the whole run, so the wait cannot
# succeed, and is killed afterwards: no sleep. The loader leaves the sentinel
# unread and still injects the frame, saying on both channels that it did not
# touch the transition state.
@test "load-handoff (the lock is held past the wait: the pending file is left, the frame is still injected, both channels say so)" {
    seed_pending "$tmp" clear "/rename A Title" "/clear" "pick up per the task file"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=0.05 run_load_handoff "$tmp" clear
    release_drive_lock
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    split_output "$output"
    assert_msg_matches "autodrive left in place — the sentinel's lock was busy; $loaded_re; No todo"
    [[ "$CTX" == "# Task — "* && "$CTX" == *"hook smoke test"* ]]
    [[ "$CTX" == *"was left in place, not consumed: the sentinel's lock was busy."* ]]
}

@test "load-compact (the lock is held past the wait: the pending file is left, the frame is still injected, both channels say so)" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- finish the parser\n' > "$tmp/TODO.md"
    seed_pending "$tmp" compact "/compact" "continue"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=0.05 run_load_compact "$tmp"
    release_drive_lock
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected; autodrive left in place — the sentinel's lock was busy." ]
    [[ "$CTX" == *"- finish the parser"* ]]
    [[ "$CTX" == *"was left in place, not consumed: the sentinel's lock was busy."* ]]
}

# With no frame to inject the lock note still reaches the agent: it cannot tell
# whether a compaction was pending, so it says so rather than staying silent.
@test "load-compact (the lock is held past the wait, no todo: the note alone is injected)" {
    rm -f "$tmp/TASK.md" "$tmp/TODO.md"
    seed_pending "$tmp" compact "/compact" "continue"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    hold_drive_lock "$tmp"
    HANDOFF_LOCK_WAIT_SECS=0.05 run_load_compact "$tmp"
    release_drive_lock
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo; autodrive left in place — the sentinel's lock was busy." ]
    [[ "$CTX" == *"was left in place, not consumed"* ]]
}

@test "load-handoff (a link at the lock: the pending file is left and the note says the lock could not be set up)" {
    seed_pending "$tmp" clear "/rename A Title" "/clear" "pick up per the task file"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    : > "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$tmp/.claude/autodrive.lock"
    run_load_handoff "$tmp" clear
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    split_output "$output"
    [[ "$MSG" == *"autodrive left in place — the sentinel's lock could not be set up"* ]]
    [[ "$CTX" == *"hook smoke test"* ]]
}

@test "load-compact (a link at the lock: the pending file is left and the note says the lock could not be set up)" {
    printf '## Remaining\n\n- finish the parser\n' > "$tmp/TODO.md"
    seed_pending "$tmp" compact "/compact" "continue"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    : > "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$tmp/.claude/autodrive.lock"
    run_load_compact "$tmp"
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    split_output "$output"
    [[ "$MSG" == *"autodrive left in place — the sentinel's lock could not be set up"* ]]
}
