#!/usr/bin/env bats
# Tests for the bash-side neighbors of the checkpoint channel that stayed
# bash in the Python split (docs/changelog/2026-08-10-python-split.md):
# scripts/inject-checkpoint-root.sh (PreToolUse(Bash) root injection),
# bin/handoff-approved (the one command that leaves a `held` sentinel) and
# bin/handoff-checkpoint (the shim).
#
# checkpoint.py's own behavior (schema validation, write semantics,
# sentinel/directive composition) is covered in
# tests/test_checkpoint_*.py (pytest) — see docs/changelog/2026-07-27-one-channel-one-writer.md
# for the channel's original design and docs/changelog/2026-08-10-python-split.md
# for what moved.
#
# Run with: bats tests/checkpoint.bats   (from plugin root)

# shellcheck disable=SC2154   # $stderr is set by bats `run --separate-stderr`
bats_require_minimum_version 1.5.0

setup() {
    repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SHIM="$repo_root/bin/handoff-checkpoint"
    APPROVED="$repo_root/bin/handoff-approved"
    INJECT_ROOT="$repo_root/scripts/inject-checkpoint-root.sh"
    load probe-helpers
    load lock-helpers

    export CLAUDE_CODE_SESSION_ID="sess-checkpoint"

    # The prompt marker's directory (/tmp/claude in production); redirect it, or
    # the suite writes into the runner's own real one.
    export HANDOFF_POINTER_DIR="$BATS_TEST_TMPDIR/pointer"

    # For asserting that what handoff-approved writes is what a loader will
    # accept, and for handoff_drive_read itself in the tests below.
    # shellcheck source-path=SCRIPTDIR source=../scripts/_lib.sh disable=SC1091
    source "$repo_root/scripts/_lib.sh"
}

# A plain git repo with .claude/ present.
make_repo() {
    local repo="${1:-$BATS_TEST_TMPDIR/repo}"
    rm -rf "$repo"; mkdir -p "$repo/.claude"
    run_git -C "$repo" init -q
    printf '%s\n' "$repo"
}

# Gitlore's pre-commit hook runs `just precommit` with GIT_DIR, GIT_INDEX_FILE
# and GIT_WORK_TREE exported for the outer repository; a git call here that
# inherits them acts on that repository. A decoy repository stands in for it.
# The pytest twin is in tests/test_checkpoint_directives.py.
export_decoy_git_env() {
    decoy="$BATS_TEST_TMPDIR/decoy"
    mkdir -p "$decoy"
    run_git -C "$decoy" init -q
    echo decoy > "$decoy/tracked.txt"
    run_git -C "$decoy" add tracked.txt
    export GIT_DIR="$decoy/.git" GIT_WORK_TREE="$decoy" GIT_INDEX_FILE="$decoy/.git/index"
}

# Every file under the decoy's .git, named and checksummed.
decoy_snapshot() {
    (cd "$decoy/.git" && find . -type f -print0 | sort -z | xargs -0 cksum)
}

@test "harness: make_repo and make_gitlore_repo act on the repository they build, whatever git's environment" {
    export_decoy_git_env
    before="$(decoy_snapshot)"
    repo="$(make_repo)"
    glrepo="$(make_gitlore_repo)"
    [ "$(decoy_snapshot)" = "$before" ]
    [ -d "$repo/.git" ]
    [ -d "$glrepo/.git" ]
    [ -d "$glrepo/memory/.git" ]
    # The seed commit landed in the built memory repo, not the decoy.
    [ "$(run_git -C "$glrepo/memory" log --format=%s)" = "seed" ]
    [ -n "$(run_git -C "$glrepo" config gitlore.memoryApprovalClauseFile)" ]
}

# ==========================================================================
# justfile validate-plugin — the two exceptions to `claude plugin validate
# --strict` are scoped to the entry (file) they name. `claude` is a stub on
# PATH that prints a fixture and ignores its arguments, so the recipe's jq
# gate is the only thing under test; the fixture's `file` paths are absolute
# under the root the recipe runs in, as the real validator's are.
# ==========================================================================

