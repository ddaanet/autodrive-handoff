# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # globals shared with release.sh's shell
#
# Sourced by release.sh, never run on its own. The checks every run makes
# before any side effect: the clean-tree check and its exemptions, the
# push-route refusal, and the MARKETPLACE_DIR checks, gathered in
# common_preflight.
#
# It runs in release.sh's shell, so release.sh's `set -euo pipefail` and its
# die/note helpers apply here, and these functions read and set the run's
# globals (`branch`, `main_branch`, `marketplace_*`, `plugin_name`,
# `clean_specs`, `clean_exempt`) directly rather than through arguments or
# output.

check_marketplace_writable() {
    # bump_marketplace replaces marketplace.json with mktemp + mv, which unlinks
    # and recreates the file in its directory — so probe the directory, not just
    # the file's mode bits. A sandboxed Bash call commonly can't write here.
    # 2>&1, not 2>/dev/null: on failure $probe carries mktemp's own diagnosis
    # (permission denied, read-only file system, no such directory), which is
    # the only thing that distinguishes them. The sandbox line below is advice
    # for the common case, not a cause this probe established.
    local probe
    probe=$(mktemp "$marketplace_dir/.release-writability-check.XXXXXX" 2>&1) \
        || die "$marketplace_dir is not writable: $probe — release needs to replace marketplace.json there. If this is a Claude Code sandbox restriction: add \"just release *\" and \"just resume-release *\" to sandbox.excludedCommands and issue the recipe bare, alone in the Bash call with no 'cd ... &&' prefix and no trailing '; echo' (a compound call stays sandboxed); or run '/add-dir $MARKETPLACE_DIR' first."
    rm -f "$probe"
}

tree_is_clean() {
    # $1=repo root. True when nothing tracked is uncommitted there, ignoring the
    # paths clean_pathspecs exempts.
    clean_pathspecs "$1"
    git -C "$1" diff --quiet HEAD -- "${clean_specs[@]}"
}

clean_pathspecs() {
    # $1=repo root. Sets two globals describing the check tree_is_clean applies
    # there: $clean_specs, the pathspecs, and $clean_exempt, the same set in the
    # words report_dirty prints. They are built together so a refusal names the
    # exemptions that were actually applied rather than a list written from
    # memory — a consumer whose vendored plugin-dev/ predates one of them would
    # otherwise be told about an exclusion its own copy does not make.
    #
    # One path is exempt, a gitlore-mounted memory submodule: its gitlink sits
    # ahead of what HEAD records between commits by design — gitlore's own
    # pre-commit hook folds that in on the next commit, not this one.
    #
    # The mount path is read from .gitmodules rather than assumed to be
    # `memory`: that is only gitlore's default, the path being $1 to gitlore's
    # install.sh. Keyed on the submodule NAME, which gitlore fixes, not its url
    # — git absolutises a relative url on the way into .git/config, so a url
    # only ever matches .gitmodules itself. `--get` of a single key returns the
    # value whole, so a path containing spaces needs no -z splitting.
    #
    # Deliberately this narrow. A consumer that vendors some other submodule
    # and forgets to commit its moved gitlink should be refused, so
    # `--ignore-submodules=all` is not the shortcut it looks like.
    local dir="$1" mem=""
    clean_specs=(.)
    clean_exempt=()
    if [ -f "$dir/.gitmodules" ]; then
        mem=$(git config -f "$dir/.gitmodules" --get submodule.gitlore-memory.path) || mem=""
    fi
    if [ -n "$mem" ]; then
        clean_specs+=(":(exclude)$mem")
        clean_exempt+=("$mem/ — the gitlore memory submodule, whose gitlink the next commit folds in")
    fi
}

