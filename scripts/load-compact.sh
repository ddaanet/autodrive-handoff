#!/usr/bin/env bash
# SessionStart(compact): consume the pending compaction and re-inject the frame.
# `source: "compact"` is the authoritative compaction-complete signal — no
# pane-marker scraping, and it also covers a compaction that finishes too fast
# to observe as a busy->idle transition.
#
# The mod (hooks/handoff.ts) ran the `/compact` and submits the continuation
# prompt itself once it resolves; this hook only clears the sentinel and
# injects the frame. The hook fires for auto-compaction too, so the
# no-transition path must be silent.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# NUL-terminated and read whole: a cwd is any string, and one ending in a
# newline would lose it to a `$(...)` capture.
IFS= read -r -d '' hook_cwd < <(jq -j '(.cwd // ""), "\u0000"') || true
handoff_root_read "$hook_cwd"
cwd="$HANDOFF_ROOT"
[[ -n "$cwd" ]] || exit 0

drive="$cwd/$HANDOFF_REL_DRIVE"
[[ -f "$drive" ]] || exit 0

if ! handoff_drive_read "$drive"; then
    rm -f "$drive"
    jq -nc --arg e "$DRIVE_ERR" \
        '{systemMessage: ("handoff: autodrive malformed — " + $e + "; not resuming.")}'
    exit 0
fi

# Only a transition in flight is ours to complete, and only our own kind. An
# armed file belongs to a Stop that has not fired; a pending `clear` armed in
# this session and overtaken by a threshold auto-compaction would otherwise fire
# its continuation into the session the clear was meant to replace.
[[ "$DRIVE_STATE" == "pending" && "$DRIVE_KIND" == "compact" ]] || exit 0

# Consume unconditionally: a transition is taken at most once.
rm -f "$drive"

# The todo remainder carries the content across the compaction; the
# continuation prompt is only a handle to it. Inject the frame here so the handle
# resolves against the real thing rather than the summariser's paraphrase. Not
# consumed by reading — the files stay on disk for the next
# SessionStart(startup|clear). The checkpoint removes the task file at this
# boundary, so one with a body was written by hand since, and is injected too.
# The message is about the todo either way.
handoff_frame "$cwd/$HANDOFF_REL_TASK" "$cwd/$HANDOFF_REL_TODO" \
    "$cwd/$HANDOFF_LEGACY_REL_TASK" "$cwd/$HANDOFF_LEGACY_REL_TODO" || true
handoff_frame_notes

if (( FRAME_TODO )); then
    msg="handoff: compacted — todo re-injected"
else
    msg="handoff: compacted — No todo"
fi

# A half read from a legacy path, or a legacy file left unread beside a root
# one, is named on both channels, the same notes as load-handoff.sh.
context="$FRAME"
for note in ${FRAME_NOTES_CTX[@]+"${FRAME_NOTES_CTX[@]}"}; do
    context+=$'\n\n'"$note"
done
for note in ${FRAME_NOTES_MSG[@]+"${FRAME_NOTES_MSG[@]}"}; do
    msg+="; $note"
done
msg+="."

jq -nc --arg f "$context" --arg m "$msg" \
    'if $f == "" then {}
     else {hookSpecificOutput: {hookEventName: "SessionStart",
           additionalContext: ($f + "\n")}}
     end
     + {systemMessage: $m}'
