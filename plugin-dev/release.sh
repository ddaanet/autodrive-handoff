#!/usr/bin/env bash
set -euo pipefail

# Release a Claude Code plugin: bump the manifest, commit, tag, push, create the
# GitHub release, and bump the plugin's entry in the marketplace repo.
#
# Usage:
#   release.sh [patch|minor|major]   full release
#   release.sh --resume              complete a release that landed partially
#
# A plugin that has never been released is a special case: with no previous
# release to bump forward from, `release.sh` with no bump argument publishes
# the manifest version as it stands. Passing a bump there is refused. See
# release_preflight, which detects this by tag alone: no tag matching
# `^v[0-9]+\.[0-9]+\.[0-9]+$` exists yet, and the plugin's marketplace entry
# plays no part in that decision.
#
# Run from the plugin root (the directory holding .claude-plugin/plugin.json);
# `just release` does that for you. Requires bash, jq, git, gh, and
# MARKETPLACE_DIR pointing at the claude-plugins repo.

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

manifest=".claude-plugin/plugin.json"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

mode="release"
bump="patch"
# Distinct from $bump: whether a bump was actually *asked for*. `just release`
# passes an empty argument through, so the patch default lives here, and a
# first release can tell "the user typed patch" from "the user typed nothing".
bump_arg=""
case "${1:-}" in
    --resume)           mode="resume" ;;
    "")                 ;;
    -*)                 die "unknown option: $1 (usage: release.sh [patch|minor|major|--resume])" ;;
    patch|minor|major)  bump="$1"; bump_arg="$1" ;;
    *)                  die "unknown bump type: $1 (usage: release.sh [patch|minor|major|--resume])" ;;
esac
acted=0
first_release=0

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
        || die "$marketplace_dir is not writable: $probe — release needs to replace marketplace.json there. If this is a Claude Code sandbox restriction: rerun this Bash call with dangerouslyDisableSandbox, or run '/add-dir $MARKETPLACE_DIR' first."
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
    # Two paths are exempt, both because an agent session moves them by design
    # between commits.
    #
    # `.claude/` is the repo's own agent working environment — settings, hooks,
    # and the task frames the handoff and precompact skills stage for "whatever
    # commit lands next". None of it is plugin content: a plugin ships
    # .claude-plugin/ and the component directories beside it. Excluded whole
    # rather than by filename, because the set of files written there is a
    # function of which skills the maintainer runs, not of this script. The
    # pathspec matches at the path separator, so .claude-plugin/ — where a dirty
    # file must still stop a release — is untouched by it.
    #
    # The second is a gitlore-mounted memory submodule: its gitlink sits ahead
    # of what HEAD records between commits by design — gitlore's own pre-commit
    # hook folds that in on the next commit, not this one.
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
    clean_specs=(. ':(exclude).claude')
    clean_exempt=(".claude/ — agent working state (settings, hooks, staged handoff frames), none of it plugin content")
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
    # dirty, then the exemptions that did not save it. Callers add the
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
    printf '      exempt from this check, and so not among the paths above:\n' >&2
    for p in "${clean_exempt[@]}"; do
        printf '        %s\n' "$p" >&2
    done
    printf '      .claude-plugin/ is NOT exempt — git pathspecs match at the path\n' >&2
    printf '      separator, so a dirty manifest still refuses.\n' >&2
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
    plugin_name=$(jq -r .name "$manifest")
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
    # dispatch at the foot of this file takes the `else resume_preflight`
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

