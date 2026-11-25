#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"
load lock-helpers

# --- load-compact (SessionStart(compact): consume, re-inject the frame) ---
#
# The regression this matrix guards is silent: a frame that stops being injected
# fails by the successor knowing less, not by anything going red.

@test "load-compact (no pending: silent, and no frame — a hand-typed /compact injects nothing)" {
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# A transition in flight with a todo and no task file (the checkpoint cleared
# it): the todo is what is re-injected, and the user is told so.
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

# Both files cleared at the checkpoint: nothing to re-inject.
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

@test "load-compact (pending of kind clear: left for SessionStart(clear))" {
    seed_pending "$tmp" "clear continue" "A Title"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    [ "$(sed -n 2p "$tmp/.claude/autodrive")" = "clear continue" ]
}

# The checkpoint writes TASK.md at this boundary as it does at the clear one,
# so a task file alone is the task frame, and it is injected.
@test "load-compact (TASK.md alone: injected, and the message says No todo)" {
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

@test "load-compact (TASK.md beside a todo: both injected, task first)" {
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
# follows it. Same effect here as the `prepare` marker, from a different
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

# A root TASK.md or TODO.md that is a symlink is no body (see load-handoff.bats).

# <root name> <link target> — the root file replaced by a link to the target.
link_root() {
    rm -f "$tmp/$1"
    ln -s "$2" "$tmp/$1"
}

@test "load-compact (TODO.md is a symlink to a body): consumed, No todo, nothing injected" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- linked item\n' > "$other/todo.md"
    link_root TODO.md "$other/todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    [ "$CTX" = "" ]
}

@test "load-compact (TASK.md is a symlink to a body): not injected" {
    printf '## Current task\n\nlinked task body\n' > "$other/task.md"
    link_root TASK.md "$other/task.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    [ "$CTX" = "" ]
}

@test "load-compact (TASK.md and TODO.md are dangling symlinks): consumed, No todo" {
    link_root TASK.md "$other/nowhere-task.md"
    link_root TODO.md "$other/nowhere-todo.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    [ "$CTX" = "" ]
}

# --- load-compact: the output limit (10000 characters of additionalContext) ---

@test "load-compact (limit): a frame that fits is unchanged, with no pointer" {
    seed_todo 1 5 100
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$(item_labels r)" = "r01r02r03r04r05" ]
    [[ "$CTX" != *"TODO.md holds"* ]]
}

@test "load-compact (limit): remaining items go from the end first, then open decisions" {
    seed_todo 2 40 300
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    (( $(chars "$CTX") <= 10000 ))
    [ "$(item_labels d)" = "d01d02" ]
    shown=$(( $(chars "$(item_labels r)") / 3 ))
    (( shown > 0 && shown < 40 ))
    [ "${CTX##*$'\n\n'}" = "TODO.md holds $((40 - shown)) more remaining items than shown here: read it before acting on either list."$'\n' ]

    seed_todo 8 3 1500
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    (( $(chars "$CTX") <= 10000 ))
    [ "$(item_labels r)" = "" ]
    [[ "${CTX##*$'\n\n'}" == "TODO.md holds 3 more remaining items and "*" more open decision"* ]]
}

@test "load-compact (limit): characters are counted, not bytes" {
    { printf '## Remaining\n\n- '; python3 -I -c 'print("é" * 6000)'; } > "$tmp/TODO.md"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    [[ "$CTX" != *"TODO.md holds"* ]]
    [[ "$CTX" == *"$(python3 -I -c 'print("é" * 6000, end="")')"* ]]
}

@test "load-compact (limit): exactly 10000 characters stay whole, 10001 are cut" {
    seed_pending "$tmp" "compact continue"
    measure_base run_load_compact "$tmp"
    seed_todo_x $((10000 - base + 1))
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    [ "$(chars "$CTX")" -eq 10000 ]
    [[ "$CTX" != *"TODO.md holds"* ]]
    seed_todo_x $((10000 - base + 2))
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    [[ "$CTX" == *"TODO.md holds 1 more remaining item than shown"* ]]
    (( $(chars "$CTX") <= 10000 ))
}

@test "load-compact (limit): the lock-failure sentence counts against the budget" {
    seed_pending "$tmp" "compact continue"
    fail_lock_helper
    measure_base run_load_compact "$tmp"
    [[ "$CTX" == *"was left in place"* ]]
    seed_todo_x $((10000 - base + 2))
    run_load_compact "$tmp"
    split_output "$output"
    [[ "$CTX" == *"TODO.md holds 1 more remaining item"* ]]
    [[ "$CTX" == *"was left in place"* ]]
    (( $(chars "$CTX") <= 10000 ))
}

@test "load-compact (limit): open decisions are cut last wherever they sit; a cut frame of exactly 10000 characters stays" {
    seed_todo 8 3 1500 last
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    [ "$(item_labels r)" = "" ]
    [ "$(item_labels d)" != "" ]
    seed_todo_pad 9700
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    n=$((9700 + 10000 - $(chars "$CTX")))
    seed_todo_pad "$n"
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    [ "$(chars "$CTX")" -eq 10000 ]
    [[ "$CTX" == *"- k"* && "$CTX" == *"TODO.md holds 1 more remaining item than"* ]]
    seed_todo_pad $((n + 1))
    seed_pending "$tmp" "compact continue"
    run_load_compact "$tmp"
    split_output "$output"
    [[ "$CTX" != *"- k"* && "$CTX" == *"TODO.md holds 2 more remaining items than"* ]]
}
