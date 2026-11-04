#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- the sentinel reader's helper fails (python3 -I prints nothing) ---
#
# A reader that could not run says nothing about the file, which may be a
# perfectly valid transition: no caller removes it, and each says so. The stub
# fails only handoff_read_regular's `python3 -I -c` (the one opening with
# O_NOFOLLOW), so every other python3 call still runs; the cwd is the project root, so the
# resolver's fast path spawns nothing.
reader_stub() {
    local real stub="$BATS_TEST_TMPDIR/broken-reader"
    real="$(command -v python3)"
    mkdir -p "$stub"
    # shellcheck disable=SC2016  # the stub's own $1/$3, expanded when it runs
    printf '#!/usr/bin/env bash\ncase "$1 $3" in "-I "*O_NOFOLLOW*) exit 97 ;; esac\nexec %q "$@"\n' "$real" > "$stub/python3"
    chmod +x "$stub/python3"
    printf '%s' "$stub"
}

@test "load-handoff (clear, the reader's helper fails: pending kept, said so)" {
    seed_pending "$tmp" "clear continue" "A Title"
    before="$(cat "$tmp/.claude/autodrive")"
    PATH="$(reader_stub):$PATH" run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$before" ]
    echo "$output" | jq -e '.systemMessage | test("helper that reads it failed") and test("left in place")' >/dev/null
}

@test "load-compact (the reader's helper fails: pending kept, said so)" {
    seed_pending "$tmp" "compact continue"
    before="$(cat "$tmp/.claude/autodrive")"
    PATH="$(reader_stub):$PATH" run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$before" ]
    echo "$output" | jq -e '.systemMessage | test("helper that reads it failed") and test("left in place")' >/dev/null
}

@test "report-drive-failure (the reader's helper fails: armed file kept, not swept, said so)" {
    seed_drive "$tmp" "compact continue"
    before="$(cat "$tmp/.claude/autodrive")"
    PATH="$(reader_stub):$PATH" run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$before" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
    echo "$output" | jq -e '.systemMessage | test("helper that reads it failed") and test("left in place")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("left in place")' >/dev/null
}

# --- the sentinel is a symlink ---
#
# Every reader refuses a link at .claude/autodrive, dangling or not, and takes
# its malformed path: the link is removed (the name, never what it names) and
# reported, and the target's bytes reach neither channel. A dangling link is
# refused too, rather than read as no file and left for ever.

# <first line> — .claude/autodrive becomes a link to a file under $other whose
# first line is $1 and which parses as nothing, so a reader that followed it
# would quote that line in its malformed report.
link_drive() {
    printf '%s\n' "$1" "clear" > "$other/linked-sentinel"
    ln -s "$other/linked-sentinel" "$tmp/.claude/autodrive"
}

# <first line> <hook output> — the link is gone, its target byte-identical, the
# report names the link, and $1 is on neither channel.
assert_link_refused() {
    [ ! -e "$tmp/.claude/autodrive" ] && [ ! -L "$tmp/.claude/autodrive" ]
    [ "$(cat "$other/linked-sentinel")" = "$1
clear" ]
    split_output "$2"
    [[ "$MSG" == *"symbolic link"* ]]
    [[ "$MSG" != *"$1"* && "$CTX" != *"$1"* ]]
}

@test "load-handoff (clear, the sentinel is a symlink: removed unread, reported)" {
    link_drive "LINKED-FIRST-LINE"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    assert_link_refused "LINKED-FIRST-LINE" "$output"
}

@test "load-handoff (clear, the sentinel is a dangling symlink: removed, reported)" {
    ln -s "$other/nowhere" "$tmp/.claude/autodrive"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ ! -L "$tmp/.claude/autodrive" ]
    [ ! -e "$other/nowhere" ]
    split_output "$output"
    [[ "$MSG" == *"symbolic link"* ]]
}

@test "load-compact (the sentinel is a symlink: removed unread, reported)" {
    link_drive "LINKED-FIRST-LINE"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    assert_link_refused "LINKED-FIRST-LINE" "$output"
}

@test "load-compact (the sentinel is a dangling symlink: removed, reported)" {
    ln -s "$other/nowhere" "$tmp/.claude/autodrive"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -L "$tmp/.claude/autodrive" ]
    split_output "$output"
    [[ "$MSG" == *"symbolic link"* ]]
}

# The sweep quotes no line of a malformed file, but it prints an armed one's
# lines for the user to type: through a link, those would be another file's.
@test "report-drive-failure (the sentinel is a symlink to this session's armed file: swept unread, no lines offered)" {
    printf '%s\n' "armed $SESSION_ID" "clear" "LINKED-TITLE" > "$other/linked-sentinel"
    ln -s "$other/linked-sentinel" "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -L "$tmp/.claude/autodrive" ]
    [ "$(head -n1 "$other/linked-sentinel")" = "armed $SESSION_ID" ]
    split_output "$output"
    [[ "$MSG" == *"symbolic link"* ]]
    [[ "$MSG" != *"LINKED-TITLE"* && "$CTX" != *"LINKED-TITLE"* ]]
}

@test "report-drive-failure (the sentinel is a dangling symlink: swept, reported)" {
    ln -s "$other/nowhere" "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -L "$tmp/.claude/autodrive" ]
    split_output "$output"
    [[ "$MSG" == *"symbolic link"* ]]
}

# A pending file is legitimate for the whole turn end -> transition window, and
# that window contains the mod's own prompt submits — each of which is a
# UserPromptSubmit. Sweeping one here would race SessionStart(compact|clear) and
# kill a live continuation. Only the failure branch above, which acts on
# something the mod observed itself, may clear one.
@test "report-drive-failure (pending file: left alone, no report)" {
    seed_pending "$tmp" "compact continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
}

# `held` is the one state that legitimately survives a turn boundary: the
# approval round trip it waits on costs at least one turn, and the answer arrives
# at a UserPromptSubmit — this hook. Sweeping this session's own held file would
# silently cancel the transition the user is in the middle of approving.
@test "report-drive-failure (held file owned by this session: left alone)" {
    printf '%s\n' "held $SESSION_ID" "clear continue" "A Title" \
        > "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "held $SESSION_ID" ]
}

# Another session's held file waits on that session's user, for as long as the
# approval takes, and an idle transcript is what such a wait looks like. It is
# never swept from here, whatever shows of its owner: with no transcript_path
# nothing does, and it is still left as it was, its lines never offered. A dead
# owner's file is replaced by the next checkpoint in the root, and only its
# owner's handoff-approved can arm it.
@test "report-drive-failure (held file of another session, no transcript_path: left untouched)" {
    printf '%s\n' "held sess-someone-else" "clear continue" "A Title" \
        > "$tmp/.claude/autodrive"
    before="$(cat "$tmp/.claude/autodrive")"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$before" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}
