#!/usr/bin/env bash
# SessionStart hook for handoff loading. Fires on `startup` and `clear`
# (see hooks/hooks.json), and does two things:
#
#   - assembles the frame in memory — a timestamp header plus the inlined
#     agent-authored task file and todo remainder, whichever count — and emits
#     it via hookSpecificOutput.additionalContext so the fresh agent sees the
#     handoff in its input for this turn, plus a curt systemMessage with
#     content size and age. A missing half, or both, is named on both channels,
#     and so is a half read from a legacy path or a legacy file left ignored;
#   - on `clear`, consumes a pending transition of kind `clear`. The mod
#     (hooks/handoff.ts) ran the `/clear` and submits the continuation itself;
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
[[ -n "$cwd" ]] || exit 0

notes=()   # systemMessage fragments from the transition, if any

drive="$cwd/$HANDOFF_REL_DRIVE"
if [[ "$hook_source" == "clear" && -f "$drive" ]]; then
    if ! handoff_drive_read "$drive"; then
        rm -f "$drive"
        notes+=("autodrive malformed — $DRIVE_ERR; not resuming")
    elif [[ "$DRIVE_STATE" == "pending" && "$DRIVE_KIND" == "clear" ]]; then
        # Only a transition in flight, and only our own kind: a compact armed in
        # the outgoing session is left for SessionStart(compact), and an armed
        # file — one whose Stop never fired — is left for the sweep.
        rm -f "$drive"
    fi
fi

# The frame is the header plus the agent-authored files that count, inlined
# verbatim: either file alone is enough. A file missing from it is named to the
# user and the agent, so a fresh session never reads an absent half as an
# oversight. The prior session's working set is served by the harness's own
# gitStatus block, not reproduced here (see
# docs/changelog/2026-07-17-task-frame-drops-transcript.md).
task="$cwd/$HANDOFF_REL_TASK"
todo="$cwd/$HANDOFF_REL_TODO"
legacy_task="$cwd/$HANDOFF_LEGACY_REL_TASK"
legacy_todo="$cwd/$HANDOFF_LEGACY_REL_TODO"
handoff_frame "$task" "$todo" "$legacy_task" "$legacy_todo" || true
handoff_frame_notes

context="$FRAME"
if [[ -n "$FRAME" ]]; then
    bytes=${#FRAME}
    if (( bytes < 1024 )); then
        size="${bytes} B"
    else
        size=$(awk -v b="$bytes" 'BEGIN { printf "%.1f KiB", b/1024 }')
    fi

    # Age of the frame is the newest of the files that count: a file the frame
    # left out does not make it younger, and a legacy file counts when its half
    # came from it.
    counted=()
    if (( FRAME_TASK_LEGACY )); then counted+=("$legacy_task")
    elif (( FRAME_TASK )); then counted+=("$task"); fi
    if (( FRAME_TODO_LEGACY )); then counted+=("$legacy_todo")
    elif (( FRAME_TODO )); then counted+=("$todo"); fi
    mtime=$(python3 -c 'import os,sys
print(int(max(os.path.getmtime(p) for p in sys.argv[1:])))' "${counted[@]}")
    now=$(date +%s)
    delta=$(( now - mtime ))
    if (( delta < 60 )); then age="just now"
    elif (( delta < 3600 )); then age="$((delta / 60))m ago"
    elif (( delta < 86400 )); then age="$((delta / 3600))h ago"
    else age="$((delta / 86400))d ago"
    fi
    notes+=("loaded — ${size}, saved ${age}")

    # Legacy notes on both channels, ahead of the gap note.
    for note in ${FRAME_NOTES_CTX[@]+"${FRAME_NOTES_CTX[@]}"}; do
        context+=$'\n\n'"$note"
    done
    for note in ${FRAME_NOTES_MSG[@]+"${FRAME_NOTES_MSG[@]}"}; do
        notes+=("$note")
    done
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

printf -v msg '%s; ' "${notes[@]}"

jq -nc \
    --arg m "handoff: ${msg%; }" \
    --arg c "$context" \
    --arg e "$hook_event" \
    '{systemMessage: $m,
      hookSpecificOutput: {hookEventName: $e, additionalContext: ($c + "\n")}}'
