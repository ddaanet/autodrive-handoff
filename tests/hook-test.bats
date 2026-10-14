#!/usr/bin/env bats
# End-to-end test of the hook scripts against synthetic input.
# Each scenario is a real invocation of the hook with a hand-crafted
# tool-event payload. bats `run` captures exit codes and output without
# toggling errexit.
#
# Usage: bats tests/hook-test.bats   (run from plugin root)

setup() {
    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    cd "$repo_root" || return 1

    tmp="$BATS_TEST_TMPDIR/proj"
    other="$BATS_TEST_TMPDIR/other"
    mkdir -p "$tmp/.claude" "$other/.claude"
    export CLAUDE_PROJECT_DIR="$tmp"

    cat > "$tmp/TASK.md" <<'TASK'
## Current task

hook smoke test

## Open decisions

- none
TASK

    # The session-keyed pointer and drift marker live at a literal path
    # (/tmp/claude) so a hook and the agent's Bash can address them without
    # sharing an environment. Redirect it, or the suite writes into the
    # runner's own real one.
    export HANDOFF_POINTER_DIR="$BATS_TEST_TMPDIR/pointer"
    export SESSION_ID="sess-hook-test"

    # shellcheck source-path=SCRIPTDIR source=../scripts/_lib.sh disable=SC1091
    source "$repo_root/scripts/_lib.sh"
}

