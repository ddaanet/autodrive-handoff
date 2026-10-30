#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=checkpoint-helpers.bash
source "$BATS_TEST_DIRNAME/checkpoint-helpers.bash"

# Tests for scripts/inject-checkpoint-root.sh (PreToolUse(Bash) root injection)
# and the prompt marker it writes, one of the bash-side neighbors of the
# checkpoint channel that stayed bash in the Python split
# (docs/changelog/2026-08-10-python-split.md). The helpers it shares with
# tests/validate-plugin.bats and tests/bin-commands.bats are in
# tests/checkpoint-helpers.bash.
#
# Run with: bats tests/inject-checkpoint-root.bats   (from plugin root)

# ==========================================================================
# scripts/inject-checkpoint-root.sh — PreToolUse(Bash): resolves this
# session's root and injects it as HANDOFF_ROOT straight into a
# handoff-checkpoint or handoff-approved command, replacing the pointer
# SessionStart used to publish. SessionStart(resume) fires with the RESUMING
# process's cwd, before the harness moves the session into its own project
# dir — the one moment sampling the root would stamp the wrong repo onto it.
# See plans/2026-08-05-checkpoint-root-via-updatedinput.md.
# ==========================================================================

# Run the hook against a Bash tool_input.command ($2) with cwd = $1. Exports
# CLAUDE_PROJECT_DIR=$1 first — a real PreToolUse(Bash) invocation always has
# it, unlike the agent's own Bash where checkpoint.py/handoff-approved run.
run_inject_root() {
    local repo="$1" command="$2"
    export CLAUDE_PROJECT_DIR="$repo"
    run bash -c '
        jq -nc --arg cwd "$1" --arg cmd "$2" \
          "{cwd:\$cwd, hook_event_name:\"PreToolUse\", tool_name:\"Bash\", tool_input:{command:\$cmd}}" \
        | bash "$3"
    ' _ "$repo" "$command" "$INJECT_ROOT"
}

@test "inject-checkpoint-root: rewrites a handoff-checkpoint call, carrying the resolved root" {
    repo="$(make_repo)"
    run_inject_root "$repo" 'handoff-checkpoint <<<"{}"'
    [ "$status" -eq 0 ]
    # No decision: the rewrite goes through the permission pipeline, not around it.
    [ "$(jq -r '.hookSpecificOutput | has("permissionDecision")' <<<"$output")" = "false" ]
    new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
    [[ "$new_cmd" == "export HANDOFF_ROOT="*";"*"handoff-checkpoint"* ]]
    [[ "$new_cmd" == *"$repo"* ]]
}

@test "inject-checkpoint-root: rewrites a handoff-approved call too" {
    repo="$(make_repo)"
    run_inject_root "$repo" 'handoff-approved'
    [ "$status" -eq 0 ]
    new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
    [[ "$new_cmd" == "export HANDOFF_ROOT="*";"*"handoff-approved"* ]]
}

