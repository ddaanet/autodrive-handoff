#!/usr/bin/env bash
# Shared synthetic-repo builder for tests/checkpoint.bats's shim test — the
# one row left there that needs a gitlore-managed repo with dirty memory.
# checkpoint.py's own memory-directive tests (schema, composition, ledger
# liveness) moved to tests/test_checkpoint_*.py, which share their own Python
# equivalents of these builders through tests/conftest.py — see
# docs/changelog/2026-08-10-python-split.md.

# git without its repository-local variables (`git rev-parse --local-env-vars`,
# a superset of GIT_DIR, GIT_INDEX_FILE and GIT_WORK_TREE). Gitlore's
# pre-commit hook exports those for the outer repository and `just precommit`
# runs inside it, so a plain `git` here would act on that repository instead of
# the one a test built. Every git call in tests/*.bats and tests/*.bash goes
# through this; the pytest equivalent is run_git in tests/conftest.py.
run_git() {
    local -a unset_args=()
    local name
    while IFS= read -r name; do
        [ -n "$name" ] && unset_args+=(-u "$name")
    done < <(git rev-parse --local-env-vars)
    env ${unset_args[@]+"${unset_args[@]}"} git "$@"
}

# A gitlore-managed repo: a .gitmodules registration for the gitlore-memory
# submodule (the FR12 activation gate) plus a nested memory git repo holding
# one committed file, and an empty .claude/ (checkpoint.py's write target).
# Clean by default — dirty it by writing into memory/. Echoes the repo path.
make_gitlore_repo() {
    local repo="${1:-$BATS_TEST_TMPDIR/glrepo}"
    rm -rf "$repo"; mkdir -p "$repo/memory" "$repo/.claude"
    run_git -C "$repo" init -q
    cat > "$repo/.gitmodules" <<'EOF'
[submodule "gitlore-memory"]
	path = memory
	url = ./memory
EOF
    run_git -C "$repo/memory" init -q
    echo "seed" > "$repo/memory/seed.md"
    run_git -C "$repo/memory" add -A
    run_git -C "$repo/memory" -c user.email=t@t -c user.name=t commit -qm seed
    # gitlore.memoryApprovalClauseFile: what a real gitlore SessionStart would
    # have seeded/re-pinned this session.
    printf '%s\n' "a stand-in approval clause" > "$repo/.gitlore-memory-approval-clause.txt"
    run_git -C "$repo" config gitlore.memoryApprovalClauseFile "$repo/.gitlore-memory-approval-clause.txt"
    printf '%s\n' "$repo"
}

# Dirty the memory submodule of $1 so the memory directive fires.
dirty_memory() {
    echo "new entry" > "$1/memory/feedback_x.md"
}
