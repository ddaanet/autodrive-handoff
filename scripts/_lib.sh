#!/usr/bin/env bash
# Shared helpers for handoff hook scripts. Source-only; no shebang
# execution. Source from siblings via:
#   # shellcheck source-path=SCRIPTDIR source=_lib.sh
#   source "$(dirname "$0")/_lib.sh"

# Canonical relative paths inside the project. Changing these is a
# breaking change (see CLAUDE.md conventions).
# shellcheck disable=SC2034  # consumed by sourcing scripts
HANDOFF_REL_TASK="TASK.md"
# The remainder ledger: open todo items only, never completion state. A plain
# tracked file in the project root, like the task file beside it. See
# docs/changelog/2026-07-22-a-place-for-the-todo-list.md.
# shellcheck disable=SC2034
HANDOFF_REL_TODO="TODO.md"

# The paths the task and todo files lived at before they moved to the project
# root. The loaders read them as a fallback and the checkpoint moves a file off
# them, and this pair is the one marker for that fallback: `grep -rni legacy`
# over scripts/ and tests/ lists all of it. It goes once no sibling repository
# still has a `.claude/handoff-*.md`.
# shellcheck disable=SC2034
HANDOFF_LEGACY_REL_TASK=".claude/handoff-task.md"
# shellcheck disable=SC2034
HANDOFF_LEGACY_REL_TODO=".claude/handoff-todo.md"
# The transition. One session, at most one transition in flight —
# so one file, whose *body* names both the transition and where it has got to.
# Line 1 is the state (armed -> pending -> gone), line 2 the kind. See
# docs/design/decisions.md, "The armed transition is one file whose body
# names the transition."
# shellcheck disable=SC2034
HANDOFF_REL_DRIVE=".claude/autodrive"
# Where the drive mod records a line it could not run (written from
# hooks/handoff.ts at the failing line). A mod's rejection goes nowhere on its
# own, so this is the only path back to the agent; consumed and reported by
# report-drive-failure.sh at the next UserPromptSubmit.
# shellcheck disable=SC2034
HANDOFF_REL_DRIVE_FAILED=".claude/autodrive.failed"
# Where report-drive-failure.sh appends one line for every transition file it
# removes: when, which session removed it, what state and owner it had, how old
# it was. The sweep reports on the removing session's own channels, which are
# invisible from the session that composed the file, so without this record a
# sentinel that vanishes leaves nothing to say who took it. Never consumed;
# trimmed to its last lines by the writer.
# shellcheck disable=SC2034
HANDOFF_REL_DRIVE_SWEPT=".claude/autodrive.swept"

# Where the drift report records the last destination it announced. A literal
# directory rather than $TMPDIR: it used to also be where session-pointer.sh
# published this session's resolved root for the agent's own sandboxed Bash to
# read back, and the two shared no environment but the session id — see
# plans/2026-08-05-checkpoint-root-via-updatedinput.md. That duty moved to
# scripts/inject-checkpoint-root.sh (PreToolUse(Bash) env injection), but the
# drift marker is still session-keyed the same way, so the literal path stays.
HANDOFF_POINTER_DIR="${HANDOFF_POINTER_DIR:-/tmp/claude}"

