#!/usr/bin/env bash
# Shared by the bats files that test the hook scripts: their setup and
# teardown, and the helpers two or more of them call. A helper only one file
# calls stays in that file. Each of those files `source`s this one, under a
# `# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash` line, so shellcheck
# follows it. It sources shared-helpers.bash, whose header names who else
# shares those helpers.
#
# End-to-end test of the hook scripts against synthetic input. Each scenario
# is a real invocation of the hook with a hand-crafted tool-event payload.
# bats `run` captures exit codes and output without toggling errexit.
#
# Usage: bats tests/<file>.bats   (run from plugin root)

# shellcheck disable=SC2034   # read by the rows of the files that source this one
# shellcheck source-path=SCRIPTDIR source=shared-helpers.bash
source "$BATS_TEST_DIRNAME/shared-helpers.bash"

setup() {
    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    cd "$repo_root" || return 1

    tmp="$BATS_TEST_TMPDIR/proj"
    other="$BATS_TEST_TMPDIR/other"
    mkdir -p "$tmp/.claude" "$other/.claude"
    export CLAUDE_PROJECT_DIR="$tmp"

    cat > "$tmp/TASK.md" <<'TASK'
## Current task

hook smoke test

## Open decisions

- none
TASK

    # The session-keyed pointer and drift marker live at a literal path
    # (/tmp/claude) so a hook and the agent's Bash can address them without
    # sharing an environment. Redirect it, or the suite writes into the
    # runner's own real one.
    export HANDOFF_POINTER_DIR="$BATS_TEST_TMPDIR/pointer"
    export SESSION_ID="sess-hook-test"

    # shellcheck source-path=SCRIPTDIR source=../scripts/_lib.sh disable=SC1091
    source "$repo_root/scripts/_lib.sh"
}

# A row may leave a file at mode 000; bats removes the temp tree afterwards and
# a leftover mode would only make that harder to debug.
teardown() {
    chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# <text> <expected> — text is one header line followed by exactly the expected
# rest, so a frame or an injected context is checked whole, not by grep.
assert_framed() {
    local header="${1%%$'\n'*}"
    local re='^# Task — [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$'
    [[ "$header" =~ $re ]] || return 1
    [ "${1#"$header"}" = "$2" ] || return 1
}

run_write_guard() {  # <tool> <cwd> <file_path> [CLAUDE_PROJECT_DIR]
    run bash -c '
        jq -nc --arg t "$1" --arg cwd "$2" --arg fp "$3" \
            "{cwd:\$cwd, tool_name:\$t, tool_input:{file_path:\$fp}}" \
        | CLAUDE_PROJECT_DIR="$4" bash scripts/write-guard.sh
    ' _ "$1" "$2" "$3" "${4:-$CLAUDE_PROJECT_DIR}"
}

# <json> — a loader's output (the $output of a `run`) split into the two
# channels, exact: MSG is systemMessage and CTX is additionalContext. The
# trailing X keeps the command substitution from eating the newlines the
# contexts end on.
split_output() {
    MSG="$(jq -j '(.systemMessage // "") + "X"' <<<"$1")"; MSG="${MSG%X}"
    CTX="$(jq -j '(.hookSpecificOutput.additionalContext // "") + "X"' <<<"$1")"; CTX="${CTX%X}"
}

# <regex> — the whole systemMessage is `handoff: ` and then the regex.
assert_msg_matches() {
    local re="^handoff: $1\$"
    [[ "$MSG" =~ $re ]]
}

loaded_re='loaded — ([0-9]+ B|[0-9]+\.[0-9] KiB), saved (just now|[0-9]+[mhd] ago)'

# The legacy-path notes, one pair per half and per case. `_ctx` is the line the
# agent reads in additionalContext, `_msg` the fragment the user reads in the
# systemMessage. Both loaders say the same thing on each channel; the checkpoint
# repeats the move on its own stdout.
#   from-legacy: the half was loaded from the old path. The next checkpoint
#                moves a todo, and removes a task: `task` is required content
#                or `clear` under handoff and removed under precompact, so a
#                legacy task is never carried.
#   shadowed:    the root file has a body, so the old file is ignored.
legacy_task_ctx='Task loaded from legacy .claude/handoff-task.md; the next checkpoint removes it, and the task a handoff checkpoint is given goes to TASK.md.'
legacy_todo_ctx='Todo loaded from legacy .claude/handoff-todo.md; edit it there until the next checkpoint moves it to TODO.md.'
legacy_task_msg='task from .claude/handoff-task.md, next checkpoint removes it'
legacy_todo_msg='todo from .claude/handoff-todo.md, next checkpoint moves it'
shadowed_task_ctx='Legacy .claude/handoff-task.md is ignored: TASK.md has a body.'
shadowed_todo_ctx='Legacy .claude/handoff-todo.md is ignored: TODO.md has a body.'
shadowed_task_msg='.claude/handoff-task.md ignored, TASK.md wins'
shadowed_todo_msg='.claude/handoff-todo.md ignored, TODO.md wins'

# <name> — a linked worktree of $tmp whose path ends in a newline; echoes it
# with an X appended, which the caller strips (the capture would eat the newline).
make_worktree_nl_end() {
    local wt="$BATS_TEST_TMPDIR/$1"$'\n'
    mkdir -p "$wt/.claude" "$tmp/.git/worktrees/$1"
    printf 'gitdir: %s\n' "$tmp/.git/worktrees/$1" > "$wt/.git"
    printf '%sX' "$wt"
}

# The same file in state `pending`: a transition drive-take.sh has already taken,
# waiting on the SessionStart that confirms it.
seed_pending() {
    local dir="$1"; shift
    printf '%s\n' "pending" "$@" > "$dir/.claude/autodrive"
}

run_load_handoff() {
    run bash -c '
        jq -nc --arg cwd "$1" --arg s "$2" \
            "{cwd:\$cwd, hook_event_name:\"SessionStart\", source:\$s}" \
        | bash scripts/load-handoff.sh
    ' _ "$1" "$2"
}

# Seed .claude/autodrive under $1 in state `armed`, owned by this suite's
# session — what the checkpoint, the file's one writer, leaves behind — with the
# remaining args as the lines below.
seed_drive() {
    local dir="$1"; shift
    printf '%s\n' "armed $SESSION_ID" "$@" > "$dir/.claude/autodrive"
}

run_load_compact() {
    run bash -c '
        jq -nc --arg cwd "$1" "{cwd:\$cwd, source:\"compact\"}" \
        | bash scripts/load-compact.sh
    ' _ "$1"
}

# $3, when given, is the hook input's transcript_path; without it the input
# carries none, as a hook that was handed no transcript would see. PROMPT_ID in
# the environment, when non-empty, is the input's prompt_id; without it the
# input carries none, as a Claude Code that does not send one would.
run_report_failure() {
    run bash -c '
        if [ "$#" -ge 3 ]; then
            jq -nc --arg cwd "$1" --arg sid "$2" --arg tp "$3" --arg pid "${PROMPT_ID-}" \
              "{cwd:\$cwd, session_id:\$sid, transcript_path:\$tp, prompt:\"anything\"}
               + (if \$pid == \"\" then {} else {prompt_id:\$pid} end)"
        else
            jq -nc --arg cwd "$1" --arg sid "$2" --arg pid "${PROMPT_ID-}" \
              "{cwd:\$cwd, session_id:\$sid, prompt:\"anything\"}
               + (if \$pid == \"\" then {} else {prompt_id:\$pid} end)"
        fi | bash scripts/report-drive-failure.sh
    ' _ "$1" "${2-$SESSION_ID}" "${@:3}"
}

noprompt_phrase='a prompt typed while that turn was still running'
unloaded_msg='stale autodrive discarded — the drive mod did not run it'

prompt_marker="handoff-prompt-sess-hook-test"

# The directory session-pointer.sh creates at session start, 0700.
make_pointer_dir() {
    mkdir -p "$HANDOFF_POINTER_DIR"
    chmod 700 "$HANDOFF_POINTER_DIR"
}

# <prompt_id> — the marker as the checkpoint call of an earlier turn leaves it:
# the id and a NUL, in the directory session-pointer.sh creates.
seed_prompt_marker() {
    make_pointer_dir
    printf '%s\0' "$1" > "$HANDOFF_POINTER_DIR/$prompt_marker"
}

# <kind> — an armed file owned by this session, and in LINES the block the
# report offers for it.
seed_armed_kind() {
    case "$1" in
        rename)
            seed_drive "$tmp" rename "Queued Title"
            LINES="/rename Queued Title" ;;
        clear)
            seed_drive "$tmp" "clear continue" "Queued Title"
            LINES=$'/rename Queued Title\n/clear\n'"$HANDOFF_CONTINUATION" ;;
        compact)
            seed_drive "$tmp" "compact continue" "keep the parser work"
            LINES=$'/compact keep the parser work\n'"$HANDOFF_CONTINUATION" ;;
        prepare)
            seed_drive "$tmp" prepare
            LINES="" ;;
    esac
}

