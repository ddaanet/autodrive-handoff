#!/usr/bin/env bash
# Shared helpers for handoff hook scripts. Source-only; no shebang
# execution. Source from siblings via:
#   # shellcheck source-path=SCRIPTDIR source=_lib.sh
#   source "$(dirname "$0")/_lib.sh"

# The directory this file is in, computed once when it is sourced so no helper
# forks `dirname` for it: the scripts it runs (`_checkpoint_lib.py`,
# `_drive_lock.py`, `worktree_root.py`) are beside it. `.` when BASH_SOURCE has
# no slash.
case "${BASH_SOURCE[0]}" in
    */*) HANDOFF_LIB_DIR="${BASH_SOURCE[0]%/*}"; : "${HANDOFF_LIB_DIR:=/}" ;;
    *) HANDOFF_LIB_DIR="." ;;
esac

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
# The advisory lock the sentinel's actors hold across a read-decide-write
# (_drive_lock.py; docs/design/driving-the-transition.md, "The sentinel's lock").
# Beside the sentinel, under the `.claude/autodrive*` ignore, and never removed.
# Mirrored in checkpoint.py.
# shellcheck disable=SC2034
HANDOFF_REL_DRIVE_LOCK=".claude/autodrive.lock"
# Where the drive mod records a line it could not run (written from
# the mod at the failing line). A mod's rejection goes nowhere on its
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

# <lockfile>. Take the sentinel's lock, held until the shell exits (or closes
# fd 9), so a script holds it across its whole read-decide-write by calling this
# before the read. Returns 0 holding it. Not holding it fails closed: the caller
# leaves the sentinel alone, since acting unlocked reopens the race the lock
# closes, and says why with HANDOFF_LOCK_MSG, which this sets on every failure.
# Two returns tell the causes apart: 1 is `busy`, the wait bound passed with
# another actor still holding the lock (HANDOFF_LOCK_WAIT_SECS, default 5); 2 is
# `unavailable`, a lock that could not be set up at all (no `.claude/`, a link
# or a non-file at the name, python3 or the helper failing, a file system with
# no flock). Callers under `set -e` write `lock_rc=0; handoff_lock_take … ||
# lock_rc=$?`. Call it directly, never in a `$(...)`: the message and the lock
# itself are the caller's shell's.
#
# fd 9 is the lock's, and a script that calls this must not use it. A lock lives
# on an open file description, which a child shares with the descriptor its
# parent opened, so bash opens fd 9 on the file, `_drive_lock.py wait` takes
# the lock on it from a child, and the lock stays with the shell's descriptor
# after that child is gone. `create` makes the file first, 0600 and
# O_NOFOLLOW, which bash's own redirection could not promise, and is skipped
# once a regular file is there (the lock file is never deleted, so after the
# first take that is the usual case: one spawn instead of two). `wait` checks
# that fd 9 is still the regular file the path names, which is the whole of the
# safety `create` adds for a file already there. Read-write so that opening a
# FIFO put there in the meantime cannot block. `wait` exits 75 for busy and
# anything else for unavailable (a crashed or missing python3 included).
# shellcheck disable=SC2034  # HANDOFF_LOCK_MSG is read by the sourcing scripts
handoff_lock_take() {
    local lock="$1" helper wait_rc=0
    HANDOFF_LOCK_MSG="the sentinel's lock could not be set up"
    helper="$HANDOFF_LIB_DIR/_drive_lock.py"
    if [[ ! -f "$lock" || -L "$lock" ]]; then
        python3 -I "$helper" create "$lock" 2>/dev/null || return 2
    fi
    { exec 9<>"$lock"; } 2>/dev/null || return 2
    python3 -I "$helper" wait 9 "$lock" 2>/dev/null || wait_rc=$?
    if (( wait_rc == 0 )); then
        return 0
    fi
    { exec 9>&-; } 2>/dev/null
    if (( wait_rc == 75 )); then
        HANDOFF_LOCK_MSG="the sentinel's lock was busy"
        return 1
    fi
    return 2
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
        python3 "$HANDOFF_LIB_DIR/worktree_root.py" "$1" "$project"
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

# The rest of the library, in parts: each defines functions and sets no state
# at load. Sourced here, after everything this file defines, from the
# directory it was found in.
# shellcheck source-path=SCRIPTDIR/../scripts source=_lib_frame.sh
source "$HANDOFF_LIB_DIR/_lib_frame.sh"
# shellcheck source-path=SCRIPTDIR/../scripts source=_lib_drive.sh
source "$HANDOFF_LIB_DIR/_lib_drive.sh"
# shellcheck source-path=SCRIPTDIR/../scripts source=_lib_files.sh
source "$HANDOFF_LIB_DIR/_lib_files.sh"
