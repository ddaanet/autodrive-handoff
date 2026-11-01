#!/usr/bin/env bash
# UserPromptSubmit: reconcile the armed-transition state at the start of a turn,
# and report anything that went wrong in the last one. Three jobs:
#
# 1. Report the drive mod's non-delivery, read from .claude/autodrive.failed
#    (docs/design/driving-the-transition.md, "Reporting a failure, sweeping a
#    stale sentinel").
# 2. Sweep an autodrive still `armed` that outlived its turn (the same section,
#    docs/design/queued-prompts.md, docs/design/sessions-sharing-a-root.md).
# 3. Report a session cwd that left the launch repo (docs/design/scoping.md).
#
# It fires on every prompt, so the no-file path must be silent and cheap.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# NUL-terminated and read whole, as in write-guard.sh: a cwd holding a newline
# or ending in a space would otherwise be cut or trimmed.
{ IFS= read -r -d '' hook_cwd; IFS= read -r -d '' session_id; IFS= read -r -d '' transcript_path; IFS= read -r -d '' prompt_id; } < <(
    jq -j '(.cwd // ""), "\u0000", (.session_id // ""), "\u0000", (.transcript_path // ""), "\u0000", (.prompt_id // ""), "\u0000"'
) || true
handoff_root_read "$hook_cwd"
cwd="$HANDOFF_ROOT"
# Without the root none of the three checks can run; that is the report.
if [[ "$HANDOFF_ROOT_BRANCH" == "unresolved" ]]; then
    jq -nc --arg m "$HANDOFF_UNRESOLVED_MSG" --arg lead $'\033[0m' '{
        systemMessage: ($lead + "handoff: " + $m + "; drift, failure and sweep checks skipped."),
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: ("The autodrive-handoff plugin could not resolve this session'"'"'s root: " + $m + ". It skipped its drift, drive-failure and stale-transition checks for this turn.")
        }
    }'
    exit 0
fi
[[ -n "$cwd" ]] || exit 0

msgs=()
notes=()

# Drift is reported here rather than at some later gate because it can be
# transient: a check that asks "is cwd foreign now?" after the fact sees
# nothing, while the writer/reader split was live for the whole blip. This hook
# already resolves the root every turn and already owns a reporting channel.
#
# Once per episode: the marker holds the destination last announced, so a
# second turn in the same place is silent and a move somewhere else is not
# swallowed. It is cleared on the way back in, so a re-drift is a new episode
# rather than a repeat. A marker directory that fails marker_dir_ok has no
# marker, and drift is reported every turn instead of once.
marker="$HANDOFF_POINTER_DIR/handoff-drift-$session_id"

case "$HANDOFF_ROOT_BRANCH" in
    foreign | unrelated)
        # NUL-terminated and read whole: a cwd holding a newline compared by
        # its first line would never match, and re-announce every turn.
        last=""
        # -m on the deepest directory only, by intent: it is the one the
        # marker lives in, and its parents are not this hook's to set.
        # shellcheck disable=SC2174
        mkdir -m 700 -p "$HANDOFF_POINTER_DIR" 2>/dev/null || true
        handoff_read_marker "$marker"
        if [[ "$MARKER_STATUS" == ok ]]; then
            last="$MARKER_VALUE"
        fi
        if [[ "$last" != "$hook_cwd" ]]; then
            if marker_dir_ok; then
                handoff_write_marker "$marker" "$hook_cwd" || true
            fi
            # Both paths enter harness text the agent reads, so each is shown
            # as quoted data: `%q` puts a newline, an escape byte or any other
            # control character in $'…' form and escapes a backtick, so a
            # directory name cannot start a line, restyle the terminal or close
            # a code span. A plain path prints unchanged.
            printf -v shown_cwd '%q' "$hook_cwd"
            printf -v shown_root '%q' "$cwd"
            msgs+=("session cwd left the launch repo — now $shown_cwd, handoff root stays $shown_root")
            notes+=("The session cwd is $shown_cwd, outside the launch repo $shown_root. Everything derived from cwd describes $shown_cwd — the environment block's working directory, the gitStatus block, the project CLAUDE.md. The transcript, the scratchpad, CLAUDE_PROJECT_DIR and every handoff file are under $shown_root.")
        fi
        ;;
    *)
        # The common case on every prompt: no marker, so nothing to clear and
        # no `find` to fork. `-L` too, so a dangling link at the name still
        # reaches the directory check and is removed (rm unlinks a link and
        # never what it names).
        if [[ -e "$marker" || -L "$marker" ]] && marker_dir_ok; then
            rm -f "$marker"
        fi
        ;;
