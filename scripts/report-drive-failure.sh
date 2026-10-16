#!/usr/bin/env bash
# UserPromptSubmit: reconcile the armed-transition state at the start of a turn,
# and report anything that went wrong in the last one.
#
# 1. The drive mod's non-delivery. A rejected command or prompt in
#    the mod has no one to tell: the turn it ran after is over. Left
#    alone, a line that never runs is silent, and the agent carries on believing
#    it armed a transition. The mod writes its reason to .claude/autodrive.failed;
#    this reads it at the first moment anything can act on it. It is written
#    only on a rejection the mod observed itself — never inferred from a file
#    still in state `pending`, which is legitimate for the whole turn-end ->
#    transition window.
#
# 2. An autodrive that outlived its turn. The file is armed by the mod's
#    drive-take.sh at the turn end that follows the write, which leaves it
#    `pending` or removes it, so one still in state `armed` when a prompt
#    arrives has not run. Three causes: that turn ended abnormally (Esc — Stop
#    does not fire on an interrupt — or a crash, or a quit); the drive mod did
#    not load at all (--safe-mode, a Claude Code older than 2.1.287, or an
#    organization-managed one that does not list the plugin in managed
#    settings); or the prompt was typed while the arming turn still ran, which
#    fires this hook inside that turn, before its Stop. Left on disk a stale file
#    would be taken by a later turn end, days later and possibly in an unrelated
#    session, driving a stale transition into work it was never written for.
#    The prompt_id tells the third cause apart: a prompt typed at an idle
#    composer, an Esc included, carries a fresh one, while a queued prompt
#    carries the arming turn's own (handoff-checkpoint and handoff-approved
#    record it in a per-session prompt marker through
#    inject-checkpoint-root.sh). So an owner's armed file whose prompt
#    marker matches this input's prompt_id is a queued case, not a stale one: a
#    rename is left for the drive to take at that turn's end, and a clear or
#    compact is swept and said so, with no lines offered, since the transition
#    and its continuation were composed before the prompt arrived. Another
#    session's prompt can fire this hook too — every session sharing the root
#    runs it, the background session the harness starts after a `git commit`
#    included — so the file names its owner, and one owned by another session
#    is swept only when that session is no longer live (its transcript has gone
#    quiet); a `held` one, waiting on its owner's user, never. For
#    an armed file the report also prints the lines it held, one per line, for
#    the user to type in order, unless the file was queued.
#
# 3. A session cwd that left the launch repo. Everything derived from cwd —
#    the environment block's working directory, gitStatus, the project
#    CLAUDE.md — follows it; the transcript, the scratchpad,
#    CLAUDE_PROJECT_DIR and every handoff file do not. Nothing announces the
#    split, and it is silent in both directions: the agent reasons about the
#    repo under cwd while the plugin reads and writes the one under the root.
#
# UserPromptSubmit: the mod drives *after* the turn that armed it, so the first
# moment anything can act on a failure is the next prompt. It fires on every
# prompt, so the no-file path must be silent and cheap.
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
# rather than a repeat.
marker="$HANDOFF_POINTER_DIR/handoff-drift-$session_id"

# The drift marker: the destination last announced. marker_dir_ok, and the
# no-follow read and the replacing write, are the shared helpers in _lib.sh; a
# directory that fails marker_dir_ok has no marker, and drift is reported every
# turn instead of once.

case "$HANDOFF_ROOT_BRANCH" in
    foreign | unrelated)
        # NUL-terminated and read whole: a cwd holding a newline compared by
        # its first line would never match, and re-announce every turn.
        last="" marker_status=""
        # -m on the deepest directory only, by intent: it is the one the
        # marker lives in, and its parents are not this hook's to set.
        # shellcheck disable=SC2174
        mkdir -m 700 -p "$HANDOFF_POINTER_DIR" 2>/dev/null || true
        if marker_dir_ok; then
            { IFS= read -r marker_status || true
              if [[ "$marker_status" == ok ]]; then
                  IFS= read -r -d '' last || true
              fi
            } < <(handoff_read_regular "$marker" own)
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
if [[ -L "$drive" || -f "$drive" ]]; then
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

# `armed` and `held` both name their owner, and every session sharing this root
# runs this hook — the background session the harness starts after a `git
# commit` included — so another session's prompt says nothing about whether
# the owner is gone.
#
# Another session's `armed` file lives only until its owner's turn ends. One
# whose owner is still live (its transcript written within
# HANDOFF_OWNER_LIVE_SECS, handoff_owner_live) is left untouched and nothing
# is said; one whose owner is not live is swept as a stale autodrive.
#
# A `held` file, whoever owns it, is not judged by liveness at all and stays in
# its state, which the sweep below exempts: it waits on a human approval,
# which takes as long as it takes, and an idle transcript is exactly what a
# session waiting on its user looks like. A dead owner's held file stays on
# disk: it is a few short lines, arms nothing by itself (only its owner's
# handoff-approved releases it) and the next checkpoint in this root replaces
# it.
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

# A prompt queued into the arming turn (the header's point 2) carries that
# turn's prompt_id, which handoff-checkpoint or handoff-approved recorded in the
# session's prompt marker. Only an armed file this session owns is judged, so no other state
# reads the marker and an ordinary prompt forks nothing here. Nothing is written.
queued=0
prompt_marker="$HANDOFF_POINTER_DIR/handoff-prompt-$session_id"
if [[ "$drive_state" == "armed" && "$drive_owner" == "$session_id" \
      && -n "$session_id" && -n "$prompt_id" ]] && marker_dir_ok; then
    prompt_status="" marked_id=""
    { IFS= read -r prompt_status || true
      if [[ "$prompt_status" == ok ]]; then
          IFS= read -r -d '' marked_id || true
      fi
    } < <(handoff_read_regular "$prompt_marker" own)
    if [[ "$prompt_status" == ok && "$marked_id" == "$prompt_id" ]]; then
        queued=1
    fi
fi

# An autodrive is taken at the turn end after the turn that writes it, and that
# take leaves it `pending` or removes it. So one still in state `armed` when a
# prompt arrives has not run, and unless that prompt was queued it never will.
#
# `held` is the exception, and the reason this is a list rather than "anything
# but pending": a held transition is *waiting* on an approval whose answer
# arrives at this very hook, so surviving the turn boundary is what it is for.
# That holds for any owner's held file. Another session's armed file while it
# is live was reclassified above as `foreign` and is not this session's to take.
armed_lines=""   # the armed lines, for the user to type in order
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
      && "$drive_state" != "foreign" && "$drive_state" != "unread" ]]; then
    record_sweep
    rm -f "$drive"
    if [[ "$drive_state" == "armed" ]]; then
        # With no prompt_id the input cannot rule out a prompt typed while the
        # arming turn ran, so the note names it as a possible cause.
        queued_cause=""
        if [[ -z "$prompt_id" ]]; then
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
