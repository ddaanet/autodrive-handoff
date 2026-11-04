#!/usr/bin/env bash
# drive-cancel.sh <cwd> <session-id>: answer a person's prompt that arrived
# after the arming turn's Stop and before the transition command was issued.
# Called by the mod's prompt.submit handler, only inside that window
# (docs/design/queued-prompts.md). Exit 0 always; it prints nothing and touches
# nothing unless it acts, and then one line of JSON:
#
# - A `clear` or `compact` is cancelled: an `armed` file this session owns, or a
#   `pending` one, with at least one line to run. The sentinel is recorded in
#   .claude/autodrive.swept and removed, and the line is {kind, message, note}:
#   `message` the user's toast, `note` the agent's directive.
# - An `armed` `rename` this session owns is not cancelled but taken, as
#   drive-take.sh would: the file is removed (nothing is recorded, nothing was
#   cancelled) and the line is that take's plan {kind, arg, continue, failFile,
#   message}, with no `note`. The sweep reads `armed` at the prompt, ahead of
#   the take, and would otherwise discard the rename; the mod runs the plan
#   after the prompt's turn like any other.
#
# `pending` has no owner (docs/design/sessions-sharing-a-root.md), so nothing
# here can tell whose it is; the mod calls this only inside its own window, in
# which the `pending` file is the one its own take just made.
#
# - An `armed` `prepare` this session owns (nothing to run, FR-G)
#   is moved to `pending`, as the take does, and nothing is printed: the sweep
#   that follows spares it, and the hand-typed /compact still finds the marker.
#
# A `pending` `prepare`, a `held` file, another session's `armed`
# file and anything unreadable print nothing and are left as they are, to the
# take and the sweep.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

handoff_root_read "${1:-}"
root="$HANDOFF_ROOT"
session_id="${2:-}"
[[ "$HANDOFF_ROOT_BRANCH" != "unresolved" && -n "$root" && -n "$session_id" ]] || exit 0

drive="$root/$HANDOFF_REL_DRIVE"
[[ -L "$drive" || -f "$drive" ]] || exit 0

# Under the sentinel's lock, as the take and the sweep are (sentinel-lock.md):
# the read and the removal are one step. A lock that cannot be taken fails
# closed: nothing printed, the file as it is. The second test is for a file the
# sweep or the take removed while this waited.
lock_rc=0
handoff_lock_take "$root/$HANDOFF_REL_DRIVE_LOCK" || lock_rc=$?
(( lock_rc == 0 )) || exit 0
[[ -L "$drive" || -f "$drive" ]] || exit 0

read_rc=0
handoff_drive_read "$drive" || read_rc=$?
(( read_rc == 0 )) || exit 0

case "$DRIVE_STATE" in
    pending) ;;
    armed) [[ "$DRIVE_OWNER" == "$session_id" ]] || exit 0 ;;
    *) exit 0 ;;
esac
if [[ "$DRIVE_KIND" == "prepare" ]]; then
    # FR-G, nothing to run: moved to pending as the take does and left, so the
    # sweep that follows spares the marker and the hand-typed /compact finds it.
    # Only an armed one needs the move; a pending one is already there.
    if [[ "$DRIVE_STATE" == "armed" ]]; then
        handoff_drive_arm "$drive" pending || true
    fi
    exit 0
fi

if handoff_drive_has_source "$DRIVE_KIND"; then
    handoff_record_sweep "$root/$HANDOFF_REL_DRIVE_SWEPT" "$drive" "$session_id" \
        "$DRIVE_STATE" "${DRIVE_OWNER:--}" "$DRIVE_KIND" "$root"
    rm -f "$drive"
    jq -nc --arg k "$DRIVE_KIND" --arg m "$HANDOFF_CANCEL_MSG" --arg n "$(handoff_cancel_note "$DRIVE_KIND")" \
        '{kind: $k, message: ("handoff: " + $m + "."), note: $n}'
else
    rm -f "$drive"
    handoff_drive_plan "$root/$HANDOFF_REL_DRIVE_FAILED"
fi