report_dirty() {
    # $1=repo root, $2=what to call it in the message. Prints what made it
    # dirty, then any exemptions that did not save it. Callers add the
    # site-specific consequence and next command, then die.
    #
    # -z / read -d '': a path containing a space is one path, and a word-split
    # read of --name-only would report it as several. A path containing a
    # newline still prints across two lines — git has no quoting mode that
    # survives -z — which is the residual bound here.
    local dir="$1" label="$2" p
    clean_pathspecs "$dir"
    printf 'hint: these tracked paths in %s differ from HEAD:\n' "$label" >&2
    while IFS= read -r -d '' p; do
        printf '        %s\n' "$p" >&2
    done < <(git -C "$dir" diff -z --name-only HEAD -- "${clean_specs[@]}")
    if [ "${#clean_exempt[@]}" -gt 0 ]; then
        printf '      exempt from this check, and so not among the paths above:\n' >&2
        for p in "${clean_exempt[@]}"; do
            printf '        %s\n' "$p" >&2
        done
    fi
}

common_preflight() {
    [ -f "$manifest" ] || die "$manifest not found — run from the plugin root"
    tree_is_clean "." || {
        report_dirty "." "the plugin repo"
        printf '      commit or stash them, then run the same command again. the release\n' >&2
        printf '      commit must be the only thing this run lands.\n' >&2
        die "uncommitted changes"
    }
    branch=$(git symbolic-ref -q --short HEAD || echo "")
    # Use symbolic-ref (not rev-parse): when origin/HEAD is unset, rev-parse
    # exits non-zero AND prints "origin/HEAD" to stdout, so the substitution
    # captures both the failed output and the fallback.
    main_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo "main")
    # A release runs from the main branch or from dev. A detached HEAD has no
    # branch name to print.
    case "$branch" in
        "$main_branch"|dev) ;;
        *) die "must be on $main_branch or dev (currently ${branch:-a detached HEAD})" ;;
    esac

    # remote.origin.pushurl sends `git push origin <tag>` (push_tag) and every
    # `git push origin <refspec>` this script runs (push_branch, push_dist) to a
    # repository other than origin, where none of the origin probes look. Refuse
    # before any side effect, in both `release` and `--resume` modes (common_preflight
    # runs in both).
    #
    # branch.<b>.pushRemote and remote.pushDefault are not checked: each picks the
    # remote for an unqualified `git push`, and the release runs none: every push,
    # the marketplace bump's included, names origin and a refspec, which ignores
    # both (measured), so they cannot move a release.
    #
    # Refuse when the key is SET, not when it diverges from origin: comparing URLs
    # for repository identity (scp-style, https and ssh spellings of one repository)
    # is not decidable in shell without a network round trip on the common path. The
    # recovery, unset it or point it at origin, covers a same-repo pushurl on another
    # protocol too.
    #
    # url.<base>.pushInsteadOf is a route NOT checked, a stated bound recorded in
    # docs/references/recovery.md. A global insteadOf rewrite is ordinary, unlike a
    # repo-scoped key whose presence is itself the anomaly; plain url.<base>.insteadOf
    # needs no check, since it rewrites fetch and push alike.
    #
    # `--get-all`, not `--get`: pushurl is multi-valued (pushing to several mirrors is
    # a supported arrangement), and `--get` prints only the last value and still exits
    # 0 (measured, git 2.47.3). `--get-all` still exits 1 when the key is unset, the
    # one status absorbed below. Values print one per line, so a value with a space
    # does not read as two; a value holding a newline still prints across two lines,
    # the residual bound report_dirty records.
    #
    # The assignment is the `if` condition, which keeps it outside errexit's
    # suppression natively. `$?` in the `elif` is still the failed condition's status:
    # exit 2 and exit 128 both reach the `elif` body, exit 1 does not (measured).
    local push_values push_value
    if push_values=$(git config --get-all remote.origin.pushurl); then
        printf 'hint: remote.origin.pushurl is set to:\n' >&2
        while IFS= read -r push_value; do
            printf '        %s\n' "$push_value" >&2
        done <<<"$push_values"
        printf '      unset it (git config --unset-all remote.origin.pushurl) or point it at\n' >&2
        printf '      origin, then run the same command again.\n' >&2
        die "push route diverges from origin: remote.origin.pushurl is set"
    elif [ "$?" -ne 1 ]; then
        die "could not read git config remote.origin.pushurl"
    fi

    [ -n "${MARKETPLACE_DIR:-}" ] \
        || die "MARKETPLACE_DIR not set (set in .envrc to the claude-plugins repo root)"
    marketplace_json="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
    [ -f "$marketplace_json" ] || die "$marketplace_json not found"
    # A detached HEAD there is only discovered by the marketplace push, which
    # runs after the plugin's commit, tag, tag push and GitHub release are all
    # public. Catch it here instead, with the other MARKETPLACE_DIR checks.
    git -C "$MARKETPLACE_DIR" symbolic-ref -q --short HEAD >/dev/null \
        || die "$MARKETPLACE_DIR is on a detached HEAD — check out its branch first"
    marketplace_dir=$(dirname "$marketplace_json")
    # A release that bumps goes to a version the marketplace doesn't have yet,
    # so the write is never a no-op — check fails fast here, before the tag and
    # the GitHub release. One release does not: a first release whose entry
    # already exists, since check-version.sh has by then required that entry to
    # equal the manifest and a first release publishes the manifest version
    # as-is, leaving bump_marketplace nothing to write. It is checked here all
    # the same — which of the two applies is only settled in release_preflight,
    # after this runs — so that state is refused for a writability it would not
    # have used. A resume may likewise find the marketplace already correct
    # (a true no-op bump_marketplace can skip entirely); its own writability
    # need is checked there, only when a write actually happens.
    # Keep this off the last line of the function: a false `&&` list is exempt
    # from errexit mid-function, but as the final command its status becomes the
    # function's, and `common_preflight` would exit 1 with no message on resume.
    [ "$mode" = "release" ] && check_marketplace_writable
    # `.name // empty`, not `.name`: a manifest without one would print the
    # literal `null`, and the marketplace lookup below would then create an
    # entry called "null" after the release was already public.
    plugin_name=$(jq -r '.name // empty' "$manifest")
    [ -n "$plugin_name" ] || die "$manifest has no .name — nothing was done"
    # A missing entry is not an error: on first publication we create one from
    # plugin.json. Synthesising its `source` needs an `origin` remote to derive
    # owner/repo from, so validate that here, before any destructive op.
    #
    # `jq -e` returns 1 for a clean no-match and non-1 (5, measured against
    # jq 1.7) for a parse error — the `elif` is what tells them apart. The old
    # two-branch `if` read a parse error as "no entry" the same as a genuine
    # absence, which in `release` mode was only ever caught downstream, by
    # check-version.sh, with an unrelated "version drift" message. In
    # `--resume` mode nothing downstream reads this file at all until
    # bump_marketplace: release_preflight never runs on resume — the mode
    # dispatch at the foot of release.sh takes the `else resume_preflight`
    # branch — so the misread survived common_preflight
    # untouched and the run reached create_github_release — a GitHub release
    # made public — before bump_marketplace's own jq call finally aborted the
    # script with a raw parse error instead of a `die`.
    if jq -e --arg n "$plugin_name" 'any(.plugins[]; .name == $n)' "$marketplace_json" >/dev/null; then
        marketplace_entry_exists=1
    elif [ "$?" -ne 1 ]; then
        die "could not read $marketplace_json — nothing was done"
    else
        marketplace_entry_exists=0
        git remote get-url origin >/dev/null 2>&1 \
            || die "'$plugin_name' has no entry in $marketplace_json and no 'origin' remote to derive one from"
    fi
    # This refusal costs more than the plugin-repo one. The marketplace bump is
    # the last step of a release and its only write outside the plugin repo, so
    # a run that already reached it — and staged the bump before its commit was
    # refused — has everything before it public. That state reads here as an
    # unrelated dirty file, and stops the very command that would finish the
    # release. Say so, and name it.
    tree_is_clean "$MARKETPLACE_DIR" || {
        report_dirty "$MARKETPLACE_DIR" "$MARKETPLACE_DIR"
        printf '      the marketplace bump is the last step of a release and its only write\n' >&2
        printf '      outside the plugin repo, so a run refused here may have left the version\n' >&2
        printf '      commit, tag, branch push and GitHub release already public.\n' >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      commit or stash the paths above in that repo, then run `just resume-release`\n' >&2
        printf '      to finish a release that got that far — or the same command again if the\n' >&2
        printf '      tag for the version being released does not exist yet.\n' >&2
        die "$MARKETPLACE_DIR has uncommitted changes"
    }
}