semver_tags() {
    # Filter: stdin to stdout, keeping only full `vX.Y.Z` lines. A no-match
    # grep exits 1, which under `set -euo pipefail` would kill the script at
    # the caller's assignment — absorb exactly that status, so an empty
    # result is a value (no matching tags) and a real grep error still exits
    # non-zero. That distinction only reaches the caller if the caller reads
    # the status: capture into a variable, never `[ -z "$(…)" ]`, which
    # discards it and makes a failed listing look like an empty one.
    #
    # That absorption is also why neither release_tags nor origin_release_tags
    # pipes its listing command straight into this filter, and why both capture
    # the listing and read ITS status first: a failed listing prints nothing,
    # this filter exits 0 on the empty input, and the pipeline's own status
    # says "no tags" rather than "listing failed" — the fail-open path into
    # publishing over a release the caller could not see. Piping would not be
    # wrong today: `set -o pipefail` yields the RIGHTMOST non-zero stage
    # status, so a listing command's failure would still reach the caller
    # past this filter's exit 0 on empty input. But pipefail is the only
    # thing that would carry it, so each caller's safety would rest on one
    # word of the `set` line at the top of the script.
    # Verified both ways (bash 5.2, git 2.47.3): piped refuses under pipefail
    # and succeeds with it off; captured refuses either way.
    { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || [ "$?" -eq 1 ]; }
}

release_tags() {
    # Local semver release tags, newest first — the order is part of the
    # contract, since a caller naming a release takes the first line. Fixed
    # here rather than at each call site so no caller can forget it.
    #
    # `git tag --list` and not `git describe`, for both callers. describe only
    # sees tags reachable from HEAD, so a release tagged on a since-abandoned
    # branch would read as no tags at all; and it returns the NEAREST tag of
    # ANY name, distance-ordered rather than version-ordered, so an unrelated
    # tag on a later commit would read as the last release.
    #
    # Capture the listing and read its own status, the same shape
    # origin_release_tags uses: this function's safety no longer depends on
    # the `set -o pipefail` line above — a failed `git tag --list` returns 1
    # here directly, rather than relying on pipefail to carry a mid-pipeline
    # failure past semver_tags.
    local listing
    listing=$(git tag --list 'v*' --sort=-v:refname) || return 1
    printf '%s\n' "$listing" | semver_tags
}

origin_release_tags() {
    # Origin's semver release tags, newest first — same contract as
    # release_tags, read from origin instead of the local clone. Evidence for
    # the lost-tags guard in release_preflight: a local tag can go missing
    # (deleted, a clone that never fetched it) while origin's copy — the
    # actual release record — is untouched.
    #
    # ls-remote's default order is lexicographic on the ref name, not semver
    # (v1.10.0 sorts before v1.2.3 sorts before v1.9.0 as strings), so
    # --sort=-v:refname is load-bearing: without it a refusal could name a tag
    # that is not actually the newest once a plugin reaches a two-digit minor
    # or patch.
    #
    # `git ls-remote` reaches the network and fails routinely (unreachable
    # origin, no origin, auth) — unlike `git tag --list`, which essentially
    # never fails. So capture its output and read ITS status rather than piping
    # it straight into cut/sed/semver_tags — for the reason semver_tags's own
    # comment gives, which applies to release_tags the same way.
    local listing
    listing=$(git ls-remote --tags --sort=-v:refname origin) || return 1
    # cut -f2 splits on TAB, and ls-remote emits exactly `<oid><TAB><ref>`.
    # A ref name can hold neither space, tab nor newline (git refuses all
    # three — verified), so the split is total for anything reaching here.
    # The residual is a line with no TAB, which cut passes through whole;
    # semver_tags's anchored pattern drops it, as it drops the `^{}` peeled
    # rows annotated tags add beside their own.
    printf '%s\n' "$listing" | cut -f2 | sed 's|^refs/tags/||' | semver_tags
}

