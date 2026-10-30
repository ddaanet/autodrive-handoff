#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- _lib.sh: handoff_drive_read shape matrix ---
#
# Line 1 is the kind and the kind fixes the shape, so the remaining lines need
# no separator and each kind keeps its own rules. The lines are the literal
# commands the mod runs: it must not know which command any kind uses, and
# validation is what anchors it — the nth line of kind k must begin with the
# expected command literal, so the file cannot be made to run something else.

# Write the args as lines of a sentinel and read it back. On rejection the
# reason is printed, so a `run read_drive ...` can assert on it — the reader
# itself only sets DRIVE_ERR, which a subshell would swallow. Call it bare (not
# under `run`) when the test needs the DRIVE_* variables it populates.
read_drive() {
    printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_read "$BATS_TEST_TMPDIR/sentinel" && return 0
    printf '%s\n' "$DRIVE_ERR"
    return 1
}

@test "handoff_drive_read (rename): one before-line, no after-line" {
    read_drive "armed sess-42" "rename" "/rename Driven Transitions"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_KIND" = rename ]
    [ "${#DRIVE_BEFORE[@]}" -eq 1 ]
    [ "${DRIVE_BEFORE[0]}" = "/rename Driven Transitions" ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

@test "handoff_drive_read (compact): command before, prose after" {
    read_drive "armed sess-42" "compact" "/compact focus on the parser" "continue with task 3"
    [ "$DRIVE_KIND" = compact ]
    [ "${DRIVE_BEFORE[0]}" = "/compact focus on the parser" ]
    [ "${DRIVE_AFTER[0]}" = "continue with task 3" ]
}

@test "handoff_drive_read (compact, bare command): accepted, /compact takes no argument" {
    read_drive "armed sess-42" "compact" "/compact" "continue with task 3"
    [ "${DRIVE_BEFORE[0]}" = "/compact" ]
}

# FR-G: the kind line alone. Nothing is run, but the transition is expected,
# and that expectation is what the frame's re-injection is gated on.
@test "handoff_drive_read (compact, kind line alone): legal, both sequences empty" {
    read_drive "armed sess-42" "compact"
    [ "$DRIVE_KIND" = compact ]
    [ "${#DRIVE_BEFORE[@]}" -eq 0 ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

@test "handoff_drive_read (clear): two before-lines in order, prose after" {
    read_drive "armed sess-42" "clear" "/rename A Title" "/clear" "pick up per the task file"
    [ "$DRIVE_KIND" = clear ]
    [ "${#DRIVE_BEFORE[@]}" -eq 2 ]
    [ "${DRIVE_BEFORE[0]}" = "/rename A Title" ]
    [ "${DRIVE_BEFORE[1]}" = "/clear" ]
    [ "${DRIVE_AFTER[0]}" = "pick up per the task file" ]
}

# The continuation is optional on both driven kinds: driving a transition and
# submitting a prompt into what it opens are separate decisions, and the cross
# product is what the two payload fields express.
@test "handoff_drive_read (clear, no continuation): nothing submitted after" {
    read_drive "armed sess-42" "clear" "/rename A Title" "/clear"
    [ "$DRIVE_KIND" = clear ]
    [ "${#DRIVE_BEFORE[@]}" -eq 2 ]
    [ "${DRIVE_BEFORE[1]}" = "/clear" ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

@test "handoff_drive_read (compact, no continuation): nothing submitted after" {
    read_drive "armed sess-42" "compact" "/compact focus on the parser"
    [ "$DRIVE_KIND" = compact ]
    [ "${DRIVE_BEFORE[0]}" = "/compact focus on the parser" ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

# The state drive-take.sh has already taken. The parser does not know which caller
# wants which state — it reports the value and the gates decide.
@test "handoff_drive_read (pending): parsed like any other state" {
    read_drive "pending" "clear" "/rename A Title" "/clear" "pick up per the task file"
    [ "$DRIVE_STATE" = pending ]
    [ "$DRIVE_KIND" = clear ]
    [ "${DRIVE_AFTER[0]}" = "pick up per the task file" ]
}

@test "handoff_drive_read (unknown kind): rejected, naming the kinds" {
    run read_drive "armed sess-42" "reboot" "/reboot"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition kind"* ]]
}

# The state a memory approval holds a typing transition in, so the keystrokes
# do not reach a pane whose turn is about to end on the approval question.
# It names its owner: the session whose approval it waits on.
@test "handoff_drive_read (held): parsed like any other state, and names its owner" {
    read_drive "held sess-42" "clear" "/rename A Title" "/clear" "pick up per the task file"
    [ "$DRIVE_STATE" = held ]
    [ "$DRIVE_OWNER" = sess-42 ]
    [ "$DRIVE_KIND" = clear ]
    [ "${DRIVE_AFTER[0]}" = "pick up per the task file" ]
}

# An unowned `held` names no session, so nothing can tell whose approval it
# waits on — which is exactly the file the sweep and handoff-approved must be
# able to reject.
@test "handoff_drive_read (held with no owner): rejected, naming the owner" {
    run read_drive "held" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"session"* ]]
}

# `armed` names its owner too: the session whose turn end takes it. Every
# session sharing the root runs the UserPromptSubmit sweep, and only the owner
# tells another session's prompt from the owner's own next one.
@test "handoff_drive_read (armed): names its owner" {
    read_drive "armed sess-42" "clear" "/rename A Title" "/clear" "resume"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_OWNER" = sess-42 ]
}

@test "handoff_drive_read (armed with no owner): rejected, naming the owner" {
    run read_drive "armed" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must name the session"* ]]
}

@test "handoff_drive_read (armed with two words for an owner): rejected" {
    run read_drive "armed sess-42 extra" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"one session id"* ]]
}

# Rejected as an owned state, not as an unknown one: `pending` is a state this
# parser knows, and the reason has to name what is actually wrong with the line,
# or the same message covers a typo and this. Past the take nothing is the
# owner's to decide: the confirming SessionStart consumes it in whichever
# session the transition opened.
@test "handoff_drive_read (owner on pending): rejected" {
    run read_drive "pending sess-42" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no session"* ]]
}

# Read an owned file first: the owner must be cleared by the next read, or a
# caller comparing it acts on the previous file's session — which is the whole
# discriminator.
@test "handoff_drive_read (pending after held): no owner carried over" {
    read_drive "held sess-42" "clear" "/rename A Title" "/clear"
    [ "$DRIVE_OWNER" = sess-42 ]
    read_drive "pending" "clear" "/rename A Title" "/clear"
    [ "$DRIVE_STATE" = pending ]
    [ "$DRIVE_OWNER" = "" ]
}

@test "handoff_drive_read (unknown state): rejected, naming the states" {
    run read_drive "queued" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition state"* ]]
    [[ "$output" == *"queued"* ]]
}

# The state line alone. It says which state, but there is no transition for it
# to be the state of.
@test "handoff_drive_read (state line alone): rejected, naming the missing kind" {
    run read_drive "armed sess-42"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition kind"* ]]
}

# The old autorename shape, and the shape this pass replaces. Neither has a
# state line, so both fail on line 1 rather than on anything below it.
@test "handoff_drive_read (bare title, the old autorename shape): rejected" {
    run read_drive "Some Session Title"
    [ "$status" -ne 0 ]
}

@test "handoff_drive_read (a pre-state-line sentinel): rejected on line 1" {
    run read_drive "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition state"* ]]
}

@test "handoff_drive_read (empty file): rejected" {
    run read_drive ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition state"* ]]
}

@test "handoff_drive_read (wrong line count for the kind): rejected, naming the count" {
    run read_drive "armed sess-42" "rename" "/rename A Title" "extra line"
    [ "$status" -ne 0 ]
    [[ "$output" == *"exactly 3 lines"* ]]

    run read_drive "armed sess-42" "clear" "/rename A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"4 or 5 lines"* ]]

    run read_drive "armed sess-42" "compact" "/compact" "continue" "extra"
    [ "$status" -ne 0 ]
    [[ "$output" == *"2, 3 or 4 lines"* ]]
}

@test "handoff_drive_read (command literal not in the kind's slot): rejected" {
    run read_drive "armed sess-42" "clear" "/clear" "/rename A Title" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"line 3"* ]]

    run read_drive "armed sess-42" "compact" "compact now" "continue"
    [ "$status" -ne 0 ]
    [[ "$output" == *"/compact"* ]]
}

