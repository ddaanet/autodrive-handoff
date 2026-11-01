#!/usr/bin/env bash
# The frame: the injectable task-and-todo frame and its legacy notes.
# Part of _lib.sh. Source-only; no shebang
# execution. Reached through _lib.sh, which sources it after its own
# definitions, so callers source _lib.sh and never this file:
#   # shellcheck source-path=SCRIPTDIR source=_lib.sh
#   source "$(dirname "$0")/_lib.sh"

# Assemble the injectable frame from the task file ($1) and the todo file
# ($2): a timestamp header plus each half that counts inlined verbatim, task
# first. $3 and $4 are the legacy task and todo paths, optional; an absent or
# empty one is a path that does not exist, and so is any of the four that is a
# symlink. Per half, the root file counts when
# it has a body (`is_empty_body` in _checkpoint_lib.py, through its
# `--has-body` CLI), and otherwise the legacy file does when it has a body. A
# missing, zero-byte, whitespace-only or headings-only file has none, and
# neither has one the check fails to run on. Either half alone is enough.
# Shared by load-handoff.sh (startup|clear) and load-compact.sh (compact) — one
# frame shape for both transitions.
#
# Prints nothing; sets in the caller's scope on every call. FRAME is the frame,
# empty when neither half counts, and never holds a note; the rest are each 1 or 0:
#   FRAME_TASK, FRAME_TODO   the half is in the frame
#   FRAME_TASK_LEGACY, FRAME_TODO_LEGACY
#                            the half came from its legacy path
#   FRAME_TASK_SHADOWED, FRAME_TODO_SHADOWED
#                            the half came from the root file and a legacy
#                            file exists beside it, whatever that one holds
# and returns 1 when FRAME is empty. Callers under `set -e` absorb the 1
# (`handoff_frame … || true`) and read the variables; a `$(…)` capture would
# lose them with the subshell. `handoff_frame_notes` turns the flags into the
# notes the loaders append.
#
# The hook does not re-state either template: each file carries its own `##`
# section headings (references/files.md is the single source of truth) and is concatenated
# verbatim under the one `#` header prepended here.
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_frame() {
    local task="$1" todo="$2" legacy_task="${3:-}" legacy_todo="${4:-}" lib
    local task_src todo_src
    lib="$HANDOFF_LIB_DIR/_checkpoint_lib.py"
    # Any of the four paths that is a symlink, dangling or not, is treated as
    # absent: never tested, read or counted as shadowing or shadowed. The
    # checkpoint refuses a symlink at each, naming the field (a dangling
    # legacy one it reads as no file), so the next checkpoint is what reports
    # it; following one here would inject whatever
    # file it names, and a repository can commit a link to anything readable.
    # A symlinked root file is a root file with no body, so the legacy file
    # beside it is loaded as it would be beside any such file.
    [[ -n "$task" && -L "$task" ]] && task=""
    [[ -n "$todo" && -L "$todo" ]] && todo=""
    [[ -n "$legacy_task" && -L "$legacy_task" ]] && legacy_task=""
    [[ -n "$legacy_todo" && -L "$legacy_todo" ]] && legacy_todo=""
    task_src="$task" todo_src="$todo"
    FRAME="" FRAME_TASK=0 FRAME_TODO=0
    FRAME_TASK_LEGACY=0 FRAME_TODO_LEGACY=0
    FRAME_TASK_SHADOWED=0 FRAME_TODO_SHADOWED=0
    if _handoff_has_body "$lib" "$task"; then
        FRAME_TASK=1
        [[ -n "$legacy_task" && -f "$legacy_task" ]] && FRAME_TASK_SHADOWED=1
    elif _handoff_has_body "$lib" "$legacy_task"; then
        FRAME_TASK=1 FRAME_TASK_LEGACY=1
        task_src="$legacy_task"
    fi
    if _handoff_has_body "$lib" "$todo"; then
        FRAME_TODO=1
        [[ -n "$legacy_todo" && -f "$legacy_todo" ]] && FRAME_TODO_SHADOWED=1
    elif _handoff_has_body "$lib" "$legacy_todo"; then
        FRAME_TODO=1 FRAME_TODO_LEGACY=1
        todo_src="$legacy_todo"
    fi
    (( FRAME_TASK + FRAME_TODO > 0 )) || return 1
    FRAME="# Task — $(date '+%Y-%m-%d %H:%M:%S %z')"
    if (( FRAME_TASK )); then
        FRAME+=$'\n\n'"$(cat "$task_src")"
    fi
    if (( FRAME_TODO )); then
        FRAME+=$'\n\n'"$(cat "$todo_src")"
    fi
}

# <is_empty_body library> <path>. True when the path is a file with a body.
# The CLI answers a body with exit 0, the one status no crash can produce (an
# uncaught exception exits 1, a library python3 cannot open exits 2), so a
# check that failed to run is never read as a body.
_handoff_has_body() {
    [[ -n "$2" && -f "$2" && -r "$2" ]] || return 1
    python3 "$1" --has-body <"$2"
}

# The notes for the legacy flags `handoff_frame` just set, in the order both
# channels carry them: task from legacy, todo from legacy, task ignored, todo
# ignored. Sets FRAME_NOTES_CTX (full sentences for the agent) and
# FRAME_NOTES_MSG (fragments for the user's one-line message), parallel arrays
# reset on every call. Expand them as `${A[@]+"${A[@]}"}` (bash 3.2).
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_frame_notes() {
    FRAME_NOTES_CTX=() FRAME_NOTES_MSG=()
    if (( FRAME_TASK_LEGACY )); then
        # Removed, never moved: `task` is required content or `clear` under
        # handoff, and precompact removes the task, so no checkpoint carries a
        # legacy task's bytes to the root the way `keep` carries a todo's.
        FRAME_NOTES_CTX+=("Task loaded from legacy $HANDOFF_LEGACY_REL_TASK; the next checkpoint removes it, and the task a handoff checkpoint is given goes to $HANDOFF_REL_TASK.")
        FRAME_NOTES_MSG+=("task from $HANDOFF_LEGACY_REL_TASK, next checkpoint removes it")
    fi
    if (( FRAME_TODO_LEGACY )); then
        FRAME_NOTES_CTX+=("Todo loaded from legacy $HANDOFF_LEGACY_REL_TODO; edit it there until the next checkpoint moves it to $HANDOFF_REL_TODO.")
        FRAME_NOTES_MSG+=("todo from $HANDOFF_LEGACY_REL_TODO, next checkpoint moves it")
    fi
    if (( FRAME_TASK_SHADOWED )); then
        FRAME_NOTES_CTX+=("Legacy $HANDOFF_LEGACY_REL_TASK is ignored: $HANDOFF_REL_TASK has a body.")
        FRAME_NOTES_MSG+=("$HANDOFF_LEGACY_REL_TASK ignored, $HANDOFF_REL_TASK wins")
    fi
    if (( FRAME_TODO_SHADOWED )); then
        FRAME_NOTES_CTX+=("Legacy $HANDOFF_LEGACY_REL_TODO is ignored: $HANDOFF_REL_TODO has a body.")
        FRAME_NOTES_MSG+=("$HANDOFF_LEGACY_REL_TODO ignored, $HANDOFF_REL_TODO wins")
    fi
}
