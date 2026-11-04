#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- _lib.sh: handoff_drive_read shape matrix ---
#
# Line 1 is the state and line 2 the kind, `continue` flagged on the two driven
# kinds; the kind fixes whether line 3 is required, optional or absent. The file
# carries data only: the commands and the one prompt are literals in the mod, so
# a line is never a command name or prompt text, only a title or a focus.

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

@test "handoff_drive_read (rename): the title is the argument, no continuation" {
    read_drive "armed sess-42" "rename" "Driven Transitions"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_KIND" = rename ]
    [ "$DRIVE_ARG" = "Driven Transitions" ]
    [ "$DRIVE_CONTINUE" -eq 0 ]
}

@test "handoff_drive_read (compact continue): the focus is the argument, continuation flagged" {
    read_drive "armed sess-42" "compact continue" "focus on the parser"
    [ "$DRIVE_KIND" = compact ]
    [ "$DRIVE_ARG" = "focus on the parser" ]
    [ "$DRIVE_CONTINUE" -eq 1 ]
}

@test "handoff_drive_read (compact continue, bare): accepted, no focus" {
    read_drive "armed sess-42" "compact continue"
    [ "$DRIVE_KIND" = compact ]
    [ "$DRIVE_ARG" = "" ]
    [ "$DRIVE_CONTINUE" -eq 1 ]
}

# FR-G: the prepare marker. Nothing is run, but the transition is expected, and
# that expectation is what the frame's re-injection is gated on.
@test "handoff_drive_read (prepare): legal, no argument, no continuation" {
    read_drive "armed sess-42" "prepare"
    [ "$DRIVE_KIND" = prepare ]
    [ "$DRIVE_ARG" = "" ]
    [ "$DRIVE_CONTINUE" -eq 0 ]
}

@test "handoff_drive_read (clear continue): the title is the argument, continuation flagged" {
    read_drive "armed sess-42" "clear continue" "A Title"
    [ "$DRIVE_KIND" = clear ]
    [ "$DRIVE_ARG" = "A Title" ]
    [ "$DRIVE_CONTINUE" -eq 1 ]
}

# The continuation is optional on both driven kinds: driving a transition and
# submitting a prompt into what it opens are separate decisions, and the cross
# product is what the two payload fields express.
@test "handoff_drive_read (clear, no continuation): the flag is clear" {
    read_drive "armed sess-42" "clear" "A Title"
    [ "$DRIVE_KIND" = clear ]
    [ "$DRIVE_CONTINUE" -eq 0 ]
}

@test "handoff_drive_read (compact, no continuation): the flag is clear" {
    read_drive "armed sess-42" "compact" "focus on the parser"
    [ "$DRIVE_KIND" = compact ]
    [ "$DRIVE_ARG" = "focus on the parser" ]
    [ "$DRIVE_CONTINUE" -eq 0 ]
}

@test "handoff_drive_read (compact, bare, no continuation): legal" {
    read_drive "armed sess-42" "compact"
    [ "$DRIVE_KIND" = compact ]
    [ "$DRIVE_ARG" = "" ]
}

# The variables are reset by every read: a caller reading a second file must not
# see the first one's argument or flag.
@test "handoff_drive_read (the argument and flag do not carry over to the next read)" {
    read_drive "armed sess-42" "clear continue" "A Title"
    read_drive "armed sess-42" "prepare"
    [ "$DRIVE_ARG" = "" ]
    [ "$DRIVE_CONTINUE" -eq 0 ]
}

# The state drive-take.sh has already taken. The parser does not know which caller
# wants which state — it reports the value and the gates decide.
@test "handoff_drive_read (pending): parsed like any other state" {
    read_drive "pending" "clear continue" "A Title"
    [ "$DRIVE_STATE" = pending ]
    [ "$DRIVE_KIND" = clear ]
    [ "$DRIVE_CONTINUE" -eq 1 ]
}

@test "handoff_drive_read (unknown kind): rejected, naming the kinds" {
    run read_drive "armed sess-42" "reboot" "now"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition kind"* ]]
}

