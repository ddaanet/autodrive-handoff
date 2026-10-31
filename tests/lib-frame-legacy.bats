#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

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