# Assemble the injectable frame from the task file ($1) and the todo file
# ($2): a timestamp header plus each half that counts inlined verbatim, task
# first. $3 and $4 are the legacy task and todo paths, optional; an absent or
# empty one is a path that does not exist, and so is any of the four that is a
# symlink. Per half, the root file counts when
# it has a body (`is_empty_body` in _checkpoint_lib.py, through its
# `--has-body` CLI), and otherwise the legacy file does when it has a body. A
# missing, zero-byte, whitespace-only or headings-only file has none, and
# neither has one the check fails to run on. Either half alone is enough.
# Shared by load-handoff.sh (startup|clear) and load-compact.sh (compact) — one
# frame shape for both transitions.
#
# Prints nothing; sets in the caller's scope on every call. FRAME is the frame,
# empty when neither half counts, and never holds a note; the rest are each 1 or 0:
#   FRAME_TASK, FRAME_TODO   the half is in the frame
#   FRAME_TASK_LEGACY, FRAME_TODO_LEGACY
#                            the half came from its legacy path
#   FRAME_TASK_SHADOWED, FRAME_TODO_SHADOWED
#                            the half came from the root file and a legacy
#                            file exists beside it, whatever that one holds
# and returns 1 when FRAME is empty. Callers under `set -e` absorb the 1
# (`handoff_frame … || true`) and read the variables; a `$(…)` capture would
# lose them with the subshell. `handoff_frame_notes` turns the flags into the
# notes the loaders append.
#
# The hook does not re-state either template: each file carries its own `##`
# section headings (SKILL.md is the single source of truth) and is concatenated
# verbatim under the one `#` header prepended here.
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_frame() {
    local task="$1" todo="$2" legacy_task="${3:-}" legacy_todo="${4:-}" lib
    local task_src todo_src
    lib="$(dirname "${BASH_SOURCE[0]}")/_checkpoint_lib.py"
    # Any of the four paths that is a symlink, dangling or not, is treated as
    # absent: never tested, read or counted as shadowing or shadowed. The
    # checkpoint refuses a symlink at each, naming the field (a dangling
    # legacy one it reads as no file), so the next checkpoint is what reports
    # it; following one here would inject whatever
    # file it names, and a repository can commit a link to anything readable.
    # A symlinked root file is a root file with no body, so the legacy file
    # beside it is loaded as it would be beside any such file.
    [[ -n "$task" && -L "$task" ]] && task=""
    [[ -n "$todo" && -L "$todo" ]] && todo=""
    [[ -n "$legacy_task" && -L "$legacy_task" ]] && legacy_task=""
    [[ -n "$legacy_todo" && -L "$legacy_todo" ]] && legacy_todo=""
    task_src="$task" todo_src="$todo"
    FRAME="" FRAME_TASK=0 FRAME_TODO=0
    FRAME_TASK_LEGACY=0 FRAME_TODO_LEGACY=0
    FRAME_TASK_SHADOWED=0 FRAME_TODO_SHADOWED=0
    if _handoff_has_body "$lib" "$task"; then
        FRAME_TASK=1
        [[ -n "$legacy_task" && -f "$legacy_task" ]] && FRAME_TASK_SHADOWED=1
    elif _handoff_has_body "$lib" "$legacy_task"; then
        FRAME_TASK=1 FRAME_TASK_LEGACY=1
        task_src="$legacy_task"
    fi
    if _handoff_has_body "$lib" "$todo"; then
        FRAME_TODO=1
        [[ -n "$legacy_todo" && -f "$legacy_todo" ]] && FRAME_TODO_SHADOWED=1
    elif _handoff_has_body "$lib" "$legacy_todo"; then
        FRAME_TODO=1 FRAME_TODO_LEGACY=1
        todo_src="$legacy_todo"
    fi
    (( FRAME_TASK + FRAME_TODO > 0 )) || return 1
    FRAME="# Task — $(date '+%Y-%m-%d %H:%M:%S %z')"
    if (( FRAME_TASK )); then
        FRAME+=$'\n\n'"$(cat "$task_src")"
    fi
    if (( FRAME_TODO )); then
        FRAME+=$'\n\n'"$(cat "$todo_src")"
    fi
}

# <is_empty_body library> <path>. True when the path is a file with a body.
# The CLI answers a body with exit 0, the one status no crash can produce (an
# uncaught exception exits 1, a library python3 cannot open exits 2), so a
# check that failed to run is never read as a body.
_handoff_has_body() {
    [[ -n "$2" && -f "$2" && -r "$2" ]] || return 1
    python3 "$1" --has-body <"$2"
}

