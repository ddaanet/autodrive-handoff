#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- _lib.sh: handoff_root_read resolver ---

@test "handoff_root_read: worktree cwd -> worktree root" {
    wt="$(make_worktree wtA)"
    handoff_root_read "$wt"
    [ "$HANDOFF_ROOT" = "$wt" ]
}

@test "handoff_root_read: worktree subdir -> worktree root" {
    wt="$(make_worktree wtB)"
    handoff_root_read "$wt/scripts"
    [ "$HANDOFF_ROOT" = "$wt" ]
}

@test "handoff_root_read: non-worktree cwd -> CLAUDE_PROJECT_DIR" {
    handoff_root_read "$other"
    [ "$HANDOFF_ROOT" = "$tmp" ]
}

# The project-root and empty-cwd cases resolve in bash without spawning
# python3 (they mirror worktree_root.py's trivial branches) — UserPromptSubmit and
# the loaders hit this on every turn. A broken python3 on PATH proves
# the fast path never leaves the shell.
@test "handoff_root_read: project-root or empty cwd -> fast path, no python3" {
    run bash -c '
        stub="$1/nopy"; mkdir -p "$stub"
        printf "#!/usr/bin/env bash\nexit 97\n" > "$stub/python3"
        chmod +x "$stub/python3"
        PATH="$stub:$PATH"
        source "$2/scripts/_lib.sh"
        handoff_root_read "$CLAUDE_PROJECT_DIR" && printf "%s\n" "$HANDOFF_ROOT"
        HANDOFF_ROOT=stale
        handoff_root_read "" && printf "%s\n" "$HANDOFF_ROOT"
    ' _ "$BATS_TEST_TMPDIR" "$repo_root"
    [ "$status" -eq 0 ]
    [ "$output" = "$tmp
$tmp" ]
}

# --- _lib.sh: handoff_root_read branch labels ---
#
# The root alone collapses four different situations into one answer. The
# branch label is what separates "cwd is still in the launch repo" from "cwd
# has left it", which is the whole drift signal. It reaches the caller as a
# global rather than on stdout, in the handoff_drive_read idiom.

@test "handoff_root_read: worktree cwd -> branch worktree" {
    wt="$(make_worktree wtBR)"
    handoff_root_read "$wt"
    [ "$HANDOFF_ROOT" = "$wt" ]
    [ "$HANDOFF_ROOT_BRANCH" = "worktree" ]
}

# The resolver's answer comes back on a line of its own; read with the default
# IFS it would lose the space this root ends on.
@test "handoff_root_read: a root ending in a space survives the slow path" {
    sp="$BATS_TEST_TMPDIR/spaced proj "
    mkdir -p "$sp" "$other/.git"
    CLAUDE_PROJECT_DIR="$sp" handoff_root_read "$other"
    [ "$HANDOFF_ROOT" = "$sp" ]
    [ "$HANDOFF_ROOT_BRANCH" = "foreign" ]
}

@test "handoff_root_read: cwd in another repo -> branch foreign" {
    mkdir -p "$other/.git"
    handoff_root_read "$other"
    [ "$HANDOFF_ROOT" = "$tmp" ]
    [ "$HANDOFF_ROOT_BRANCH" = "foreign" ]
}

@test "handoff_root_read: cwd in no repo at all -> branch unrelated" {
    handoff_root_read "$other"
    [ "$HANDOFF_ROOT" = "$tmp" ]
    [ "$HANDOFF_ROOT_BRANCH" = "unrelated" ]
}

# The fast path returns without spawning python3, so it has to label the branch
# itself or a caller reads whatever the previous resolution left behind.
@test "handoff_root_read: project root and empty cwd -> branch inside, no python3" {
    run bash -c '
        stub="$1/nopy-branch"; mkdir -p "$stub"
        printf "#!/usr/bin/env bash\nexit 97\n" > "$stub/python3"
        chmod +x "$stub/python3"
        PATH="$stub:$PATH"
        source "$2/scripts/_lib.sh"
        HANDOFF_ROOT_BRANCH=stale; handoff_root_read "$3"
        printf "%s\n%s\n" "$HANDOFF_ROOT" "$HANDOFF_ROOT_BRANCH"
        HANDOFF_ROOT_BRANCH=stale; handoff_root_read ""
        printf "%s\n" "$HANDOFF_ROOT_BRANCH"
    ' _ "$BATS_TEST_TMPDIR" "$repo_root" "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "$tmp
inside
inside" ]
}

@test "handoff_root_read: subdirectory of the project -> branch inside" {
    mkdir -p "$tmp/scripts"
    handoff_root_read "$tmp/scripts"
    [ "$HANDOFF_ROOT" = "$tmp" ]
    [ "$HANDOFF_ROOT_BRANCH" = "inside" ]
}

# The root comes back in a variable, never through stdout, so a root ending in
# a newline keeps it: a `$(...)` capture would strip it and name a sibling.
@test "handoff_root_read: a worktree root ending in a newline survives, and nothing is printed" {
    wt="$(make_worktree_nl_end wtnlR)"; wt="${wt%X}"
    run handoff_root_read "$wt"
    [ "$output" = "" ]
    handoff_root_read "$wt"
    [ "$HANDOFF_ROOT" = "$wt" ]
    [ "$HANDOFF_ROOT_BRANCH" = "worktree" ]
}

# --- a resolver that crashes ---
#
# Past the fast path the root comes from worktree_root.py. When that fails the
# root is unknown, and a hook acting on an empty or guessed root is the failure
# that goes unseen: the write guard let a sentinel write through (a PreToolUse
# that exits 1 is non-blocking), and the others exited 1 with nothing said.
# handoff_root_read labels the branch `unresolved` and each caller says so on
# its own channel.

# Echoes a directory holding a python3 that exits 97, to put first on PATH.
broken_python() {
    local stub="$BATS_TEST_TMPDIR/broken-python"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\nexit 97\n' > "$stub/python3"
    chmod +x "$stub/python3"
    printf '%s\n' "$stub"
}

@test "handoff_root_read (resolver crashes): branch unresolved, root empty, rc 0" {
    stub="$(broken_python)"
    HANDOFF_ROOT=stale HANDOFF_ROOT_BRANCH=stale
    rc=0; PATH="$stub:$PATH" handoff_root_read "$other" || rc=$?
    [ "$rc" -eq 0 ]
    [ "$HANDOFF_ROOT" = "" ]
    [ "$HANDOFF_ROOT_BRANCH" = "unresolved" ]
}

@test "write-guard (resolver crashes, a write to the sentinel): denied" {
    stub="$(broken_python)"
    PATH="$stub:$PATH" run_write_guard Write "$other" "$tmp/.claude/autodrive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("did not resolve")' >/dev/null
}

@test "write-guard (resolver crashes, a write not naming the sentinel): allowed, silent" {
    stub="$(broken_python)"
    PATH="$stub:$PATH" run_write_guard Write "$other" "$tmp/TODO.md"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "report-drive-failure (resolver crashes): says so on both channels, exit 0" {
    stub="$(broken_python)"
    PATH="$stub:$PATH" run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage | test("did not resolve")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("did not resolve")' >/dev/null
}

@test "load-handoff (resolver crashes): says so on both channels, no frame, exit 0" {
    stub="$(broken_python)"
    PATH="$stub:$PATH" run_load_handoff "$other" startup
    [ "$status" -eq 0 ]
    split_output "$output"
    [[ "$MSG" == "handoff: "*"did not resolve"* ]]
    [[ "$CTX" == *"did not resolve"* ]]
    [[ "$CTX" != *"hook smoke test"* ]]
}

@test "load-compact (resolver crashes): says so, exit 0" {
    stub="$(broken_python)"
    seed_pending "$tmp" "compact" "/compact" "continue"
    PATH="$stub:$PATH" run_load_compact "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage | test("did not resolve")' >/dev/null
}

# --- _lib.sh: handoff_deny emitter ---
# handoff_deny calls `exit 0`; `run` invokes it in a subshell so that exit
# terminates only the subshell, not the test.

@test "handoff_deny (emitter): deny decision, event, reason and systemMessage passthrough" {
    run handoff_deny "reason text" "system text"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null
    [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" = "reason text" ]
    [ "$(echo "$output" | jq -r '.systemMessage')" = "system text" ]
}

# --- _lib.sh: handoff_read_regular ---
#
# The check and the read are one open(2) with O_NOFOLLOW, so a link put at the
# name is never followed, whenever it was put there.

@test "handoff_read_regular (a regular file): ok, then its bytes" {
    printf 'a\nb' > "$BATS_TEST_TMPDIR/f"
    run handoff_read_regular "$BATS_TEST_TMPDIR/f"
    [ "$output" = $'ok\na\nb' ]
}

@test "handoff_read_regular (a link to a regular file): link, and nothing of the target" {
    printf 'TARGET-BYTES\n' > "$other/target"
    ln -s "$other/target" "$BATS_TEST_TMPDIR/f"
    run handoff_read_regular "$BATS_TEST_TMPDIR/f"
    [ "$output" = "link" ]
}

@test "handoff_read_regular (a dangling link): link" {
    ln -s "$other/nowhere" "$BATS_TEST_TMPDIR/f"
    run handoff_read_regular "$BATS_TEST_TMPDIR/f"
    [ "$output" = "link" ]
}

@test "handoff_read_regular (absent, a directory, a fifo): absent, other, other — no hang" {
    run handoff_read_regular "$BATS_TEST_TMPDIR/none"
    [ "$output" = "absent" ]
    mkdir "$BATS_TEST_TMPDIR/d"
    run handoff_read_regular "$BATS_TEST_TMPDIR/d"
    [ "$output" = "other" ]
    mkfifo "$BATS_TEST_TMPDIR/p"
    # shellcheck disable=SC2016   # $1/$2 are the inner bash -c's own positional params
    run timeout 5 bash -c 'source "$1"; handoff_read_regular "$2"' _ "$repo_root/scripts/_lib.sh" "$BATS_TEST_TMPDIR/p"
    [ "$output" = "other" ]
}

@test "handoff_read_regular (own, this user's file): ok" {
    printf 'x' > "$BATS_TEST_TMPDIR/f"
    run handoff_read_regular "$BATS_TEST_TMPDIR/f" own
    [ "$output" = $'ok\nx' ]
}

# `python3 -c` puts the working directory first on sys.path, and every hook
# runs in a repository that can commit a module of any name there. Isolated
# mode (-I) leaves it off, and ignores PYTHON* variables and the user site.
@test "every python3 -c in the hooks and bin runs isolated (-I)" {
    run grep -n 'python3 -c' scripts/*.sh bin/*
    [ "$status" -eq 1 ]
    run grep -h 'python3 -I -c' scripts/_lib.sh scripts/_lib_*.sh
    [ "$status" -eq 0 ]
}
