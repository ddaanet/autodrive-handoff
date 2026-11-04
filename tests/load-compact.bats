#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- load-compact (SessionStart(compact): consume, re-inject the frame) ---
#
# The regression this matrix guards is silent: a frame that stops being injected
# fails by the successor knowing less, not by anything going red.

@test "load-compact (no pending: silent, and no frame — a hand-typed /compact injects nothing)" {
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# A transition in flight with a todo: the todo is what is re-injected, and the
# user is told so. The seeded TASK.md is removed first, which is the state the
# checkpoint leaves behind.
@test "load-compact (pending present, todo present: consumes it, todo re-injected)" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- finish the parser\n' > "$tmp/TODO.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected." ]
    assert_framed "$CTX" $'\n\n## Remaining\n\n- finish the parser\n'
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
    # The continuation is the mod's to submit, so it is not echoed here.
    [[ "$output" != *"continue with task 3"* ]]
}

# The seeded TASK.md is removed and no todo is written: nothing to re-inject.
# The message goes to the user alone; the agent is told nothing.
@test "load-compact (pending present, no todo, no task: consumed, No todo, nothing injected)" {
    rm -f "$tmp/TASK.md" "$tmp/TODO.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    echo "$output" | jq -e 'has("hookSpecificOutput") | not' >/dev/null
}

# A todo that is headings and nothing else is no todo.
@test "load-compact (pending present, headings-only todo, no task: consumed, No todo, nothing injected)" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n' > "$tmp/TODO.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    echo "$output" | jq -e 'has("hookSpecificOutput") | not' >/dev/null
}

# --- load-compact: legacy paths ---
#
# The same two notes as the other loader, on both channels. The message keeps its
# `compacted — todo re-injected` / `compacted — No todo` lead and appends the
# notes, "; "-joined, before the closing full stop; the context is the frame, a
# blank line, then each note (from-legacy task, todo, then ignored task, todo)
# as its own paragraph. There is no gap line on this channel.

@test "load-compact (legacy todo alone, no task): re-injected from the old path, noted on both channels" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected; $legacy_todo_msg." ]
    assert_framed "$CTX" $'\n\n## Remaining\n\n- legacy item\n\n'"$legacy_todo_ctx"$'\n'
    [ -s "$tmp/.claude/handoff-todo.md" ]
}

@test "load-compact (legacy todo is a symlink to a body): consumed, No todo, nothing injected" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- linked item\n' > "$other/todo.md"
    ln -s "$other/todo.md" "$tmp/.claude/handoff-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    [ "$CTX" = "" ]
}

@test "load-compact (legacy task alone): injected from the old path, the message says No todo and names it" {
    rm -f "$tmp/TASK.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo; $legacy_task_msg." ]
    assert_framed "$CTX" $'\n\n## Current task\n\nlegacy task body\n\n'"$legacy_task_ctx"$'\n'
}

@test "load-compact (both halves legacy): task then todo, one note each" {
    rm -f "$tmp/TASK.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected; $legacy_task_msg; $legacy_todo_msg." ]
    assert_framed "$CTX" $'\n\n## Current task\n\nlegacy task body\n\n## Remaining\n\n- legacy item\n\n'"$legacy_task_ctx"$'\n\n'"$legacy_todo_ctx"$'\n'
}

@test "load-compact (root todo with a body shadows a legacy todo): the root frame, an ignored note on both channels" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- root item\n' > "$tmp/TODO.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected; $shadowed_todo_msg." ]
    assert_framed "$CTX" $'\n\n## Remaining\n\n- root item\n\n'"$shadowed_todo_ctx"$'\n'
    [[ "$CTX" != *"legacy item"* ]]
    [ "$(cat "$tmp/.claude/handoff-todo.md")" = $'## Remaining\n\n- legacy item' ]
}