# <kind> — an owner's armed file of that kind, a copy of it kept for the
# comparison, and the marker holding the id the next input will carry.
seed_queued() {
    seed_armed_kind "$1"
    cp "$tmp/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    seed_prompt_marker arming-prompt
}

# <output> <lines> [unsettled] — <output> is today's unloaded-mod report, whole,
# with the lines to type. It says nothing of a typed-ahead prompt, unless the
# third argument is `unsettled`: the input carried a prompt_id but the marker
# could not say whether it was the arming turn's, so the note names a queued
# prompt as a possible cause, as it does for an input with no id.
assert_unloaded_report() {
    split_output "$1"
    [ "$MSG" = $'\033[0m'"handoff: $unloaded_msg."$'\nType in order:\n'"$2" ]
    [[ "$CTX" == *"safe-mode"* && "$CTX" == *"2.1.287"* && "$CTX" == *"managed settings"* ]]
    [[ "$CTX" == *"Present these lines to the user in a fenced code block, to type in order:"$'\n'"$2" ]]
    if [[ "${3-}" == unsettled ]]; then
        [[ "$CTX" == *"$noprompt_phrase"* ]]
    else
        [[ "$CTX" != *"$noprompt_phrase"* ]]
    fi
}

# Seed a transcript for session $1 in the shared transcript directory and print
# this session's transcript path, which is what the hook input carries. $2, when
# given, is the owner transcript's age in seconds.
seed_transcript() {
    local dir="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$dir"
    printf '{}\n' > "$dir/$1.jsonl"
    if [ -n "${2:-}" ]; then
        python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]); os.utime(sys.argv[1], (t, t))' \
            "$dir/$1.jsonl" "$2"
    fi
    printf '%s\n' "$dir/$SESSION_ID.jsonl"
}

seed_owned() {  # <state> <owner>
    printf '%s\n' "$1 $2" "clear continue" "A Title" > "$tmp/.claude/autodrive"
}