release_preflight() {
    local manifest_version latest_tag release_tag_list verifiably_unpublished=0
    # Capture the listing rather than substituting it inline: a `git tag` that
    # fails, or a real grep error in the filter, prints nothing, and
    # `[ -z "$(release_tags)" ]` would discard that status and read the
    # silence as "never released" — then tag HEAD and publish the manifest
    # version of a plugin whose history it could not read.
    release_tag_list=$(release_tags) \
        || die "could not list this plugin's release tags — nothing was done"

    # Lost-tags guard, before check-version.sh and so before any side effect
    # (bump_commit_tag tagging, push_branch pushing): an empty LOCAL tag list
    # is not by itself evidence this plugin was never released — a clone can
    # lose a tag it once had while origin still carries it. Only origin
    # silence, not local silence, may say "never released" and continue.
    #
    # Read as any semver tag on origin, not only v$manifest_version: a
    # tagless clone whose manifest was hand-advanced past a real release
    # (e.g. to 1.3.0 over a published v1.2.3) would otherwise find no
    # v1.3.0, read as first release, and publish the hand-written version
    # without ever consulting the release it is actually ahead of.
    #
    # Capture rule applies here exactly as above: never
    # `[ -n "$(origin_release_tags)" ]`, which would discard a broken
    # listing's status and let a network failure read as "origin has no
    # tags either" — a fail-open path into publishing a duplicate release.
    # A failed listing refuses instead: push_branch and push_tag need origin
    # anyway, so proceeding would only move the failure past the point a
    # local tag could still have caught it.
    if [ -z "$release_tag_list" ]; then
        local origin_tag_list origin_newest
        origin_tag_list=$(origin_release_tags) \
            || die "could not verify this plugin's release history on origin — nothing was done"
        if [ -n "$origin_tag_list" ]; then
            # First line, because origin_release_tags sorts newest first; sed
            # and not `head -1`, for the SIGPIPE reason spelled out at the
            # latest_tag read below. Neither printf nor sed can fail on an
            # already-captured non-empty string, so the status check on
            # origin_tag_list above is the only one this needs.
            origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '1p')
            printf 'hint: origin already has release tags for this plugin — the newest is\n' >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      %s, missing from this clone. Run `git fetch --tags` to catch up,\n' "$origin_newest" >&2
            printf '      then run the same command again.\n' >&2
            die "local release tags are missing — refusing to guess whether $origin_newest was published"
        fi
        # Reached only when the probe above found nothing either: no semver
        # tag locally and none on origin. This plugin is verifiably
        # unpublished — read below, at the check-version.sh failure point,
        # so drift there gets decision 1's wording instead of the ordinary
        # resume hint. Captured as a flag rather than re-running the probe: a
        # second `git ls-remote` is a second network call that can fail on
        # its own, and the whole point of the probe is that its status is
        # read exactly once.
        verifiably_unpublished=1
    fi

    # manifest_version is needed below regardless of which branch fires: the
    # ordinary resume hint doesn't read it, but decision 1's hint names it, so
    # read it once here rather than only in the first-release branch further
    # down (which also uses it).
    manifest_version=$(jq -r .version "$manifest")

    # Catch a previous release that didn't fully complete (tag/manifest bumped,
    # marketplace bump never landed) before starting a new one on top of it.
    bash "$here/check-version.sh" || {
        if [ "$verifiably_unpublished" = 1 ]; then
            # Decision 1: a marketplace entry that disagrees with the manifest
            # while no release is recorded anywhere is an anomaly, not a
            # partial release — there is nothing to resume. Point at the
            # entry as the default fix (a successful first release would
            # write $manifest_version there anyway via bump_marketplace), but
            # name the manifest edit too, for the case where the entry's
            # version was the one actually intended.
            # Capture rule, and it bites here: `set -e` IS in force inside
            # this `|| { … }` group (measured, bash 5.2 — errexit is suppressed
            # for an AND-OR list's non-final elements, not for the commands
            # inside its final one), so an unread failure would abort the run
            # with jq's own status and no `error:` line at all. Reachable:
            # check-version.sh exits non-zero on a malformed or
            # non-marketplace-shaped marketplace.json as well as on drift, and
            # this jq then fails the same way.
            local market_version
            market_version=$(jq -r --arg n "$plugin_name" \
                '.plugins[] | select(.name==$n) | .version' "$marketplace_json") \
                || die "could not read $plugin_name's entry in $marketplace_json — nothing was done"
            # Empty rather than failed: jq matched no entry. check-version.sh
            # skips (exit 0) when the entry is absent, so on its exit-1 drift
            # path the entry is always present — this only obtains if the two
            # scripts resolved different manifests, which they do when
            # release.sh is run from a plugin root other than the one vendoring
            # it ($manifest is relative to the CWD, check-version.sh's default
            # to the toolkit's own parent).
            [ -n "$market_version" ] \
                || die "no $plugin_name entry in $marketplace_json to compare against — nothing was done"
            # "no vX.Y.Z tag", not "no release tag at all" and not "never
            # published": what the probe established is exactly that no
            # `vX.Y.Z` tag exists here or on origin. A plugin released only
            # under some other tag scheme is the residual the outline records,
            # and this message must not deny it — so it names the shape it
            # actually looked for rather than claiming the plugin has no
            # release history of any kind.
            printf 'hint: no release is recorded at %s or %s — this plugin has no\n' \
                "$manifest_version" "$market_version" >&2
            printf '      vX.Y.Z tag, here or on origin, so there is nothing to resume.\n' >&2
            printf '      correct the marketplace entry to match plugin.json (a successful\n' >&2
            printf '      first release would write %s there anyway), or if %s was the\n' \
                "$manifest_version" "$market_version" >&2
            printf '      intended version, set .version in %s\n' "$manifest" >&2
            printf '      to %s and commit that edit, then re-run.\n' "$market_version" >&2
            die "fix the version drift above before releasing"
        fi
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf 'hint: `just resume-release` completes a release that landed partially.\n' >&2
        die "fix the version drift above before releasing"
    }

    # A plugin that has never been released has no last-released version to bump
    # forward from: its manifest holds the version it wants to publish FIRST.
    # Plugins scaffolded by the unrelated official `plugin-dev` marketplace
    # plugin arrive seeded at 0.1.0 exactly this way, and bumping past it
    # publishes a version nobody asked for. So publish the manifest verbatim.
    if [ -z "$release_tag_list" ]; then
        first_release=1
        if [ -n "$bump_arg" ]; then
            printf 'hint: a first release publishes the manifest version as-is — there is no\n' >&2
            printf '      previous release to bump forward from. Re-run with no bump argument\n' >&2
            printf '      to publish v%s.\n' "$manifest_version" >&2
            printf '      to publish some other version instead, set .version in %s\n' "$manifest" >&2
            printf '      to it and commit that edit, then re-run with no bump argument. That\n' >&2
            printf '      edit is the one the version-guard hook refuses from an agent: it is\n' >&2
            printf '      the maintainer who decides what a plugin first ships as.\n' >&2
            die "'$bump_arg' bump refused: this plugin has never been released"
        fi
        V="$manifest_version"
        tag="v$V"
        ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "tag $tag already exists"
        note "first release: publishing the manifest version $V as-is (no bump)"
        return
    fi

    # release_tag_list is already release_tags's output: local semver tags,
    # newest first, junk like `vnext` or `v1.2` already dropped by
    # semver_tags. Reuse it instead of listing again, so a non-semver v-tag
    # that sorts above the real release (`vnext` sorts above `v9.9` under
    # --sort=-v:refname) can never be read as the latest release, while the
    # newest real release tag still is. sed -n '1s…p' and not `head -1`: head
    # exits after the line it wants, which under pipefail would surface as a
    # SIGPIPE on a long list. Neither printf nor sed can fail on the
    # already-captured string, so release_tag_list's own status check above is
    # the only one this needs. The listing is non-empty here (the branch above
    # returned), and its first line matched the semver anchor, so latest_tag
    # is always set; the -n test below is belt and braces.
    latest_tag=$(printf '%s\n' "$release_tag_list" | sed -n '1s/^v//p')
    # One remedy. This hint used to offer two more; both are gone — recorded so
    # they do not come back:
    #
    # `git checkout HEAD -- $manifest` is always a no-op. common_preflight
    # refuses a dirty tree before release_preflight runs, and clean_pathspecs
    # exempts only `.claude/` and the gitlore submodule — never
    # `.claude-plugin/` — so the hand-written bump this refusal is about has
    # always been committed already. Reverting it therefore takes a new commit,
    # which is what the hint now says.
    #
    # `git fetch --tags` is not the remedy for the state this refusal names.
    # latest_tag comes from release_tag_list, the LOCAL semver tags, and this
    # refusal fires only when that list came back non-empty — which is exactly
    # when the lost-tags probe above did NOT run, so origin was never consulted
    # on this path. The probe establishes nothing here. A clone missing every
    # release tag takes the probe instead and is sent to fetch by the probe's
    # own hint, so offering one here would only duplicate it. What is left is a
    # clone that kept older release tags but lost the newest: there a fetch
    # would genuinely help, and this hint still sends the operator to write the
    # manifest back to a stale tag. That partial tag loss is a stated bound of
    # the probe rather than an oversight — closing it means listing origin on
    # every release and not only on an empty local list, a network round trip
    # and a listing whose failure has to be absorbed on the common path.
    if [ -n "$latest_tag" ] && [ "$manifest_version" != "$latest_tag" ]; then
        printf 'hint: plugin.json holds the LAST released version, never the next one.\n' >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      `just release <bump>` computes the next one from it, so a manifest\n' >&2
        printf '      ahead of the newest tag means the bump was already written by hand and\n' >&2
        printf '      this run would publish a version past the one that was intended.\n' >&2
        printf '      set .version in %s back to %s, commit that\n' "$manifest" "$latest_tag" >&2
        printf '      edit, then re-run with the bump that produces the version you want.\n' >&2
        die "plugin.json version ($manifest_version) does not match latest tag (v$latest_tag)"
    fi
    V=$(jq -r --arg bump "$bump" '
      (.version | split(".") | map(tonumber)) as [$maj,$min,$pat]
      | if   $bump == "major" then [$maj+1, 0, 0]
        elif $bump == "minor" then [$maj, $min+1, 0]
        elif $bump == "patch" then [$maj, $min, $pat+1]
        else error("unknown bump type: " + $bump) end
      | map(tostring) | join(".")
    ' "$manifest")
    tag="v$V"
    ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "tag $tag already exists"
}