# The notes for the legacy flags `handoff_frame` just set, in the order both
# channels carry them: task from legacy, todo from legacy, task ignored, todo
# ignored. Sets FRAME_NOTES_CTX (full sentences for the agent) and
# FRAME_NOTES_MSG (fragments for the user's one-line message), parallel arrays
# reset on every call. Expand them as `${A[@]+"${A[@]}"}` (bash 3.2).
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_frame_notes() {
    FRAME_NOTES_CTX=() FRAME_NOTES_MSG=()
    if (( FRAME_TASK_LEGACY )); then
        # Removed, never moved: `task` is required content or `clear` under
        # handoff, and precompact removes the task, so no checkpoint carries a
        # legacy task's bytes to the root the way `keep` carries a todo's.
        FRAME_NOTES_CTX+=("Task loaded from legacy $HANDOFF_LEGACY_REL_TASK; the next checkpoint removes it, and the task a handoff checkpoint is given goes to $HANDOFF_REL_TASK.")
        FRAME_NOTES_MSG+=("task from $HANDOFF_LEGACY_REL_TASK, next checkpoint removes it")
    fi
    if (( FRAME_TODO_LEGACY )); then
        FRAME_NOTES_CTX+=("Todo loaded from legacy $HANDOFF_LEGACY_REL_TODO; edit it there until the next checkpoint moves it to $HANDOFF_REL_TODO.")
        FRAME_NOTES_MSG+=("todo from $HANDOFF_LEGACY_REL_TODO, next checkpoint moves it")
    fi
    if (( FRAME_TASK_SHADOWED )); then
        FRAME_NOTES_CTX+=("Legacy $HANDOFF_LEGACY_REL_TASK is ignored: $HANDOFF_REL_TASK has a body.")
        FRAME_NOTES_MSG+=("$HANDOFF_LEGACY_REL_TASK ignored, $HANDOFF_REL_TASK wins")
    fi
    if (( FRAME_TODO_SHADOWED )); then
        FRAME_NOTES_CTX+=("Legacy $HANDOFF_LEGACY_REL_TODO is ignored: $HANDOFF_REL_TODO has a body.")
        FRAME_NOTES_MSG+=("$HANDOFF_LEGACY_REL_TODO ignored, $HANDOFF_REL_TODO wins")
    fi
}

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
    # `rm -f` removes the link and not what it names. The check is on the last
    # component only: a symlinked `.claude/` is read and written where it
    # points, as the root and legacy files are.
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
        *)
            DRIVE_ERR="the file is not a regular file that can be read"
            return 1 ;;
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