# A row may leave a file at mode 000; bats removes the temp tree afterwards and
# a leftover mode would only make that harder to debug.
teardown() {
    chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# Build a fake linked git worktree of $tmp under $BATS_TEST_TMPDIR/$name and
# echo its path. Its .git is a *file* pointing under $tmp/.git/worktrees/$name,
# mirroring real git worktree layout. $tmp is CLAUDE_PROJECT_DIR (set in setup).
make_worktree() {
    local name="${1:-wt}"
    local wt="$BATS_TEST_TMPDIR/$name"
    mkdir -p "$wt/.claude" "$tmp/.git/worktrees/$name"
    printf 'gitdir: %s\n' "$tmp/.git/worktrees/$name" > "$wt/.git"
    printf '%s\n' "$wt"
}

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

# --- _lib.sh: handoff_frame assembly ---
# A file counts when it exists and still has a body once headings and blank
# lines are set aside. The function prints nothing: it sets FRAME (one header
# line, then each counting file preceded by a blank line, task first; empty
# when neither counts) and the flags FRAME_TASK / FRAME_TODO (1 or 0) in the
# caller's scope, and returns 1 when FRAME is empty. These rows call it
# directly: `run` is a subshell, and a variable it set would never reach the
# test.

# <text> <expected> — text is one header line followed by exactly the expected
# rest, so a frame or an injected context is checked whole, not by grep.
assert_framed() {
    local header="${1%%$'\n'*}"
    local re='^# Task — [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$'
    [[ "$header" =~ $re ]] || return 1
    [ "${1#"$header"}" = "$2" ] || return 1
}

@test "handoff_frame (task and todo count): header, task, then todo; both flags 1" {
    fr="$BATS_TEST_TMPDIR/frame"; mkdir -p "$fr"
    printf '## Current task\n\ntask body\n' > "$fr/task.md"
    printf '## Remaining\n\n- todo body\n' > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\ntask body\n\n## Remaining\n\n- todo body'
    [ "${FRAME_TASK:-unset}" = "1" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
}

@test "handoff_frame (todo alone): the frame is the header and the todo; task flag 0" {
    fr="$BATS_TEST_TMPDIR/frame-todo"; mkdir -p "$fr"
    printf '## Remaining\n\n- lone remainder\n' > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Remaining\n\n- lone remainder'
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
}

@test "handoff_frame (task alone): the frame is the header and the task; todo flag 0" {
    fr="$BATS_TEST_TMPDIR/frame-task"; mkdir -p "$fr"
    printf '## Current task\n\nsolo task\n' > "$fr/task.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nsolo task'
    [ "${FRAME_TASK:-unset}" = "1" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
}

@test "handoff_frame (neither file exists): rc 1, FRAME empty, both flags 0" {
    fr="$BATS_TEST_TMPDIR/frame-none"; mkdir -p "$fr"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
}

@test "handoff_frame (zero-byte files): do not count" {
    fr="$BATS_TEST_TMPDIR/frame-empty"; mkdir -p "$fr"
    : > "$fr/task.md"; : > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
}

@test "handoff_frame (headings-only task beside a todo): the task headings stay out of FRAME" {
    fr="$BATS_TEST_TMPDIR/frame-heads"; mkdir -p "$fr"
    printf '## Current task\n\n## Open decisions\n' > "$fr/task.md"
    printf '## Remaining\n\n- real item\n' > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    # The positive: the todo is there. The exact rest rules the task headings out.
    assert_framed "${FRAME-}" $'\n\n## Remaining\n\n- real item'
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
}

@test "handoff_frame (headings-only on both sides): rc 1, FRAME empty, both flags 0" {
    fr="$BATS_TEST_TMPDIR/frame-heads-both"; mkdir -p "$fr"
    printf '## Current task\n\n## Open decisions\n' > "$fr/task.md"
    printf '## Remaining\n' > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
}

@test "handoff_frame (whitespace-only task beside a todo): the task does not count" {
    fr="$BATS_TEST_TMPDIR/frame-blank"; mkdir -p "$fr"
    printf '   \n\n\t\n' > "$fr/task.md"
    printf '## Remaining\n\n- real item\n' > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Remaining\n\n- real item'
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
}

# `#tag` and `#!/bin/sh` begin with a `#` and are body all the same: the rule is
# markdown's heading test, not a prefix test.
@test "handoff_frame (a #tag line and a #!/bin/sh line): both are body and both count" {
    fr="$BATS_TEST_TMPDIR/frame-hash"; mkdir -p "$fr"
    printf '#tag\n' > "$fr/task.md"
    printf '#!/bin/sh\n' > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n#tag\n\n#!/bin/sh'
    [ "${FRAME_TASK:-unset}" = "1" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
}

@test "handoff_frame (a second call): resets FRAME and both flags" {
    fr="$BATS_TEST_TMPDIR/frame-reset"; mkdir -p "$fr"
    printf '## Current task\n\ntask body\n' > "$fr/task.md"
    printf '## Remaining\n\n- todo body\n' > "$fr/todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    # The first call counts, or the reset below proves nothing.
    [ "${FRAME_TASK:-unset}" = "1" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
    [ -n "${FRAME-}" ]
    rc=0; handoff_frame "$fr/gone-task.md" "$fr/gone-todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
}

# The one place a `$(…)` capture is right: proving nothing is printed, with a
# missing file to show the shell's own redirect error stays out of it too.
@test "handoff_frame (output): nothing on stdout or stderr, with a missing todo" {
    fr="$BATS_TEST_TMPDIR/frame-quiet"; mkdir -p "$fr"
    printf '## Current task\n\nsolo task\n' > "$fr/task.md"
    out="$(handoff_frame "$fr/task.md" "$fr/todo.md" 2>"$fr/err")" || true
    [ "$out" = "" ]
    [ ! -s "$fr/err" ]
    # The same call, direct, does produce a frame: the silence is not a failure.
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nsolo task'
}

# --- _lib.sh: handoff_frame, legacy paths ---
# The call takes four paths: <task> <todo> <legacy-task> <legacy-todo>, the last
# two optional (absent is the same as a path that does not exist). Per half the
# root file counts when it has a body, else the legacy file when it has a body;
# FRAME inlines whichever counted, task first, exactly as before. Four more
# variables say what the loader must tell the agent, each 1 or 0 and reset on
# every call: FRAME_TASK_LEGACY / FRAME_TODO_LEGACY (the half came from the
# legacy path) and FRAME_TASK_SHADOWED / FRAME_TODO_SHADOWED (the half came from
# the root file and a legacy file exists beside it, so it is ignored). A
# headings-only root file does not shadow: the legacy file's body is loaded.

@test "handoff_frame (legacy task alone): the legacy task is the frame; task flag and task-legacy flag 1" {
    fr="$BATS_TEST_TMPDIR/frame-leg-task"; mkdir -p "$fr"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nlegacy task body'
    [ "${FRAME_TASK:-unset}" = "1" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (legacy todo alone): the legacy todo is the frame; todo flag and todo-legacy flag 1" {
    fr="$BATS_TEST_TMPDIR/frame-leg-todo"; mkdir -p "$fr"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Remaining\n\n- legacy item'
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (both halves legacy): task then todo, both legacy flags 1" {
    fr="$BATS_TEST_TMPDIR/frame-leg-both"; mkdir -p "$fr"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nlegacy task body\n\n## Remaining\n\n- legacy item'
    [ "${FRAME_TASK:-unset}" = "1" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (root with a body beside a legacy file): root wins, the legacy file is shadowed" {
    fr="$BATS_TEST_TMPDIR/frame-shadow"; mkdir -p "$fr"
    printf '## Current task\n\nroot task body\n' > "$fr/task.md"
    printf '## Remaining\n\n- root item\n' > "$fr/todo.md"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    # The exact rest rules the legacy bodies out.
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nroot task body\n\n## Remaining\n\n- root item'
    [ "${FRAME_TASK:-unset}" = "1" ]
    [ "${FRAME_TODO:-unset}" = "1" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "1" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "1" ]
}

@test "handoff_frame (root task shadows a legacy task, todo only legacy): the halves are told apart" {
    fr="$BATS_TEST_TMPDIR/frame-mixed"; mkdir -p "$fr"
    printf '## Current task\n\nroot task body\n' > "$fr/task.md"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nroot task body\n\n## Remaining\n\n- legacy item'
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "1" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

# Shadowed is decided by the legacy file existing, not by its having a body: the
# checkpoint reports a legacy file beside a root file with a body as ignored
# whatever it holds, and the loader and the checkpoint must not disagree about
# the same file. Each half uses a different kind of body-less legacy file.
@test "handoff_frame (root with a body beside a legacy file with no body): still shadowed, by existence" {
    fr="$BATS_TEST_TMPDIR/frame-shadow-empty"; mkdir -p "$fr"
    printf '## Current task\n\nroot task body\n' > "$fr/task.md"
    printf '## Remaining\n\n- root item\n' > "$fr/todo.md"
    printf '## Current task\n\n## Open decisions\n' > "$fr/legacy-task.md"
    : > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nroot task body\n\n## Remaining\n\n- root item'
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "1" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "1" ]
}

# A legacy path that is a symlink is neither read nor counted as existing: the
# checkpoint refuses one naming the field, and following it would inject
# whatever file it names. A dangling link is the same refusal; it is the valid
# link that discriminates, since `-f` already fails on a dangling one.
@test "handoff_frame (legacy files are symlinks to bodies): not read — rc 1, FRAME empty, flags 0" {
    fr="$BATS_TEST_TMPDIR/frame-leg-link"; mkdir -p "$fr"
    printf '## Current task\n\nlinked task body\n' > "$fr/elsewhere-task.md"
    printf '## Remaining\n\n- linked item\n' > "$fr/elsewhere-todo.md"
    ln -s "$fr/elsewhere-task.md" "$fr/legacy-task.md"
    ln -s "$fr/elsewhere-todo.md" "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
}

@test "handoff_frame (root with a body beside symlinked legacy files): root loaded, nothing shadowed" {
    fr="$BATS_TEST_TMPDIR/frame-leg-link-shadow"; mkdir -p "$fr"
    printf '## Current task\n\nroot task body\n' > "$fr/task.md"
    printf '## Remaining\n\n- root item\n' > "$fr/todo.md"
    printf 'x\n' > "$fr/elsewhere.md"
    ln -s "$fr/elsewhere.md" "$fr/legacy-task.md"
    ln -s "$fr/elsewhere.md" "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nroot task body\n\n## Remaining\n\n- root item'
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (dangling legacy symlinks, root with a body): root loaded, nothing read or shadowed" {
    fr="$BATS_TEST_TMPDIR/frame-leg-dangling"; mkdir -p "$fr"
    printf '## Remaining\n\n- root item\n' > "$fr/todo.md"
    ln -s "$fr/nowhere-task.md" "$fr/legacy-task.md"
    ln -s "$fr/nowhere-todo.md" "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Remaining\n\n- root item'
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (headings-only root beside a legacy body): the legacy body is loaded, nothing shadowed" {
    fr="$BATS_TEST_TMPDIR/frame-heads-leg"; mkdir -p "$fr"
    printf '## Current task\n\n## Open decisions\n' > "$fr/task.md"
    printf '## Remaining\n' > "$fr/todo.md"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nlegacy task body\n\n## Remaining\n\n- legacy item'
    [ "${FRAME_TASK_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (neither root nor legacy has a body): rc 1, FRAME empty, every flag 0" {
    fr="$BATS_TEST_TMPDIR/frame-leg-none"; mkdir -p "$fr"
    printf '## Current task\n\n## Open decisions\n' > "$fr/task.md"
    : > "$fr/legacy-task.md"
    printf '## Remaining\n' > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (a second call): resets the legacy and shadowed flags" {
    fr="$BATS_TEST_TMPDIR/frame-leg-reset"; mkdir -p "$fr"
    printf '## Current task\n\nroot task body\n' > "$fr/task.md"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    # Each call sets two flags and leaves the other two at 0: a task cannot be
    # both legacy and shadowed in one call. Two calls with complementary pairs
    # make every flag go 1 and then back to 0, or a flag that is only
    # initialised when unset passes.
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "1" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
    fr2="$BATS_TEST_TMPDIR/frame-leg-reset-2"; mkdir -p "$fr2"
    printf '## Remaining\n\n- root item\n' > "$fr2/todo.md"
    printf '## Current task\n\nlegacy task body\n' > "$fr2/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr2/legacy-todo.md"
    rc=0; handoff_frame "$fr2/task.md" "$fr2/todo.md" "$fr2/legacy-task.md" "$fr2/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "1" ]
    rc=0; handoff_frame "$fr/gone-task.md" "$fr/gone-todo.md" "$fr/gone-legacy-task.md" "$fr/gone-legacy-todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

# --- _lib.sh: handoff_frame, what counts as a body ---
# A half counts only when the file is readable and the library answers with its
# "has a body" status, exit 0, the one status no crash produces. An unreadable
# file is no body, and neither is an answer that is not that status (a crash, a
# missing library): the loader must not inject a frame because a check failed
# to run.

# <path> — skip when mode 000 does not deny this user's read (running as root).
require_read_denied() {
    if { : <"$1"; } 2>/dev/null; then
        skip "mode 000 does not deny reads for this user"
    fi
}

@test "handoff_frame (unreadable root files with a body): not a body — rc 1, FRAME empty, flags 0" {
    fr="$BATS_TEST_TMPDIR/frame-unreadable"; mkdir -p "$fr"
    printf '## Current task\n\ntask body\n' > "$fr/task.md"
    printf '## Remaining\n\n- todo body\n' > "$fr/todo.md"
    chmod 000 "$fr/task.md" "$fr/todo.md"
    require_read_denied "$fr/task.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
}

@test "handoff_frame (unreadable root files beside legacy bodies): the legacy files are loaded, not shadowing" {
    fr="$BATS_TEST_TMPDIR/frame-unreadable-leg"; mkdir -p "$fr"
    printf '## Current task\n\nroot task body\n' > "$fr/task.md"
    printf '## Remaining\n\n- root item\n' > "$fr/todo.md"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    chmod 000 "$fr/task.md" "$fr/todo.md"
    require_read_denied "$fr/task.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 0 ]
    assert_framed "${FRAME-}" $'\n\n## Current task\n\nlegacy task body\n\n## Remaining\n\n- legacy item'
    [ "${FRAME_TASK_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "1" ]
    [ "${FRAME_TASK_SHADOWED:-unset}" = "0" ]
    [ "${FRAME_TODO_SHADOWED:-unset}" = "0" ]
}

@test "handoff_frame (unreadable legacy files, no root files): not a body — rc 1, FRAME empty, legacy flags 0" {
    fr="$BATS_TEST_TMPDIR/frame-leg-unreadable"; mkdir -p "$fr"
    printf '## Current task\n\nlegacy task body\n' > "$fr/legacy-task.md"
    printf '## Remaining\n\n- legacy item\n' > "$fr/legacy-todo.md"
    chmod 000 "$fr/legacy-task.md" "$fr/legacy-todo.md"
    require_read_denied "$fr/legacy-task.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" "$fr/legacy-task.md" "$fr/legacy-todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
    [ "${FRAME_TODO:-unset}" = "0" ]
    [ "${FRAME_TASK_LEGACY:-unset}" = "0" ]
    [ "${FRAME_TODO_LEGACY:-unset}" = "0" ]
}

# The library is found beside the sourced _lib.sh, so a copy of _lib.sh in a
# directory of its own, sourced over the setup's, reads the stub placed beside
# it. Nothing in production changes for the test.
# <exit status> — a stubbed library answering that status; a task file with a
# body is then handed to handoff_frame.
frame_with_stub_status() {
    frame_with_stub_lib "$1" "$(printf 'import sys\nsys.exit(%s)\n' "$1")"
}

# <name> <library source> — the same, with the stub library's whole source.
frame_with_stub_lib() {
    stub="$BATS_TEST_TMPDIR/stub-lib-$1"; mkdir -p "$stub"
    cp "$repo_root/scripts/_lib.sh" "$stub/_lib.sh"
    printf '%s\n' "$2" > "$stub/_checkpoint_lib.py"
    # shellcheck source-path=SCRIPTDIR source=../scripts/_lib.sh disable=SC1090,SC1091
    source "$stub/_lib.sh"
    fr="$BATS_TEST_TMPDIR/frame-stub-$1"; mkdir -p "$fr"
    printf '## Current task\n\ntask body\n' > "$fr/task.md"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" 2>/dev/null || rc=$?
}

@test "handoff_frame (library exits 0, the has-a-body status): the task counts" {
    frame_with_stub_status 0
    [ "$rc" -eq 0 ]
    [ "${FRAME_TASK:-unset}" = "1" ]
}

@test "handoff_frame (library exits 1, the empty status): the task does not count" {
    frame_with_stub_status 1
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
}

@test "handoff_frame (library exits 2): not evidence of a body — rc 1, FRAME empty" {
    frame_with_stub_status 2
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
}

# A library that crashes exits 1 through Python's own uncaught-exception path,
# whatever the CLI's contract says, so the crash must land on a "no body" status.
@test "handoff_frame (library crashes with an uncaught exception): not evidence of a body" {
    frame_with_stub_lib crash 'raise RuntimeError("boom")'
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
}

@test "handoff_frame (library missing, so python3 cannot open it): not evidence of a body" {
    frame_with_stub_status 0
    rm "$stub/_checkpoint_lib.py"
    rc=0; handoff_frame "$fr/task.md" "$fr/todo.md" || rc=$?
    [ "$rc" -eq 1 ]
    [ "${FRAME-unset}" = "" ]
    [ "${FRAME_TASK:-unset}" = "0" ]
}

# --- _lib.sh: handoff_drive_read shape matrix ---
#
# Line 1 is the kind and the kind fixes the shape, so the remaining lines need
# no separator and each kind keeps its own rules. The lines are the literal
# commands the mod runs: it must not know which command any kind uses, and
# validation is what anchors it — the nth line of kind k must begin with the
# expected command literal, so the file cannot be made to run something else.

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

@test "handoff_drive_read (rename): one before-line, no after-line" {
    read_drive "armed sess-42" "rename" "/rename Driven Transitions"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_KIND" = rename ]
    [ "${#DRIVE_BEFORE[@]}" -eq 1 ]
    [ "${DRIVE_BEFORE[0]}" = "/rename Driven Transitions" ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

@test "handoff_drive_read (compact): command before, prose after" {
    read_drive "armed sess-42" "compact" "/compact focus on the parser" "continue with task 3"
    [ "$DRIVE_KIND" = compact ]
    [ "${DRIVE_BEFORE[0]}" = "/compact focus on the parser" ]
    [ "${DRIVE_AFTER[0]}" = "continue with task 3" ]
}

@test "handoff_drive_read (compact, bare command): accepted, /compact takes no argument" {
    read_drive "armed sess-42" "compact" "/compact" "continue with task 3"
    [ "${DRIVE_BEFORE[0]}" = "/compact" ]
}

# FR-G: the kind line alone. Nothing is run, but the transition is expected,
# and that expectation is what the frame's re-injection is gated on.
@test "handoff_drive_read (compact, kind line alone): legal, both sequences empty" {
    read_drive "armed sess-42" "compact"
    [ "$DRIVE_KIND" = compact ]
    [ "${#DRIVE_BEFORE[@]}" -eq 0 ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

@test "handoff_drive_read (clear): two before-lines in order, prose after" {
    read_drive "armed sess-42" "clear" "/rename A Title" "/clear" "pick up per the task file"
    [ "$DRIVE_KIND" = clear ]
    [ "${#DRIVE_BEFORE[@]}" -eq 2 ]
    [ "${DRIVE_BEFORE[0]}" = "/rename A Title" ]
    [ "${DRIVE_BEFORE[1]}" = "/clear" ]
    [ "${DRIVE_AFTER[0]}" = "pick up per the task file" ]
}

# The continuation is optional on both driven kinds: driving a transition and
# submitting a prompt into what it opens are separate decisions, and the cross
# product is what the two payload fields express.
@test "handoff_drive_read (clear, no continuation): nothing submitted after" {
    read_drive "armed sess-42" "clear" "/rename A Title" "/clear"
    [ "$DRIVE_KIND" = clear ]
    [ "${#DRIVE_BEFORE[@]}" -eq 2 ]
    [ "${DRIVE_BEFORE[1]}" = "/clear" ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

@test "handoff_drive_read (compact, no continuation): nothing submitted after" {
    read_drive "armed sess-42" "compact" "/compact focus on the parser"
    [ "$DRIVE_KIND" = compact ]
    [ "${DRIVE_BEFORE[0]}" = "/compact focus on the parser" ]
    [ "${#DRIVE_AFTER[@]}" -eq 0 ]
}

# The state drive-take.sh has already taken. The parser does not know which caller
# wants which state — it reports the value and the gates decide.
@test "handoff_drive_read (pending): parsed like any other state" {
    read_drive "pending" "clear" "/rename A Title" "/clear" "pick up per the task file"
    [ "$DRIVE_STATE" = pending ]
    [ "$DRIVE_KIND" = clear ]
    [ "${DRIVE_AFTER[0]}" = "pick up per the task file" ]
}

@test "handoff_drive_read (unknown kind): rejected, naming the kinds" {
    run read_drive "armed sess-42" "reboot" "/reboot"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition kind"* ]]
}

# The state a memory approval holds a typing transition in, so the keystrokes
# do not reach a pane whose turn is about to end on the approval question.
# It names its owner: the session whose approval it waits on.
@test "handoff_drive_read (held): parsed like any other state, and names its owner" {
    read_drive "held sess-42" "clear" "/rename A Title" "/clear" "pick up per the task file"
    [ "$DRIVE_STATE" = held ]
    [ "$DRIVE_OWNER" = sess-42 ]
    [ "$DRIVE_KIND" = clear ]
    [ "${DRIVE_AFTER[0]}" = "pick up per the task file" ]
}

# An unowned `held` names no session, so nothing can tell whose approval it
# waits on — which is exactly the file the sweep and handoff-approved must be
# able to reject.
@test "handoff_drive_read (held with no owner): rejected, naming the owner" {
    run read_drive "held" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"session"* ]]
}

# `armed` names its owner too: the session whose turn end takes it. Every
# session sharing the root runs the UserPromptSubmit sweep, and only the owner
# tells another session's prompt from the owner's own next one.
@test "handoff_drive_read (armed): names its owner" {
    read_drive "armed sess-42" "clear" "/rename A Title" "/clear" "resume"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_OWNER" = sess-42 ]
}

@test "handoff_drive_read (armed with no owner): rejected, naming the owner" {
    run read_drive "armed" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must name the session"* ]]
}

@test "handoff_drive_read (armed with two words for an owner): rejected" {
    run read_drive "armed sess-42 extra" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"one session id"* ]]
}

# Rejected as an owned state, not as an unknown one: `pending` is a state this
# parser knows, and the reason has to name what is actually wrong with the line,
# or the same message covers a typo and this. Past the take nothing is the
# owner's to decide: the confirming SessionStart consumes it in whichever
# session the transition opened.
@test "handoff_drive_read (owner on pending): rejected" {
    run read_drive "pending sess-42" "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no session"* ]]
}

# Read an owned file first: the owner must be cleared by the next read, or a
# caller comparing it acts on the previous file's session — which is the whole
# discriminator.
@test "handoff_drive_read (pending after held): no owner carried over" {
    read_drive "held sess-42" "clear" "/rename A Title" "/clear"
    [ "$DRIVE_OWNER" = sess-42 ]
    read_drive "pending" "clear" "/rename A Title" "/clear"
    [ "$DRIVE_STATE" = pending ]
    [ "$DRIVE_OWNER" = "" ]
}

@test "handoff_drive_read (unknown state): rejected, naming the states" {
    run read_drive "queued" "clear" "/rename A Title" "/clear" "resume"
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
    run read_drive "clear" "/rename A Title" "/clear" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition state"* ]]
}

@test "handoff_drive_read (empty file): rejected" {
    run read_drive ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"transition state"* ]]
}

@test "handoff_drive_read (wrong line count for the kind): rejected, naming the count" {
    run read_drive "armed sess-42" "rename" "/rename A Title" "extra line"
    [ "$status" -ne 0 ]
    [[ "$output" == *"exactly 3 lines"* ]]

    run read_drive "armed sess-42" "clear" "/rename A Title"
    [ "$status" -ne 0 ]
    [[ "$output" == *"4 or 5 lines"* ]]

    run read_drive "armed sess-42" "compact" "/compact" "continue" "extra"
    [ "$status" -ne 0 ]
    [[ "$output" == *"2, 3 or 4 lines"* ]]
}

@test "handoff_drive_read (command literal not in the kind's slot): rejected" {
    run read_drive "armed sess-42" "clear" "/clear" "/rename A Title" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"line 3"* ]]

    run read_drive "armed sess-42" "compact" "compact now" "continue"
    [ "$status" -ne 0 ]
    [[ "$output" == *"/compact"* ]]
}

@test "handoff_drive_read (/rename with no argument): rejected" {
    run read_drive "armed sess-42" "rename" "/rename"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-empty argument"* ]]

    run read_drive "armed sess-42" "rename" "/rename    "
    [ "$status" -ne 0 ]
}

@test "handoff_drive_read (/clear with an argument): rejected" {
    run read_drive "armed sess-42" "clear" "/rename A Title" "/clear now" "resume"
    [ "$status" -ne 0 ]
    [[ "$output" == *"exactly"* ]]
}

@test "handoff_drive_read (empty continuation prompt): rejected" {
    run read_drive "armed sess-42" "compact" "/compact" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"must not be empty"* ]]
}

# The mod dispatches on the leading character: a `/` line runs as a command,
# prose is submitted as a prompt. A prose line that looks like a command would
# run as the wrong one.
@test "handoff_drive_read (continuation prompt beginning with /): rejected" {
    run read_drive "armed sess-42" "clear" "/rename A Title" "/clear" "/resume the work"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must not begin"* ]]
}

# No writer of the sentinel makes a link, and a repository can commit one to
# anything readable: following it would parse that file, quote its first line
# into a report and let a later rewrite land on it. A link is refused before a
# byte is read, whatever it names.
@test "handoff_drive_read (a symlink to a well-formed sentinel): refused, nothing parsed" {
    printf '%s\n' "armed sess-42" "rename" "/rename Linked" > "$other/sentinel"
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
    run grep -c 'python3 -I -c' scripts/_lib.sh
    [ "$output" -ge 1 ]
}

# --- _lib.sh: handoff_drive_arm ---

# Everything below line 1 is copied through untouched: the arm never has to know
# the kind's shape, which is what lets one helper serve drive-take.sh and
# handoff-approved.
@test "handoff_drive_arm (rewrites line 1, preserves every line below)" {
    printf '%s\n' "armed sess-42" "clear" "/rename A Title" "/clear" "pick up per the task file" \
        > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
clear
/rename A Title
/clear
pick up per the task file" ]
}

# The FR-G marker is two lines, so the tail below line 1 is a single line.
@test "handoff_drive_arm (two-line file: still just the state line)" {
    printf '%s\n' "armed sess-42" "compact" > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
compact" ]
}

# The helper writes line 1 as given, so the owner is the caller's to carry or
# drop: handoff-approved keeps it across held -> armed, drive-take.sh drops it
# on armed -> pending.
@test "handoff_drive_arm (held -> armed with its owner: still parses, owner kept)" {
    printf '%s\n' "held sess-42" "clear" "/rename A Title" "/clear" \
        > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" "armed sess-42"
    handoff_drive_read "$BATS_TEST_TMPDIR/sentinel"
    [ "$DRIVE_STATE" = armed ]
    [ "$DRIVE_OWNER" = sess-42 ]
}

@test "handoff_drive_arm (armed -> pending: the owner goes with the state)" {
    printf '%s\n' "armed sess-42" "clear" "/rename A Title" "/clear" \
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
    printf '%s\n' "armed sess-42" "compact" "/compact" "continue" > "$BATS_TEST_TMPDIR/sentinel"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ "$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'sentinel*' | wc -l)" -eq 1 ]
}

# The temporary file is mktemp's, never a fixed or PID-derived name: a
# repository can commit links at as many such names as it likes, and the arm
# would write the state line through one and rename the link over the
# sentinel. `$$` here is the PID the helper sees, the name it used to take.
@test "handoff_drive_arm (a link at the old temporary name: not written through, the sentinel stays a file)" {
    printf '%s\n' "armed sess-42" "compact" "/compact" > "$BATS_TEST_TMPDIR/sentinel"
    ln -s "$other/planted" "$BATS_TEST_TMPDIR/sentinel.arming.$$"
    handoff_drive_arm "$BATS_TEST_TMPDIR/sentinel" pending
    [ ! -e "$other/planted" ]
    [ ! -L "$BATS_TEST_TMPDIR/sentinel" ]
    [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = "pending
compact
/compact" ]
}

# A link to a directory put at the sentinel after it was read: mv would move
# the temporary file into that directory. The rename replaces the link.
@test "handoff_drive_arm (the sentinel became a link to a directory: replaced, nothing moved into it)" {
    printf '%s\n' "armed sess-42" "compact" "/compact" > "$BATS_TEST_TMPDIR/sentinel"
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

# --- write-guard ---
# The autodrive sentinel is checkpoint-only: a direct agent Write/Edit to a file
# of that name is denied, in this project or outside it. Nothing else is
# guarded — TASK.md and TODO.md are plain files the agent may edit.

run_write_guard() {  # <tool> <cwd> <file_path> [CLAUDE_PROJECT_DIR]
    run bash -c '
        jq -nc --arg t "$1" --arg cwd "$2" --arg fp "$3" \
            "{cwd:\$cwd, tool_name:\$t, tool_input:{file_path:\$fp}}" \
        | CLAUDE_PROJECT_DIR="$4" bash scripts/write-guard.sh
    ' _ "$1" "$2" "$3" "${4:-$CLAUDE_PROJECT_DIR}"
}

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

# <json> — a loader's output (the $output of a `run`) split into the two
# channels, exact: MSG is systemMessage and CTX is additionalContext. The
# trailing X keeps the command substitution from eating the newlines the
# contexts end on.
split_output() {
    MSG="$(jq -j '(.systemMessage // "") + "X"' <<<"$1")"; MSG="${MSG%X}"
    CTX="$(jq -j '(.hookSpecificOutput.additionalContext // "") + "X"' <<<"$1")"; CTX="${CTX%X}"
}

# <regex> — the whole systemMessage is `handoff: ` and then the regex.
assert_msg_matches() {
    local re="^handoff: $1\$"
    [[ "$MSG" =~ $re ]]
}

loaded_re='loaded — ([0-9]+ B|[0-9]+\.[0-9] KiB), saved (just now|[0-9]+[mhd] ago)'

# The legacy-path notes, one pair per half and per case. `_ctx` is the line the
# agent reads in additionalContext, `_msg` the fragment the user reads in the
# systemMessage. Both loaders say the same thing on each channel; the checkpoint
# repeats the move on its own stdout.
#   from-legacy: the half was loaded from the old path. The next checkpoint
#                moves a todo, and removes a task: `task` is required content
#                or `clear` under handoff and removed under precompact, so a
#                legacy task is never carried.
#   shadowed:    the root file has a body, so the old file is ignored.
legacy_task_ctx='Task loaded from legacy .claude/handoff-task.md; the next checkpoint removes it, and the task a handoff checkpoint is given goes to TASK.md.'
legacy_todo_ctx='Todo loaded from legacy .claude/handoff-todo.md; edit it there until the next checkpoint moves it to TODO.md.'
legacy_task_msg='task from .claude/handoff-task.md, next checkpoint removes it'
legacy_todo_msg='todo from .claude/handoff-todo.md, next checkpoint moves it'
shadowed_task_ctx='Legacy .claude/handoff-task.md is ignored: TASK.md has a body.'
shadowed_todo_ctx='Legacy .claude/handoff-todo.md is ignored: TODO.md has a body.'
shadowed_task_msg='.claude/handoff-task.md ignored, TASK.md wins'
shadowed_todo_msg='.claude/handoff-todo.md ignored, TODO.md wins'

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

# <name> — a linked worktree of $tmp whose path ends in a newline; echoes it
# with an X appended, which the caller strips (the capture would eat the newline).
make_worktree_nl_end() {
    local wt="$BATS_TEST_TMPDIR/$1"$'\n'
    mkdir -p "$wt/.claude" "$tmp/.git/worktrees/$1"
    printf 'gitdir: %s\n' "$tmp/.git/worktrees/$1" > "$wt/.git"
    printf '%sX' "$wt"
}

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

# --- load-handoff on source: "clear" (consume the pending clear) ---
#
# The mod ran the `/clear` and submits the continuation itself; the loader only
# consumes the sentinel and injects the frame.

# The same file in state `pending`: a transition drive-take.sh has already taken,
# waiting on the SessionStart that confirms it.
seed_pending() {
    local dir="$1"; shift
    printf '%s\n' "pending" "$@" > "$dir/.claude/autodrive"
}

run_load_handoff() {
    run bash -c '
        jq -nc --arg cwd "$1" --arg s "$2" \
            "{cwd:\$cwd, hook_event_name:\"SessionStart\", source:\$s}" \
        | bash scripts/load-handoff.sh
    ' _ "$1" "$2"
}

@test "load-handoff (clear, pending present: consumes it, injects the frame)" {
    seed_pending "$tmp" "clear" "/rename A Title" "/clear" "pick up per the task file"
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
    seed_pending "$tmp" "clear" "/rename A Title" "/clear" "resume anyway"
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
    seed_pending "$tmp" "clear" "/rename A Title" "/clear"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    [ "$(sed -n 2p "$tmp/.claude/autodrive")" = "compact" ]
}

@test "load-handoff (startup with a pending present: does not consume it)" {
    seed_pending "$tmp" "clear" "/rename A Title" "/clear" "pick up per the task file"
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
    seed_drive "$tmp" "clear" "/rename A Title" "/clear" "pick up per the task file"
    run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed $SESSION_ID" ]
    echo "$output" | jq -e '.systemMessage | test("pick up") | not' >/dev/null
}

# Seed .claude/autodrive under $1 in state `armed`, owned by this suite's
# session — what the checkpoint, the file's one writer, leaves behind — with the
# remaining args as the lines below.
seed_drive() {
    local dir="$1"; shift
    printf '%s\n' "armed $SESSION_ID" "$@" > "$dir/.claude/autodrive"
}

# --- load-compact (SessionStart(compact): consume, re-inject the frame) ---
#
# The regression this matrix guards is silent: a frame that stops being injected
# fails by the successor knowing less, not by anything going red.

run_load_compact() {
    run bash -c '
        jq -nc --arg cwd "$1" "{cwd:\$cwd, source:\"compact\"}" \
        | bash scripts/load-compact.sh
    ' _ "$1"
}

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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_pending "$tmp" "compact" "/compact" "continue with task 3"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    split_output "$output"
    [ "$MSG" = "handoff: compacted — No todo." ]
    echo "$output" | jq -e 'has("hookSpecificOutput") | not' >/dev/null
}

@test "load-compact (pending of kind clear: left for SessionStart(clear))" {
    seed_pending "$tmp" "clear" "/rename A Title" "/clear" "pick up per the task file"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "pending" ]
    [ "$(sed -n 2p "$tmp/.claude/autodrive")" = "clear" ]
}

# The checkpoint removes TASK.md at this boundary, so the only way one is there
# when the compaction completes is a hand-written file. It is still the task
# frame, and it is injected.
@test "load-compact (a hand-written TASK.md alone: injected, and the message says No todo)" {
    seed_pending "$tmp" "compact" "/compact" "resume per the task file"
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
    seed_pending "$tmp" "compact" "/compact" "resume per the task file"
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
    seed_pending "$tmp" "compact" "/compact keep the parser work"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("hook smoke test")' >/dev/null
    echo "$output" | jq -e '.systemMessage == "handoff: compacted — No todo."' >/dev/null
}

# FR-G's other half: the prepare-only marker arrives here as a pending file with
# no after-line. Inject what there is.
@test "load-compact (empty after-sequence: frame injected)" {
    seed_pending "$tmp" "compact"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("hook smoke test")' >/dev/null
    echo "$output" | jq -e '.systemMessage == "handoff: compacted — No todo."' >/dev/null
}

@test "load-compact (worktree cwd: consumes the worktree pending file)" {
    wt="$(make_worktree wtLC)"
    seed_pending "$wt" "compact" "/compact" "continue with task 3"
    run_load_compact "$wt"
    [ "$status" -eq 0 ]
    [ ! -e "$wt/.claude/autodrive" ]
}

@test "load-compact (armed file: not consumed, no frame)" {
    seed_drive "$tmp" "compact" "/compact" "continue with task 3"
    run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed $SESSION_ID" ]
}

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
    seed_pending "$tmp" "clear" "/rename A Title" "/clear" "pick up per the task file"
    before="$(cat "$tmp/.claude/autodrive")"
    PATH="$(reader_stub):$PATH" run_load_handoff "$tmp" clear
    [ "$status" -eq 0 ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$before" ]
    echo "$output" | jq -e '.systemMessage | test("helper that reads it failed") and test("left in place")' >/dev/null
}

@test "load-compact (the reader's helper fails: pending kept, said so)" {
    seed_pending "$tmp" "compact" "/compact" "continue"
    before="$(cat "$tmp/.claude/autodrive")"
    PATH="$(reader_stub):$PATH" run_load_compact "$tmp"
    [ "$status" -eq 0 ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$before" ]
    echo "$output" | jq -e '.systemMessage | test("helper that reads it failed") and test("left in place")' >/dev/null
}

@test "report-drive-failure (the reader's helper fails: armed file kept, not swept, said so)" {
    seed_drive "$tmp" "compact" "/compact" "continue"
    before="$(cat "$tmp/.claude/autodrive")"
    PATH="$(reader_stub):$PATH" run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$(cat "$tmp/.claude/autodrive")" = "$before" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
    echo "$output" | jq -e '.systemMessage | test("helper that reads it failed") and test("left in place")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("left in place")' >/dev/null
}

# --- session-pointer (SessionStart, every source: sweep stale pointer files) ---
#
# Used to also publish this session's resolved root here, at a session-keyed
# path handoff-checkpoint (running in the agent's own Bash, where
# CLAUDE_PROJECT_DIR is unset) could address blind. Replaced by
# scripts/inject-checkpoint-root.sh (PreToolUse(Bash)), which resolves the
# root fresh on every matching call instead.

run_session_pointer() {
    local cwd="$1"
    run bash -c '
        jq -nc --arg cwd "$1" --arg sid "$2" \
          "{cwd:\$cwd, session_id:\$sid, source:\"startup\", hook_event_name:\"SessionStart\"}" \
        | bash scripts/session-pointer.sh
    ' _ "$cwd" "$SESSION_ID"
}

# scripts/inject-checkpoint-root.sh (PreToolUse(Bash)) resolves the root fresh
# on every matching call and injects it straight into the command now, instead
# of this hook sampling and publishing it once at SessionStart.
# SessionStart(resume) fires with the RESUMING process's cwd, before the
# harness moves the session into its own project dir — the one moment a sample
# taken here would stamp the wrong repo onto it. Mutation-checked: the first
# assertion cannot go red before the write is removed, so it is verified by
# reintroducing the old write and watching this alone go red. See
# plans/2026-08-05-checkpoint-root-via-updatedinput.md.
@test "session-pointer (no longer writes a root pointer)" {
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$HANDOFF_POINTER_DIR/handoff-root-$SESSION_ID" ]
}

@test "session-pointer (creates the pointer directory)" {
    [ ! -d "$HANDOFF_POINTER_DIR" ]
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ -d "$HANDOFF_POINTER_DIR" ]
}

# Created first at session start, so its mode is the one the drift report's
# marker_dir_ok judges: under a group-writable umask a plain `mkdir -p` makes
# it 0775, the marker is never used and the drift note repeats every prompt.
@test "session-pointer (creates the pointer directory 0700 under umask 002)" {
    mkdir -p "$other/.git"
    umask 002
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$HANDOFF_POINTER_DIR")" = "0o700" ]
    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
    run_report_failure "$other"
    [ "$output" = "" ]
}

# Nothing else removes these. The pointer outlives the session that published
# it, the drift marker outlives the episode it recorded, and the directory they
# share is swept by nobody. The producer sweeps its own leavings — once per
# session start, which is the only moment anything of this plugin's runs there.

@test "session-pointer (sweeps its own long-stale files)" {
    mkdir -p "$HANDOFF_POINTER_DIR"
    touch -t 202001010000 "$HANDOFF_POINTER_DIR/handoff-root-ancient" \
        "$HANDOFF_POINTER_DIR/handoff-drift-ancient"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$HANDOFF_POINTER_DIR/handoff-root-ancient" ]
    [ ! -e "$HANDOFF_POINTER_DIR/handoff-drift-ancient" ]
}

@test "session-pointer (keeps another live session's files)" {
    mkdir -p "$HANDOFF_POINTER_DIR"
    touch "$HANDOFF_POINTER_DIR/handoff-root-other" \
        "$HANDOFF_POINTER_DIR/handoff-drift-other"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-root-other" ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-drift-other" ]
}

# The load-bearing negative: the directory is shared and holds files this
# plugin never wrote, some of them weeks old. The sweep is scoped to the two
# names it publishes, at the one level it publishes them.
#
# The handoff-prefixed file pins the narrower claim — the two names, not the
# prefix. Collapsing the two -name clauses into one `handoff-*` is the
# plausible refactor, and every other row here is blind to it: it would claim
# any later handoff- file in this shared directory whose lifetime is not seven
# days. A new published name must be added here as deliberately as to the
# filter.
@test "session-pointer (never sweeps a file it does not own)" {
    mkdir -p "$HANDOFF_POINTER_DIR/sub"
    touch -t 202001010000 "$HANDOFF_POINTER_DIR/somebody-elses-file" \
        "$HANDOFF_POINTER_DIR/handoff-unpublished-ancient" \
        "$HANDOFF_POINTER_DIR/sub/handoff-root-nested"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ -e "$HANDOFF_POINTER_DIR/somebody-elses-file" ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-unpublished-ancient" ]
    [ -e "$HANDOFF_POINTER_DIR/sub/handoff-root-nested" ]
}

# --- report-drive-failure (UserPromptSubmit: surface a non-delivery) ---
#
# The drive mod has no channel back to the agent: a line it could not run is
# invisible once its turn is over. The mod drops a reason file; this hook is
# what reads it. One channel, since the transition is a singleton.

# $3, when given, is the hook input's transcript_path; without it the input
# carries none, as a hook that was handed no transcript would see.
run_report_failure() {
    run bash -c '
        if [ "$#" -ge 3 ]; then
            jq -nc --arg cwd "$1" --arg sid "$2" --arg tp "$3" \
              "{cwd:\$cwd, session_id:\$sid, transcript_path:\$tp, prompt:\"anything\"}"
        else
            jq -nc --arg cwd "$1" --arg sid "$2" \
              "{cwd:\$cwd, session_id:\$sid, prompt:\"anything\"}"
        fi | bash scripts/report-drive-failure.sh
    ' _ "$1" "${2-$SESSION_ID}" "${@:3}"
}

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
    seed_pending "$tmp" "compact" "/compact" "continue"
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
    seed_pending "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact keep the parser work" "continue with task 3"
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
    seed_drive "$tmp" "compact" "/compact" "continue with task 3"
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
    seed_drive "$tmp" "compact" "/compact" "continue with task 3"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    [ "$(wc -l < "$tmp/.claude/autodrive.swept")" -eq 1 ]
    line="$(cat "$tmp/.claude/autodrive.swept")"
    [[ "$line" == *$'\tsweeper='"$SESSION_ID"$'\tstate=armed\towner='"$SESSION_ID"$'\tkind=compact\tage='[0-9]*s$'\tcwd='* ]]
}

@test "report-drive-failure (a sweep records who removed what: held by another session)" {
    printf '%s\n' "held other-session" "clear" "/rename t" "/clear" "go" > "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    line="$(cat "$tmp/.claude/autodrive.swept")"
    [[ "$line" == *$'\tsweeper='"$SESSION_ID"$'\tstate=abandoned\towner=other-session\tkind=clear\t'* ]]
}

@test "report-drive-failure (a sweep records a stranded pending file)" {
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    seed_pending "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact" "continue"
    swap_on_first date "$tmp/.claude/autodrive.swept" "$other/dir"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$other/dir")" ]
    [ ! -L "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (a symlink at the old temporary name: not written through, the record still lands)" {
    printf 'decoy bytes\n' > "$other/decoy"
    ln -s "$other/decoy" "$tmp/.claude/autodrive.swept.tmp"
    seed_drive "$tmp" "compact" "/compact" "continue"
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
    seed_drive "$tmp" "compact" "/compact" "continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$(cd "$tmp/.claude" && printf '%s\n' autodrive.swept*)" = "autodrive.swept" ]
}

# The armed sentinel that survived to the next prompt never ran. One cause is a
# drive mod that did not load (--safe-mode, or Claude Code older than 2.1.287),
# in which case nothing will ever run it: the report names that cause and prints
# the lines the file held, before then after, one per line, for the user to type.
@test "report-drive-failure (stale armed autodrive: names the mod and prints the lines to type)" {
    # shellcheck disable=SC2016  # the literal $HOME is the odd content under test
    seed_drive "$tmp" "clear" '/rename Fix "the  $HOME" bug & more' "/clear" \
        "pick up 'task  3' per the *file*; then \\ done"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("drive mod")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("safe-mode")' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("2.1.287")' >/dev/null
    # shellcheck disable=SC2016
    expected='/rename Fix "the  $HOME" bug & more
/clear
pick up '"'"'task  3'"'"' per the *file*; then \ done'
    # Both channels carry the three lines whole, contiguous and in order.
    echo "$output" | jq -e --arg e "$expected" '.systemMessage | contains($e)' >/dev/null
    echo "$output" | jq -e --arg e "$expected" '.hookSpecificOutput.additionalContext | contains($e)' >/dev/null
}

# Prepare-only (FR-G): the kind line alone. The cause is still reported, but
# there is nothing to type, so no empty block is offered.
@test "report-drive-failure (stale armed autodrive with no lines: names the mod, prints nothing to type)" {
    seed_drive "$tmp" "compact"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("drive mod")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("Type in order") | not' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("fenced code block") | not' >/dev/null
}

# A held file owned by a dead session is a different cause entirely, and its
# lines are a dead session's: offering them for typing would replay them into
# this conversation.
@test "report-drive-failure (held file of a dead session: lines are not offered)" {
    printf '%s\n' "held sess-someone-else" "clear" "/rename A Title" "/clear" "resume" \
        > "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage | test("Type in order") | not' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("/rename A Title") | not' >/dev/null
}

# A sentinel that does not parse — here, a `clear` with only one of its four
# command/prose lines — describes no transition this session can complete.
# handoff_drive_read returns 1, drive_state is recorded as "malformed", and
# the sweep (any state other than "pending" or "held") discards it, but offers
# no lines to type: there is nothing it could say they were.
@test "report-drive-failure (malformed sentinel: discarded and reported)" {
    seed_drive "$tmp" "clear" "/rename A Title"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("discarded")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("Type in order") | not' >/dev/null
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
    printf '%s\n' "armed $SESSION_ID" "clear" "/rename LINKED-TITLE" "/clear" > "$other/linked-sentinel"
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
    seed_pending "$tmp" "compact" "/compact" "continue"
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
    printf '%s\n' "held $SESSION_ID" "clear" "/rename A Title" "/clear" "resume" \
        > "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "held $SESSION_ID" ]
}

# The exemption reaches exactly as far as its reason. A held file belongs to the
# session whose approval it waits on; once that session is gone the approval can
# never arrive. Left on disk it stays armable indefinitely, and handoff-approved
# would arm a dead session's `/rename` + `/clear` into a live conversation. With
# no transcript_path nothing shows the owner alive, so it is swept.
@test "report-drive-failure (held file owned by a dead session: discarded)" {
    printf '%s\n' "held sess-someone-else" "clear" "/rename A Title" "/clear" "resume" \
        > "$tmp/.claude/autodrive"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale|discarded")' >/dev/null
}

# --- report-drive-failure: a sentinel owned by another live session ---
#
# Every session sharing the root runs this hook — the background session the
# harness starts after a `git commit` among them — so another session's prompt
# says nothing about whether the owner is gone. The owner is live when its
# transcript, beside this session's, was written within HANDOFF_OWNER_LIVE_SECS.

# Seed a transcript for session $1 in the shared transcript directory and print
# this session's transcript path, which is what the hook input carries. $2, when
# given, is the owner transcript's age in seconds.
seed_transcript() {
    local dir="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$dir"
    printf '{}\n' > "$dir/$1.jsonl"
    if [ -n "${2:-}" ]; then
        python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]); os.utime(sys.argv[1], (t, t))' \
            "$dir/$1.jsonl" "$2"
    fi
    printf '%s\n' "$dir/$SESSION_ID.jsonl"
}