resume_preflight() {
    V=$(jq -r .version "$manifest")
    tag="v$V"
    # Resume only ever finishes a release whose commit and tag already landed
    # locally. No tag means no release was started at this version, and tagging
    # HEAD on a guess would tag whatever work landed since.
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || {
        # The refusal above is already decided — everything below only picks
        # which hint explains it, so a failed probe must never turn this into a
        # harder refusal. Capture rule as in release_preflight, applied to BOTH
        # listings: this is a `|| { … }` group, where `set -e` is in force (the
        # jq capture at the check-version.sh failure point spells out why), so
        # an unread failure aborts the run with git's own status and neither the
        # hint nor the `error:` line ever prints — a bare crash where a clean
        # refusal was already decided. Neither failure is fatal here, unlike in
        # release_preflight: there is no side effect left to protect, and each
        # is absorbed into the branch that claims least about this plugin.
        local origin_tag_list release_tag_list no_local_tags=0
        origin_tag_list=$(origin_release_tags) || origin_tag_list=""
        # Only a listing that SUCCEEDED and came back empty is evidence this
        # clone holds no release tag, so the flag is set on exactly that.
        # Folding a failed one into the empty case would let silence claim
        # "never released" — the fail-open read semver_tags's comment warns
        # against — and route to a bare `just release`. Reachable, both
        # measured: `git tag --list` erroring, and a status-2 grep error inside
        # semver_tags. A failure falls to the last branch instead, whose advice
        # is safe either way: release_preflight refuses a bump on a plugin that
        # turns out never to have been released, and says why.
        if release_tag_list=$(release_tags) && [ -z "$release_tag_list" ]; then
            no_local_tags=1
        fi
        # -F: $tag is a fixed string, not a BRE whose dots would match any
        # character. No semver_tags-filtered line can false-positive on that BRE
        # anyway, but $V is whatever the manifest holds. -x pins the whole line,
        # so the single empty line an empty listing prints cannot match.
        # Herestring, not a pipe: a pipe's `grep -qxF` can exit 0 on its first
        # match while `printf` is still writing, and SIGPIPE-killed `printf`
        # reports 141 over `grep`'s 0 under `pipefail`, promoting the wrong
        # side's status. `toolkit/version-guard.sh`'s tag filter,
        # `grep -E '…' <<<"$listing"`, is the in-repo precedent for this fix.
        if grep -qxF -- "$tag" <<<"$origin_tag_list"; then
            # Origin already has the tag this clone is missing: the release
            # was published, and this clone just never fetched it. Resuming
            # after the fetch picks it up; starting a new release would try
            # to recreate a tag that already exists.
            printf 'hint: origin already has %s — this clone is just missing it.\n' "$tag" >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      run `git fetch --tags`, then run `just resume-release`.\n' >&2
        elif [ -n "$origin_tag_list" ]; then
            # Origin holds some other semver release, but not this one — any
            # tag counts, not only $tag, for the same reason as the lost-tags
            # guard above: an empty local tag set says nothing about what is
            # published. Naming the bump form rather than falling through to
            # the no-argument hint below: once the fetch lands, origin has a
            # real release to bump from, and a bare `just release` would be
            # refused on sight.
            printf 'hint: origin has release tags, but none matching %s.\n' "$tag" >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      run `git fetch --tags`, then run `just release <bump>`.\n' >&2
        elif [ "$no_local_tags" = 1 ]; then
            # No local semver tag — verified, not merely unread — and no origin
            # evidence either: nothing here to bump forward from, so the next
            # release names no bump.
            printf 'hint: no release was started at this version.\n' >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      run `just release` instead.\n' >&2
        else
            # Origin has nothing to say, and this clone's own tags are either
            # present but not this one — today's default — or unreadable, which
            # lands here because this branch asserts nothing either could
            # contradict.
            printf 'hint: no release was started at this version.\n' >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      run `just release <bump>` instead.\n' >&2
        fi
        die "no tag $tag for plugin.json version $V"
    }
}