esac

failed="$cwd/$HANDOFF_REL_DRIVE_FAILED"
drive="$cwd/$HANDOFF_REL_DRIVE"
swept="$cwd/$HANDOFF_REL_DRIVE_SWEPT"

# Append one line to the sweep record before the sentinel goes: the removing
# session, the state and owner it saw, the kind, the sentinel's age in seconds
# and the hook's cwd. Tab-separated; the cwd is %q-quoted so one holding a
# newline stays on its line. Keeps the last 50 lines. A failure to write is not
# the sweep's failure, so every step is guarded: this runs under `set -e`.
#
# .claude/ is a directory the agent writes freely, so the record may be a
# symlink: reading through one would copy what it names into the record. A
# record that is a symlink, or anything but a regular file, is left alone and
# nothing is recorded; the test and the read are one O_NOFOLLOW open
# (handoff_read_regular), so a link put there after a look at the name is
# never read. The new record is built in a temporary file mktemp creates beside
# it (never a fixed name, which could be a planted link to write through) under
# the `autodrive.` prefix the `.claude/autodrive*` ignore covers, and renamed
# over the record by rename(2) (handoff_replace), which replaces a link put at
# the name meanwhile where `mv` would move the file into a directory it names.
record_sweep() {
    local mtime now age tmp_record record_status=""
    tmp_record="$(mktemp "$swept.XXXXXX" 2>/dev/null)" || return 0
    {
        IFS= read -r record_status || true
        case "$record_status" in
            ok | absent) ;;
            *) rm -f "$tmp_record"; return 0 ;;
        esac
        now="$(date +%s)"
        mtime="$(stat -c %Y "$drive" 2>/dev/null || stat -f %m "$drive" 2>/dev/null || true)"
        age="?"
        if [[ "$mtime" =~ ^[0-9]+$ ]]; then
            age=$(( now - mtime ))
        fi
        {
            printf '%s\tsweeper=%s\tstate=%s\towner=%s\tkind=%s\tage=%ss\tcwd=%q\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${session_id:-?}" "$drive_state" \
                "${drive_owner:--}" "${drive_kind:--}" "$age" "$hook_cwd"
            # The old record is the rest of this stream.
            if [[ "$record_status" == ok ]]; then
                cat
            fi
        } 2>/dev/null | head -n 50 > "$tmp_record" 2>/dev/null || true
    } < <(handoff_read_regular "$swept")
    handoff_replace "$tmp_record" "$swept" 2>/dev/null || rm -f "$tmp_record" || true
}

# Parse once: the failure branch and the sweep want different states of the same
# file. A file that will not parse is recorded as its own value — it describes
# no transition anyone can complete, so the sweep takes it. So is a link at the
# sentinel, dangling or not, which the reader refuses unread: it is recorded as
# `link`, so the report names it and offers no line of whatever it points at.
# A reader that could not run at all is `unread`: no evidence either way, so
# the file is reported and left for a later turn.
drive_state=""
drive_owner=""
drive_kind=""
drive_lines=()   # the lines an armed file held, before then after
drive_err=""
# Held from the read to the exit, so the sweep's decision and every removal it
# makes, record_sweep and the failure branch's removal of a stranded `pending`
# included, are one step. A lock that cannot be taken fails closed: the file is
# neither read nor judged and the state is `locked`, as `unread` is for a reader
# that could not run (docs/design/sentinel-lock.md). Taken only for a file that
# is there, so the ordinary prompt forks nothing; the second test is for one
# removed while this waited.
lock_rc=0
if [[ -L "$drive" || -f "$drive" ]]; then
    handoff_lock_take "$cwd/$HANDOFF_REL_DRIVE_LOCK" || lock_rc=$?
fi
if (( lock_rc != 0 )); then
    drive_state="locked"
    drive_err="$HANDOFF_LOCK_MSG"
