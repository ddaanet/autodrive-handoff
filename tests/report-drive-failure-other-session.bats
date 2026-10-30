#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- report-drive-failure: a sentinel owned by another live session ---
#
# Every session sharing the root runs this hook — the background session the
# harness starts after a `git commit` among them — so another session's prompt
# says nothing about whether the owner is gone. The owner is live when its
# transcript, beside this session's, was written within HANDOFF_OWNER_LIVE_SECS.

@test "report-drive-failure (armed by another live session: left untouched, nothing said)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed sess-owner" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (armed by another session, its transcript stale: swept)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner 3600)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale autodrive discarded — the drive mod")' >/dev/null
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner=sess-owner\t'* ]]
    # Its lines are a dead session's: offering them for typing would replay them
    # into this conversation.
    echo "$output" | jq -e '.systemMessage | test("Type in order") | not' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("/rename A Title") | not' >/dev/null
}

@test "report-drive-failure (armed by another session with no transcript of its own: swept)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript "$SESSION_ID")"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale autodrive discarded")' >/dev/null
}

@test "report-drive-failure (armed by another session, no transcript_path in the input: swept)" {
    seed_owned armed sess-owner
    seed_transcript sess-owner >/dev/null
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale autodrive discarded")' >/dev/null
}

# The owner's own next prompt is the exact discriminator for an aborted turn, and
# its own transcript is always fresh: liveness must not exempt the owner itself.
@test "report-drive-failure (armed by this session, its transcript fresh: swept as an aborted turn)" {
    seed_owned armed "$SESSION_ID"
    tp="$(seed_transcript "$SESSION_ID")"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("the drive mod did not run it")' >/dev/null
}

@test "report-drive-failure (liveness window: HANDOFF_OWNER_LIVE_SECS sets it, 600 s by default)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner 120)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$output" = "" ]
    [ -e "$tmp/.claude/autodrive" ]

    HANDOFF_OWNER_LIVE_SECS=60 run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ ! -e "$tmp/.claude/autodrive" ]
}

@test "report-drive-failure (held by another live session: left untouched, nothing said)" {
    seed_owned held sess-owner
    tp="$(seed_transcript sess-owner)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "held sess-owner" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

# The pair to the stale-armed row above, over the same transcript age: a held
# file waits on a human, so a quiet transcript sweeps the armed file and not
# this one.
@test "report-drive-failure (held by another session, its transcript stale: left untouched)" {
    seed_owned held sess-owner
    tp="$(seed_transcript sess-owner 3600)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "held sess-owner" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (held by another session with no transcript of its own: left untouched)" {
    seed_owned held sess-owner
    tp="$(seed_transcript "$SESSION_ID")"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "held sess-owner" ]
}

@test "report-drive-failure (failure and stale file: one report covering both)" {
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    seed_drive "$tmp" "compact" "/compact" "continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -sr 'length')" = "1" ]
    echo "$output" | jq -e '.systemMessage | test("rejected before it ran")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
}