bump_commit_tag() {
    local tmp
    if [ "$first_release" = 1 ]; then
        # The manifest already holds $V — a first release publishes it as-is, so
        # there is nothing to rewrite and nothing to commit. Tag HEAD, which
        # common_preflight has already established is clean and on the main branch.
        git tag -a "$tag" -m "Release $V"
        acted=1
        note "tag: $tag created locally (manifest already at $V)"
        return
    fi
    local prev
    prev=$(jq -r .version "$manifest")
    tmp=$(mktemp)
    jq --arg v "$V" '.version = $v' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
    git add "$manifest"
    # A consumer's pre-commit hook can refuse this commit. Dying here with the
    # bump written and staged strands it: nothing committed, nothing tagged, and
    # a dirty manifest that then blocks BOTH a re-run and --resume on
    # common_preflight's "uncommitted changes" — which names neither the gate nor
    # the leftover. Restoring from HEAD leaves the tree as this run found it, so
    # satisfying the gate and re-running is the whole recovery.
    git commit -m "release: $V" || {
        git checkout HEAD -- "$manifest"
        printf 'hint: the manifest was rolled back to %s and nothing was tagged.\n' "$prev" >&2
        printf '      fix what the gate reported above, then run the same command again.\n' >&2
        die "commit gate refused the release commit"
    }
    git tag -a "$tag" -m "Release $V"
    acted=1
    note "manifest + tag: $tag created locally"
}