seed_owned() {  # <state> <owner>
    printf '%s\n' "$1 $2" "clear" "/rename A Title" "/clear" "resume" > "$tmp/.claude/autodrive"
}

@test "report-drive-failure (armed by another live session: left untouched, nothing said)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "armed sess-owner" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (armed by another session, its transcript stale: swept)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner 3600)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale autodrive discarded — the drive mod")' >/dev/null
    [[ "$(cat "$tmp/.claude/autodrive.swept")" == *$'\tstate=armed\towner=sess-owner\t'* ]]
    # Its lines are a dead session's: offering them for typing would replay them
    # into this conversation, as for a dead session's held file.
    echo "$output" | jq -e '.systemMessage | test("Type in order") | not' >/dev/null
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("/rename A Title") | not' >/dev/null
}

@test "report-drive-failure (armed by another session with no transcript of its own: swept)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript "$SESSION_ID")"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale autodrive discarded")' >/dev/null
}

@test "report-drive-failure (armed by another session, no transcript_path in the input: swept)" {
    seed_owned armed sess-owner
    seed_transcript sess-owner >/dev/null
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale autodrive discarded")' >/dev/null
}

# The owner's own next prompt is the exact discriminator for an aborted turn, and
# its own transcript is always fresh: liveness must not exempt the owner itself.
@test "report-drive-failure (armed by this session, its transcript fresh: swept as an aborted turn)" {
    seed_owned armed "$SESSION_ID"
    tp="$(seed_transcript "$SESSION_ID")"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("the drive mod did not run it")' >/dev/null
}