@test "inject-checkpoint-root: leaves an unrelated Bash command untouched" {
    repo="$(make_repo)"
    run_inject_root "$repo" 'echo hello'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# A path containing whitespace must round-trip: assert the value the rewritten
# command's own shell sees, not the string the hook printed.
@test "inject-checkpoint-root: a root containing whitespace round-trips through the rewrite" {
    repo="$(make_repo "$BATS_TEST_TMPDIR/has space/repo")"
    # shellcheck disable=SC2016   # $HANDOFF_ROOT is meant literal — it expands inside new_cmd's own bash -c, below
    run_inject_root "$repo" 'printf %s "$HANDOFF_ROOT" > seen; true # handoff-checkpoint'
    [ "$status" -eq 0 ]
    new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
    (cd "$repo" && bash -c "$new_cmd")
    [ "$(cat "$repo/seen")" = "$repo" ]
}

# A root ending in a newline is what a `$(...)` capture of it loses: the
# rewritten command would export a sibling directory.
@test "inject-checkpoint-root: a root ending in a newline round-trips through the rewrite" {
    repo="$(make_repo "$BATS_TEST_TMPDIR/nl-end"$'\n'; printf X)"; repo="${repo%$'\n'X}"
    # shellcheck disable=SC2016   # $HANDOFF_ROOT is meant literal — it expands inside new_cmd's own bash -c, below
    run_inject_root "$repo" 'printf %s "$HANDOFF_ROOT" > seen; true # handoff-checkpoint'
    [ "$status" -eq 0 ]
    new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
    (cd "$repo" && bash -c "$new_cmd")
    [ "$(cat "$repo/seen"; printf X)" = "$repo"X ]
}

# A resolver that crashes leaves the root unknown: the command is left as it
# is, so the checkpoint refuses an unset HANDOFF_ROOT naming it, and the user
# is told why.
@test "inject-checkpoint-root: a resolver that crashes leaves the command alone and says so" {
    repo="$(make_repo)"
    stub="$BATS_TEST_TMPDIR/broken-python"; mkdir -p "$stub"
    printf '#!/usr/bin/env bash\nexit 97\n' > "$stub/python3"; chmod +x "$stub/python3"
    run bash -c '
        jq -nc --arg cwd "$1/sub" --arg cmd "handoff-checkpoint" \
          "{cwd:\$cwd, hook_event_name:\"PreToolUse\", tool_name:\"Bash\", tool_input:{command:\$cmd}}" \
        | CLAUDE_PROJECT_DIR="$1" PATH="$2:$PATH" bash "$3"
    ' _ "$repo" "$stub" "$INJECT_ROOT"
    [ "$status" -eq 0 ]
    jq -e '.hookSpecificOutput.updatedInput == null and (.systemMessage | test("did not resolve"))' <<<"$output" >/dev/null
}

# The row that would stay green under a bare `VAR=… cmd` prefix only by
# accident: `VAR=x a && b` sets the variable for `a` alone, so a batched
# command's SECOND stage would see nothing. `export …;` must survive it.
@test "inject-checkpoint-root: export survives a batched command, unlike a bare VAR= prefix" {
    repo="$(make_repo)"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/handoff-checkpoint" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/handoff-checkpoint"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export PATH
    # shellcheck disable=SC2016   # $HANDOFF_ROOT is meant literal — it expands inside new_cmd's own bash -c, below
    run_inject_root "$repo" 'handoff-checkpoint <<<"{}" && printf %s "$HANDOFF_ROOT" > seen'
    [ "$status" -eq 0 ]
    new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
    (cd "$repo" && bash -c "$new_cmd")
    [ "$(cat "$repo/seen")" = "$repo" ]
}

# The prompt marker. A prompt typed while the turn that ran the checkpoint is
# still running fires UserPromptSubmit inside that turn with that turn's
# prompt_id; report-drive-failure.sh compares its input's against this marker to
# tell it from one typed at an idle composer (its rows are in
# tests/hook-test.bats, where the marker is a fixture). The one writer is this
# hook, on its matching path, so the id it records is the checkpoint call's own
# turn's. The pointer directory is not made by the setup: the hook makes it.

prompt_marker="handoff-prompt-sess-checkpoint"

# <repo> <command> <session_id> <prompt_id> — run_inject_root with the ids in the
# input. An id of `-` leaves its key out; an empty one sends it empty.
run_inject_root_ids() {
    local repo="$1" command="$2"
    export CLAUDE_PROJECT_DIR="$repo"
    run bash -c '
        jq -nc --arg cwd "$1" --arg cmd "$2" --arg sid "$3" --arg pid "$4" \
          "{cwd:\$cwd, hook_event_name:\"PreToolUse\", tool_name:\"Bash\", tool_input:{command:\$cmd}}
           + (if \$sid == \"-\" then {} else {session_id:\$sid} end)
           + (if \$pid == \"-\" then {} else {prompt_id:\$pid} end)" \
        | bash "$5"
    ' _ "$repo" "$command" "$3" "$4" "$INJECT_ROOT"
}

# <prompt_id> [<path>] — the marker holds the id and its NUL, exactly.
marker_holds() {
    cmp -s "${2-$HANDOFF_POINTER_DIR/$prompt_marker}" <(printf '%s\0' "$1")
}

@test "inject-checkpoint-root: a handoff-checkpoint call leaves the prompt_id, NUL-terminated, in a private directory" {
    repo="$(make_repo)"
    run_inject_root_ids "$repo" 'handoff-checkpoint <<<"{}"' sess-checkpoint arming-prompt
    [ "$status" -eq 0 ]
    new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
    [[ "$new_cmd" == "export HANDOFF_ROOT="*";"*"handoff-checkpoint"* ]]
    marker_holds arming-prompt
    # The temporary sibling is gone: the marker is the directory's only entry.
    [ "$(ls -A "$HANDOFF_POINTER_DIR")" = "$prompt_marker" ]
    [ -n "$(find "$HANDOFF_POINTER_DIR" -maxdepth 0 -perm 700)" ]
}

@test "inject-checkpoint-root: a handoff-approved call leaves the prompt_id too" {
    repo="$(make_repo)"
    run_inject_root_ids "$repo" 'handoff-approved' sess-checkpoint approving-prompt
    [ "$status" -eq 0 ]
    new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
    [[ "$new_cmd" == "export HANDOFF_ROOT="*";"*"handoff-approved"* ]]
    marker_holds approving-prompt
}

@test "inject-checkpoint-root: a later call replaces the prompt_id, and the marker is the session's own" {
    repo="$(make_repo)"
    run_inject_root_ids "$repo" 'handoff-checkpoint' sess-checkpoint prompt-one
    run_inject_root_ids "$repo" 'handoff-approved' sess-checkpoint prompt-two
    marker_holds prompt-two
    run_inject_root_ids "$repo" 'handoff-checkpoint' sess-other prompt-three
    marker_holds prompt-two
    marker_holds prompt-three "$HANDOFF_POINTER_DIR/handoff-prompt-sess-other"
    [ "$(find "$HANDOFF_POINTER_DIR" -mindepth 1 | wc -l)" -eq 2 ]
}

@test "inject-checkpoint-root: a command that is neither call writes no marker and says nothing" {
    repo="$(make_repo)"
    run_inject_root_ids "$repo" 'echo hello' sess-checkpoint some-prompt
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$HANDOFF_POINTER_DIR" ]
}

# Each of the two ids missing, and each empty: nothing to record, and the
# rewrite is the same as without them.
@test "inject-checkpoint-root: no marker without a session_id or without a prompt_id, the rewrite unchanged" {
    repo="$(make_repo)"
    local sid pid
    for ids in "- some-prompt" "'' some-prompt" "sess-checkpoint -" "sess-checkpoint ''" "- -" "'' ''"; do
        eval "set -- $ids"
        sid="$1" pid="$2"
        run_inject_root_ids "$repo" 'handoff-checkpoint' "$sid" "$pid"
        [ "$status" -eq 0 ]
        new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$output")"
        [[ "$new_cmd" == "export HANDOFF_ROOT="*";"*"handoff-checkpoint"* ]]
        [ ! -e "$HANDOFF_POINTER_DIR" ]
    done
}

# Resolution comes first: a root that did not resolve leaves the command alone,
# and the marker with it.
@test "inject-checkpoint-root: a resolver that crashes leaves no marker either" {
    repo="$(make_repo)"
    stub="$BATS_TEST_TMPDIR/broken-python"; mkdir -p "$stub"
    printf '#!/usr/bin/env bash\nexit 97\n' > "$stub/python3"; chmod +x "$stub/python3"
    run bash -c '
        jq -nc --arg cwd "$1/sub" --arg cmd "handoff-checkpoint" \
          "{cwd:\$cwd, session_id:\"sess-checkpoint\", prompt_id:\"arming-prompt\", hook_event_name:\"PreToolUse\", tool_name:\"Bash\", tool_input:{command:\$cmd}}" \
        | CLAUDE_PROJECT_DIR="$1" PATH="$2:$PATH" bash "$3"
    ' _ "$repo" "$stub" "$INJECT_ROOT"
    [ "$status" -eq 0 ]
    jq -e '.hookSpecificOutput.updatedInput == null and (.systemMessage | test("did not resolve"))' <<<"$output" >/dev/null
    [ ! -e "$HANDOFF_POINTER_DIR" ]
}

# The directory is shared by every local user, so a name in it may be a link
# someone else planted: the link is replaced, never written through.
@test "inject-checkpoint-root: a symlinked marker is replaced, its target untouched" {
    repo="$(make_repo)"
    mkdir -m 700 "$HANDOFF_POINTER_DIR"
    ln -s "$BATS_TEST_TMPDIR/planted-target" "$HANDOFF_POINTER_DIR/$prompt_marker"
    run_inject_root_ids "$repo" 'handoff-checkpoint' sess-checkpoint arming-prompt
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/planted-target" ]
    [ ! -L "$HANDOFF_POINTER_DIR/$prompt_marker" ]
    marker_holds arming-prompt
}

# A marker that cannot be written costs nothing: the hook's output is
# byte-identical to the one where it was. The first run shows the marker is
# written at all, so the rows after it compare against a real baseline.
@test "inject-checkpoint-root: a marker that cannot be written leaves the output byte-identical" {
    repo="$(make_repo)"
    run_inject_root_ids "$repo" 'handoff-checkpoint <<<"{}"' sess-checkpoint arming-prompt
    [ "$status" -eq 0 ]
    marker_holds arming-prompt
    baseline="$output"
    pointer="$HANDOFF_POINTER_DIR"

    # A parent that is a file: the directory cannot be made.
    printf x > "$BATS_TEST_TMPDIR/not-a-dir"
    HANDOFF_POINTER_DIR="$BATS_TEST_TMPDIR/not-a-dir/pointer" run_inject_root_ids "$repo" 'handoff-checkpoint <<<"{}"' sess-checkpoint arming-prompt
    [ "$status" -eq 0 ]
    [ "$output" = "$baseline" ]

    # A directory open to the group or the world: not used.
    mkdir "$BATS_TEST_TMPDIR/open-dir"; chmod 777 "$BATS_TEST_TMPDIR/open-dir"
    HANDOFF_POINTER_DIR="$BATS_TEST_TMPDIR/open-dir" run_inject_root_ids "$repo" 'handoff-checkpoint <<<"{}"' sess-checkpoint arming-prompt
    [ "$status" -eq 0 ]
    [ "$output" = "$baseline" ]
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/open-dir")" ]

    # A link at the directory: not followed.
    mkdir "$BATS_TEST_TMPDIR/linked-to"
    ln -s "$BATS_TEST_TMPDIR/linked-to" "$BATS_TEST_TMPDIR/linked-dir"
    HANDOFF_POINTER_DIR="$BATS_TEST_TMPDIR/linked-dir" run_inject_root_ids "$repo" 'handoff-checkpoint <<<"{}"' sess-checkpoint arming-prompt
    [ "$status" -eq 0 ]
    [ "$output" = "$baseline" ]
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/linked-to")" ]
    [ "$pointer" = "$HANDOFF_POINTER_DIR" ]
}

# The id is data: a space or a final newline survives the round trip, which a
# `read -r`, a `$(...)` capture or an `echo` would not give.
@test "inject-checkpoint-root: a prompt_id holding a space or ending in a newline round-trips into the marker" {
    repo="$(make_repo)"
    local pid
    for pid in 'two words' $'ends in newline\n' $'inner\nnewline' ' leading and trailing ' $'-n\\n'; do
        run_inject_root_ids "$repo" 'handoff-checkpoint' sess-checkpoint "$pid"
        [ "$status" -eq 0 ]
        marker_holds "$pid"
    done
}

@test "inject-checkpoint-root: hooks.json dispatches PreToolUse(Bash) to it" {
    cmd="$(jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[0].command' "$repo_root/hooks/hooks.json")"
    [[ "$cmd" == *"scripts/inject-checkpoint-root.sh"* ]]
    [ -f "$repo_root/scripts/inject-checkpoint-root.sh" ]
}
