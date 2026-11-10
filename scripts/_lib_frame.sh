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
    FRAME="" FRAME_TASK=0 FRAME_TODO=0
    _handoff_has_body "$lib" "$task" && FRAME_TASK=1
    _handoff_has_body "$lib" "$todo" && FRAME_TODO=1
    (( FRAME_TASK + FRAME_TODO > 0 )) || return 1
    FRAME="# Task — $(date '+%Y-%m-%d %H:%M:%S %z')"
    if (( FRAME_TASK )); then
        FRAME+=$'\n\n'"$(cat "$task")"
    fi
    if (( FRAME_TODO )); then
        FRAME+=$'\n\n'"$(cat "$todo")"
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
