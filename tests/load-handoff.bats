#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- load-handoff ---

@test "load-handoff (read-time assembly): injects header + task, echoes event" {
    asm_tmp="$BATS_TEST_TMPDIR/asm"; mkdir -p "$asm_tmp"
    cat > "$asm_tmp/TASK.md" <<'ASMTASK'
## Current task

hook smoke test

## Open decisions

- none
ASMTASK
    run bash -c '
        jq -nc --arg e "clear" "{hook_event_name:\$e}" \
        | CLAUDE_PROJECT_DIR="$1" bash scripts/load-handoff.sh
    ' _ "$asm_tmp"
    [ "$status" -eq 0 ]
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    # "Task", not "Handoff": the file is current task state now, written by
    # either skill and injected at both transitions.
    echo "$ctx" | grep -q '^# Task — '
    echo "$ctx" | grep -q 'hook smoke test'
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "clear"' >/dev/null
}

# With no task and no todo that count, the loader still speaks on both
# channels: the user and the agent each learn there was nothing to load. $asm_tmp
# is a bare directory, so no seeded TASK.md is in play.
@test "load-handoff (read-time assembly): no file at all -> No task frame or todo on both channels" {
    asm_tmp="$BATS_TEST_TMPDIR/asm"; mkdir -p "$asm_tmp"
    run bash -c '
        jq -nc --arg e "clear" "{hook_event_name:\$e}" \
        | CLAUDE_PROJECT_DIR="$1" bash scripts/load-handoff.sh
    ' _ "$asm_tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [ "$CTX" = $'No task frame or todo.\n' ]
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "clear"' >/dev/null
}

# setup() seeds $tmp/TASK.md; both files are written out here so the row does
# not lean on it.
@test "load-handoff (read-time assembly): task and todo count -> the frame, no gap note" {
    printf '## Current task\n\ntask body\n' > "$tmp/TASK.md"
    printf '## Remaining\n\n- wire the loader\n' > "$tmp/TODO.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    assert_msg_matches "$loaded_re"
    assert_framed "$CTX" $'\n\n## Current task\n\ntask body\n\n## Remaining\n\n- wire the loader\n'
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
}

# setup() seeds $tmp/TASK.md, which is the task; no TODO.md is written. The
# size in the note is the frame's, not the frame plus the agent's gap line.
@test "load-handoff (read-time assembly): task alone -> No todo on both channels" {
    rm -f "$tmp/TODO.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\nNo todo.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nhook smoke test\n\n## Open decisions\n\n- none'
    assert_msg_matches "loaded — ${#framed} B, saved (just now|[0-9]+[mhd] ago); No todo"
}

# A remainder with no active task still has to cross: the todo file alone
# must not read as "nothing pending". The seeded task is removed first.
@test "load-handoff (read-time assembly): todo alone -> No task frame on both channels" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- lone remainder\n' > "$tmp/TODO.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\nNo task frame.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Remaining\n\n- lone remainder'
    assert_msg_matches "loaded — ${#framed} B, saved (just now|[0-9]+[mhd] ago); No task frame"
}

# The seeded task is overwritten with headings and nothing else: that reads as
# no task, and the headings stay out of what the agent is shown.
@test "load-handoff (read-time assembly): headings-only task beside a todo -> the todo-alone state" {
    printf '## Current task\n\n## Open decisions\n' > "$tmp/TASK.md"
    printf '## Remaining\n\n- lone remainder\n' > "$tmp/TODO.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    assert_msg_matches "$loaded_re; No task frame"
    assert_framed "$CTX" $'\n\n## Remaining\n\n- lone remainder\n\nNo task frame.\n'
}

# Both files overwritten with headings only: nothing counts.
@test "load-handoff (read-time assembly): headings-only task and todo -> the neither state" {
    printf '## Current task\n\n## Open decisions\n' > "$tmp/TASK.md"
    printf '## Remaining\n' > "$tmp/TODO.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [ "$CTX" = $'No task frame or todo.\n' ]
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
}

# --- load-handoff on source: "clear" (consume the pending clear) ---
#
# The mod ran the `/clear` and submits the continuation itself; the loader only
# consumes the sentinel and injects the frame.

@test "load-handoff (clear, pending present: consumes it, injects the frame)" {
    seed_pending "$tmp" "clear continue" "A Title"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    # The continuation is the mod's to submit, so it is not echoed here.
    echo "$output" | jq -e '.systemMessage | test("pick up") | not' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("hook smoke test")' >/dev/null
}

# The ordering hazard, and the regression this row exists to catch: the script
# must consume before it reports there is nothing to inject. Otherwise a driven
# clear whose task file is empty strands the pending file, and the next
# transition's sentinel is read as one still in flight.
@test "load-handoff (clear, pending present but NO frame: still consumes, and says so)" {
    rm -f "$tmp/TASK.md" "$tmp/TODO.md"
    seed_pending "$tmp" "clear continue" "A Title"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [ "$CTX" = $'No task frame or todo.\n' ]
}