ls_remote_sha() {
    # $1 = a repo directory, $2 = a full ref name. Prints that ref's sha on the
    # repo's origin, and nothing when origin does not have it.
    #
    # Captured whole and trimmed with a parameter expansion rather than piped
    # into `cut`: a pipeline reports cut's status, and cut succeeds on the empty
    # input a failed `ls-remote` hands it — so without `set -o pipefail` a
    # network or auth failure would read as "the ref is not on origin", which is
    # the answer each caller below treats as licence to act. push_tag is the
    # sharp one: absence there is what lets it push, so a misread would walk
    # straight past the refusal that keeps a published tag from being moved.
    # pipefail does cover this today. Not depending on that is the point; a
    # `set -o` line is easy to lose and nothing here would say so.
    local line
    line=$(git -C "$1" ls-remote origin "$2") \
        || die "git ls-remote origin $2 failed in $1"
    printf '%s' "${line%%$'\t'*}"
}

push_branch() {
    local remote_head
    remote_head=$(ls_remote_sha . "refs/heads/$branch")
    if [ -n "$remote_head" ] && [ "$remote_head" = "$(git rev-parse HEAD)" ]; then
        note "branch $branch: already pushed"
        return
    fi
    # A consumer's pre-push hook can refuse this. gitlore's publishes every
    # memory store before the parent push and refuses when one diverged, and the
    # window it opens is human-paced: the release commit's own approval round
    # sits inside it. The commit and the tag are already local, so the recovery
    # is resume — never an amend re-pinning the gitlink at the merged memory.
    # The gitlink a release commit records is always an ancestor of memory's
    # `live` or `live` itself (each merge takes the pending commit as its second
    # parent), and a push of `live` publishes every ancestor — so nothing needs
    # the tagged commit to name the merge, and the tag is never rewritten.
    # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
    git push || {
        printf 'hint: the release commit and tag %s are local; nothing was pushed.\n' "$tag" >&2
        printf '      clear what the push reported above, then run `just resume-release`.\n' >&2
        printf '      gitlore refuses the push while a memory store is diverged: `/gitlore:resolve`\n' >&2
        printf '      in Claude Code clears it. Repeat the pair if the push is refused again.\n' >&2
        die "push of $branch failed"
    }
    acted=1
    note "branch $branch: pushed"
}

