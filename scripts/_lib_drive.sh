#!/usr/bin/env bash
# The sentinel grammar: parse, validate and rewrite .claude/autodrive.
# Part of _lib.sh. Source-only; no shebang
# execution. Reached through _lib.sh, which sources it after its own
# definitions, so callers source _lib.sh and never this file:
#   # shellcheck source-path=SCRIPTDIR source=_lib.sh
#   source "$(dirname "$0")/_lib.sh"

# Shape helpers for handoff_drive_read. Each sets DRIVE_ERR and returns 1.

# <found> <accepted...>. More than one count is legal on the driven kinds: the
# continuation line is optional on both, and the command line is optional on
# `compact` (its kind line alone is the prepare-only marker).
_handoff_drive_expect() {
    local found="$1" want list; shift
    for want in "$@"; do
        [ "$found" -eq "$want" ] && return 0
    done
    if [ "$#" -eq 1 ]; then
        list="exactly $1 lines"
    else
        list="$1"; shift
        while [ "$#" -gt 1 ]; do list="$list, $1"; shift; done
        list="$list or $1 lines"
    fi
    DRIVE_ERR="kind \`$DRIVE_KIND\` takes $list (found $found)"
    return 1
}

# <line> <lineno> <literal> <arg|optional|none>. The kind fixes which command
# belongs in which slot, so the file cannot be made to type something else.
_handoff_drive_command() {
    local line="$1" no="$2" cmd="$3" mode="$4"
    case "$mode" in
        none)
            [ "$line" = "$cmd" ] && return 0
            DRIVE_ERR="line $no must be exactly \`$cmd\`" ;;
        optional)
            case "$line" in "$cmd"|"$cmd "*) return 0 ;; esac
            DRIVE_ERR="line $no must be \`$cmd\` or \`$cmd <argument>\`" ;;
        arg)
            case "$line" in "$cmd "*)
                if [ -n "$(printf '%s' "${line#"$cmd" }" | tr -d '[:space:]')" ]; then
                    return 0
                fi ;;
            esac
            DRIVE_ERR="line $no must be \`$cmd <argument>\`, with a non-empty argument" ;;
    esac
    return 1
}

# <line> <lineno>. Prose is submitted with a bare Enter, so a line that looks
# like a command would take the recognition path instead and be confirmed by
# the wrong primitive.
_handoff_drive_prose() {
    local line="$1" no="$2"
    if [ -z "$(printf '%s' "$line" | tr -d '[:space:]')" ]; then
        DRIVE_ERR="line $no is the continuation prompt, and must not be empty"
        return 1
    fi
    case "$line" in /*)
        DRIVE_ERR="line $no is the continuation prompt, and must not begin with \`/\`"
        return 1 ;;
    esac
    return 0
}

# Parse and validate the sentinel ($1) into the caller's DRIVE_STATE,
# DRIVE_OWNER, DRIVE_KIND, DRIVE_BEFORE (lines the mod runs before the transition) and
# DRIVE_AFTER (lines it runs in the session the transition opens). Returns 0 when
# well-formed; otherwise returns 1 with DRIVE_ERR set to a one-phrase reason
# naming the constraint that failed. A symlink at $1 is refused, unread.
# Returns 2, DRIVE_ERR set, when the reader could not run at all
# (handoff_read_regular printed nothing): the file is neither valid nor
# malformed as far as anyone knows, so a caller keeps it and reports that.
#
# Line 1 is the state and line 2 is the kind, and the kind fixes the shape — so
# the remaining lines need no separator, and each kind keeps its own rules:
#
#   held <session-id>
#            written, but not yet the turn's to arm: a memory approval or,
#            ahead of a driven transition, the turn's commit is outstanding,
#            and handoff-approved is what releases it. The session
#            id is the one whose approval it waits on
#   armed <session-id>
#            the transition drive-take.sh takes after the owner's turn ends.
#            The session id is the one that wrote it (or approved it out of
#            `held`): every session sharing the root runs the UserPromptSubmit
#            sweep, and only the owner tells another session's prompt from
#            the owner's own next one
#   pending  armed, in flight, waiting on its confirming SessionStart; no
#            owner, since the session that consumes it is whichever one the
#            transition opened
#
#   rename   /rename <title>
#   compact  /compact [directive]         [+ continuation prose]
#   compact  (kind line alone: a transition is expected, nothing runs)
#   clear    /rename <title>, /clear      [+ continuation prose]
#
# The continuation is optional on both driven kinds: running the transition and
# submitting a prompt into what it opens are separate decisions, and the payload
# the checkpoint composes this file from carries them as separate fields.
#
# The state is reported, never interpreted: which state a caller wants is the
# caller's business, and the parser serves drive-take.sh, both loaders and the
# UserPromptSubmit sweep with one answer.
#
# The lines are literal: the mod runs a `/x args` line as that command and the
# rest as a prompt, and must not know which command any
# kind uses. Every prose line is a single line because in the TUI one Enter is
# one submit — an embedded newline would submit it early. Read with a `read`
# loop rather than mapfile: bash 3.2 (macOS system bash) has no mapfile, and for
# the same reason callers must expand the arrays as
# `${DRIVE_BEFORE[@]+"${DRIVE_BEFORE[@]}"}` — an empty array is an unbound
# variable under `set -u` before bash 4.4.
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_drive_read() {
    local file="$1" line n
    local -a lines=()
    DRIVE_STATE=""; DRIVE_OWNER=""; DRIVE_KIND=""
    DRIVE_BEFORE=(); DRIVE_AFTER=(); DRIVE_ERR=""

    # A link at the sentinel is refused before a byte is read, dangling or not.
    # No writer makes one — the checkpoint and handoff_drive_arm rename a file
    # into place, which replaces a link rather than writing through it — and a
    # repository can commit one to anything readable: followed, its target
    # would be parsed, its first line quoted into a report, and a rewrite would
    # land on it. The test and the read are one O_NOFOLLOW open
    # (handoff_read_regular), so a link put at the name after a caller looked
    # at it is refused too. Every caller takes its malformed path, whose
    # `rm -f` removes the link and not what it names. The bound is the last
    # component: a symlinked `.claude/` is read and written where it points,
    # as the root and legacy files are, and one shared between roots is
    # unsupported (docs/design/sessions-sharing-a-root.md).
    local read_status=""
    {
        IFS= read -r read_status || true
        if [[ "$read_status" == ok ]]; then
            while IFS= read -r line || [ -n "$line" ]; do
                lines+=("$line")
            done
        fi
    } < <(handoff_read_regular "$file")
    case "$read_status" in
        ok) ;;
        link)
            DRIVE_ERR="the file is a symbolic link, which no checkpoint writes"
            return 1 ;;
        absent)
            DRIVE_ERR="the file does not exist"
            return 1 ;;
        other | foreign)
            DRIVE_ERR="the file is not a regular file that can be read"
            return 1 ;;
        *)
            # Nothing printed: the helper itself failed (python3 missing or
            # broken), which says nothing about the file. Its own status, so
            # no caller removes a sentinel that may be perfectly valid.
            DRIVE_ERR="the python3 helper that reads it failed, so its state is unknown"
            return 2 ;;
    esac

    n=${#lines[@]}
    if [ "$n" -eq 0 ]; then
        DRIVE_ERR="the file is empty; line 1 must be the transition state"
        return 1
    fi
    DRIVE_STATE="${lines[0]%% *}"
    case "${lines[0]}" in
        *' '*) DRIVE_OWNER="${lines[0]#* }" ;;
    esac
    case "$DRIVE_STATE" in
        held | armed)
            # Both outlive the turn that wrote them in some session's eyes:
            # `held` waits on an approval that arrives in its owner's later
            # turn, and `armed` sits on disk until its owner's turn ends while
            # other sessions sharing the root take prompts. So each says whose
            # it is, and the sweep and handoff-approved compare against it.
            if [ -z "$DRIVE_OWNER" ]; then
                DRIVE_ERR="line 1 state \`$DRIVE_STATE\` must name the session that owns it"
                return 1
            fi
            case "$DRIVE_OWNER" in *' '*)
                DRIVE_ERR="line 1 state \`$DRIVE_STATE\` takes one session id, not \`$DRIVE_OWNER\`"
                return 1 ;;
            esac
            ;;
        pending)
            if [ -n "$DRIVE_OWNER" ]; then
                DRIVE_ERR="line 1 state \`$DRIVE_STATE\` takes no session id (got \`$DRIVE_OWNER\`)"
                return 1
            fi
            ;;
        *)
            DRIVE_STATE="${lines[0]}"
            DRIVE_ERR="line 1 must be the transition state — held, armed or pending — not \`$DRIVE_STATE\`"
            return 1 ;;
    esac

    if [ "$n" -eq 1 ]; then
        DRIVE_ERR="line 2 must be the transition kind — rename, compact, clear"
        return 1
    fi
    DRIVE_KIND="${lines[1]}"

    case "$DRIVE_KIND" in
        rename)
            _handoff_drive_expect "$n" 3 || return 1
            _handoff_drive_command "${lines[2]}" 3 "/rename" arg || return 1
            DRIVE_BEFORE=("${lines[2]}")
            ;;
        compact)
            # The kind line alone is the prepare-only marker: nothing is run,
            # but the transition is expected, so the loader still injects.
            [ "$n" -eq 2 ] && return 0
            _handoff_drive_expect "$n" 2 3 4 || return 1
            _handoff_drive_command "${lines[2]}" 3 "/compact" optional || return 1
            DRIVE_BEFORE=("${lines[2]}")
            if [ "$n" -eq 4 ]; then
                _handoff_drive_prose "${lines[3]}" 4 || return 1
                DRIVE_AFTER=("${lines[3]}")
            fi
            ;;
        clear)
            _handoff_drive_expect "$n" 4 5 || return 1
            _handoff_drive_command "${lines[2]}" 3 "/rename" arg || return 1
            _handoff_drive_command "${lines[3]}" 4 "/clear" none || return 1
            DRIVE_BEFORE=("${lines[2]}" "${lines[3]}")
            if [ "$n" -eq 5 ]; then
                _handoff_drive_prose "${lines[4]}" 5 || return 1
                DRIVE_AFTER=("${lines[4]}")
            fi
            ;;
        *)
            DRIVE_ERR="line 2 must be the transition kind — rename, compact, clear — not \`$DRIVE_KIND\`"
            return 1
            ;;
    esac
    return 0
}

# Kinds whose transition is confirmed by a SessionStart. `rename` is not one:
# no loader consumes it, so drive-take.sh deletes its sentinel outright instead
# of leaving it pending for nobody to clear.
handoff_drive_has_source() {
    case "$1" in
        compact|clear) return 0 ;;
        *) return 1 ;;
    esac
}

# Rewrite the sentinel ($1) with $2 as its line 1 — the state, and the owner
# when the state takes one — preserving every line below the first. Line 1 is
# the only line any transition changes, so one helper serves them all and none
# of them has to know the kind's shape.
#
# Line 1 is replaced whole, so the owner is the caller's to carry or drop:
# handoff-approved passes `armed <owner>` on, since the session that approved is
# the one whose turn end takes it, and drive-take.sh writes a bare `pending`,
# since past the take the transition is the confirming SessionStart's, in
# whichever session it opened.
#
# Atomic: a sibling temp file renamed over the original. Concurrent readers
# exist — both loaders, drive-take.sh and the sweep parse this file — so a
# partially written file must never be observable under the real name. The temp
# lands in the same directory because rename(2) is only atomic within one
# filesystem, under the `autodrive.` prefix the `.claude/autodrive*` ignore
# covers, so a temp orphaned by a kill is never committed.
#
# The temp is mktemp's, created exclusively under an unpredictable name: a
# fixed or PID-derived one is a name a repository can commit a link at, and
# the state line would be written through it. The rename is os.replace, not
# `mv`, which stats its destination and would move the temp *into* a directory
# a link put at the sentinel since it was read points at; rename(2) replaces
# the link itself (handoff_replace). The lines below line 1 are still read
# through whatever is at the name when `tail` opens it; the reader refused a
# link a moment before.
handoff_drive_arm() {
    local file="$1" state="$2" tmp
    tmp="$(mktemp "$file.XXXXXX")" || return 1
    if ! printf '%s\n' "$state" > "$tmp" || ! tail -n +2 "$file" >> "$tmp" \
        || ! handoff_replace "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
}

# What a cancelled clear or compact tells the user and the agent: the one source
# for the UserPromptSubmit sweep (a queued prompt) and drive-cancel.sh (a prompt
# after Stop). The message is the fragment the callers wrap as
# `handoff: <msg>.`; the note is the agent's directive for the kind.
# shellcheck disable=SC2034  # read by the sourcing scripts
HANDOFF_CANCEL_MSG='transition cancelled — a prompt arrived before it ran'

handoff_cancel_note() {
    case "$1" in
        clear) printf '%s' "The driven /clear did not run. Answer this prompt, then run the handoff skill again with the same transition, unless this prompt changes that." ;;
        compact) printf '%s' "The driven /compact did not run. Answer this prompt, then run the precompact skill again with the same transition, unless this prompt changes that." ;;
    esac
}

# handoff_record_sweep <record> <sentinel> <sweeper> <state> <owner> <kind> <cwd>
# Append one line to the sweep record before the sentinel goes: the removing
# session, the state and owner it saw, the kind, the sentinel's age in seconds
# and the hook's cwd. Tab-separated; the cwd is %q-quoted so one holding a
# newline stays on its line. Keeps the last 50 lines. A failure to write is not
# the sweep's failure, so every step is guarded: callers run under `set -e`.
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
handoff_record_sweep() {
    local swept="$1" drive="$2" sweeper="$3" state="$4" owner="$5" kind="$6" cwd="$7"
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
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sweeper" "$state" \
                "$owner" "$kind" "$age" "$cwd"
            # The old record is the rest of this stream.
            if [[ "$record_status" == ok ]]; then
                cat
            fi
        } 2>/dev/null | head -n 50 > "$tmp_record" 2>/dev/null || true
    } < <(handoff_read_regular "$swept")
    handoff_replace "$tmp_record" "$swept" 2>/dev/null || rm -f "$tmp_record" || true
}

# handoff_drive_plan <kind> <failFile> <before...>: print the plan of a taken
# transition (drive-take.sh's, and drive-cancel.sh's for a rename) as one line
# of JSON {kind, before, after, failFile, message}, `after` read from
# DRIVE_AFTER. The lines are NUL-delimited into jq: a line is free text and may
# hold anything but a NUL.
handoff_drive_plan() {
    local kind="$1" fail_file="$2"; shift 2
    local -a lines=( "$@" )
    local -a rest=( ${DRIVE_AFTER[@]+"${DRIVE_AFTER[@]}"} )
    local before_json after_json="[]"
    to_json() { printf '%s\0' "$@" | jq -Rsc 'split("\u0000")[:-1]'; }
    before_json="$(to_json "${lines[@]}")"
    if (( ${#rest[@]} > 0 )); then
        after_json="$(to_json "${rest[@]}")"
    fi
    jq -nc --arg k "$kind" --arg f "$fail_file" --arg l "${lines[0]}" \
        --argjson b "$before_json" --argjson a "$after_json" \
        '{kind: $k, before: $b, after: $a, failFile: $f,
          message: ("handoff: will run " + $l + " once the turn ends.")}'
}