# validate_entry <file> <path> <message> [errors|warnings]: one validator
# entry carrying one finding, in the list named by the last argument.
validate_entry() {
    jq -nc --arg file "$1" --arg path "$2" --arg msg "$3" --arg list "${4:-errors}" \
        '{file:$file, type:"x", errors:[], warnings:[], notes:[], gatingHooks:[]}
         | .[$list] = [{path:$path, message:$msg, code:null}]'
}

# The validator's own wording for the two findings.
mcp_syntax_entry() {
    validate_entry "$1" json 'Invalid JSON syntax: JSON Parse error: Unexpected EOF. The plugin loader logs this at debug level and loads no servers from the file.'
}
claude_md_entry() {
    validate_entry "$1" root 'CLAUDE.md at the plugin root is not loaded as project context. To ship context with your plugin, use a skill (skills/<name>/SKILL.md) instead.' warnings
}

# physical_dir <path> — make the directory and print its physical path. The
# validator's entries carry physical paths (checked against the real one: `claude
# plugin validate .` reports the realpath of the directory it runs in), and
# $BATS_TEST_TMPDIR is not one where /var is a link, as on macOS.
physical_dir() {
    mkdir -p "$1" && (cd "$1" && pwd -P)
}

# validate_run <root> <entry>...: a stub `claude` printing the fixture (an
# empty manifest plus the entries), then the real recipe with <root> as its
# working directory (or $VALIDATE_CWD, a path that reaches it). Sets $status and
# $output.
validate_run() {
    local root="$1" entries; shift
    entries="$(IFS=,; echo "$*")"
    mkdir -p "$root" "$BATS_TEST_TMPDIR/stubbin"
    jq -nc --arg root "$root" --argjson entries "[$entries]" \
        '{manifest:{file:($root + "/.claude-plugin/plugin.json"), type:"manifest", errors:[], warnings:[], notes:[], gatingHooks:[]}, contents:$entries}' \
        > "$BATS_TEST_TMPDIR/fixture.json"
    cat > "$BATS_TEST_TMPDIR/stubbin/claude" <<'STUB'
#!/bin/sh
cat "$FIXTURE"
STUB
    chmod +x "$BATS_TEST_TMPDIR/stubbin/claude"
    FIXTURE="$BATS_TEST_TMPDIR/fixture.json" PATH="$BATS_TEST_TMPDIR/stubbin:$PATH" \
        PWD="${VALIDATE_CWD:-$root}" run just --justfile "$repo_root/justfile" --working-directory "${VALIDATE_CWD:-$root}" validate-plugin
}

@test "validate-plugin: an empty .mcp.json's syntax error and the CLAUDE.md warning pass" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -eq 0 ]
}

@test "validate-plugin: a root path holding a space passes the same fixture" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/my plugin dir")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -eq 0 ]
}

# The recipe runs the validator on `.`, which reports the physical path of the
# directory, so a working directory reached through a link still matches. The
# recipe's shell inherits the link as its $PWD, as it does from a user who cd'd
# through one, so a plain `pwd` there would name the link.
@test "validate-plugin: a working directory reached through a symlink passes with the validator's physical paths" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    ln -s "$root" "$BATS_TEST_TMPDIR/plugin-link"
    VALIDATE_CWD="$BATS_TEST_TMPDIR/plugin-link" \
        validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -eq 0 ]
}

@test "validate-plugin: the same syntax error on hooks.json fails beside an empty .mcp.json" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" \
        "$(mcp_syntax_entry "$root/hooks/hooks.json")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: the syntax error on a non-empty .mcp.json fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; echo '{' > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: the syntax error with no .mcp.json at all fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: the CLAUDE.md warning on another entry's file fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/skills/x/SKILL.md")" "$(mcp_syntax_entry "$root/.mcp.json")"
    [ "$status" -ne 0 ]
}

@test "validate-plugin: an unrelated finding on an exempt file still fails" {
    root="$(physical_dir "$BATS_TEST_TMPDIR/plugin")"; : > "$root/.mcp.json"
    validate_run "$root" "$(claude_md_entry "$root/CLAUDE.md")" \
        "$(validate_entry "$root/.mcp.json" servers 'bad server')"
    [ "$status" -ne 0 ]
}

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

# ==========================================================================
# bin/handoff-approved — the one command that leaves `held`
# ==========================================================================