branch_preflight() {
    # Release mode only, after release_preflight and before any side effect, so a
    # refusal leaves no commit and no tag. `--no-tags` because this fetch reads one
    # thing, origin's main: a tag that arrived after release_preflight chose the
    # version would meet bump_commit_tag only once the release commit exists.
    git fetch --no-tags -q origin \
        || die "could not fetch origin — nothing was done"
    # Refs named in full: a bare name resolves a tag of the same name first. A
    # clone with no local main skips its check, since move_main creates it.
    if git rev-parse -q --verify "refs/heads/$main_branch" >/dev/null \
        && ! is_ancestor "refs/heads/$main_branch" HEAD; then
        printf 'hint: local %s has commits %s lacks. Merge it first:\n' "$main_branch" "$branch" >&2
        printf '      git merge %s\n' "$main_branch" >&2
        printf '      then run the same command again.\n' >&2
        die "local $main_branch is not an ancestor of $branch — nothing was done"
    fi
    if git rev-parse -q --verify "refs/remotes/origin/$main_branch" >/dev/null; then
        if ! is_ancestor "refs/remotes/origin/$main_branch" HEAD; then
            printf 'hint: origin/%s has commits %s lacks. Merge it first:\n' "$main_branch" "$branch" >&2
            printf '      git merge origin/%s\n' "$main_branch" >&2
            printf '      then run the same command again.\n' >&2
            die "origin/$main_branch is not an ancestor of $branch — nothing was done"
        fi
    else
        note "origin has no $main_branch branch, so there is nothing on origin to compare $branch with"
    fi
    # move_main later fast-forwards local main with a fetch into the ref, which git
    # 2.35 and later refuse while another worktree holds it — after the release
    # commit and tag exist. An older git does not refuse, so neither this probe
    # nor move_main stops it. Run the same fetch now as a no-op (main is an
    # ancestor of HEAD, so it moves nothing) and let git apply its own rule: it
    # also refuses a main held by a worktree mid-rebase: a state a parse of
    # `git worktree list` would miss. git's `fatal:` line stays visible because
    # it names the worktree. Not needed on main itself: move_main moves nothing
    # there.
    if [ "$branch" != "$main_branch" ] \
        && git rev-parse -q --verify "refs/heads/$main_branch" >/dev/null \
        && ! git fetch -q . "refs/heads/$main_branch:refs/heads/$main_branch"; then
        printf 'hint: git refuses to move %s while the worktree named above holds it.\n' "$main_branch" >&2
        printf '      free %s in that worktree; to see its state, run:\n' "$main_branch" >&2
        printf '      git worktree list\n' >&2
        printf '      then run the same command again.\n' >&2
        die "$main_branch is held by another worktree — nothing was done"
    fi
}

is_ancestor() {
    # $1 $2: `git merge-base --is-ancestor`, but only its exit 1 means "not an
    # ancestor"; any other failure (an unreadable ref, a corrupt object) dies
    # rather than reading as a refusal with a hint that cannot clear it.
    local rc=0
    git merge-base --is-ancestor "$1" "$2" || rc=$?
    [ "$rc" -le 1 ] || die "could not compare $1 with $2 (git exit $rc) — nothing was done"
    return "$rc"
}
