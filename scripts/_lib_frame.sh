#!/usr/bin/env bash
# The frame: the injectable task-and-todo frame.
# Part of _lib.sh. Source-only; no shebang
# execution. Reached through _lib.sh, which sources it after its own
# definitions, so callers source _lib.sh and never this file:
#   # shellcheck source-path=SCRIPTDIR source=_lib.sh
#   source "$(dirname "$0")/_lib.sh"

# Assemble the injectable frame from the task file ($1) and the todo file
# ($2): a timestamp header plus each half that counts inlined verbatim, task
# first. A half counts when its file has a body (`is_empty_body` in
# _checkpoint_lib.py, through its `--has-body` CLI). A missing, zero-byte,
# whitespace-only or headings-only file has none, and neither has one the
# check fails to run on, or one that is a symlink. Either half alone is enough.
# Shared by load-handoff.sh (startup|clear) and load-compact.sh (compact) — one
# frame shape for both transitions.
#
# Prints nothing; sets in the caller's scope on every call. FRAME is the frame,
# empty when neither half counts; FRAME_TASK and FRAME_TODO are each 1 or 0,
# the half being in the frame. Returns 1 when FRAME is empty. Callers under
# `set -e` absorb the 1 (`handoff_frame … || true`) and read the variables; a
# `$(…)` capture would lose them with the subshell.
#
# The hook does not re-state either template: each file carries its own `##`
# section headings (skills/handoff/SKILL.md holds the templates) and is concatenated
# verbatim under the one `#` header prepended here.
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_frame() {
    local task="$1" todo="$2" lib
    lib="$HANDOFF_LIB_DIR/_checkpoint_lib.py"
    # A path that is a symlink, dangling or not, is treated as absent: never
    # tested, read or counted. The checkpoint refuses a symlink at each, naming
    # the field, so the next checkpoint is what reports it; following one here
    # would inject whatever file it names, and a repository can commit a link
    # to anything readable.
    [[ -n "$task" && -L "$task" ]] && task=""
    [[ -n "$todo" && -L "$todo" ]] && todo=""
    FRAME="" FRAME_HEAD="" FRAME_TODO_TEXT="" FRAME_TASK=0 FRAME_TODO=0
    _handoff_has_body "$lib" "$task" && FRAME_TASK=1
    _handoff_has_body "$lib" "$todo" && FRAME_TODO=1
    (( FRAME_TASK + FRAME_TODO > 0 )) || return 1
    FRAME_HEAD="# Task — $(date '+%Y-%m-%d %H:%M:%S %z')"
    if (( FRAME_TASK )); then
        FRAME_HEAD+=$'\n\n'"$(cat "$task")"
    fi
    FRAME="$FRAME_HEAD"
    if (( FRAME_TODO )); then
        FRAME_TODO_TEXT="$(cat "$todo")"
        FRAME+=$'\n\n'"$FRAME_TODO_TEXT"
    fi
}

# Fit FRAME, as handoff_frame left it, to the hook's output limit once the
# loader's own text ($1, appended after the frame) and the closing newline are
# counted: TODO.md items are cut from the end, the open decisions last, and a
# line says how many. A frame that fits is untouched. The cut is
# `fit_frame` in _checkpoint_lib.py, which counts characters whatever the hook's
# locale. A cut that cannot run leaves the frame whole: a long frame is the
# lesser loss. Sets FRAME in the caller's scope; call it bare, as handoff_frame.
handoff_frame_fit() {
    local lib="$HANDOFF_LIB_DIR/_checkpoint_lib.py" fitted
    (( FRAME_TODO )) || return 0
    if fitted=$(printf '%s\0%s\0%s\0' "$FRAME_HEAD" "$FRAME_TODO_TEXT" "$1" \
            | python3 -I "$lib" --fit-frame); then
        FRAME="$fitted"
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
