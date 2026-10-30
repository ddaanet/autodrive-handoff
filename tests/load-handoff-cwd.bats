#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- load-handoff and report-drive-failure: a cwd that survives a line-wise read ---
#
# A path is any string, and these hooks take the hook input's `.cwd` (and the
# root they resolve from it) through `read -r`: a newline cuts it short and the
# default IFS trims a leading or trailing space. The rows assert the behaviour a
# path of that shape is owed, the same as any other: the hook acts on the
# project it was launched in. write-guard.sh reads its fields NUL-terminated and
# has the rows (see "newline in a directory component").

# <json> — the additionalContext of a loader's output, whole ("" when none).
context_of() {
    jq -j '.hookSpecificOutput.additionalContext // ""' <<<"$1"
}

@test "load-handoff (project root with a newline in a directory component): the frame is injected" {
    nl="$BATS_TEST_TMPDIR/nl"$'\n'"proj"
    mkdir -p "$nl/.claude"
    printf '## Current task\n\nnewline root body\n' > "$nl/TASK.md"
    CLAUDE_PROJECT_DIR="$nl" run_load_handoff "$nl" "startup"
    [ "$status" -eq 0 ]
    ctx="$(context_of "$output")"
    [[ "$ctx" == *"newline root body"* ]]
    split_output "$output"
    [[ "$MSG" != *"No task frame or todo."* ]]
}

@test "load-handoff (project root ending in a space): the frame is injected" {
    sp="$BATS_TEST_TMPDIR/trailing "
    mkdir -p "$sp/.claude"
    printf '## Current task\n\ntrailing space body\n' > "$sp/TASK.md"
    CLAUDE_PROJECT_DIR="$sp" run_load_handoff "$sp" "startup"
    [ "$status" -eq 0 ]
    ctx="$(context_of "$output")"
    [[ "$ctx" == *"trailing space body"* ]]
    split_output "$output"
    [[ "$MSG" != *"No task frame or todo."* ]]
}

@test "load-handoff (cwd in a linked worktree whose path has a newline): the worktree's frame is injected" {
    wt="$BATS_TEST_TMPDIR/wt"$'\n'"nl"
    mkdir -p "$wt/.claude" "$tmp/.git/worktrees/wtnl"
    printf 'gitdir: %s\n' "$tmp/.git/worktrees/wtnl" > "$wt/.git"
    printf '## Current task\n\nnewline worktree body\n' > "$wt/TASK.md"
    run_load_handoff "$wt" "startup"
    [ "$status" -eq 0 ]
    ctx="$(context_of "$output")"
    [[ "$ctx" == *"newline worktree body"* ]]
    [[ "$ctx" != *"hook smoke test"* ]]
}

@test "load-handoff (cwd in a linked worktree whose path ends in a space): the worktree's frame is injected" {
    wt="$BATS_TEST_TMPDIR/wt trailing "
    mkdir -p "$wt/.claude" "$tmp/.git/worktrees/wtsp"
    printf 'gitdir: %s\n' "$tmp/.git/worktrees/wtsp" > "$wt/.git"
    printf '## Current task\n\ntrailing worktree body\n' > "$wt/TASK.md"
    run_load_handoff "$wt" "startup"
    [ "$status" -eq 0 ]
    ctx="$(context_of "$output")"
    [[ "$ctx" == *"trailing worktree body"* ]]
    [[ "$ctx" != *"hook smoke test"* ]]
}

# A path ENDING in a newline is the shape a `$(...)` capture loses: command
# substitution strips trailing newlines, so a root printed into one comes back
# naming a sibling directory. Each hook that resolves the root is owed the same
# answer as for any other path.

@test "load-handoff (cwd in a linked worktree whose path ends in a newline): the worktree's frame is injected" {
    wt="$(make_worktree_nl_end wtnlA)"; wt="${wt%X}"
    printf '## Current task\n\nnewline-ended worktree body\n' > "$wt/TASK.md"
    run_load_handoff "$wt" "startup"
    [ "$status" -eq 0 ]
    ctx="$(context_of "$output")"
    [[ "$ctx" == *"newline-ended worktree body"* ]]
    [[ "$ctx" != *"hook smoke test"* ]]
}

@test "load-compact (cwd in a linked worktree whose path ends in a newline): consumed, todo re-injected" {
    wt="$(make_worktree_nl_end wtnlB)"; wt="${wt%X}"
    printf '## Remaining\n\n- newline-ended item\n' > "$wt/TODO.md"
    printf '%s\n' pending compact /compact > "$wt/.claude/autodrive"
    run_load_compact "$wt"
    [ "$status" -eq 0 ]
    [ ! -e "$wt/.claude/autodrive" ]
    ctx="$(context_of "$output")"
    [[ "$ctx" == *"newline-ended item"* ]]
}

@test "write-guard (worktree whose path ends in a newline: its own sentinel is checkpoint-only)" {
    wt="$(make_worktree_nl_end wtnlC)"; wt="${wt%X}"
    run_write_guard Write "$wt" "$wt/.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage == "write-guard: autodrive is checkpoint-only"' >/dev/null
}

@test "report-drive-failure (drift to a cwd holding a newline: reported once, not every prompt)" {
    nlo="$BATS_TEST_TMPDIR/oth"$'\n'"er"
    mkdir -p "$nlo/.git"
    run_report_failure "$nlo"
    [ -n "$output" ]
    run_report_failure "$nlo"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "report-drive-failure (drift to a cwd ending in a newline: reported once, not every prompt)" {
    nlo="$BATS_TEST_TMPDIR/other-nl"$'\n'
    mkdir -p "$nlo/.git"
    run_report_failure "$nlo"
    [ -n "$output" ]
    run_report_failure "$nlo"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "report-drive-failure (project root with a newline in a directory component): sweeps an armed sentinel" {
    nl="$BATS_TEST_TMPDIR/nl"$'\n'"proj"
    mkdir -p "$nl/.claude"
    seed_drive "$nl" "clear" "/rename Title" "/clear" "continue the work"
    CLAUDE_PROJECT_DIR="$nl" run_report_failure "$nl"
    [ "$status" -eq 0 ]
    [ ! -e "$nl/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale autodrive discarded")' >/dev/null
}

# With the cwd in the first position of a line-wise read, its second line
# becomes the next field, so the rows above can pass on the root alone (the
# project is known from CLAUDE_PROJECT_DIR) while the fields that follow the cwd
# are wrong. These two pin those fields.
@test "load-handoff (clear, pending present, project root with a newline): consumed, the source field intact" {
    nl="$BATS_TEST_TMPDIR/nl"$'\n'"proj"
    mkdir -p "$nl/.claude"
    printf '## Current task\n\nnewline root body\n' > "$nl/TASK.md"
    seed_pending "$nl" "clear" "/rename A Title" "/clear" "pick up per the task file"
    CLAUDE_PROJECT_DIR="$nl" run_load_handoff "$nl" clear
    [ "$status" -eq 0 ]
    [ ! -e "$nl/.claude/autodrive" ]
}

@test "report-drive-failure (held file owned by this session, project root with a newline): left alone" {
    nl="$BATS_TEST_TMPDIR/nl"$'\n'"proj"
    mkdir -p "$nl/.claude"
    printf '%s\n' "held $SESSION_ID" "clear" "/rename A Title" "/clear" "resume" \
        > "$nl/.claude/autodrive"
    CLAUDE_PROJECT_DIR="$nl" run_report_failure "$nl"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$nl/.claude/autodrive")" = "held $SESSION_ID" ]
}
