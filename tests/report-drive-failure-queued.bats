#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- report-drive-failure: a prompt queued into the arming turn ---
#
# A prompt typed while the turn that armed the transition is still running
# fires UserPromptSubmit inside that turn, before its Stop, and carries that
# turn's prompt_id; one typed at an idle composer, after an Esc, carries a fresh
# one. inject-checkpoint-root.sh leaves the prompt_id of the turn that ran the
# checkpoint in a per-session marker (its rows are in
# tests/inject-checkpoint-root.bats); this hook only reads it, and only for an
# armed file this session owns, so the rows here write the marker themselves. A
# queued `rename` is left for the drive to take at that turn's end; a queued
# `clear` or `compact` is swept and cancelled with no lines offered, since the
# prompt is lost as handoff state. See
# plans/reports/2026-10-16-queued-prompt-sweep-repro.md and
# plans/reports/2026-10-16-queued-prompt-with-clear-compact.md.

cancel_msg='transition cancelled — a prompt arrived before it ran'

# <output> <command> <skill> — <output> is the cancel report for a queued clear
# or compact, whole: the user's message is the cancel fragment and offers no
# lines, and the agent's note is the directive for <command> and <skill>
# (`/clear` and `handoff`, `/compact` and `precompact`), nothing before or after.
assert_cancel_report() {
    local note
    note="The driven $2 did not run. Answer this prompt, then run the $3 skill again with the same transition, unless this prompt changes that."
    split_output "$1"
    [ "$MSG" = $'\033[0m'"handoff: $cancel_msg." ]
    [ "$CTX" = "$note" ]
}

@test "report-drive-failure (queued prompt: an owner's armed rename is spared, nothing said or recorded)" {
    seed_queued rename
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

# The pair to the row above over the same fixture: the marker holds another
# prompt's id, so this is the idle-composer prompt after an Esc, and the sweep
# is the one that exists for it. Fails if the compare uses the id this very
# call carries as the marker's.
@test "report-drive-failure (fresh prompt id: the owner's armed rename is swept with the unloaded-mod note)" {
    seed_armed_kind rename
    seed_prompt_marker arming-prompt
    PROMPT_ID=idle-composer-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES"
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner='"$SESSION_ID"$'\tkind=rename\t'* ]]
}

@test "report-drive-failure (queued prompt: an owner's armed clear is swept and recorded, cancelled with no lines)" {
    seed_queued clear
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_cancel_report "$output" /clear handoff
    [ "$(wc -l < "$tmp/.claude/autodrive.swept")" -eq 1 ]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner='"$SESSION_ID"$'\tkind=clear\t'* ]]
    marker_holds arming-prompt
}

@test "report-drive-failure (fresh prompt id: the owner's armed clear is swept with the unloaded-mod note)" {
    seed_armed_kind clear
    seed_prompt_marker arming-prompt
    PROMPT_ID=idle-composer-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES"
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner='"$SESSION_ID"$'\tkind=clear\t'* ]]
}

@test "report-drive-failure (queued prompt: an owner's armed compact is swept and recorded, cancelled with no lines)" {
    seed_queued compact
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_cancel_report "$output" /compact precompact
    [ "$(wc -l < "$tmp/.claude/autodrive.swept")" -eq 1 ]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner='"$SESSION_ID"$'\tkind=compact\t'* ]]
    marker_holds arming-prompt
}

@test "report-drive-failure (fresh prompt id: the owner's armed compact is swept with the unloaded-mod note)" {
    seed_armed_kind compact
    seed_prompt_marker arming-prompt
    PROMPT_ID=idle-composer-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES"
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner='"$SESSION_ID"$'\tkind=compact\t'* ]]
}

# A Claude Code that sends no prompt_id (2.1.287 is not known to) cannot be told
# queued from idle, so the sweep is as today and the armed note adds the cause
# it cannot rule out. The marker, here holding an id, is not consulted.
@test "report-drive-failure (no prompt_id in the input: swept as today, the note names a typed-ahead prompt)" {
    seed_armed_kind clear
    seed_prompt_marker arming-prompt
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = $'\033[0m'"handoff: $unloaded_msg."$'\nType in order:\n'"$LINES" ]
    [[ "$CTX" == *"safe-mode"* && "$CTX" == *"2.1.287"* && "$CTX" == *"managed settings"* ]]
    [[ "$CTX" == *"$noprompt_phrase"* ]]
    [[ "$CTX" == *"Present these lines to the user in a fenced code block, to type in order:"$'\n'"$LINES" ]]
}

# An absent id and an absent marker, or one holding an empty id, are both empty,
# and equal: the compare must need the id to be non-empty. The directory exists,
# as it does once a session has started, so the marker is looked for.
@test "report-drive-failure (no prompt_id and no marker: swept, not mistaken for a queued prompt)" {
    local marker
    for marker in absent empty; do
        seed_armed_kind rename
        rm -rf "$HANDOFF_POINTER_DIR"
        make_pointer_dir
        [ "$marker" = absent ] || seed_prompt_marker ""
        run_report_failure "$tmp"
        [ "$status" -eq 0 ]
        [ ! -e "$tmp/.claude/autodrive" ]
        split_output "$output"
        [ "$MSG" = $'\033[0m'"handoff: $unloaded_msg."$'\nType in order:\n'"$LINES" ]
        [[ "$CTX" == *"$noprompt_phrase"* ]]
    done
}