push_tag() {
    local remote_tag local_tag
    remote_tag=$(ls_remote_sha . "refs/tags/$tag")
    local_tag=$(git rev-parse "$tag")
    if [ -n "$remote_tag" ]; then
        # Never move a published tag: a mismatch means it was reused, which no
        # recovery should paper over.
        [ "$remote_tag" = "$local_tag" ] \
            || die "$tag on origin points at $remote_tag, not $local_tag — refusing to move a published tag"
        note "github tag $tag: already pushed"
        return
    fi
    git push origin "$tag"
    acted=1
    note "github tag $tag: pushed"
}

create_github_release() {
    if gh release view "$tag" >/dev/null 2>&1; then
        note "github release $tag: already created"
        return
    fi
    gh release create "$tag" --title "Release $V" --generate-notes
    acted=1
    note "github release $tag: created"
}

bump_marketplace() {
    local mp_tmp repo_slug mp_branch mp_remote_head mp_local_head committed=0
    mp_tmp=$(mktemp)
    if [ "$marketplace_entry_exists" = 1 ]; then
        jq --arg n "$plugin_name" --arg v "$V" \
            '(.plugins[] | select(.name == $n) | .version) = $v' \
            "$marketplace_json" > "$mp_tmp"
    else
        # Derive owner/repo from origin for the `github` source. Strip a trailing
        # .git, then everything up to the host separator, leaving `owner/repo`
        # for both git@host:owner/repo and https://host/owner/repo.
        repo_slug=$(git remote get-url origin | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')
        jq --arg v "$V" --arg repo "$repo_slug" --slurpfile m "$manifest" '
          .plugins += [{
            name: $m[0].name,
            source: { source: "github", repo: $repo },
            description: ($m[0].description // ""),
            version: $v,
            author: ($m[0].author // { name: "" }),
            repository: ($m[0].repository // $m[0].homepage // ("https://github.com/" + $repo)),
            license: ($m[0].license // "MIT")
          }]
        ' "$marketplace_json" > "$mp_tmp"
    fi
    # A no-op rewrite (marketplace already at $V) must not touch the file: the
    # mktemp+mv replace needs to unlink and recreate marketplace.json in its
    # directory, which a sandboxed resume-release can't do even when nothing
    # actually needs to change.
    if cmp -s "$mp_tmp" "$marketplace_json"; then
        rm -f "$mp_tmp"
    else
        check_marketplace_writable
        # mktemp creates 0600 and mv carries that mode onto the destination, so
        # every bump silently narrowed a tracked file. 644 is the mode a clone
        # of the marketplace repo gets under the usual umask; the mv is kept
        # (rather than writing through the file) because the no-op guard above
        # depends on the replace needing directory write, not file write.
        chmod 644 "$mp_tmp"
        mv "$mp_tmp" "$marketplace_json"
        git -C "$MARKETPLACE_DIR" add .claude-plugin/marketplace.json
    fi
    # Committing and pushing are separate questions: the working tree can
    # already hold $V (nothing to commit) while the commit that put it there
    # never reached origin (nothing pushed) — e.g. this same push rejected on
    # a previous run. A no-op diff must not short-circuit before the push is
    # checked, or an interrupted marketplace push can never be resumed.
    if git -C "$MARKETPLACE_DIR" diff --cached --quiet; then
        : # already at $V locally; still must check whether it reached origin
    else
        # A hook in the marketplace repo can refuse this, and by now everything
        # before it is public. Leaving the bump staged strands it: common_preflight
        # reads that as an unrelated dirty tree and refuses `resume-release`, the
        # one command that would finish the release. Restore from HEAD for the
        # same reason bump_commit_tag does — common_preflight established that
        # tree clean, so this leaves it as this run found it, and resume can then
        # write the bump again and push it with no manual repair in between.
        git -C "$MARKETPLACE_DIR" commit -m "release: $plugin_name $V" || {
            git -C "$MARKETPLACE_DIR" checkout HEAD -- .claude-plugin/marketplace.json
            printf 'hint: %s is public through its GitHub release; only the\n' "$tag" >&2
            printf '      marketplace entry is behind. the bump to %s was rolled back, so\n' "$V" >&2
            printf '      %s is as this run found it.\n' "$MARKETPLACE_DIR" >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      fix what the gate reported above, then run `just resume-release`,\n' >&2
            printf '      which writes the bump again and pushes it.\n' >&2
            die "commit gate refused the marketplace bump"
        }
        committed=1
        acted=1
    fi

    mp_branch=$(git -C "$MARKETPLACE_DIR" symbolic-ref -q --short HEAD || echo "")
    mp_remote_head=$(ls_remote_sha "$MARKETPLACE_DIR" "refs/heads/$mp_branch")
    mp_local_head=$(git -C "$MARKETPLACE_DIR" rev-parse HEAD)
    if [ "$mp_remote_head" = "$mp_local_head" ]; then
        if [ "$committed" = 1 ]; then
            if [ "$marketplace_entry_exists" = 1 ]; then
                note "marketplace: bumped to $V"
            else
                note "marketplace: entry created at $V"
            fi
        else
            note "marketplace: already at $V"
        fi
        return
    fi

    # The last outward step of the whole release, and the only one in another
    # repo. Under Claude Code's auto-mode classifier this is where a push is
    # refused as an external repo outside the trusted source-control org —
    # check_marketplace_writable's /add-dir advice covers the file write, not
    # this. Everything else is already public by now, so the message has to say
    # that rather than leave a bare git error as the last word.
    git -C "$MARKETPLACE_DIR" push || {
        printf 'hint: %s is public through its GitHub release, and the marketplace bump\n' "$tag" >&2
        printf '      to %s is committed in %s — only the push is missing.\n' "$V" "$MARKETPLACE_DIR" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      clear what the push reported above, then run `just resume-release`.\n' >&2
        printf '      if Claude Code refused it as a repo outside the trusted source-control\n' >&2
        printf "      org, run '/add-dir %s' first.\n" "$MARKETPLACE_DIR" >&2
        die "push of the marketplace bump failed"
    }
    acted=1
    if [ "$committed" = 1 ]; then
        if [ "$marketplace_entry_exists" = 1 ]; then
            note "marketplace: bumped to $V"
        else
            note "marketplace: entry created at $V"
        fi
    else
        note "marketplace: committed earlier, pushed now"
    fi
}

common_preflight
if [ "$mode" = "release" ]; then
    release_preflight
    bump_commit_tag
else
    resume_preflight
fi
push_branch
push_tag
create_github_release
bump_marketplace
if [ "$mode" = "resume" ] && [ "$acted" = 0 ]; then
    note "release $tag is already complete (nothing to do)"
else
    note "Release $tag complete"
fi