# Whether session $2 is live, judged from this session's transcript path ($1):
# the owner's transcript is `<owner>.jsonl` in the same directory, and it is
# live when that file was written within HANDOFF_OWNER_LIVE_SECS (default 600).
# A heuristic: a running turn writes its transcript on every message, but an
# owner idle longer than the window reads as gone. No transcript path, an owner
# that is not a plain file name, or no transcript for it: not live.
handoff_owner_live() {
    local transcript="$1" owner="$2" file mtime now
    [ -n "$transcript" ] && [ -n "$owner" ] || return 1
    case "$owner" in */* | . | ..) return 1 ;; esac
    file="$(dirname "$transcript")/$owner.jsonl"
    [ -f "$file" ] || return 1
    mtime="$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || true)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
    now="$(date +%s)"
    (( now - mtime <= ${HANDOFF_OWNER_LIVE_SECS:-600} ))
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

# <path> [own]. Print a status line, then on `ok` the file's bytes, opened with
# O_NOFOLLOW so the check and the read are one step: no link put at the name
# at any moment is followed. The status is `ok`, `absent`, `link` (the last
# component is a link, dangling or not), `other` (not a regular file, or
# unreadable) or, with `own`, `foreign` (a regular file another user owns).
# Nothing printed means python3 failed; callers read that as `other`. Read it
# as `{ IFS= read -r status; …; } < <(handoff_read_regular …)`, so the bytes
# follow on the same stream and a NUL in them survives a `read -d ''`.
handoff_read_regular() {
    python3 -c '
import errno, os, stat, sys
try:
    fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
except FileNotFoundError:
    print("absent")
    sys.exit(0)
except OSError as e:
    print("link" if e.errno == errno.ELOOP else "other")
    sys.exit(0)
st = os.fstat(fd)
if not stat.S_ISREG(st.st_mode):
    print("other")
elif sys.argv[2] == "own" and st.st_uid != os.geteuid():
    print("foreign")
else:
    try:
        sys.stdout.write("ok\n")
        sys.stdout.flush()
        with os.fdopen(fd, "rb") as f:
            sys.stdout.buffer.write(f.read())
            sys.stdout.flush()
    except BrokenPipeError:
        # A caller that stops reading early, as the record trim does.
        os._exit(0)
' "$1" "${2:-any}"
}

# <source> <destination>. rename(2) through os.replace: a link at the
# destination is replaced, never followed. `mv` stats the destination, and a
# link to a directory there would receive the file inside it.
handoff_replace() {
    python3 -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' "$1" "$2"
}

# Effective project root for the handoff files of THIS session, into the
# caller's HANDOFF_ROOT, plus the branch that produced it in
# HANDOFF_ROOT_BRANCH: `inside` (cwd is the project or under it), `worktree`
# (a linked worktree of it), `foreign` (another repo) or `unrelated` (no repo).
# When the session cwd ($1, from hook-input .cwd) is inside a linked git
# worktree of CLAUDE_PROJECT_DIR, the root is the worktree root so each
# worktree owns its own .claude/; otherwise CLAUDE_PROJECT_DIR (fallback $PWD).
# The branch-heavy resolution lives in worktree_root.py (unit-tested with
# pytest); this is the thin shell wrapper. See
# plans/2026-06-09-per-worktree-handoff-root-design.md and
# plans/2026-07-31-session-root-drift-design.md.
#
# Caller-scope globals rather than stdout (the handoff_drive_read idiom): a
# root printed into a `$(...)` capture loses any trailing newline it ends on,
# naming a sibling directory, so no caller takes the root from stdout.
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_root_read() {
    local project="${CLAUDE_PROJECT_DIR:-$PWD}"
    # Fast path: an empty cwd or one already at the project root is exactly
    # worktree_root.py's trivial branches (`if not cwd` / `if d == project`).
    # Skipping the interpreter matters because Stop and UserPromptSubmit call
    # this on every turn, where python3 startup dominates the hook's cost. It
    # labels the branch itself — leaving the previous resolution's label in
    # place would report drift on a session that never drifted.
    if [[ -z "${1:-}" || "${1:-}" == "$project" ]]; then
        HANDOFF_ROOT="$project"
        HANDOFF_ROOT_BRANCH="inside"
        return 0
    fi
    # The resolver answers NUL-terminated: a root is any string, and one holding
    # a newline would be cut by a line-wise read.
    HANDOFF_ROOT="" HANDOFF_ROOT_BRANCH=""
    { IFS= read -r -d '' HANDOFF_ROOT; IFS= read -r -d '' HANDOFF_ROOT_BRANCH; } < <(
        python3 "$(dirname "${BASH_SOURCE[0]}")/worktree_root.py" "$1" "$project"
    ) || true
    # A process substitution's exit status is out of reach in bash 3.2, so the
    # answer is judged instead: a resolver that crashed printed nothing, or not
    # a label it has. Then the root is unknown, and saying so is each caller's
    # business on its own channel — `unresolved` with an empty root, rc 0, so a
    # caller under `set -e` reaches its report rather than dying silent.
    case "$HANDOFF_ROOT_BRANCH" in
        inside | worktree | foreign | unrelated)
            [[ -n "$HANDOFF_ROOT" ]] && return 0 ;;
    esac
    HANDOFF_ROOT="" HANDOFF_ROOT_BRANCH="unresolved"
}

# The one wording of an unresolved root, for every caller's channels.
# shellcheck disable=SC2034  # consumed by sourcing scripts
HANDOFF_UNRESOLVED_MSG="the session root did not resolve (scripts/worktree_root.py failed)"

# Emit a PreToolUse deny on stdout, then `exit 0` (not `return`) —
# terminates the calling process, so only safe from a standalone hook
# script, not a general sourced context (subshell/interactive/setup).
# Modern PreToolUse permissionDecision deny channel. $1 = agent-facing
# reason (factual, no actionable phrasing);
# $2 = user-facing systemMessage.
handoff_deny() {
    jq -nc --arg r "$1" --arg s "$2" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
    exit 0
}