@test "report-drive-failure (liveness window: HANDOFF_OWNER_LIVE_SECS sets it, 600 s by default)" {
    seed_owned armed sess-owner
    tp="$(seed_transcript sess-owner 120)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$output" = "" ]
    [ -e "$tmp/.claude/autodrive" ]

    HANDOFF_OWNER_LIVE_SECS=60 run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ ! -e "$tmp/.claude/autodrive" ]
}

@test "report-drive-failure (held by another live session: left untouched, nothing said)" {
    seed_owned held sess-owner
    tp="$(seed_transcript sess-owner)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(head -n1 "$tmp/.claude/autodrive")" = "held sess-owner" ]
    [ ! -e "$tmp/.claude/autodrive.swept" ]
}

@test "report-drive-failure (held by another session, its transcript stale: swept as abandoned)" {
    seed_owned held sess-owner
    tp="$(seed_transcript sess-owner 3600)"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("held by a session that is gone")' >/dev/null
}

@test "report-drive-failure (held by another session with no transcript of its own: swept as abandoned)" {
    seed_owned held sess-owner
    tp="$(seed_transcript "$SESSION_ID")"
    run_report_failure "$tmp" "$SESSION_ID" "$tp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("held by a session that is gone")' >/dev/null
}

@test "report-drive-failure (failure and stale file: one report covering both)" {
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    seed_drive "$tmp" "compact" "/compact" "continue"
    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -sr 'length')" = "1" ]
    echo "$output" | jq -e '.systemMessage | test("rejected before it ran")' >/dev/null
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
}

