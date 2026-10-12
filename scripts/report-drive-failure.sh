#!/usr/bin/env bash
# UserPromptSubmit: reconcile the armed-transition state at the start of a turn,
# and report anything that went wrong in the last one.
#
# 1. The drive mod's non-delivery. A rejected command or prompt in
#    hooks/handoff.ts has no one to tell: the turn it ran after is over. Left
#    alone, a line that never runs is silent, and the agent carries on believing
#    it armed a transition. The mod writes its reason to .claude/autodrive.failed;
#    this reads it at the first moment anything can act on it. It is written
#    only on a rejection the mod observed itself — never inferred from a file
#    still in state `pending`, which is legitimate for the whole turn-end ->
#    transition window.
#
# 2. An autodrive that outlived its turn. The file is armed by the mod's
#    drive-take.sh at the turn end that follows the write, which leaves it
#    `pending` or removes it, so one still in state `armed` when a later turn
#    begins never ran. Two causes: that turn ended abnormally (Esc — Stop does
#    not fire on an interrupt — or a crash, or a quit), or the drive mod did not
#    load at all (--safe-mode, or a Claude Code older than 2.1.287). Left on disk
#    it would be taken by a later turn end, days later and possibly in an
#    unrelated session, driving a stale transition into work it was never
#    written for. UserPromptSubmit is the exact discriminator: it cannot fire
#    between the write and that turn's own end. For an armed file the report
#    also prints the lines it held, one per line, for the user to type in order.
#    (Prose injected into a still-running turn is the one exception, and it
#    fails safe — the transition is cancelled and said so, not deferred.)
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
{ IFS= read -r -d '' hook_cwd; IFS= read -r -d '' session_id; } < <(
    jq -j '(.cwd // ""), "\u0000", (.session_id // ""), "\u0000"'
) || true
handoff_root_read "$hook_cwd"
cwd="$HANDOFF_ROOT"
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
case "$HANDOFF_ROOT_BRANCH" in
    foreign | unrelated)
        last=""
        if [[ -f "$marker" ]]; then
            last="$(head -n1 "$marker")"
        fi
        if [[ "$last" != "$hook_cwd" ]]; then
            mkdir -p "$HANDOFF_POINTER_DIR"
            printf '%s\n' "$hook_cwd" > "$marker"
            msgs+=("session cwd left the launch repo — now $hook_cwd, handoff root stays $cwd")
            notes+=("The session cwd is $hook_cwd, outside the launch repo $cwd. Everything derived from cwd describes $hook_cwd — the environment block's working directory, the gitStatus block, the project CLAUDE.md. The transcript, the scratchpad, CLAUDE_PROJECT_DIR and every handoff file are under $cwd.")
        fi
        ;;
    *)
        rm -f "$marker"
        ;;
esac

failed="$cwd/$HANDOFF_REL_DRIVE_FAILED"
drive="$cwd/$HANDOFF_REL_DRIVE"

# Parse once: the failure branch and the sweep want different states of the same
# file. A file that will not parse is recorded as its own value — it describes
# no transition anyone can complete, so the sweep takes it.
drive_state=""
drive_owner=""
drive_lines=()   # the lines an armed file held, before then after
if [[ -f "$drive" ]]; then
    if handoff_drive_read "$drive"; then
        drive_state="$DRIVE_STATE"
        drive_owner="$DRIVE_OWNER"
        drive_lines=( ${DRIVE_BEFORE[@]+"${DRIVE_BEFORE[@]}"} ${DRIVE_AFTER[@]+"${DRIVE_AFTER[@]}"} )
    else
        drive_state="malformed"
    fi
fi

# A held file waits on an approval that arrives in the session that composed it.
# Once another session is taking prompts in this repo, that session is gone and
# the answer can never come — so its exemption from the sweep below ends with it.
# Left on disk it stays armable by handoff-approved indefinitely.
if [[ "$drive_state" == "held" && -n "$session_id" && "$drive_owner" != "$session_id" ]]; then
    drive_state="abandoned"
fi

if [[ -f "$failed" ]]; then
    reason="$(head -n1 "$failed")"
    rm -f "$failed"
    # A failure part-way through a sequence strands the transition in `pending`:
    # nothing will consume it (its SessionStart never fires) and drive-take.sh
    # will not take it again from that state. Clear it with the report. Only
    # here — a stale armed file says nothing about one in flight, and sweeping
    # on that evidence would race a live SessionStart(compact|clear).
    if [[ "$drive_state" == "pending" ]]; then
        rm -f "$drive"
    fi
    msgs+=("transition drive did not deliver — $reason")
    notes+=("The handoff transition drive failed to run its line: $reason. The transition or continuation it was driving did not happen, and any lines after it in the sequence were never run.")
fi

# An autodrive is taken at the turn end after the turn that writes it, and that
# take leaves it `pending` or removes it. So one still in state `armed` when a later
# turn begins never ran.
#
# `held` is the exception, and the reason this is a list rather than "anything
# but pending": a held transition is *waiting* on an approval whose answer
# arrives at this very hook, so surviving the turn boundary is what it is for.
# The exemption reaches exactly as far as that reason — a held file owned by
# another session was reclassified above, because the approval it waits on
# cannot arrive and handoff-approved would otherwise arm it into this
# conversation.
armed_lines=""   # the armed lines, for the user to type in order
if [[ -n "$drive_state" && "$drive_state" != "pending" && "$drive_state" != "held" ]]; then
    rm -f "$drive"
    if [[ "$drive_state" == "armed" ]]; then
        msgs+=("stale autodrive discarded — the drive mod did not run it")
        notes+=("A .claude/autodrive file was still armed when this turn began, so the transition it described did not run. Most likely the drive mod did not load (--safe-mode, or a Claude Code older than 2.1.287); an interrupt or crash that ended the turn before it was taken leaves the same trace. The file has been discarded, so it cannot fire into unrelated work later.")
        if (( ${#drive_lines[@]} > 0 )); then
            armed_lines="$(printf '%s\n' "${drive_lines[@]}")"
            notes+=("Present these lines to the user in a fenced code block, to type in order:
$armed_lines")
        fi
    elif [[ "$drive_state" == "abandoned" ]]; then
        msgs+=("stale autodrive discarded — it was held by a session that is gone")
        notes+=("A .claude/autodrive file held by another session was still on disk when this turn began. The approval it waited on can no longer arrive, so it has been discarded and the transition it described did not happen.")
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
