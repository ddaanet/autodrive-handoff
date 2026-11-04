#!/usr/bin/env bash
# shellcheck disable=SC2154   # $tmp, $prompt_marker and $repo_root are set by the file that sources or loads this
# Helpers shared by bats files whose setup is not common: drive-take.bats and
# drive-cancel.bats (`load shared-helpers` in their setup),
# inject-checkpoint-root.bats and hook-helpers.bash (each `source`s this at its
# top, under a `# shellcheck source-path=SCRIPTDIR source=shared-helpers.bash`
# line).
# Each caller defines `prompt_marker` itself, since its value differs per file.

# Build a fake linked git worktree of $tmp under $BATS_TEST_TMPDIR/$name and
# echo its path. Its .git is a *file* pointing under $tmp/.git/worktrees/$name,
# mirroring real git worktree layout. $tmp is CLAUDE_PROJECT_DIR (set in setup).
make_worktree() {
    local name="${1:-wt}"
    local wt="$BATS_TEST_TMPDIR/$name"
    mkdir -p "$wt/.claude" "$tmp/.git/worktrees/$name"
    printf 'gitdir: %s\n' "$tmp/.git/worktrees/$name" > "$wt/.git"
    printf '%s\n' "$wt"
}

# <prompt_id> [<path>] — the marker holds the id and its NUL, exactly.
marker_holds() {
    cmp -s "${2-$HANDOFF_POINTER_DIR/$prompt_marker}" <(printf '%s\0' "$1")
}

# The continuation line's one definition, HANDOFF_CONTINUATION in
# scripts/_lib_drive.sh, so no row retypes it. Needs $repo_root, set in the
# caller's setup.
continuation_line() {
    bash -c 'source "$1/scripts/_lib.sh" && printf "%s\n" "$HANDOFF_CONTINUATION"' _ "$repo_root"
}