# --- report-drive-failure: session-root drift ---
#
# Nothing announces a cwd that leaves the launch repo: the environment block,
# gitStatus and the project CLAUDE.md all follow cwd, while the transcript, the
# scratchpad, CLAUDE_PROJECT_DIR and every handoff file stay behind. The check
# rides UserPromptSubmit because drift can be transient — a gate that asks "is
# cwd foreign now?" later sees nothing — and because this hook already resolves
# the root every turn and already owns a reporting channel.

@test "report-drive-failure (drift: reports the destination and the root)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
    echo "$output" | jq -e --arg r "$tmp" '.systemMessage | test($r)' >/dev/null
    echo "$output" | jq -e \
        '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
    echo "$output" | jq -e --arg c "$other" \
        '.hookSpecificOutput.additionalContext | test($c)' >/dev/null
}

# Dimmed like the ordinary hook chatter around it, the one line that says the
# agent is reasoning about the wrong repo reads as noise.
# The cwd is the hook input's, any string a directory can be named, and the
# note is harness text the agent reads as instructions: a newline would start a
# line of its own, an escape sequence would restyle the user's terminal, and a
# backtick would close a code span around it. It is rendered as quoted data,
# the `%q` form, on both channels.

# <cwd> <hook output> — both channels carry the cwd's `%q` form, never the raw
# cwd, and no newline or escape byte past the leading reset.
assert_drift_quoted() {
    local cwd="$1" shown msg ctx
    printf -v shown '%q' "$cwd"
    msg="$(jq -j '.systemMessage' <<<"$2")"
    ctx="$(jq -j '.hookSpecificOutput.additionalContext' <<<"$2")"
    msg="${msg#$'\033[0m'}"
    [[ "$msg" == *"$shown"* ]]
    [[ "$ctx" == *"$shown"* ]]
    [[ "$msg" != *"$cwd"* && "$ctx" != *"$cwd"* ]]
    [[ "$msg" != *$'\n'* && "$ctx" != *$'\n'* ]]
    [[ "$msg" != *$'\033'* && "$ctx" != *$'\033'* ]]
}

