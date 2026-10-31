#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- session-pointer (SessionStart, every source: sweep stale pointer files) ---
#
# Used to also publish this session's resolved root here, at a session-keyed
# path handoff-checkpoint (running in the agent's own Bash, where
# CLAUDE_PROJECT_DIR is unset) could address blind. Replaced by
# scripts/inject-checkpoint-root.sh (PreToolUse(Bash)), which resolves the
# root fresh on every matching call instead.

run_session_pointer() {
    local cwd="$1"
    run bash -c '
        jq -nc --arg cwd "$1" --arg sid "$2" \
          "{cwd:\$cwd, session_id:\$sid, source:\"startup\", hook_event_name:\"SessionStart\"}" \
        | bash scripts/session-pointer.sh
    ' _ "$cwd" "$SESSION_ID"
}

# scripts/inject-checkpoint-root.sh (PreToolUse(Bash)) resolves the root fresh
# on every matching call and injects it straight into the command now, instead
# of this hook sampling and publishing it once at SessionStart.
# SessionStart(resume) fires with the RESUMING process's cwd, before the
# harness moves the session into its own project dir — the one moment a sample
# taken here would stamp the wrong repo onto it. Mutation-checked: the first
# assertion cannot go red before the write is removed, so it is verified by
# reintroducing the old write and watching this alone go red. See
# plans/2026-08-05-checkpoint-root-via-updatedinput.md.
@test "session-pointer (no longer writes a root pointer)" {
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$HANDOFF_POINTER_DIR/handoff-root-$SESSION_ID" ]
}

@test "session-pointer (creates the pointer directory)" {
    [ ! -d "$HANDOFF_POINTER_DIR" ]
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ -d "$HANDOFF_POINTER_DIR" ]
}

# Created first at session start, so its mode is the one the drift report's
# marker_dir_ok judges: under a group-writable umask a plain `mkdir -p` makes
# it 0775, the marker is never used and the drift note repeats every prompt.
@test "session-pointer (creates the pointer directory 0700 under umask 002)" {
    mkdir -p "$other/.git"
    umask 002
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$HANDOFF_POINTER_DIR")" = "0o700" ]
    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
    run_report_failure "$other"
    [ "$output" = "" ]
}

# Nothing else removes these. The pointer outlives the session that published
# it, the drift marker outlives the episode it recorded, and the directory they
# share is swept by nobody. The producer sweeps its own leavings — once per
# session start, which is the only moment anything of this plugin's runs there.

@test "session-pointer (sweeps its own long-stale files)" {
    mkdir -p "$HANDOFF_POINTER_DIR"
    touch -t 202001010000 "$HANDOFF_POINTER_DIR/handoff-root-ancient" \
        "$HANDOFF_POINTER_DIR/handoff-drift-ancient"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$HANDOFF_POINTER_DIR/handoff-root-ancient" ]
    [ ! -e "$HANDOFF_POINTER_DIR/handoff-drift-ancient" ]
}

# The prompt marker is written per session by inject-checkpoint-root.sh and, like
# the drift marker, is cleared by nothing else.
@test "session-pointer (sweeps a long-stale prompt marker)" {
    mkdir -p "$HANDOFF_POINTER_DIR"
    touch -t 202001010000 "$HANDOFF_POINTER_DIR/handoff-prompt-ancient"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$HANDOFF_POINTER_DIR/handoff-prompt-ancient" ]
}

@test "session-pointer (keeps another live session's prompt marker)" {
    mkdir -p "$HANDOFF_POINTER_DIR"
    touch "$HANDOFF_POINTER_DIR/handoff-prompt-other"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-prompt-other" ]
}

@test "session-pointer (keeps another live session's files)" {
    mkdir -p "$HANDOFF_POINTER_DIR"
    touch "$HANDOFF_POINTER_DIR/handoff-root-other" \
        "$HANDOFF_POINTER_DIR/handoff-drift-other"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-root-other" ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-drift-other" ]
}

# The load-bearing negative: the directory is shared and holds files this
# plugin never wrote, some of them weeks old. The sweep is scoped to the two
# names it publishes, at the one level it publishes them.
#
# The handoff-prefixed file pins the narrower claim — the two names, not the
# prefix. Collapsing the two -name clauses into one `handoff-*` is the
# plausible refactor, and every other row here is blind to it: it would claim
# any later handoff- file in this shared directory whose lifetime is not seven
# days. A new published name must be added here as deliberately as to the
# filter.
@test "session-pointer (never sweeps a file it does not own)" {
    mkdir -p "$HANDOFF_POINTER_DIR/sub"
    touch -t 202001010000 "$HANDOFF_POINTER_DIR/somebody-elses-file" \
        "$HANDOFF_POINTER_DIR/handoff-unpublished-ancient" \
        "$HANDOFF_POINTER_DIR/sub/handoff-root-nested"
    run_session_pointer "$tmp"
    [ "$status" -eq 0 ]
    [ -e "$HANDOFF_POINTER_DIR/somebody-elses-file" ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-unpublished-ancient" ]
    [ -e "$HANDOFF_POINTER_DIR/sub/handoff-root-nested" ]
}
