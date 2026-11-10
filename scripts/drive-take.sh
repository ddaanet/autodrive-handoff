#!/usr/bin/env bash
# drive-take.sh <cwd> <session-id>: take this session's armed transition and
# print the plan the mod runs. Called by the mod, once per window, after
# a Stop, with the Stop event's cwd and session id. Exit 0 always; empty stdout
# means nothing was armed for this session (no file, `pending`, `held`, or
# `armed` by another session); an `armed` file with no session id given is a
# `kind: null` plan saying so, and so is a sentinel whose lock could not be taken
# (nothing touched). Otherwise one line of JSON:
# {kind, arg, continue, failFile, message}: data only, the mod holds the
# commands and the prompt (docs/design/driving-the-transition.md).
#
# The mod never touches the sentinel: this script takes it, through the same
# parser every other reader uses, so there is no second copy to drift. The mod
# runs it once per window, at turn.complete or at a prompt in the window,
# whichever comes first; drive-cancel.sh then only removes the `pending` file
# this take left. Leaving `armed` happens BEFORE the plan is printed, so a later
# turn cannot take the same transition twice.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

handoff_root_read "${1:-}"
root="$HANDOFF_ROOT"
# Nothing can be taken without the root; the plan carries the message alone, as
# for a malformed file, so the mod toasts it instead of the turn ending silent.
if [[ "$HANDOFF_ROOT_BRANCH" == "unresolved" ]]; then
    _handoff_drive_plan_json null "" false "" \
        "handoff: $HANDOFF_UNRESOLVED_MSG; no transition taken."
    exit 0
fi
session_id="${2:-}"
[[ -n "$root" ]] || exit 0

drive="$root/$HANDOFF_REL_DRIVE"
fail_file="$root/$HANDOFF_REL_DRIVE_FAILED"

# A link, dangling or not, reaches the reader, which refuses it.
[[ -L "$drive" || -f "$drive" ]] || exit 0

# The read and the move out of `armed` are one step under the sentinel's lock
# (_drive_lock.py), held until this script exits. The prompt-time sweep judges
# and removes the same file, and the host does not order its hook against this
# take: without the lock the sweep could read `armed`, lose the race to the
# arm below and then delete the `pending` file of a transition about to run,
# telling the user the mod never ran it. A checkpoint or an approval writing the
# file waits the same way. A lock that cannot be taken fails closed, whether
# busy past the wait (HANDOFF_LOCK_WAIT_SECS) or not set up at all: nothing is
# taken, the file is left exactly as it is (still `armed`, so the next prompt's
# sweep deals with it) and the plan carries the message alone, as for an
# unresolved root. The second test is for a file the sweep removed while this
# waited.
lock_rc=0
handoff_lock_take "$root/$HANDOFF_REL_DRIVE_LOCK" || lock_rc=$?
if (( lock_rc != 0 )); then
    _handoff_drive_plan_json null "" false "" \
        "handoff: $HANDOFF_LOCK_MSG; .claude/autodrive left untouched, nothing taken."
    exit 0
fi
[[ -L "$drive" || -f "$drive" ]] || exit 0

read_rc=0
handoff_drive_read "$drive" || read_rc=$?
if (( read_rc == 2 )); then
    # The reader could not run: the file may be a valid transition, so it is
    # left where it is and the plan carries the message alone, as for an
    # unresolved root. A later turn end, with a working reader, takes it.
    _handoff_drive_plan_json null "" false "" \
        "handoff: autodrive not read — $DRIVE_ERR; left in place, nothing taken."
    exit 0
fi
if (( read_rc != 0 )); then
    # A file no writer of this version composed: consume it so the complaint
    # does not repeat at every turn.
    rm -f "$drive"
    _handoff_drive_plan_json null "" false "$fail_file" \
        "handoff: autodrive malformed — $DRIVE_ERR; discarded, transition not armed."
    exit 0
fi

# Only an armed transition is this turn's to take; a pending one is in flight,
# waiting on its confirming SessionStart. And only the owner's: every session
# sharing the root ends turns here, the background session the harness starts
# after a `git commit` among them, and the prompt-time sweep leaves a live
# owner's file alone, so another session's turn end would otherwise run the
# owner's /rename and /clear in itself. No session id takes nothing, and says
# so: whose file it is cannot be told, and a Stop that carried none is a host
# fault no one would otherwise see. The plan carries the failFile, which the
# mod writes, so the next prompt reports it and sweeps the file.
[[ "$DRIVE_STATE" == "armed" ]] || exit 0
if [[ -z "$session_id" ]]; then
    _handoff_drive_plan_json null "" false "$fail_file" \
        "handoff: the turn ended with no session id, so the armed transition was not taken; the next prompt reports it."
    exit 0
fi
[[ "$DRIVE_OWNER" == "$session_id" ]] || exit 0

# `rename` has no confirming SessionStart, so a pending file would never clear.
case "$DRIVE_KIND" in
    rename) rm -f "$drive" ;;
    *) handoff_drive_arm "$drive" pending ;;
esac

# FR-G: nothing to run. The pending state alone is the loader's signal that the
# frame belongs in this compaction.
if [[ "$DRIVE_KIND" == "prepare" ]]; then
    _handoff_drive_plan_json '"prepare"' "" false "$fail_file" \
        "handoff: prepared for compact; nothing to run, frame will be re-injected."
    exit 0
fi

handoff_drive_plan "$fail_file"
