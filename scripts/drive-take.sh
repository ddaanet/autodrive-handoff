#!/usr/bin/env bash
# drive-take.sh <cwd> <session-id>: take this session's armed transition and
# print the plan the mod runs. Called by hooks/handoff.ts at turn.complete after
# a Stop, with the Stop event's cwd and session id. Exit 0 always; empty stdout
# means nothing was armed for this session (no file, `pending`, `held`, or
# `armed` by another session); an `armed` file with no session id given is a
# `kind: null` plan saying so. Otherwise one line of JSON:
# {kind, before[], after[], failFile, message}.
#
# The mod never touches the sentinel: this script is the one place that leaves
# `armed`, through the same parser every other reader uses, so there is no second
# copy to drift. Leaving `armed` happens BEFORE the plan is printed, so a later
# turn cannot take the same transition twice.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

handoff_root_read "${1:-}"
root="$HANDOFF_ROOT"
# Nothing can be taken without the root; the plan carries the message alone, as
# for a malformed file, so the mod toasts it instead of the turn ending silent.
if [[ "$HANDOFF_ROOT_BRANCH" == "unresolved" ]]; then
    jq -nc --arg m "$HANDOFF_UNRESOLVED_MSG" \
        '{kind: null, before: [], after: [], failFile: "",
          message: ("handoff: " + $m + "; no transition taken.")}'
    exit 0
fi
session_id="${2:-}"
[[ -n "$root" ]] || exit 0

drive="$root/$HANDOFF_REL_DRIVE"
fail_file="$root/$HANDOFF_REL_DRIVE_FAILED"

# A link, dangling or not, reaches the reader, which refuses it.
[[ -L "$drive" || -f "$drive" ]] || exit 0

read_rc=0
handoff_drive_read "$drive" || read_rc=$?
if (( read_rc == 2 )); then
    # The reader could not run: the file may be a valid transition, so it is
    # left where it is and the plan carries the message alone, as for an
    # unresolved root. A later turn end, with a working reader, takes it.
    jq -nc --arg e "$DRIVE_ERR" \
        '{kind: null, before: [], after: [], failFile: "",
          message: ("handoff: autodrive not read — " + $e + "; left in place, nothing taken.")}'
    exit 0
fi
if (( read_rc != 0 )); then
    # A file no writer of this version composed: consume it so the complaint
    # does not repeat at every turn.
    rm -f "$drive"
    jq -nc --arg e "$DRIVE_ERR" --arg f "$fail_file" \
        '{kind: null, before: [], after: [], failFile: $f,
          message: ("handoff: autodrive malformed — " + $e + "; discarded, transition not armed.")}'
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
    jq -nc --arg f "$fail_file" \
        '{kind: null, before: [], after: [], failFile: $f,
          message: "handoff: the turn ended with no session id, so the armed transition was not taken; the next prompt reports it."}'
    exit 0
fi
[[ "$DRIVE_OWNER" == "$session_id" ]] || exit 0

# `rename` has no confirming SessionStart, so a pending file would never clear.
if handoff_drive_has_source "$DRIVE_KIND"; then
    handoff_drive_arm "$drive" pending
else
    rm -f "$drive"
fi

before=( ${DRIVE_BEFORE[@]+"${DRIVE_BEFORE[@]}"} )
after=( ${DRIVE_AFTER[@]+"${DRIVE_AFTER[@]}"} )

# FR-G: nothing to run. The pending state alone is the loader's signal that the
# frame belongs in this compaction.
if (( ${#before[@]} == 0 )); then
    jq -nc --arg k "$DRIVE_KIND" --arg f "$fail_file" \
        '{kind: $k, before: [], after: [], failFile: $f,
          message: ("handoff: prepared for " + $k + "; nothing to run, frame will be re-injected.")}'
    exit 0
fi

# jq reads the lines NUL-delimited: a line is free text and may hold anything
# but a NUL.
to_json() { printf '%s\0' "$@" | jq -Rsc 'split("\u0000")[:-1]'; }
before_json="$(to_json "${before[@]}")"
after_json="[]"
if (( ${#after[@]} > 0 )); then
    after_json="$(to_json "${after[@]}")"
fi

jq -nc --arg k "$DRIVE_KIND" --arg f "$fail_file" --arg l "${before[0]}" \
    --argjson b "$before_json" --argjson a "$after_json" \
    '{kind: $k, before: $b, after: $a, failFile: $f,
      message: ("handoff: will run " + $l + " once the turn ends.")}'