# Run it with cwd = $1 and HANDOFF_ROOT = $2 (default $1). Invoked through
# its own path here; the bare-name row below is what covers the invocation path.
run_approved() {
    local repo="$1" root="${2:-$1}"
    # shellcheck disable=SC2016   # $1/$2/$3 are the inner bash -c's own positional params
    run --separate-stderr bash -c 'cd "$1" && HANDOFF_ROOT="$2" bash "$3"' _ "$repo" "$root" "$APPROVED"
}

@test "handoff-approved: a held sentinel becomes armed, every line below preserved" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" clear "/rename A Title" /clear \
        "pick up per the task file" > "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/.claude/autodrive")" = "armed $CLAUDE_CODE_SESSION_ID
clear
/rename A Title
/clear
pick up per the task file" ]
}

# The sentinel's lock. Another actor holds it, an approval starts and has to
# wait, and a checkpoint of another session replaces the held file under the
# lock. The approval must then judge that file: an unlocked one has already read
# the first and armed it.
@test "handoff-approved: the held file is replaced while the approval waits on the lock -> it judges the new file, exit 2" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" clear "/rename A Title" /clear \
        "pick up per the task file" > "$repo/.claude/autodrive"
    hold_drive_lock "$repo"
    (cd "$repo" && HANDOFF_ROOT="$repo" HANDOFF_LOCK_WAIT_SECS=30 bash "$APPROVED") \
        > "$BATS_TEST_TMPDIR/approved.out" 2>&1 3>&- &
    approved_pid=$!
    wait_until_blocked "$approved_pid"
    printf '%s\n' "held sess-someone-else" clear "/rename A Title" /clear \
        > "$repo/.claude/autodrive"
    release_drive_lock
    approved_rc=0
    wait "$approved_pid" || approved_rc=$?
    [ "$approved_rc" -eq 2 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/approved.out")" == *"session"* ]]
    [ "$(head -n1 "$repo/.claude/autodrive")" = "held sess-someone-else" ]
}

# The approval this command speaks for is the one *this* session was asked for.
# A held file another session left behind waits on an answer that can no longer
# arrive, and arming it drives that session's /rename and /clear into this
# conversation — so the state alone is not enough to act on.
@test "handoff-approved: a held sentinel from another session -> exit 2, left held" {
    repo="$(make_repo)"
    printf '%s\n' "held sess-someone-else" clear "/rename A Title" /clear \
        > "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"session"* ]]
    [ "$(head -n1 "$repo/.claude/autodrive")" = "held sess-someone-else" ]
}

@test "handoff-approved: no sentinel -> exit 2 naming the absence" {
    repo="$(make_repo)"
    run_approved "$repo"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"autodrive"* ]]
}

# Already armed: this turn's Stop will fire it, and rewriting the state would
# say the approval released something it did not.
@test "handoff-approved: an armed sentinel -> exit 2 naming the state it found" {
    repo="$(make_repo)"
    printf '%s\n' "armed $CLAUDE_CODE_SESSION_ID" clear "/rename A Title" /clear \
        > "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"armed"* ]]
    [ "$(head -n1 "$repo/.claude/autodrive")" = "armed $CLAUDE_CODE_SESSION_ID" ]
}

# Armed through a link, the approval would rewrite whatever file it names.
@test "handoff-approved: the sentinel is a symlink to a held file -> exit 2, target untouched" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" compact "/compact" > "$BATS_TEST_TMPDIR/linked"
    ln -s "$BATS_TEST_TMPDIR/linked" "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"symbolic link"* ]]
    [ "$(head -n1 "$BATS_TEST_TMPDIR/linked")" = "held $CLAUDE_CODE_SESSION_ID" ]
    [ -L "$repo/.claude/autodrive" ]
}

# A reader that could not run says nothing about the file: it is reported as
# unreadable, not malformed, and left where it is.
@test "handoff-approved: the reader helper failing -> exit 2 saying it could not be read, file kept" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" compact "/compact" > "$repo/.claude/autodrive"
    stub="$BATS_TEST_TMPDIR/broken-python"; mkdir -p "$stub"
    printf '#!/usr/bin/env bash\nexit 97\n' > "$stub/python3"; chmod +x "$stub/python3"
    # shellcheck disable=SC2016   # $1/$2/$3 are the inner bash -c's own positional params
    run --separate-stderr bash -c 'cd "$1" && PATH="$2:$PATH" HANDOFF_ROOT="$1" bash "$3"' _ "$repo" "$stub" "$APPROVED"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"could not be read"* ]]
    [[ "$stderr" != *"malformed"* ]]
    [ "$(head -n1 "$repo/.claude/autodrive")" = "held $CLAUDE_CODE_SESSION_ID" ]
}