elif [[ -L "$drive" || -f "$drive" ]]; then
    read_rc=0
    handoff_drive_read "$drive" || read_rc=$?
    if (( read_rc == 0 )); then
        drive_state="$DRIVE_STATE"
        drive_owner="$DRIVE_OWNER"
        drive_kind="$DRIVE_KIND"
        drive_lines=( ${DRIVE_BEFORE[@]+"${DRIVE_BEFORE[@]}"} ${DRIVE_AFTER[@]+"${DRIVE_AFTER[@]}"} )
    elif (( read_rc == 2 )); then
        # The reader could not run: no evidence about the file, which may be
        # a live transition. Reported and never swept.
        drive_state="unread"
        drive_err="$DRIVE_ERR"
    elif [[ -L "$drive" ]]; then
        drive_state="link"
    else
        drive_state="malformed"
    fi
fi

# Another session's `armed` file whose owner is live is reclassified `foreign`:
# left untouched, nothing said. Only `armed` is asked about liveness; a `held`
# file, whoever owns it, is never judged by it (docs/design/sessions-sharing-a-root.md).
if [[ "$drive_state" == "armed" && -n "$session_id" && "$drive_owner" != "$session_id" ]] \
    && handoff_owner_live "$transcript_path" "$drive_owner"; then
    drive_state="foreign"
fi

# The mod writes the record only on a rejection it observed, and never a link:
# a link there, dangling or not, is no evidence of one, and following it would
# quote another file's first line onto both channels. It is removed unread and
# said so, and a pending transition is not cleared on its account.
#
# The look and the read are one O_NOFOLLOW open (handoff_read_regular): a link
# put at the name at any moment is reported, never read. The `-e`/`-L` test
# before it only keeps the no-file path free of a python3 spawn.
failed_status="" reason=""
if [[ -L "$failed" || -e "$failed" ]]; then
    { IFS= read -r failed_status || true
      if [[ "$failed_status" == ok ]]; then
          IFS= read -r reason || true
      fi
    } < <(handoff_read_regular "$failed")
fi
if [[ "$failed_status" == link ]]; then
    rm -f "$failed"
    msgs+=("a symbolic link at $HANDOFF_REL_DRIVE_FAILED was removed unread")
    notes+=("A symbolic link sat where the handoff drive mod records a rejected line ($HANDOFF_REL_DRIVE_FAILED). The mod never writes one, so it was removed without reading what it points at; it says nothing about whether a transition ran.")
elif [[ "$failed_status" == ok && "$drive_state" == "locked" ]]; then
    # Its report and the clearing of a stranded `pending` go together, and the
    # sentinel was not judged: the record stays for the next prompt.
    :
elif [[ "$failed_status" == ok ]]; then
    rm -f "$failed"
    # A failure part-way through a sequence strands the transition in `pending`:
    # nothing will consume it (its SessionStart never fires) and drive-take.sh
    # will not take it again from that state. Clear it with the report. Only
    # here — a stale armed file says nothing about one in flight, and sweeping
    # on that evidence would race a live SessionStart(compact|clear).
    if [[ "$drive_state" == "pending" ]]; then
        record_sweep
        rm -f "$drive"
    fi
    msgs+=("transition drive did not deliver — $reason")
    notes+=("The handoff transition drive failed to run its line: $reason. The transition or continuation it was driving did not happen, and any lines after it in the sequence were never run.")
fi

# Only an armed file this session owns is judged against the prompt marker, so no
# other state reads it and an ordinary prompt forks nothing here; nothing is
# written. `marker_unsettled` is set when the input has an id and the marker
# could not answer (docs/design/queued-prompts.md).
queued=0
marker_unsettled=0
prompt_marker="$HANDOFF_POINTER_DIR/handoff-prompt-$session_id"
if [[ "$drive_state" == "armed" && "$drive_owner" == "$session_id" \
      && -n "$session_id" && -n "$prompt_id" ]]; then
    handoff_read_marker "$prompt_marker"
    if [[ "$MARKER_STATUS" == ok && "$MARKER_VALUE" == "$prompt_id" ]]; then
        queued=1
    elif [[ "$MARKER_STATUS" != ok && "$MARKER_STATUS" != absent ]]; then
        marker_unsettled=1
    fi
fi

