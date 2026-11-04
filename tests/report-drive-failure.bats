#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- report-drive-failure (UserPromptSubmit: surface a non-delivery) ---
#
# The drive mod has no channel back to the agent: a line it could not run is
# invisible once its turn is over. The mod drops a reason file; this hook is
# what reads it. One channel, since the transition is a singleton.

@test "report-drive-failure (no failure file: silent no-op)" {
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "report-drive-failure (failure present: reports on both channels)" {
    printf '%s\n' "the host did not recognize \`/compact\`" \
        > "$tmp/.claude/autodrive.failed"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage | test("did not recognize")' >/dev/null
    echo "$output" | jq -e \
        '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
    echo "$output" | jq -e \
        '.hookSpecificOutput.additionalContext | test("did not recognize")' >/dev/null
}

# The failure record is the mod's, and the mod observed a rejection only when
# it wrote one: a link there is no such record, and its target's first line
# would be quoted onto both channels. It is removed unread and said so, and a
# pending transition is not cleared on its evidence.
@test "report-drive-failure (the failure record is a symlink: removed unread, said so, pending kept)" {
    printf '%s\n' "LINKED-FAILURE-LINE" > "$other/linked-failed"
    ln -s "$other/linked-failed" "$tmp/.claude/autodrive.failed"
    seed_pending "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -L "$tmp/.claude/autodrive.failed" ]
    [ "$(cat "$other/linked-failed")" = "LINKED-FAILURE-LINE" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    split_output "$output"
    [[ "$MSG" == *"symbolic link"* && "$CTX" == *"symbolic link"* ]]
    [[ "$MSG" != *"LINKED-FAILURE-LINE"* && "$CTX" != *"LINKED-FAILURE-LINE"* ]]
}

# A link put at the failure record between the hook's look at the name and
# its read is not followed either: here `head`, the old reader, plants it.
@test "report-drive-failure (the failure record becomes a symlink before the read: its target is not quoted)" {
    printf '%s\n' "the real reason" > "$tmp/.claude/autodrive.failed"
    printf '%s\n' "LINKED-FAILURE-LINE" > "$other/linked-failed"
    swap_on_first head "$tmp/.claude/autodrive.failed" "$other/linked-failed"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [[ "$MSG" != *"LINKED-FAILURE-LINE"* && "$CTX" != *"LINKED-FAILURE-LINE"* ]]
    [[ "$MSG" == *"the real reason"* ]]
    [ "$(cat "$other/linked-failed")" = "LINKED-FAILURE-LINE" ]
}

@test "report-drive-failure (the failure record is a dangling symlink: removed, said so)" {
    ln -s "$other/nowhere" "$tmp/.claude/autodrive.failed"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -L "$tmp/.claude/autodrive.failed" ]
    split_output "$output"
    [[ "$MSG" == *"symbolic link"* ]]
}

@test "report-drive-failure (consumes the file: reports once, not every prompt)" {
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    run_report_failure "$tmp"
    [ ! -e "$tmp/.claude/autodrive.failed" ]

    run_report_failure "$tmp"
    [ "$output" = "" ]
}

# A failure part-way through a sequence leaves the transition stranded in
# state `pending`: no transition will consume it, and drive-take.sh will not take
# it again from that state.
@test "report-drive-failure (clears a stranded pending file)" {
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    seed_pending "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
}

@test "report-drive-failure (worktree cwd: reads the worktree file)" {
    wt="$(make_worktree wtF)"
    printf '%s\n' "rejected before it ran" > "$wt/.claude/autodrive.failed"
    run_report_failure "$wt"
    [ "$status" -eq 0 ]
    [ ! -e "$wt/.claude/autodrive.failed" ]
    echo "$output" | jq -e '.systemMessage | test("rejected before it ran")' >/dev/null
}

# An autodrive is taken at the turn end after the turn that writes it, and that
# take leaves it `pending` or removes it. So one still in state `armed` at a
# *later* turn's UserPromptSubmit never ran — its turn ended abnormally (Esc,
# crash, quit) or the drive mod did not load. Left alone it is taken by the next
# normal turn end, days later and possibly in another session, driving a stale
# transition into unrelated work.
@test "report-drive-failure (stale autodrive: discards it and reports)" {
    seed_drive "$tmp" "compact continue" "keep the parser work"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
    echo "$output" | jq -e \
        '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
    echo "$output" | jq -e \
        '.hookSpecificOutput.additionalContext | test("autodrive")' >/dev/null
}

@test "report-drive-failure (stale autodrive: reports once, not every prompt)" {
    seed_drive "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ -n "$output" ]

    run_report_failure "$tmp"
    [ "$output" = "" ]
}

# Every sweep leaves a line in .claude/autodrive.swept: the removing session's
# report goes to that session's own channels, so without the record a sentinel
# that vanishes leaves nothing to say who took it, from what state, or how old.
@test "report-drive-failure (a sweep records who removed what: armed)" {
    seed_drive "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    [ "$(wc -l < "$tmp/.claude/autodrive.swept")" -eq 1 ]
    line="$(cat "$tmp/.claude/autodrive.swept")"
    [[ "$line" == *$'\tsweeper='"$SESSION_ID"$'\tstate=armed\towner='"$SESSION_ID"$'\tkind=compact\tage='[0-9]*s$'\tcwd='* ]]
}

@test "report-drive-failure (a sweep records who removed what: armed by another session)" {
    printf '%s\n' "armed other-session" "clear continue" "t" > "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    line="$(cat "$tmp/.claude/autodrive.swept")"
    [[ "$line" == *$'\tsweeper='"$SESSION_ID"$'\tstate=armed\towner=other-session\tkind=clear\t'* ]]
}

@test "report-drive-failure (a sweep records a stranded pending file)" {
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    seed_pending "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=pending\t'* ]]
}

@test "report-drive-failure (nothing swept: no record is written)" {
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

# head closing its end of the pipe early must not take the script down under
# pipefail: the sweep still removes the file and still reports.
@test "report-drive-failure (the record keeps the newest 50 lines, newest first, and the sweep still reports)" {
    # Enough bytes that cat is still writing when head closes its end of the pipe.
    for i in $(seq 1 4000); do printf 'old-%s %0100d\n' "$i" 0; done > "$tmp/.claude/autodrive.swept"
    seed_drive "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
    [ "$(wc -l < "$tmp/.claude/autodrive.swept")" -eq 50 ]
    [[ "$(head -n1 "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\t'* ]]
    [[ "$(sed -n 2p "$tmp/.claude/autodrive.swept")" == "old-1 "* ]]
    [[ "$(tail -n1 "$tmp/.claude/autodrive.swept")" == "old-49 "* ]]
}

# The record is a diagnostic: when it cannot be written, the sweep is not
# blocked and still reports.
@test "report-drive-failure (an unwritable record does not stop the sweep)" {
    mkdir "$tmp/.claude/autodrive.swept"
    seed_drive "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
    [ -z "$(ls -A "$tmp/.claude/autodrive.swept")" ]
}

# mktemp failing (a read-only directory) is the record's failure, not the sweep's.
@test "report-drive-failure (no temporary file can be made: the sweep still reports)" {
    mkdir -p "$BATS_TEST_TMPDIR/stubmk"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubmk/mktemp"
    chmod +x "$BATS_TEST_TMPDIR/stubmk/mktemp"
    seed_drive "$tmp" "compact continue"
    PATH="$BATS_TEST_TMPDIR/stubmk:$PATH" run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

# The record's paths sit in a directory the agent writes freely, so either may
# be a symlink. Followed, the record would copy whatever the link names into a
# file the agent reads, and write over it.
@test "report-drive-failure (the record is a symlink: not read or replaced, the sweep still reports)" {
    printf 'decoy bytes\n' > "$other/decoy"
    ln -s "$other/decoy" "$tmp/.claude/autodrive.swept"
    seed_drive "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
    [ -L "$tmp/.claude/autodrive.swept" ]
    [ "$(cat "$other/decoy")" = "decoy bytes" ]
}

# <command> <path> <link target> — put a stub <command> first on PATH that, the
# first time it runs, replaces <path> with a link to <link target> and then
# runs the real command: a link planted between a hook's check of the name and
# its use of it, at the one moment a test can reach.
swap_on_first() {
    local bin="$BATS_TEST_TMPDIR/swapbin" real
    real="$(command -v "$1")"
    mkdir -p "$bin"
    : > "$BATS_TEST_TMPDIR/swap-once"
    cat > "$bin/$1" <<STUB
#!/usr/bin/env bash
if [ -e "$BATS_TEST_TMPDIR/swap-once" ]; then
    rm -f "$BATS_TEST_TMPDIR/swap-once"
    rm -rf "$2"
    ln -s "$3" "$2"
fi
exec "$real" "\$@"
STUB
    chmod +x "$bin/$1"
    export PATH="$bin:$PATH"
}

# The check and the read are one open: a link put at the record after the hook
# looked at it is not read into the record.
@test "report-drive-failure (the record becomes a symlink after the check: its target is not copied in)" {
    printf 'old line\n' > "$tmp/.claude/autodrive.swept"
    printf 'DECOY-RECORD-BYTES\n' > "$other/decoy"
    seed_drive "$tmp" "compact continue"
    swap_on_first date "$tmp/.claude/autodrive.swept" "$other/decoy"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$(cat "$other/decoy")" = "DECOY-RECORD-BYTES" ]
    [ ! -L "$tmp/.claude/autodrive.swept" ]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" != *"DECOY-RECORD-BYTES"* ]]
}

# The rename replaces a link at the record; `mv` would move the new record
# into the directory the link names.
@test "report-drive-failure (the record becomes a symlink to a directory: nothing lands in it)" {
    mkdir -p "$other/dir"
    seed_drive "$tmp" "compact continue"
    swap_on_first date "$tmp/.claude/autodrive.swept" "$other/dir"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$other/dir")" ]
    [ ! -L "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (a symlink at the old temporary name: not written through, the record still lands)" {
    printf 'decoy bytes\n' > "$other/decoy"
    ln -s "$other/decoy" "$tmp/.claude/autodrive.swept.tmp"
    seed_drive "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    [ "$(cat "$other/decoy")" = "decoy bytes" ]
    [ ! -L "$tmp/.claude/autodrive.swept" ]
    [ "$(wc -l < "$tmp/.claude/autodrive.swept")" -eq 1 ]
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\t'* ]]
}

# The temporary file is the writer's own and is gone once the record is in place.
@test "report-drive-failure (the record leaves no temporary file behind)" {
    seed_drive "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$(cd "$tmp/.claude" && printf '%s\n' autodrive.swept*)" = "autodrive.swept" ]
}

# The armed sentinel that survived to the next prompt never ran. One cause is a
# drive mod that did not load (--safe-mode, Claude Code older than 2.1.287, or an
# organization-managed one that does not list the plugin in managed settings),
# in which case nothing will ever run it: the report names that cause and prints
# the lines the file's kind runs, rendered from its data, one per line, for the
# user to type.
@test "report-drive-failure (stale armed autodrive: names the mod and prints the lines to type)" {
    # shellcheck disable=SC2016  # the literal $HOME is the odd content under test
    seed_drive "$tmp" "clear continue" 'Fix "the  $HOME" bug & more'
    continuation="$HANDOFF_CONTINUATION"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("drive mod")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("safe-mode")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("2.1.287")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("managed settings")' >/dev/null
    # shellcheck disable=SC2016
    expected='/rename Fix "the  $HOME" bug & more
/clear
'"$continuation"
    # Both channels carry the three lines whole, contiguous and in order.
    echo "$output" | jq -e --arg e "$expected" '.systemMessage | contains($e)' >/dev/null
    echo "$output" | jq -e --arg e "$expected" '.hookSpecificOutput.additionalContext | contains($e)' >/dev/null
}

# The prepare marker (FR-G). The cause is still reported, but
# there is nothing to type, so no empty block is offered.
@test "report-drive-failure (stale armed autodrive with no lines: names the mod, prints nothing to type)" {
    seed_drive "$tmp" "prepare"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("drive mod")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("Type in order") | not' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("fenced code block") | not' >/dev/null
}