# The state a memory approval holds a driven transition in, so it does not run
# ahead of a turn about to end on the approval question.
# It names its owner: the session whose approval it waits on.
@test "handoff_drive_read (held): parsed like any other state, and names its owner" {
    read_drive "held sess-42" "clear continue" "A Title"
    [ "$DRIVE_STATE" = held ]
    [ "$DRIVE_OWNER" = sess-42 ]
    [ "$DRIVE_KIND" = clear ]
    [ "$DRIVE_CONTINUE" -eq 1 ]
}

# An unowned `held` names no session, so nothing can tell whose approval it
# waits on — which is exactly the file the sweep and handoff-approved must be
# able to reject.
@test "handoff_drive_read (held with no owner): rejected, naming the owner" {
    run read_drive "held" "clear continue" "A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"session"* ]]
}

# `armed` names its owner too: the session whose turn end takes it. Every
# session sharing the root runs the UserPromptSubmit sweep, and only the owner
# tells another session's prompt from the owner's own next one.
@test "handoff_drive_read (armed): names its owner" {
    read_drive "armed sess-42" "clear continue" "A Title"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_OWNER" = sess-42 ]
}

@test "handoff_drive_read (armed with no owner): rejected, naming the owner" {
    run read_drive "armed" "clear continue" "A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must name the session"* ]]
}

@test "handoff_drive_read (armed with two words for an owner): rejected" {
    run read_drive "armed sess-42 extra" "clear continue" "A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"one session id"* ]]
}

# Rejected as an owned state, not as an unknown one: `pending` is a state this
# parser knows, and the reason has to name what is actually wrong with the line,
# or the same message covers a typo and this. Past the take nothing is the
# owner's to decide: the confirming SessionStart consumes it in whichever
# session the transition opened.
@test "handoff_drive_read (owner on pending): rejected" {
    run read_drive "pending sess-42" "clear continue" "A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no session"* ]]
}

# Read an owned file first: the owner must be cleared by the next read, or a
# caller comparing it acts on the previous file's session — which is the whole
# discriminator.
@test "handoff_drive_read (pending after held): no owner carried over" {
    read_drive "held sess-42" "clear" "A Title"
    [ "$DRIVE_OWNER" = sess-42 ]
    read_drive "pending" "clear" "A Title"
    [ "$DRIVE_STATE" = pending ]
    [ "$DRIVE_OWNER" = "" ]
}

@test "handoff_drive_read (unknown state): rejected, naming the states" {
    run read_drive "queued" "clear continue" "A Title"
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
    run read_drive "clear continue" "A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition state"* ]]
}

@test "handoff_drive_read (empty file): rejected" {
    run read_drive ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition state"* ]]
}

# Every malformed form is refused through rc=1 with the reason in DRIVE_ERR.
@test "handoff_drive_read (rename or clear without the title): rejected" {
    run read_drive "armed sess-42" "rename"
    [ "$status" -ne 0 ]
    [[ "$output" == *"title"* ]]

    run read_drive "armed sess-42" "clear"
    [ "$status" -ne 0 ]
    [[ "$output" == *"title"* ]]

    run read_drive "armed sess-42" "clear continue"
    [ "$status" -ne 0 ]
}

@test "handoff_drive_read (a blank line 3): rejected on every kind that takes one" {
    run read_drive "armed sess-42" "rename" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"must not be blank"* ]]

    run read_drive "armed sess-42" "rename" "   "
    [ "$status" -ne 0 ]

    run read_drive "armed sess-42" "clear" "  "
    [ "$status" -ne 0 ]

    run read_drive "armed sess-42" "compact" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"must not be blank"* ]]

    run read_drive "armed sess-42" "compact continue" "   "
    [ "$status" -ne 0 ]
}

@test "handoff_drive_read (a fourth line): rejected on every kind" {
    run read_drive "armed sess-42" "rename" "A Title" "extra line"
    [ "$status" -ne 0 ]
    [[ "$output" == *"4 lines"* ]]

    run read_drive "armed sess-42" "clear continue" "A Title" "extra line"
    [ "$status" -ne 0 ]

    run read_drive "armed sess-42" "compact continue" "focus" "extra line"
    [ "$status" -ne 0 ]
    [[ "$output" == *"4 lines"* ]]
}

@test "handoff_drive_read (prepare with a line 3): rejected" {
    run read_drive "armed sess-42" "prepare" "a focus"
    [ "$status" -ne 0 ]
    [[ "$output" == *"takes no line 3"* ]]
}

