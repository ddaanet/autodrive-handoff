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
    [ "$branch" = "$main_branch" ] || die "must be on $main_branch (currently $branch)"

    # A push redirected away from origin makes
    # push_branch's unqualified `git push` and/or push_tag's
    # `git push origin <tag>` — redirected only by pushurl — land somewhere the
    # origin-tag probes below never inspect. Refuse before any side effect,
    # here, in both `release` and `--resume` modes (common_preflight runs in
    # both).
    #
    # Refuse when any of the three is SET, not when it "diverges" from origin:
    # comparing URLs for repository identity (git@host:o/p.git vs
    # https://host/o/p vs ssh://host/o/p vs an insteadOf rewrite, all one
    # repository) is not decidable in shell without a network round trip on
    # the common path. The recovery — unset it, or point it at origin — covers
    # a same-repo pushurl on a different protocol too.
    #
    # url.<base>.pushInsteadOf is a fourth route and is NOT checked — a stated
    # bound, recorded in the toolkit repo's docs/references/recovery.md. Set, it
    # sends the push to
    # the rewritten repository while ls-remote still reads the original
    # (measured). "Refuse when set" is what fails to carry over: the rewrite
    # fires only when its base prefixes origin's URL, a non-matching base is
    # inert (measured), and a global insteadOf/pushInsteadOf rewrite is ordinary
    # — unlike these three repo-scoped keys, whose presence is itself the
    # anomaly. Plain url.<base>.insteadOf needs no check: it rewrites fetch and
    # push alike, so the probe reads where the release publishes.
    #
    # `$branch` (not a hardcoded "main"): a master- or trunk-default plugin is
    # supported above, and this must protect it too.
    #
    # `--get-all`, not `--get`. remote.<name>.pushurl is genuinely multi-valued
    # — pushing to several mirrors is a supported arrangement — and `--get` on
    # such a key prints only the LAST value and still exits 0 (measured, git
    # 2.47.3; it does not fail). The refusal would then name one of two URLs
    # and advise `--unset`, which refuses a multi-valued key with status 5: a
    # correct refusal handing back a recovery that does not work. The other two
    # keys are last-one-wins for git, but a config file can still hold several
    # lines of them and `--unset` refuses those identically, so all three are
    # read the same way. `--get-all` still exits 1 when the key is unset —
    # the status every healthy fixture produces, and the only one absorbed.
    #
    # Values are listed one per line instead of interpolated into the `die`:
    # a pushurl holding a space must not read as two. A value holding a
    # newline still prints across two lines — the same residual bound
    # report_dirty records, and `git config` has no quoting mode that avoids
    # it.
    #
    # Using the assignment as the `if` condition (rather than `cmd || { ... }`)
    # keeps this outside errexit's suppression natively: an `if` condition's
    # status is never fatal under set -e, so no group-body pitfall applies.
    # `$?` in the `elif` condition is still the failed `if` condition's status
    # — measured, not assumed: exit 2 and exit 128 both reach the `elif` body,
    # exit 1 does not.
    local push_key push_values push_value
    for push_key in remote.origin.pushurl "branch.$branch.pushRemote" remote.pushDefault; do
        if push_values=$(git config --get-all "$push_key"); then
            printf 'hint: %s is set to:\n' "$push_key" >&2
            while IFS= read -r push_value; do
                printf '        %s\n' "$push_value" >&2
            done <<<"$push_values"
            printf '      unset it (git config --unset-all %s) or point it at\n' "$push_key" >&2
            printf '      origin, then run the same command again.\n' >&2
            die "push route diverges from origin: $push_key is set"
        elif [ "$?" -ne 1 ]; then
            die "could not read git config $push_key"
        fi
    done

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
