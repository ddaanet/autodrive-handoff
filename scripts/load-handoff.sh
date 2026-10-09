#!/usr/bin/env bash
# SessionStart hook for handoff loading. Fires on `startup` and `clear`
# (see hooks/hooks.json), and does two things:
#
#   - assembles the frame in memory — a timestamp header plus the inlined
#     agent-authored task file and todo remainder — and emits it via
#     hookSpecificOutput.additionalContext so the fresh agent sees the handoff
#     in its input for this turn, plus a curt systemMessage with content size
#     and age;
#   - on `clear`, consumes a pending transition of kind `clear`. The mod
#     (hooks/handoff.ts) ran the `/clear` and submits the continuation itself;
#     the file disappearing is what leaves the sentinel clean for the next
#     transition.
#
# Those two are independent: a driven clear whose task file is empty must still
# consume, so the consume comes BEFORE the no-frame exit. Silent only when there
# is nothing to inject and nothing was pending.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

{ read -r hook_cwd; read -r hook_event; read -r hook_source; } < <(
    jq -r '.cwd // "", .hook_event_name // "SessionStart", .source // ""'
)
cwd="$(handoff_root "$hook_cwd")"
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

# The frame is the header plus the agent-authored files inlined verbatim, and
# it gates itself: either file alone is enough, neither means nothing to
# inject. The prior session's working set is served by the harness's own
# gitStatus block, not reproduced here (see
# docs/changelog/2026-07-17-task-frame-drops-transcript.md).
task="$cwd/$HANDOFF_REL_TASK"
todo="$cwd/$HANDOFF_REL_TODO"
assembled="$(handoff_frame "$task" "$todo")" || assembled=""

if [[ -n "$assembled" ]]; then
    bytes=${#assembled}
    if (( bytes < 1024 )); then
        size="${bytes} B"
    else
        size=$(awk -v b="$bytes" 'BEGIN { printf "%.1f KiB", b/1024 }')
    fi

    # Age of the frame is the newest of whichever files it drew on — the frame
    # assembled, so at least one of them exists.
    mtime=$(python3 -c 'import os,sys
print(int(max(os.path.getmtime(p) for p in sys.argv[1:] if os.path.exists(p))))' \
        "$task" "$todo")
    now=$(date +%s)
    delta=$(( now - mtime ))
    if (( delta < 60 )); then age="just now"
    elif (( delta < 3600 )); then age="$((delta / 60))m ago"
    elif (( delta < 86400 )); then age="$((delta / 3600))h ago"
    else age="$((delta / 86400))d ago"
    fi
    notes=("loaded — ${size}, saved ${age}" ${notes[@]+"${notes[@]}"})
fi

(( ${#notes[@]} > 0 )) || exit 0

printf -v msg '%s; ' "${notes[@]}"

jq -nc \
    --arg m "handoff: ${msg%; }" \
    --arg c "$assembled" \
    --arg e "$hook_event" \
    '{systemMessage: $m}
     + (if $c == "" then {}
        else {hookSpecificOutput: {hookEventName: $e, additionalContext: ($c + "\n")}}
        end)'
