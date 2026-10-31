#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- load-handoff: legacy paths (.claude/handoff-task.md, .claude/handoff-todo.md) ---
#
# Per half the root file wins when it has a body, else the legacy file when it
# has a body. A half loaded from a legacy path, and a legacy file ignored behind
# a root file, are each named on both channels, after the frame and before the
# gap line: from-legacy notes (task, todo), then ignored notes (task, todo), then
# the gap note. The size in the message is the frame's alone.

# <frame-size> <tail> — the whole systemMessage is the loaded note for a frame of
# that size, then exactly <tail> (the "; "-joined notes that follow it).
assert_notes() {
    local re="^handoff: loaded — $1 B, saved (just now|[0-9]+[mhd] ago); "
    [[ "$MSG" =~ $re ]] && [ "${MSG#"${BASH_REMATCH[0]}"}" = "$2" ]
}

# setup() seeds $tmp/TASK.md; a row that wants no root task removes it, and a
# row that keeps it says so in its expected frame.
@test "load-handoff (legacy task alone): loaded from the old path, noted on both channels, No todo last" {
    rm -f "$tmp/TASK.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_task_ctx"$'\n\nNo todo.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nlegacy task body'
    assert_notes "${#framed}" "$legacy_task_msg; No todo"
    # Reading is not consuming.
    [ -s "$tmp/.claude/handoff-task.md" ]
}

@test "load-handoff (legacy files are symlinks to bodies, no root file): the neither state, no legacy note" {
    rm -f "$tmp/TASK.md"
    printf '## Current task\n\nlinked task body\n' > "$other/task.md"
    printf '## Remaining\n\n- linked item\n' > "$other/todo.md"
    ln -s "$other/task.md" "$tmp/.claude/handoff-task.md"
    ln -s "$other/todo.md" "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [ "$CTX" = $'No task frame or todo.\n' ]
}

@test "load-handoff (dangling legacy symlinks, no root file): the neither state, no legacy note" {
    rm -f "$tmp/TASK.md"
    ln -s "$other/nowhere-task.md" "$tmp/.claude/handoff-task.md"
    ln -s "$other/nowhere-todo.md" "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [ "$CTX" = $'No task frame or todo.\n' ]
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

# A symlinked root file has no body, so it shadows nothing: the legacy file's
# body is loaded as for any root file without one.
@test "load-handoff (TODO.md is a symlink beside a legacy todo body): the legacy todo is loaded, nothing ignored" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- linked item\n' > "$other/todo.md"
    link_root TODO.md "$other/todo.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    [[ "$CTX" == *"legacy item"* ]]
    [[ "$CTX" != *"linked item"* ]]
    [[ "$MSG" == *"$legacy_todo_msg"* ]]
    [[ "$MSG" != *"ignored"* ]]
}

@test "load-compact (TODO.md is a symlink to a body): consumed, No todo, nothing injected" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- linked item\n' > "$other/todo.md"
    link_root TODO.md "$other/todo.md"
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    [ "$CTX" = "" ]
}

@test "load-compact (TASK.md and TODO.md are dangling symlinks): consumed, No todo" {
    link_root TASK.md "$other/nowhere-task.md"
    link_root TODO.md "$other/nowhere-todo.md"
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    [ "$CTX" = "" ]
}

@test "load-handoff (legacy todo alone): loaded from the old path, noted on both channels, No task frame last" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_todo_ctx"$'\n\nNo task frame.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Remaining\n\n- legacy item'
    assert_notes "${#framed}" "$legacy_todo_msg; No task frame"
    [ -s "$tmp/.claude/handoff-todo.md" ]
}

@test "load-handoff (both halves legacy): task then todo, one note each, no gap note" {
    rm -f "$tmp/TASK.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_task_ctx"$'\n\n'"$legacy_todo_ctx"$'\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nlegacy task body\n\n## Remaining\n\n- legacy item'
    assert_notes "${#framed}" "$legacy_task_msg; $legacy_todo_msg"
    [ -s "$tmp/.claude/handoff-task.md" ]
    [ -s "$tmp/.claude/handoff-todo.md" ]
}

# The case a project's own TODO.md makes real: the root file is the frame, the
# old one is never read, and the agent is told it is there.
@test "load-handoff (root files with a body shadow legacy files): the root frame, an ignored note per half on both channels" {
    printf '## Current task\n\nroot task body\n' > "$tmp/TASK.md"
    printf '## Remaining\n\n- root item\n' > "$tmp/TODO.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$shadowed_task_ctx"$'\n\n'"$shadowed_todo_ctx"$'\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nroot task body\n\n## Remaining\n\n- root item'
    assert_notes "${#framed}" "$shadowed_task_msg; $shadowed_todo_msg"
    # Never merged, never removed: the legacy bodies are untouched and unread.
    [[ "$CTX" != *"legacy task body"* && "$CTX" != *"legacy item"* ]]
    [ "$(cat "$tmp/.claude/handoff-task.md")" = $'## Current task\n\nlegacy task body' ]
    [ "$(cat "$tmp/.claude/handoff-todo.md")" = $'## Remaining\n\n- legacy item' ]
}

@test "load-handoff (root task shadows a legacy task, todo only legacy): from-legacy note first, then the ignored one" {
    printf '## Current task\n\nroot task body\n' > "$tmp/TASK.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_todo_ctx"$'\n\n'"$shadowed_task_ctx"$'\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nroot task body\n\n## Remaining\n\n- legacy item'
    assert_notes "${#framed}" "$legacy_todo_msg; $shadowed_task_msg"
}