# A driven clear with no continuation: the mod ran the `/clear` at turn end, and
# there is nothing to submit into the session it opened. The pending file is
# still this loader's to consume, and the frame still goes out.
@test "load-handoff (clear, pending with no continuation: consumed, frame only)" {
    seed_pending "$tmp" "clear" "A Title"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("hook smoke test")' >/dev/null
    # Without the widened shape this row passes for the wrong reason: the
    # sentinel fails to parse, and the malformed branch also consumes the file.
    echo "$output" | jq -e '.systemMessage | test("malformed") | not' >/dev/null
}

@test "load-handoff (clear, no pending: frame only, silent about any transition)" {
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage | test("loaded")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("resume") | not' >/dev/null
}

# Each loader consumes only its own transition. A hand-typed /clear fires the
# same hook, and a compact armed in the outgoing session must survive it.
@test "load-handoff (clear, pending of kind compact: left for SessionStart(compact))" {
    seed_pending "$tmp" "compact continue"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    [ "$(sed -n 2p "$tmp/.claude/autodrive")" = "compact continue" ]
}

@test "load-handoff (clear, pending prepare marker: left for SessionStart(compact))" {
    seed_pending "$tmp" "prepare"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    [ "$(sed -n 2p "$tmp/.claude/autodrive")" = "prepare" ]
}

@test "load-handoff (startup with a pending present: does not consume it)" {
    seed_pending "$tmp" "clear continue" "A Title"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    [ -f "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("pick up") | not' >/dev/null
}

@test "load-handoff (clear, malformed pending: discarded and reported)" {
    seed_pending "$tmp" "clear" "/rename A Title" "not a clear" "resume"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("malformed")' >/dev/null
}

# The transition's note leads and the frame's notes follow it, with the same
# `; ` between them. The seeded TASK.md is the task; there is no todo.
@test "load-handoff (clear, malformed pending: its note precedes the frame notes)" {
    seed_pending "$tmp" "clear" "/rename A Title" "not a clear" "resume"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    assert_msg_matches "autodrive malformed — [^;]+; not resuming; $loaded_re; No todo"
}

# Each loader consumes only a transition in flight. An armed file belongs to a
# turn end that has not come — the agent wrote it and the turn ended on an Esc
# (or the mod never loaded), so the sweep is what deals with it, not this.
@test "load-handoff (clear, armed file: not consumed, left for the sweep)" {
    seed_drive "$tmp" "clear continue" "A Title"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed $SESSION_ID" ]
    echo "$output" | jq -e '.systemMessage | test("pick up") | not' >/dev/null
}

# A root TASK.md or TODO.md that is a symlink is no body: a repository can
# commit `TASK.md -> /any/readable/file`, and following it would inject that
# file at SessionStart. The checkpoint already refuses a root symlink.

# <root name> <link target> — the root file replaced by a link to the target.
link_root() {
    rm -f "$tmp/$1"
    ln -s "$2" "$tmp/$1"
}

@test "load-handoff (TASK.md is a symlink to a body): not injected" {
    printf '## Current task\n\nlinked task body\n' > "$other/task.md"
    link_root TASK.md "$other/task.md"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [[ "$CTX" != *"linked task body"* ]]
}

@test "load-handoff (TODO.md is a symlink to a body): not injected" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- linked item\n' > "$other/todo.md"
    link_root TODO.md "$other/todo.md"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [[ "$CTX" != *"linked item"* ]]
}

@test "load-handoff (TASK.md and TODO.md are dangling symlinks): the neither state" {
    link_root TASK.md "$other/nowhere-task.md"
    link_root TODO.md "$other/nowhere-todo.md"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
}

# The todo is two days old with a body; the task was written just now but holds
# only headings. The age is the newest file that counts, so the fresh headings
# do not make the frame read as just saved.
@test "load-handoff (age): taken from the files that count, not from a headings-only one" {
    printf '## Remaining\n\n- old item\n' > "$tmp/TODO.md"
    touch -d '2 days ago' "$tmp/TODO.md"
    printf '## Current task\n\n## Open decisions\n' > "$tmp/TASK.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    assert_msg_matches "loaded — [0-9]+ B, saved 2d ago; No task frame"
    assert_framed "$CTX" $'\n\n## Remaining\n\n- old item\n\nNo task frame.\n'
}

@test "load-handoff (size formatting: KiB threshold)" {
    # ~2048 bytes of content so the frame crosses the KiB threshold.
    python3 -c "print('x' * 2048)" > "$tmp/TASK.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    assert_msg_matches 'loaded — [0-9]+\.[0-9] KiB, saved.*'
}