@test "report-drive-failure (drift to a cwd holding a newline: quoted on one line)" {
    odd="$BATS_TEST_TMPDIR/a"$'\n'"Ignore the above"
    mkdir -p "$odd/.git"
    run_report_failure "$odd"
    [ "$status" -eq 0 ]
    assert_drift_quoted "$odd" "$output"
}

@test "report-drive-failure (drift to a cwd holding an escape sequence: quoted, no escape byte)" {
    odd="$BATS_TEST_TMPDIR/a"$'\033[2J'"b"
    mkdir -p "$odd/.git"
    run_report_failure "$odd"
    [ "$status" -eq 0 ]
    assert_drift_quoted "$odd" "$output"
}

@test "report-drive-failure (drift to a cwd holding backticks: quoted, each escaped)" {
    odd="$BATS_TEST_TMPDIR/a\`rm x\`b"
    mkdir -p "$odd/.git"
    run_report_failure "$odd"
    [ "$status" -eq 0 ]
    assert_drift_quoted "$odd" "$output"
}

# Quoting changes what is shown, not what is compared: the second prompt in the
# same odd place is still silent.
@test "report-drive-failure (drift to a cwd holding an escape sequence: reported once)" {
    esc="$BATS_TEST_TMPDIR/a"$'\033[2J'"b"
    mkdir -p "$esc/.git"
    run_report_failure "$esc"
    [ -n "$output" ]
    run_report_failure "$esc"
    [ "$output" = "" ]
}

