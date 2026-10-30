#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- _lib.sh: handoff_frame assembly ---
# A file counts when it exists and still has a body once headings and blank
# lines are set aside. The function prints nothing: it sets FRAME (one header
# line, then each counting file preceded by a blank line, task first; empty
# when neither counts) and the flags FRAME_TASK / FRAME_TODO (1 or 0) in the
# caller's scope, and returns 1 when FRAME is empty. These rows call it
# directly: `run` is a subshell, and a variable it set would never reach the
# test.

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

# The library is found beside the sourced _lib.sh, so a copy of _lib.sh and its
# parts in a directory of its own, sourced over the setup's, reads the stub
# placed beside it. Nothing in production changes for the test.
# <exit status> — a stubbed library answering that status; a task file with a
# body is then handed to handoff_frame.
frame_with_stub_status() {
    frame_with_stub_lib "$1" "$(printf 'import sys\nsys.exit(%s)\n' "$1")"
}

# <name> <library source> — the same, with the stub library's whole source.
frame_with_stub_lib() {
    stub="$BATS_TEST_TMPDIR/stub-lib-$1"; mkdir -p "$stub"
    cp "$repo_root/scripts/_lib.sh" "$repo_root"/scripts/_lib_*.sh "$stub/"
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