@test "report-drive-failure (no marker yet, the first prompt of the session: swept with the unloaded-mod note)" {
    seed_armed_kind rename
    make_pointer_dir
    [ ! -e "$HANDOFF_POINTER_DIR/$prompt_marker" ]
    PROMPT_ID=first-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES"
}

# A pointer directory that does not exist yet (nothing has ever written a
# marker, so there is none) is `absent`, which settles the id as another turn's.
# It is not an untrusted directory, which leaves the id unsettled.
@test "report-drive-failure (no pointer directory at all: the marker is absent, swept without the typed-ahead phrase)" {
    seed_armed_kind rename
    [ ! -e "$HANDOFF_POINTER_DIR" ]
    PROMPT_ID=first-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES"
}

# The marker is compared whole, NUL-terminated on one side and carried by jq on
# the other: a read that trims (`read -r`), strips trailing newlines (`$(cat)`)
# or stops at the first line would match these pairs. Each id is the other's
# near-miss; the one that matches exactly is spared, and the near misses are not.
@test "report-drive-failure (queued prompt: an id with leading and trailing spaces and a newline, matching exactly, is spared)" {
    local pid=$' lead  and trail \nsecond line \n'
    seed_armed_kind rename
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    seed_prompt_marker "$pid"
    PROMPT_ID="$pid" run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$tmp/.claude/autodrive"
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (an id differing from the marker's by whitespace alone is swept, not spared)" {
    local pid
    for pid in $'p1 ' $'p1\n' ' p1' $'p1\nextra'; do
        seed_armed_kind rename
        seed_prompt_marker p1
        PROMPT_ID="$pid" run_report_failure "$tmp"
        [ "$status" -eq 0 ]
        [ ! -e "$tmp/.claude/autodrive" ]
        assert_unloaded_report "$output" "$LINES"
    done
    # The other way round: the marker is the longer.
    for pid in p1 $'p1\n'; do
        seed_armed_kind rename
        seed_prompt_marker $'p1 \n'
        PROMPT_ID="$pid" run_report_failure "$tmp"
        [ ! -e "$tmp/.claude/autodrive" ]
        assert_unloaded_report "$output" "$LINES"
    done
}

# This hook only reads the marker. Whatever the prompt carries, and whatever
# state the sentinel is in, nothing is created, changed or left behind.
@test "report-drive-failure (a prompt with an id writes no marker, whatever the sentinel does)" {
    make_pointer_dir
    PROMPT_ID=prompt-one run_report_failure "$tmp"
    [ "$output" = "" ]
    [ -z "$(ls -A "$HANDOFF_POINTER_DIR")" ]
    seed_armed_kind rename
    PROMPT_ID=prompt-two run_report_failure "$tmp"
    [ ! -e "$tmp/.claude/autodrive" ]
    [ -z "$(ls -A "$HANDOFF_POINTER_DIR")" ]
    seed_prompt_marker older-prompt
    touch -t 202001010000 "$HANDOFF_POINTER_DIR/$prompt_marker"
    seed_armed_kind rename
    PROMPT_ID=prompt-three run_report_failure "$tmp"
    [ ! -e "$tmp/.claude/autodrive" ]
    [ "$(ls -A "$HANDOFF_POINTER_DIR")" = "$prompt_marker" ]
    marker_holds older-prompt
    [ -z "$(find "$HANDOFF_POINTER_DIR/$prompt_marker" -newermt 2020-01-02)" ]
}

# The marker is per session: another session's file whose owner is live is left
# alone whatever the marker and the input say, and one whose owner is gone is
# swept as today: sparing or cancelling a queued file is the owner's alone.
@test "report-drive-failure (queued id, armed by another live session: left untouched, nothing said)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner)"
    seed_prompt_marker arming-prompt
    PROMPT_ID=arming-prompt run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed sess-owner" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (queued id, armed by another session whose transcript is stale: swept as today, not as queued)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner 3600)"
    seed_prompt_marker arming-prompt
    PROMPT_ID=arming-prompt run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = $'\033[0m'"handoff: $unloaded_msg." ]
    [[ "$CTX" == *"safe-mode"* ]]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner=sess-owner\t'* ]]
}

# States other than armed do not look at the id.
@test "report-drive-failure (queued id, a held or pending file: left untouched, nothing said)" {
    seed_prompt_marker arming-prompt
    seed_owned held "$SESSION_ID"
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "held $SESSION_ID" ]
    seed_pending "$tmp" compact "/compact" "continue"
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (queued id, a malformed file: swept as malformed, not spared)" {
    seed_drive "$tmp" "clear" "/rename A Title"
    seed_prompt_marker arming-prompt
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = $'\033[0m'"handoff: stale autodrive discarded — it does not parse in this version's format." ]
}

# The marker's guards are the drift marker's. A link at the name is not read: one
# naming a file that holds the very id of the input must not spare the file.
@test "report-drive-failure (a symlinked prompt marker holding the current id is not read: the file is swept)" {
    make_pointer_dir
    printf '%s\0' arming-prompt > "$BATS_TEST_TMPDIR/planted-marker"
    ln -s "$BATS_TEST_TMPDIR/planted-marker" "$HANDOFF_POINTER_DIR/$prompt_marker"
    seed_armed_kind rename
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES" unsettled
}

# <directory> — an armed rename, and in <directory> a marker holding the id the
# input will carry: a directory the hook must not read, since a read through it
# would spare the file.