@test "load-compact (headings-only root todo beside a legacy todo body): the legacy todo is re-injected, nothing ignored" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n' > "$tmp/TODO.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected; $legacy_todo_msg." ]
    assert_framed "$CTX" $'\n\n## Remaining\n\n- legacy item\n\n'"$legacy_todo_ctx"$'\n'
}

# Both kinds of note on this boundary: the todo comes from the old path while a
# hand-written root task has a body, so the legacy task is ignored. The order is
# the one the other loader uses, from-legacy before ignored.
@test "load-compact (root task shadows a legacy task, todo only legacy): from-legacy note first, then the ignored one" {
    printf '## Current task\n\nroot task body\n' > "$tmp/TASK.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected; $legacy_todo_msg; $shadowed_task_msg." ]
    assert_framed "$CTX" $'\n\n## Current task\n\nroot task body\n\n## Remaining\n\n- legacy item\n\n'"$legacy_todo_ctx"$'\n\n'"$shadowed_task_ctx"$'\n'
    [[ "$CTX" != *"legacy task body"* ]]
}

# A guard, not a red row: legacy files with no body are no frame and no note.
@test "load-compact (legacy files with no body, no root file): consumed, No todo, nothing injected" {
    rm -f "$tmp/TASK.md"
    : > "$tmp/.claude/handoff-task.md"
    printf '## Remaining\n' > "$tmp/.claude/handoff-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    echo "$output" | jq -e 'has("hookSpecificOutput") | not' >/dev/null
}

@test "load-compact (pending of kind clear: left for SessionStart(clear))" {
    seed_pending "$tmp" "clear continue" "A Title"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    [ "$(sed -n 2p "$tmp/.claude/autodrive")" = "clear continue" ]
}

# The checkpoint removes TASK.md at this boundary, so the only way one is there
# when the compaction completes is a hand-written file. It is still the task
# frame, and it is injected.
@test "load-compact (a hand-written TASK.md alone: injected, and the message says No todo)" {
    seed_pending "$tmp" "compact continue"
    printf '%s\n' "## Now" "- rewire the parser" > "$tmp/TASK.md"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    assert_framed "$CTX" $'\n\n## Now\n- rewire the parser\n'
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
    # The task file survives — it is not consumed by being read.
    [ -s "$tmp/TASK.md" ]
}

@test "load-compact (a hand-written TASK.md beside a todo: both injected, task first)" {
    seed_pending "$tmp" "compact continue"
    printf '%s\n' "## Now" "- rewire the parser" > "$tmp/TASK.md"
    printf '## Remaining\n\n- finish the parser\n' > "$tmp/TODO.md"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — todo re-injected." ]
    assert_framed "$CTX" $'\n\n## Now\n- rewire the parser\n\n## Remaining\n\n- finish the parser\n'
}

# A driven compaction with no continuation — the /compact line ran, and nothing
# follows it. Same effect here as the prepare-only marker, from a different
# sentinel: consume, inject what there is.
@test "load-compact (pending with no continuation: consumed, frame only)" {
    seed_pending "$tmp" "compact" "keep the parser work"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("hook smoke test")' >/dev/null
    echo "$output" | jq -e '.systemMessage == "handoff: compacted — No todo."' >/dev/null
}

# FR-G's other half: the prepare marker (`compact: false`) arrives here as a
# pending `prepare`, which runs nothing. Inject what there is.
@test "load-compact (a pending prepare marker: consumed, frame injected)" {
    seed_pending "$tmp" "prepare"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("hook smoke test")' >/dev/null
    echo "$output" | jq -e '.systemMessage == "handoff: compacted — No todo."' >/dev/null
}

@test "load-compact (worktree cwd: consumes the worktree pending file)" {
    wt="$(make_worktree wtLC)"
    seed_pending "$wt" "compact continue"
    run_load_compact "$wt"
    [ "$status" -eq 0 ]
    [ ! -e "$wt/.claude/autodrive" ]
}

@test "load-compact (armed file: not consumed, no frame)" {
    seed_drive "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed $SESSION_ID" ]
}