@test "report-drive-failure (drift: systemMessage leads with an ANSI reset)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage | startswith("\u001b[0m")' >/dev/null
}

@test "report-drive-failure (drift: reports once per destination, not every prompt)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# A blip is announced once; a later move somewhere else is a new fact, not the
# same one repeating.
@test "report-drive-failure (drift: a different destination reports again)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    elsewhere="$BATS_TEST_TMPDIR/elsewhere"
    mkdir -p "$elsewhere/.git"
    run_report_failure "$elsewhere"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$elsewhere" '.systemMessage | test($c)' >/dev/null
}

# Back inside the launch repo, and back to silence — including from the marker
# the earlier drift left behind.
@test "report-drive-failure (drift: cwd back in the project is silent)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# Returning ends the episode, so the same destination reached again is a new
# fact — the transient blip is the shape this has to survive.
@test "report-drive-failure (drift: returning and drifting again reports again)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    run_report_failure "$tmp"
    [ "$output" = "" ]

    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

# The marker sits in a directory shared by every local user, so a name in it
# may be a link someone else planted. A link at the marker is neither read nor
# written through: one holding this very cwd must not silence the report, and
# one naming a file must not have the marker written into it.
@test "report-drive-failure (drift: a symlinked marker holding the cwd does not silence it)" {
    mkdir -p "$other/.git" "$HANDOFF_POINTER_DIR"
    printf '%s\0' "$other" > "$BATS_TEST_TMPDIR/planted-marker"
    ln -s "$BATS_TEST_TMPDIR/planted-marker" "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

@test "report-drive-failure (drift: a symlinked marker is replaced, its target untouched)" {
    mkdir -p "$other/.git" "$HANDOFF_POINTER_DIR"
    ln -s "$BATS_TEST_TMPDIR/planted-target" "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/planted-target" ]
    [ ! -L "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID" ]
    # The marker it wrote instead still keeps the episode to one report.
    run_report_failure "$other"
    [ "$output" = "" ]
}