@test "handoff_drive_read (continue where the kind takes none: rename, prepare): rejected" {
    run read_drive "armed sess-42" "rename continue" "A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"takes no \`continue\`"* ]]

    run read_drive "armed sess-42" "prepare continue"
    [ "$status" -ne 0 ]
    [[ "$output" == *"takes no \`continue\`"* ]]
}

@test "handoff_drive_read (an unknown second token or spacing on line 2): rejected" {
    run read_drive "armed sess-42" "clear now" "A Title"
    [ "$status" -ne 0 ]

    run read_drive "armed sess-42" "clear  continue" "A Title"
    [ "$status" -ne 0 ]

    run read_drive "armed sess-42" "compact continue now"
    [ "$status" -ne 0 ]

    run read_drive "armed sess-42" "continue clear" "A Title"
    [ "$status" -ne 0 ]
}

# The old format is refused or, where line 3 is a free argument, is only an
# argument. None of these is a command to the mod, which holds the commands.
@test "handoff_drive_read (old format, a /-line kind): refused as an unknown kind" {
    run read_drive "armed sess-42" "/rename x"
    [ "$status" -ne 0 ]
    run read_drive "armed sess-42" "/clear"
    [ "$status" -ne 0 ]
    run read_drive "armed sess-42" "/plugin marketplace add hacker1337/payload"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition kind"* ]]
}

@test "handoff_drive_read (old format, a prose line 2): refused as an unknown kind" {
    run read_drive "armed sess-42" "Continue where the previous context stopped."
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition kind"* ]]
}

@test "handoff_drive_read (old format clear: kind, /rename, /clear, prose): refused, five and four lines" {
    run read_drive "armed sess-42" "clear" "/rename x" "/clear" "Continue where the previous context stopped."
    [ "$status" -ne 0 ]
    [[ "$output" == *"5 lines"* ]]

    run read_drive "armed sess-42" "clear" "/rename x" "/clear"
    [ "$status" -ne 0 ]
    [[ "$output" == *"4 lines"* ]]
}

@test "handoff_drive_read (old format compact with prose after the command): refused, four lines" {
    run read_drive "armed sess-42" "compact" "/compact" "Continue where the previous context stopped."
    [ "$status" -ne 0 ]
    [[ "$output" == *"4 lines"* ]]
}

# Where line 3 is a free argument, a slash line is only text: the mod passes it
# on as an argument of its own literal command and never as a command.
@test "handoff_drive_read (a /-line as line 3): only an argument" {
    read_drive "armed sess-42" "rename" "/plugin marketplace add hacker1337/payload"
    [ "$DRIVE_KIND" = rename ]
    [ "$DRIVE_ARG" = "/plugin marketplace add hacker1337/payload" ]

    read_drive "armed sess-42" "compact" "/clear"
    [ "$DRIVE_KIND" = compact ]
    [ "$DRIVE_ARG" = "/clear" ]

    read_drive "armed sess-42" "clear continue" "/rename x"
    [ "$DRIVE_ARG" = "/rename x" ]
}

@test "handoff_drive_read (old format rename, a /rename line 3): only the title" {
    read_drive "armed sess-42" "rename" "/rename x"
    [ "$DRIVE_ARG" = "/rename x" ]
}

# --- _lib.sh: handoff_drive_lines, the display renderer ---

# <kind> <arg> <continue>: render into DRIVE_LINES.
render_lines() {
    DRIVE_KIND="$1" DRIVE_ARG="$2" DRIVE_CONTINUE="$3"
    handoff_drive_lines
}

@test "handoff_drive_lines (rename, clear, compact): the lines a person would type, in order" {
    render_lines rename "A Title" 0
    [ "${DRIVE_LINES[*]}" = "/rename A Title" ]
    [ "${#DRIVE_LINES[@]}" -eq 1 ]

    render_lines clear "A Title" 0
    [ "${#DRIVE_LINES[@]}" -eq 2 ]
    [ "${DRIVE_LINES[0]}" = "/rename A Title" ]
    [ "${DRIVE_LINES[1]}" = "/clear" ]

    render_lines clear "A Title" 1
    [ "${#DRIVE_LINES[@]}" -eq 3 ]
    [ "${DRIVE_LINES[2]}" = "$HANDOFF_CONTINUATION" ]

    render_lines compact "" 0
    [ "${#DRIVE_LINES[@]}" -eq 1 ]
    [ "${DRIVE_LINES[0]}" = "/compact" ]

    render_lines compact "keep it" 1
    [ "${#DRIVE_LINES[@]}" -eq 2 ]
    [ "${DRIVE_LINES[0]}" = "/compact keep it" ]
    [ "${DRIVE_LINES[1]}" = "$HANDOFF_CONTINUATION" ]
}

@test "handoff_drive_lines (prepare): nothing to type" {
    DRIVE_LINES=(stale)
    render_lines prepare "" 0
    [ "${#DRIVE_LINES[@]}" -eq 0 ]
}

# --- _lib.sh: handoff_drive_plan ---

@test "handoff_drive_plan (a clear: data only, key order kind, arg, continue, failFile, message)" {
    read_drive "armed sess-42" "clear continue" "A Title"
    run handoff_drive_plan clear "/x/.claude/autodrive.failed"
    [ "$status" -eq 0 ]
    [ "$output" = '{"kind":"clear","arg":"A Title","continue":true,"failFile":"/x/.claude/autodrive.failed","message":"handoff: will run /rename A Title once the turn ends."}' ]
}

@test "handoff_drive_plan (a rename: continue is a JSON false)" {
    read_drive "armed sess-42" "rename" "A Title"
    run handoff_drive_plan rename "/x/f"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.continue, .arg]' <<<"$output")" = '[false,"A Title"]' ]
}

# No writer of the sentinel makes a link, and a repository can commit one to
# anything readable: following it would parse that file, quote its first line
# into a report and let a later rewrite land on it. A link is refused before a
# byte is read, whatever it names.
@test "handoff_drive_read (a symlink to a well-formed sentinel): refused, nothing parsed" {
    printf '%s\n' "armed sess-42" "rename" "Linked" > "$other/sentinel"
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
    printf '%s\n' "armed sess-42" "clear continue" "A Title" \
        > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
clear continue
A Title" ]
}

# The FR-G marker is two lines, so the tail below line 1 is a single line.
@test "handoff_drive_arm (two-line file: still just the state line)" {
    printf '%s\n' "armed sess-42" "prepare" > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
prepare" ]
}

# The helper writes line 1 as given, so the owner is the caller's to carry or
# drop: handoff-approved keeps it across held -> armed, drive-take.sh drops it
# on armed -> pending.
@test "handoff_drive_arm (held -> armed with its owner: still parses, owner kept)" {
    printf '%s\n' "held sess-42" "clear" "A Title" \
        > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" "armed sess-42"
    handoff_drive_read "$BATS_TEST_TMPDIR/sentinel"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_OWNER" = sess-42 ]
}

@test "handoff_drive_arm (armed -> pending: the owner goes with the state)" {
    printf '%s\n' "armed sess-42" "clear" "A Title" \
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
    printf '%s\n' "armed sess-42" "compact continue" > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'sentinel*' | wc -l)" -eq 1 ]
}

# The temporary file is mktemp's, never a fixed or PID-derived name: a
# repository can commit links at as many such names as it likes, and the arm
# would write the state line through one and rename the link over the
# sentinel. `$$` here is the PID the helper sees, the name it used to take.
@test "handoff_drive_arm (a link at the old temporary name: not written through, the sentinel stays a file)" {
    printf '%s\n' "armed sess-42" "compact" "keep it" > "$BATS_TEST_TMPDIR/sentinel"
    ln -s "$other/planted" "$BATS_TEST_TMPDIR/sentinel.arming.$$"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ ! -e "$other/planted" ]
    [ ! -L "$BATS_TEST_TMPDIR/sentinel" ]
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
compact
keep it" ]
}

# A link to a directory put at the sentinel after it was read: mv would move
# the temporary file into that directory. The rename replaces the link.
# shellcheck disable=SC2317   # tail() below is called by handoff_drive_arm, in _lib.sh, which setup sources
@test "handoff_drive_arm (the sentinel became a link to a directory: replaced, nothing moved into it)" {
    printf '%s\n' "armed sess-42" "compact" > "$BATS_TEST_TMPDIR/sentinel"
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
