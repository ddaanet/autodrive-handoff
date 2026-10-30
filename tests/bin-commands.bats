#!/usr/bin/env bats
# shellcheck disable=SC2154   # $stderr is set by bats `run --separate-stderr`
# shellcheck disable=SC2119   # make_repo (checkpoint-helpers.bash) takes an optional path; no row here passes one
# shellcheck source-path=SCRIPTDIR source=checkpoint-helpers.bash
source "$BATS_TEST_DIRNAME/checkpoint-helpers.bash"

# Tests for bin/handoff-approved (the one command that leaves a `held`
# sentinel) and bin/handoff-checkpoint (the shim), two of the bash-side
# neighbors of the checkpoint channel that stayed bash in the Python split
# (docs/changelog/2026-08-10-python-split.md). The harness row, which checks
# make_repo and make_gitlore_repo, is here because the shim row is where
# make_gitlore_repo is used. The helpers shared with
# tests/validate-plugin.bats and tests/inject-checkpoint-root.bats are in
# tests/checkpoint-helpers.bash.
#
# Run with: bats tests/bin-commands.bats   (from plugin root)

bats_require_minimum_version 1.5.0

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
    wait_until_blocked
    printf '%s\n' "held sess-someone-else" clear "/rename A Title" /clear \
        > "$repo/.claude/autodrive"
    release_drive_lock
    approved_rc=0
    wait "$approved_pid" || approved_rc=$?
    [ "$approved_rc" -eq 2 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/approved.out")" == *"session"* ]]
    [ "$(head -n1 "$repo/.claude/autodrive")" = "held sess-someone-else" ]
}

# The bound fails closed: the lock is held for the whole run (and the holder is
# killed afterwards, no sleep), the wait is tiny, and the approval arms nothing,
# exits 2 naming the lock and leaves the held file as it was.
@test "handoff-approved: the lock is held past the wait -> exit 2 naming the lock, the held file untouched" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" clear "/rename A Title" /clear \
        "pick up per the task file" > "$repo/.claude/autodrive"
    cp "$repo/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    hold_drive_lock "$repo"
    HANDOFF_LOCK_WAIT_SECS=0.05 run_approved "$repo"
    release_drive_lock
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"the sentinel's lock was busy"* ]]
    [[ "$output" != *"armed"* ]]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$repo/.claude/autodrive"
}

@test "handoff-approved: a link at the lock -> exit 2 saying it could not be set up, the held file untouched" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" clear "/rename A Title" /clear \
        "pick up per the task file" > "$repo/.claude/autodrive"
    cp "$repo/.claude/autodrive" "$BATS_TEST_TMPDIR/sentinel.before"
    : > "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$repo/.claude/autodrive.lock"
    run_approved "$repo"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"the sentinel's lock could not be set up"* ]]
    cmp "$BATS_TEST_TMPDIR/sentinel.before" "$repo/.claude/autodrive"
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
    # The lock's helper still runs (a lock that cannot be set up fails closed
    # before the read, and has its own row); every other python3 call fails.
    real_python="$(command -v python3)"
    printf '#!/usr/bin/env bash\ncase "$*" in *_drive_lock.py*) exec "%s" "$@" ;; esac\nexit 97\n' "$real_python" > "$stub/python3"
    chmod +x "$stub/python3"
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
    echo "$output" | grep -qF "gitlore:commit"
}

@test "shim: bin/handoff-checkpoint surfaces a schema violation" {
    repo="$(make_repo)"
    # shellcheck disable=SC2016   # $1/$2/$3 are the inner bash -c's own positional params
    run --separate-stderr -2 bash -c 'cd "$1" && HANDOFF_ROOT="$1" "$2" <<<"$3"' \
        _ "$repo" "$SHIM" '{"commit":"with-commit"}'
    [[ "$stderr" == *"skill"* ]]
}