# The directory itself may be a link another user planted: nothing is written
# through it, and the drift is still reported, every turn rather than never.
@test "report-drive-failure (drift: a symlinked marker directory is not written through)" {
    mkdir -p "$other/.git" "$BATS_TEST_TMPDIR/planted-dir"
    ln -s "$BATS_TEST_TMPDIR/planted-dir" "$HANDOFF_POINTER_DIR"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/planted-dir")" ]
    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

# A directory the hook creates is this user's alone, so no one else can plant
# a name in it.
@test "report-drive-failure (drift: the marker directory is created 0700)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$HANDOFF_POINTER_DIR")" = "0o700" ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID" ]
}

# This user's, but writable by others: anyone could replace the marker. It is
# not used, and the drift is reported every turn.
@test "report-drive-failure (drift: a group- or world-writable marker directory is not used)" {
    mkdir -p "$other/.git" "$HANDOFF_POINTER_DIR"
    chmod 777 "$HANDOFF_POINTER_DIR"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$HANDOFF_POINTER_DIR")" ]
    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

@test "report-drive-failure (drift: a worktree cwd is not drift)" {
    wt="$(make_worktree wtDR)"
    run_report_failure "$wt"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "report-drive-failure (drift and a non-delivery: one report covering both)" {
    mkdir -p "$other/.git"
    printf '%s\n' "rejected before it ran" > "$other/.claude/autodrive.failed"
    # The failure file the hook reads is the *root's*, not cwd's — that is the
    # split being reported.
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -sr 'length')" = "1" ]
    echo "$output" | jq -e '.systemMessage | test("rejected before it ran")' >/dev/null
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

@test "report-drive-failure (worktree cwd: sweeps the worktree file)" {
    wt="$(make_worktree wtG)"
    seed_drive "$wt" "compact" "/compact" "continue"
    run_report_failure "$wt"
    [ "$status" -eq 0 ]
    [ ! -e "$wt/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
}
