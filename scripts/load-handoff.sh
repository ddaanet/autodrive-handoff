#!/usr/bin/env bash
# SessionStart hook for handoff loading. Fires on `startup` and `clear`
# (see the hooks manifest), and does two things:
#
#   - assembles the frame in memory — a timestamp header plus the inlined
#     agent-authored task file and todo remainder, whichever count — and emits
#     it via hookSpecificOutput.additionalContext so the fresh agent sees the
#     handoff in its input for this turn, plus a curt systemMessage with
#     content size and age. A missing half, or both, is named on both channels;
#   - on `clear`, consumes a pending transition of kind `clear`. The mod
#     ran the `/clear` and submits the continuation itself;
#     the file disappearing is what leaves the sentinel clean for the next
#     transition.
#
# Those two are independent: a driven clear with no frame must still consume,
# so the consume comes BEFORE the frame is assembled. Always emits one JSON
# object, except when the root does not resolve.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# NUL-terminated and read whole: a cwd is any string, and one holding a newline
# or ending in a space would otherwise be cut or trimmed, and shift the fields.
{ IFS= read -r -d '' hook_cwd; IFS= read -r -d '' hook_event; IFS= read -r -d '' hook_source; } < <(
    jq -j '(.cwd // ""), "\u0000", (.hook_event_name // "SessionStart"), "\u0000", (.source // ""), "\u0000"'
) || true
handoff_root_read "$hook_cwd"
cwd="$HANDOFF_ROOT"
if [[ "$HANDOFF_ROOT_BRANCH" == "unresolved" ]]; then
    jq -nc --arg m "$HANDOFF_UNRESOLVED_MSG" --arg e "$hook_event" \
        '{systemMessage: ("handoff: " + $m + "; no frame loaded."),
          hookSpecificOutput: {hookEventName: $e,
            additionalContext: ("The handoff frame was not loaded: " + $m + ".\n")}}'
    exit 0
fi
[[ -n "$cwd" ]] || exit 0

notes=()   # systemMessage fragments from the transition, if any

drive="$cwd/$HANDOFF_REL_DRIVE"
# `-L` as well as `-f`: a link at the sentinel, dangling or not, is refused by
# the reader and removed here, never read as no file and left in place.
#
# The read and the removal are one step under the sentinel's lock
# (_drive_lock.py): a checkpoint replaces whatever sentinel is there, so without
# it one could land between the two and be removed unread. The lock is let go
# once the file is consumed, ahead of the frame assembly. A lock that cannot be
# taken fails closed, busy past the wait (HANDOFF_LOCK_WAIT_SECS) or not set up
# at all: the sentinel is neither read nor removed, the frame below is assembled
# and injected as usual, and both channels say the transition state was left.
# The inner test is for a file removed while this waited.
lock_ctx=""   # the agent's half of that note
if [[ "$hook_source" == "clear" && ( -L "$drive" || -f "$drive" ) ]]; then
    lock_rc=0
    handoff_lock_take "$cwd/$HANDOFF_REL_DRIVE_LOCK" || lock_rc=$?
    if (( lock_rc != 0 )); then
        notes+=("autodrive left in place — $HANDOFF_LOCK_MSG")
        lock_ctx="The transition state ($HANDOFF_REL_DRIVE) was left in place, not consumed: $HANDOFF_LOCK_MSG."
    elif [[ -L "$drive" || -f "$drive" ]]; then
        read_rc=0
        handoff_drive_read "$drive" || read_rc=$?
        if (( read_rc == 2 )); then
            # The reader could not run, which says nothing about the file: kept.
            notes+=("autodrive not read — $DRIVE_ERR; left in place")
        elif (( read_rc != 0 )); then
            rm -f "$drive"
            notes+=("autodrive malformed — $DRIVE_ERR; not resuming")
        elif [[ "$DRIVE_STATE" == "pending" && "$DRIVE_KIND" == "clear" ]]; then
            # Only a transition in flight, and only our own kind: a compact armed
            # in the outgoing session is left for SessionStart(compact), and an
            # armed file — one whose Stop never fired — is left for the sweep.
            rm -f "$drive"
        fi
    fi
    { exec 9>&-; } 2>/dev/null
fi

# The frame is the header plus the agent-authored files that count, inlined
# verbatim: either file alone is enough. A file missing from it is named to the
# user and the agent, so a fresh session never reads an absent half as an
# oversight. The prior session's working set is served by the harness's own
# gitStatus block, not reproduced here.
task="$cwd/$HANDOFF_REL_TASK"
todo="$cwd/$HANDOFF_REL_TODO"
handoff_frame "$task" "$todo" || true

context="$FRAME"
if [[ -n "$FRAME" ]]; then
    bytes=${#FRAME}
    if (( bytes < 1024 )); then
        size="${bytes} B"
    else
        size=$(awk -v b="$bytes" 'BEGIN { printf "%.1f KiB", b/1024 }')
    fi

    # Age of the frame is the newest of the files that count: a file the frame
    # left out does not make it younger.
    counted=()
    if (( FRAME_TASK )); then counted+=("$task"); fi
    if (( FRAME_TODO )); then counted+=("$todo"); fi
    mtime=$(python3 -I -c 'import os,sys
print(int(max(os.path.getmtime(p) for p in sys.argv[1:])))' "${counted[@]}")
    now=$(date +%s)
    delta=$(( now - mtime ))
    if (( delta < 60 )); then age="just now"
    elif (( delta < 3600 )); then age="$((delta / 60))m ago"
    elif (( delta < 86400 )); then age="$((delta / 3600))h ago"
    else age="$((delta / 86400))d ago"
    fi
    notes+=("loaded — ${size}, saved ${age}")

    if (( ! FRAME_TODO )); then
        notes+=("No todo")
        context+=$'\n\n'"No todo."
    elif (( ! FRAME_TASK )); then
        notes+=("No task frame")
        context+=$'\n\n'"No task frame."
    fi
else
    notes+=("No task frame or todo.")
    context="No task frame or todo."
fi

if [[ -n "$lock_ctx" ]]; then
    context+=$'\n\n'"$lock_ctx"
fi

printf -v msg '%s; ' "${notes[@]}"

jq -nc \
    --arg m "handoff: ${msg%; }" \
    --arg c "$context" \
    --arg e "$hook_event" \
    '{systemMessage: $m,
      hookSpecificOutput: {hookEventName: $e, additionalContext: ($c + "\n")}}'