@test "handoff_drive_read (/rename with no argument): rejected" {
    run read_drive "armed sess-42" "rename" "/rename"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-empty argument"* ]]

    run read_drive "armed sess-42" "rename" "/rename    "
    [ "$status" -ne 0 ]
}

@test "handoff_drive_read (/clear with an argument): rejected" {
    run read_drive "armed sess-42" "clear" "/rename A Title" "/clear now" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"exactly"* ]]
}

@test "handoff_drive_read (empty continuation prompt): rejected" {
    run read_drive "armed sess-42" "compact" "/compact" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"must not be empty"* ]]
}

# The mod dispatches on the leading character: a `/` line runs as a command,
# prose is submitted as a prompt. A prose line that looks like a command would
# run as the wrong one.
@test "handoff_drive_read (continuation prompt beginning with /): rejected" {
    run read_drive "armed sess-42" "clear" "/rename A Title" "/clear" "/resume the work"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must not begin"* ]]
}

# No writer of the sentinel makes a link, and a repository can commit one to
# anything readable: following it would parse that file, quote its first line
# into a report and let a later rewrite land on it. A link is refused before a
# byte is read, whatever it names.
@test "handoff_drive_read (a symlink to a well-formed sentinel): refused, nothing parsed" {
    printf '%s\n' "armed sess-42" "rename" "/rename Linked" > "$other/sentinel"
    ln -s "$other/sentinel" "$BATS_TEST_TMPDIR/sentinel"
    run handoff_drive_read "$BATS_TEST_TMPDIR/sentinel"
    [ "$status" -ne 0 ]
    handoff_drive_read "$BATS_TEST_TMPDIR/sentinel" || true
    [[ "$DRIVE_ERR" == *"symbolic link"* ]]
    [ "$DRIVE_STATE" = "" ]
    [ "$DRIVE_KIND" = "" ]
}

