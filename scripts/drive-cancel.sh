#!/usr/bin/env bash
# drive-cancel.sh <cwd> <session-id> <kind>: cancel the `clear` or `compact`
# the window's own take just moved to `pending`, for a person's prompt that
# arrived after the arming turn's Stop and before the transition command was
# issued. Called by the mod's prompt.submit handler, only inside that window and
# only after its take returned a plan of that kind
# (docs/design/queued-prompts.md). Exit 0 always; it prints nothing and touches
# nothing unless it cancels, and then one line of JSON {kind, message, note}:
# `message` the user's toast, `note` the agent's directive. The sentinel is
# recorded in .claude/autodrive.swept and removed.
#
# `pending` has no owner (docs/design/sessions-sharing-a-root.md); the file is
# the one the take made in the same window, so the kind passed must match it.
# Anything else, `armed`, `held`, another kind or an unreadable file, prints
# nothing and is left as it is.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

handoff_root_read "${1:-}"
root="$HANDOFF_ROOT"
session_id="${2:-}"
kind="${3:-}"
[[ "$HANDOFF_ROOT_BRANCH" != "unresolved" && -n "$root" && -n "$session_id" ]] || exit 0
case "$kind" in
    clear | compact) ;;
    *) exit 0 ;;
esac

drive="$root/$HANDOFF_REL_DRIVE"
[[ -L "$drive" || -f "$drive" ]] || exit 0

# Under the sentinel's lock, as the take and the sweep are (sentinel-lock.md):
# the read and the removal are one step. A lock that cannot be taken fails
# closed: nothing printed, the file as it is. The second test is for a file the
# sweep removed while this waited.
lock_rc=0
handoff_lock_take "$root/$HANDOFF_REL_DRIVE_LOCK" || lock_rc=$?
(( lock_rc == 0 )) || exit 0
[[ -L "$drive" || -f "$drive" ]] || exit 0

read_rc=0
handoff_drive_read "$drive" || read_rc=$?
(( read_rc == 0 )) || exit 0
[[ "$DRIVE_STATE" == "pending" && "$DRIVE_KIND" == "$kind" ]] || exit 0

handoff_record_sweep "$root/$HANDOFF_REL_DRIVE_SWEPT" "$drive" "$session_id" \
    "$DRIVE_STATE" "${DRIVE_OWNER:--}" "$DRIVE_KIND" "$root"
rm -f "$drive"
jq -nc --arg k "$DRIVE_KIND" --arg m "$HANDOFF_CANCEL_MSG" --arg n "$(handoff_cancel_note "$DRIVE_KIND")" \
    '{kind: $k, message: ("handoff: " + $m + "."), note: $n}'