# The sweep names the states it removes rather than taking anything that is not
# `pending`: `held` is exempt whoever owns it, and another session's live `armed`
# file is `foreign`, not this session's to take (docs/design/driving-the-transition.md,
# docs/design/sessions-sharing-a-root.md).
armed_lines=""   # the armed lines, for the user to type in order
if [[ "$drive_state" == "locked" ]]; then
    msgs+=("autodrive not judged — $drive_err; left in place")
    notes+=("The autodrive-handoff plugin could not take the lock on .claude/autodrive ($drive_err), so it was left in place and not judged: a transition it holds may still run, and the next prompt judges what is there.")
fi
if [[ "$drive_state" == "unread" ]]; then
    msgs+=("autodrive not read — $drive_err; left in place")
    notes+=("The autodrive-handoff plugin could not read .claude/autodrive ($drive_err). The file was left in place and not judged; a transition it holds may still run or be swept on a later turn.")
fi
if [[ "$queued" == 1 && "$drive_kind" == "rename" ]]; then
    : # left in place: the drive takes it at the end of the turn the prompt is in
elif [[ "$queued" == 1 ]]; then
    record_sweep
    rm -f "$drive"
    msgs+=("transition cancelled — a prompt arrived before it ran")
    case "$drive_kind" in
        clear)
            notes+=("The driven /clear did not run. Answer this prompt, then run the handoff skill again with the same transition, unless this prompt changes that.") ;;
        compact)
            notes+=("The driven /compact did not run. Answer this prompt, then run the precompact skill again with the same transition, unless this prompt changes that.") ;;
    esac
elif [[ -n "$drive_state" && "$drive_state" != "pending" && "$drive_state" != "held" \
      && "$drive_state" != "foreign" && "$drive_state" != "unread" \
      && "$drive_state" != "locked" ]]; then
    record_sweep
    rm -f "$drive"
    if [[ "$drive_state" == "armed" ]]; then
        # With no prompt_id, or one the marker could not settle, the input
        # cannot rule out a prompt typed while the arming turn ran, so the note
        # names it as a possible cause.
        queued_cause=""
        if [[ -z "$prompt_id" || "$marker_unsettled" == 1 ]]; then
            queued_cause=", as does a prompt typed while that turn was still running"
        fi
        msgs+=("stale autodrive discarded — the drive mod did not run it")
        notes+=("A .claude/autodrive file was still armed when this turn began, so the transition it described did not run. Most likely the drive mod did not load (--safe-mode, a Claude Code older than 2.1.287, or an organization-managed Claude Code that does not list the plugin in managed settings); an interrupt or crash that ended the turn before it was taken leaves the same trace$queued_cause. The file has been discarded, so it cannot fire into unrelated work later.")
        # The lines are offered only to the session that wrote them. Another
        # session's, swept because its owner is not live, would be replayed into
        # this conversation.
        if (( ${#drive_lines[@]} > 0 )) && [[ "$drive_owner" == "$session_id" ]]; then
            armed_lines="$(printf '%s\n' "${drive_lines[@]}")"
            notes+=("Present these lines to the user in a fenced code block, to type in order:
$armed_lines")
        fi
    elif [[ "$drive_state" == "link" ]]; then
        msgs+=("autodrive discarded — it was a symbolic link, which no checkpoint writes")
        notes+=("A .claude/autodrive symbolic link was on disk when this turn began. No checkpoint writes one, so it was removed without reading what it points at, and no transition ran from it.")
    else
        msgs+=("stale autodrive discarded — it does not parse in this version's format")
        notes+=("A .claude/autodrive file was still on disk when this turn began and does not parse in this version's format. It has been discarded, so the transition it described did not happen and cannot fire into unrelated work later.")
    fi
fi

(( ${#msgs[@]} > 0 )) || exit 0

printf -v msg '%s; ' "${msgs[@]}"
printf -v note '%s ' "${notes[@]}"

# Lead with a style reset. This hook speaks only when something went wrong, and
# the ordinary hook chatter it sits among is rendered dimmed.
jq -nc --arg m "${msg%; }" --arg n "${note% }" --arg p "$armed_lines" --arg lead $'\033[0m' '{
    systemMessage: ($lead + "handoff: " + $m + "." + (if $p == "" then "" else "\nType in order:\n" + $p end)),
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $n
    }
}'