@test "handoff-approved: HANDOFF_ROOT unset -> refuses, naming the unrecognised invocation" {
    repo="$(make_repo)"
    # shellcheck disable=SC2016   # $1/$2 are the inner bash -c's own positional params
    run --separate-stderr bash -c 'cd "$1" && unset HANDOFF_ROOT; bash "$2"' _ "$repo" "$APPROVED"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"HANDOFF_ROOT"* ]]
}

# The invocation path: the agent runs this by bare name off PATH, so a
# non-executable entry point is a failure every other row here would miss.
@test "handoff-approved: runs by bare name off PATH" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" compact "/compact" \
        > "$repo/.claude/autodrive"
    run bash -c 'cd "$1" && PATH="$2:$PATH" HANDOFF_ROOT="$1" handoff-approved' _ "$repo" "$repo_root/bin"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$repo/.claude/autodrive")" = "armed $CLAUDE_CODE_SESSION_ID" ]
}

# After arming, handoff-approved prints the status fact, a blank line, then the
# closing line for the kind. The closing line is literal in the script and
# composed by closing_directive() in scripts/_checkpoint_lib.py for the
# checkpoint's own path; these rows are what keeps the two producers from
# drifting. Both sides pass through `$(...)`, so trailing newlines are the one
# difference they cannot see.
expected_closing() {
    local skill="$1" typed="$2"
    PYTHONPATH="$repo_root/scripts" python3 -c "
from _checkpoint_lib import closing_directive
print(closing_directive('$skill', typed=$typed), end='')
"
}

@test "handoff-approved: status fact, blank line, the checkpoint's closing line — rename" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" rename "/rename A Title" \
        > "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 0 ]
    expected="$(expected_closing handoff False)"
    [ -n "$expected" ]
    [ "$output" = "handoff: rename armed; it runs at the end of this turn."$'\n\n'"$expected" ]
}

@test "handoff-approved: status fact, blank line, the checkpoint's closing line — clear" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" clear "/rename A Title" /clear \
        > "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 0 ]
    expected="$(expected_closing handoff True)"
    [ -n "$expected" ]
    [ "$output" = "handoff: clear armed; it runs at the end of this turn."$'\n\n'"$expected" ]
}

@test "handoff-approved: status fact, blank line, the checkpoint's closing line — compact" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" compact "/compact" \
        > "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 0 ]
    expected="$(expected_closing precompact True)"
    [ -n "$expected" ]
    [ "$output" = "handoff: compact armed; it runs at the end of this turn."$'\n\n'"$expected" ]
}

# ==========================================================================
# shim (bin/handoff-checkpoint)
# ==========================================================================

# The union's spelling, hardcoded outside the Python factories: keep in step
# with task_clear()/todo_keep() in tests/conftest.py.
handoff_payload() {
    jq -nc --arg commit "$1" '{skill:"handoff", commit:$commit, rename:"Session Title", clear:false, continue:false, task:{action:"clear"}, todo:{action:"keep"}}'
}

@test "shim: bin/handoff-checkpoint execs the checkpoint, forwards stdin" {
    repo="$(make_gitlore_repo)"
    dirty_memory "$repo"
    run bash -c 'cd "$1" && HANDOFF_ROOT="$1" "$2" <<<"$3"' \
        _ "$repo" "$SHIM" "$(handoff_payload without-commit)"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "$repo/.claude/gitlore-commit-memory"
}

@test "shim: bin/handoff-checkpoint surfaces a schema violation" {
    repo="$(make_repo)"
    # shellcheck disable=SC2016   # $1/$2/$3 are the inner bash -c's own positional params
    run --separate-stderr -2 bash -c 'cd "$1" && HANDOFF_ROOT="$1" "$2" <<<"$3"' \
        _ "$repo" "$SHIM" '{"commit":"with-commit"}'
    [[ "$stderr" == *"skill"* ]]
}
