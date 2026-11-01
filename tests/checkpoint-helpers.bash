#!/usr/bin/env bash
# shellcheck disable=SC2034   # SHIM, APPROVED and INJECT_ROOT are read by the files that source this
# Shared by the bats files that test the bash-side neighbors of the checkpoint
# channel (the changelog-archive tag's 2026-08-10 record, "checkpoint.sh and the watcher move to Python"): validate-plugin.bats,
# inject-checkpoint-root.bats and bin-commands.bats. Each `source`s this at its
# top, under the line
# `# shellcheck source-path=SCRIPTDIR source=checkpoint-helpers.bash`
# so that shellcheck follows it, which gives it the shared `setup` and
# `make_repo`. A helper only one of them calls stays in that file.
#
# checkpoint.py's own behavior (schema validation, write semantics,
# sentinel/directive composition) is covered in tests/test_checkpoint_*.py
# (pytest) — see the changelog-archive tag's 2026-07-27 record, "One channel, one writer" for the
# channel's original design.

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
