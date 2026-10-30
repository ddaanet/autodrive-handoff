#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- write-guard ---
# The autodrive sentinel is checkpoint-only: a direct agent Write/Edit to a file
# of that name is denied, in this project or outside it. Nothing else is
# guarded — TASK.md and TODO.md are plain files the agent may edit.

@test "write-guard (autodrive: deny a Write, checkpoint-only)" {
    run_write_guard Write "$tmp" "$tmp/.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("autodrive") and test("checkpoint")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("checkpoint-only")' >/dev/null
}

@test "write-guard (autodrive: deny an Edit too)" {
    run_write_guard Edit "$tmp" "$tmp/.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}

@test "write-guard (cross-project autodrive: deny, naming both paths)" {
    run_write_guard Write "$tmp" "$other/.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
    echo "$output" | jq -e --arg o "$other" --arg t "$tmp" \
        '.hookSpecificOutput.permissionDecisionReason
         | test("outside this project") and contains($o) and contains($t)' >/dev/null
}

@test "write-guard (CLAUDE_PROJECT_DIR overrides cwd drift: denies as checkpoint-only, not cross-project)" {
    # Simulates shell cwd drifting to another directory (e.g. /add-dir + cd)
    # while the project root stays $tmp. Despite the drifted cwd, the write
    # resolves as in-project and is denied on the checkpoint-only ground, not
    # misclassified as cross-project.
    run_write_guard Write "$other" "$tmp/.claude/autodrive" "$tmp"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("written only by handoff-checkpoint")' >/dev/null
}

@test "write-guard (worktree cwd: the worktree's own autodrive is in-project, not main's)" {
    wt="$(make_worktree wtG)"
    run_write_guard Write "$wt" "$wt/.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("written only by handoff-checkpoint")' >/dev/null
    run_write_guard Write "$wt" "$tmp/.claude/autodrive"
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("outside this project")' >/dev/null
}

@test "write-guard (TASK.md: allow a Write and an Edit)" {
    run_write_guard Write "$tmp" "$tmp/TASK.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run_write_guard Edit "$tmp" "$tmp/TASK.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "write-guard (TODO.md: allow a Write and an Edit)" {
    run_write_guard Write "$tmp" "$tmp/TODO.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run_write_guard Edit "$tmp" "$tmp/TODO.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "write-guard (autodrive.md: a longer basename is not the sentinel, allow)" {
    run_write_guard Write "$tmp" "$tmp/.claude/autodrive.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# A JSON string may hold a newline, and the tool resolves `a<LF>b/..` away
# lexically, so this path lands on the sentinel. Read line by line, the hook
# would see `…/a` as the path and let it through.
@test "write-guard (newline in a directory component: still the sentinel, deny)" {
    run_write_guard Write "$tmp" "$tmp/a"$'\n'"b/../.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("written only by handoff-checkpoint")' >/dev/null
}

# The tool normalises the path it is given, so each of these lands on the
# sentinel although its last component is not the sentinel's name.
@test "write-guard (trailing slash, trailing /., a .. detour: each still the sentinel, deny)" {
    for fp in "$tmp/.claude/autodrive/" "$tmp/.claude/autodrive/." \
              "$tmp/.claude/sub/../autodrive" "$tmp/.claude//autodrive"; do
        run_write_guard Write "$tmp" "$fp"
        [ "$status" -eq 0 ]
        echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
            | test("written only by handoff-checkpoint")' >/dev/null
    done
}

# Resolving follows symlinks, so the sentinel's own resolved name need not be
# `autodrive`. The verdict is on where the write lands against where the
# sentinel lands, and on the name at either end.
@test "write-guard (the sentinel is a symlink: a write through it is still denied)" {
    printf 'armed\n' > "$tmp/.claude/real-sentinel"
    ln -s real-sentinel "$tmp/.claude/autodrive"
    run_write_guard Write "$tmp" "$tmp/.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("written only by handoff-checkpoint")' >/dev/null
}

@test "write-guard (a symlink under another name that mentions it, onto the sentinel: denied)" {
    printf 'armed\n' > "$tmp/.claude/autodrive"
    ln -s "$tmp/.claude/autodrive" "$tmp/autodrive-alias"
    run_write_guard Write "$tmp" "$tmp/autodrive-alias"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("written only by handoff-checkpoint")' >/dev/null
}

@test "write-guard (another project's sentinel is a symlink: denied as cross-project)" {
    printf 'armed\n' > "$other/.claude/real-sentinel"
    ln -s real-sentinel "$other/.claude/autodrive"
    for fp in "$other/.claude/autodrive" "$other/.claude/autodrive/."; do
        run_write_guard Write "$tmp" "$fp"
        [ "$status" -eq 0 ]
        echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
            | test("outside this project")' >/dev/null
    done
}

@test "write-guard (an alias onto another project's sentinel: denied as cross-project)" {
    printf 'armed\n' > "$other/.claude/autodrive"
    ln -s "$other/.claude/autodrive" "$tmp/autodrive-alias"
    run_write_guard Write "$tmp" "$tmp/autodrive-alias"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("outside this project")' >/dev/null
}

@test "write-guard (trailing whitespace after the name: deny)" {
    run_write_guard Write "$tmp" "$tmp/.claude/autodrive "
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}

@test "write-guard (a file under a directory named autodrive: allow)" {
    run_write_guard Write "$tmp" "$tmp/autodrive/notes.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "write-guard (root with a space and a trailing space in the cwd: in-project, deny)" {
    sp="$BATS_TEST_TMPDIR/spaced proj "
    mkdir -p "$sp/.claude"
    run_write_guard Write "$sp" "$sp/.claude/autodrive" "$sp"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason
        | test("written only by handoff-checkpoint")' >/dev/null
}

@test "write-guard (no file_path in the event: allow)" {
    run bash -c 'jq -nc "{cwd:\"$1\", tool_name:\"Write\", tool_input:{}}" \
        | bash scripts/write-guard.sh' _ "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