@test "handoff_drive_read (a dangling symlink): refused as a link" {
    ln -s "$other/nowhere" "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_read "$BATS_TEST_TMPDIR/sentinel" && false
    [[ "$DRIVE_ERR" == *"symbolic link"* ]]
}

# --- _lib.sh: handoff_drive_arm ---

# Everything below line 1 is copied through untouched: the arm never has to know
# the kind's shape, which is what lets one helper serve drive-take.sh and
# handoff-approved.
@test "handoff_drive_arm (rewrites line 1, preserves every line below)" {
    printf '%s\n' "armed sess-42" "clear" "/rename A Title" "/clear" "pick up per the task file" \
        > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
clear
/rename A Title
/clear
pick up per the task file" ]
}

# The FR-G marker is two lines, so the tail below line 1 is a single line.
@test "handoff_drive_arm (two-line file: still just the state line)" {
    printf '%s\n' "armed sess-42" "compact" > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
compact" ]
}

# The helper writes line 1 as given, so the owner is the caller's to carry or
# drop: handoff-approved keeps it across held -> armed, drive-take.sh drops it
# on armed -> pending.
@test "handoff_drive_arm (held -> armed with its owner: still parses, owner kept)" {
    printf '%s\n' "held sess-42" "clear" "/rename A Title" "/clear" \
        > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" "armed sess-42"
    handoff_drive_read "$BATS_TEST_TMPDIR/sentinel"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_OWNER" = sess-42 ]
}

@test "handoff_drive_arm (armed -> pending: the owner goes with the state)" {
    printf '%s\n' "armed sess-42" "clear" "/rename A Title" "/clear" \
        > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(head -n1 "$BATS_TEST_TMPDIR/sentinel")" = "pending" ]
    handoff_drive_read "$BATS_TEST_TMPDIR/sentinel"
    [ "$DRIVE_STATE" = pending ]
    [ "$DRIVE_OWNER" = "" ]
}

# Readers exist concurrently — both loaders, drive-take.sh and the sweep parse this
# file — so a half-written file must never be observable under the
# real name. The temp lands beside it and is renamed over it.
@test "handoff_drive_arm (leaves no temp file behind)" {
    printf '%s\n' "armed sess-42" "compact" "/compact" "continue" > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'sentinel*' | wc -l)" -eq 1 ]
}

# The temporary file is mktemp's, never a fixed or PID-derived name: a
# repository can commit links at as many such names as it likes, and the arm
# would write the state line through one and rename the link over the
# sentinel. `$$` here is the PID the helper sees, the name it used to take.
@test "handoff_drive_arm (a link at the old temporary name: not written through, the sentinel stays a file)" {
    printf '%s\n' "armed sess-42" "compact" "/compact" > "$BATS_TEST_TMPDIR/sentinel"
    ln -s "$other/planted" "$BATS_TEST_TMPDIR/sentinel.arming.$$"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ ! -e "$other/planted" ]
    [ ! -L "$BATS_TEST_TMPDIR/sentinel" ]
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
compact
/compact" ]
}

# A link to a directory put at the sentinel after it was read: mv would move
# the temporary file into that directory. The rename replaces the link.
# shellcheck disable=SC2317   # tail() below is called by handoff_drive_arm, in _lib.sh, which setup sources
@test "handoff_drive_arm (the sentinel became a link to a directory: replaced, nothing moved into it)" {
    printf '%s\n' "armed sess-42" "compact" "/compact" > "$BATS_TEST_TMPDIR/sentinel"
    mkdir -p "$other/dir"
    # The swap lands between the arm's copy of the lines below line 1 and its
    # rename: a `tail` that plants the link as it returns.
    tail() { command tail "$@"; rm -f "$BATS_TEST_TMPDIR/sentinel"; ln -s "$other/dir" "$BATS_TEST_TMPDIR/sentinel"; }
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    unset -f tail
    [ -z "$(ls -A "$other/dir")" ]
    [ ! -L "$BATS_TEST_TMPDIR/sentinel" ]
    [ "$(head -n1 "$BATS_TEST_TMPDIR/sentinel")" = "pending" ]
}