# A root file that is headings and nothing else is no task, so it does not
# shadow: the legacy file's body is the frame and nothing is ignored.
@test "load-handoff (headings-only root task beside a legacy task body): the legacy task is loaded, nothing ignored" {
    printf '## Current task\n\n## Open decisions\n' > "$tmp/TASK.md"
    printf '## Current task\n\nlegacy task body\n' > "$tmp/.claude/handoff-task.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_task_ctx"$'\n\nNo todo.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nlegacy task body'
    assert_notes "${#framed}" "$legacy_task_msg; No todo"
    [[ "$CTX" != *"is ignored"* ]]
}

@test "load-handoff (headings-only root todo beside a legacy todo body): the legacy todo is loaded, nothing ignored" {
    printf '## Remaining\n' > "$tmp/TODO.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_todo_ctx"$'\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nhook smoke test\n\n## Open decisions\n\n- none\n\n## Remaining\n\n- legacy item'
    assert_notes "${#framed}" "$legacy_todo_msg"
    [[ "$CTX" != *"is ignored"* ]]
}

# The legacy paths hang off the root the loader anchors on, never off
# CLAUDE_PROJECT_DIR (the main tree, in a worktree session). The main tree has
# its own legacy task with a different body, so reading from the wrong root
# shows.
@test "load-handoff (worktree cwd: reads the worktree's legacy task, not main's)" {
    wt="$(make_worktree wtLeg)"
    rm -f "$tmp/TASK.md"
    printf '## Current task\n\nworktree legacy task body\n' > "$wt/.claude/handoff-task.md"
    printf '## Current task\n\nmain legacy task body\n' > "$tmp/.claude/handoff-task.md"
    run_load_handoff "$wt" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_task_ctx"$'\n\nNo todo.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Current task\n\nworktree legacy task body'
    assert_notes "${#framed}" "$legacy_task_msg; No todo"
    [[ "$CTX" != *"main legacy task body"* ]]
}

# The age is the newest file that counts, and a legacy file counts only when its
# half was loaded from it. The first row puts the old mtime on the legacy file
# the frame came from; the second puts it on the root file and a fresh mtime on
# the legacy file it shadows, which must not make the frame read as just saved.
@test "load-handoff (age): a half loaded from a legacy path is aged by that file" {
    printf '## Current task\n\n## Open decisions\n' > "$tmp/TASK.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    touch -d '2 days ago' "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$legacy_todo_ctx"$'\n\nNo task frame.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Remaining\n\n- legacy item'
    [ "$MSG" = "handoff: loaded — ${#framed} B, saved 2d ago; $legacy_todo_msg; No task frame" ]
}

@test "load-handoff (age): a legacy file shadowed by a root file does not make the frame younger" {
    rm -f "$tmp/TASK.md"
    printf '## Remaining\n\n- root item\n' > "$tmp/TODO.md"
    touch -d '2 days ago' "$tmp/TODO.md"
    printf '## Remaining\n\n- legacy item\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    framed="${CTX%$'\n\n'"$shadowed_todo_ctx"$'\n\nNo task frame.\n'}"
    [ "$framed" != "$CTX" ]
    assert_framed "$framed" $'\n\n## Remaining\n\n- root item'
    [ "$MSG" = "handoff: loaded — ${#framed} B, saved 2d ago; $shadowed_todo_msg; No task frame" ]
}

# A guard, not a red row: it holds before the change and must keep holding. A
# legacy file with no body is no more a frame than a root one, and says nothing.
@test "load-handoff (legacy files with no body, no root file): the neither state, no legacy note" {
    rm -f "$tmp/TASK.md"
    : > "$tmp/.claude/handoff-task.md"
    printf '## Remaining\n' > "$tmp/.claude/handoff-todo.md"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    split_output "$output"
    [ "$MSG" = "handoff: No task frame or todo." ]
    [ "$CTX" = $'No task frame or todo.\n' ]
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
    sz_tmp="$BATS_TEST_TMPDIR/sz"; mkdir -p "$sz_tmp"
    # ~2048 bytes of content so the assembled output crosses the KiB threshold.
    python3 -c "print('x' * 2048)" > "$sz_tmp/TASK.md"
    touch "$sz_tmp/TASK.md"
    run bash -c '
        jq -nc --arg e "SessionStart" "{hook_event_name:\$e}" \
        | CLAUDE_PROJECT_DIR="$1" bash scripts/load-handoff.sh
    ' _ "$sz_tmp"
    [ "$status" -eq 0 ]
    echo "$output" | jq -r '.systemMessage // ""' | grep -Eq '^handoff: loaded — [0-9]+\.[0-9]+ KiB, saved'
}

@test "load-handoff (worktree cwd: reads worktree task, not main)" {
    wt="$(make_worktree wtL)"
    cat > "$wt/TASK.md" <<'WTTASK'
## Current task

worktree handoff body

## Open decisions

- none
WTTASK
    run bash -c '
        jq -nc --arg cwd "$1" --arg e "clear" "{cwd:\$cwd, hook_event_name:\$e}" \
        | bash scripts/load-handoff.sh
    ' _ "$wt"
    [ "$status" -eq 0 ]
    echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'worktree handoff body'
}
