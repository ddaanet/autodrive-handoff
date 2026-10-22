# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # globals shared with release.sh's shell
#
# Sourced by release.sh, never run on its own. The plugin-repo half of
# publishing: the dist opt-in and its pre-flight, the version commit and tag,
# each push and the GitHub release, every outward step probed before it is
# taken.
#
# It runs in release.sh's shell, so release.sh's `set -euo pipefail` and its
# die/note helpers apply here, and these functions read and set the run's
# globals (`V`, `tag`, `mode`, `dist_on`, `acted`, `branch`) directly rather
# than through arguments or output.

dist_preflight() {
    # Release mode, after release_preflight and before bump_commit_tag, so a
    # refusal here leaves no commit and no tag. It runs as its own step because
    # release_preflight returns early on a first release. The tree is checked as
    # it stands at HEAD: the bump changes only .version, so the tree push_dist
    # ships differs from this one in that string alone.
    dist_opted_in HEAD
    [ "$dist_on" = 1 ] || return 0
    command -v claude >/dev/null 2>&1 \
        || die "dist.include is present but claude is not on PATH; validation runs claude plugin validate --strict — nothing was done"
    local tree
    tree=$(bash "$here/dist.sh" tree HEAD) \
        || die "the dist tree at HEAD was refused (see dist: lines above) — nothing was done"
    bash "$here/dist.sh" validate "$tree" \
        || die "the dist tree failed claude plugin validate --strict (see output above) — nothing was done"
}

dist_opted_in() {
    # $1 = a commit-ish. Sets dist_on: 1 when that commit carries dist.include,
    # 0 when it does not. dist.sh exits 1 for "not opted in"; any other status
    # is a failure of the probe itself, which must not read as "not opted in".
    local rc=0
    if [ ! -f "$here/dist.sh" ]; then
        # A toolkit vendored without dist.sh predates dist. Such a plugin is
        # refused if it carries dist.include, rather than released without the
        # dist branch it asked for.
        if [ -n "$(git ls-tree --full-tree "$1" -- dist.include)" ]; then
            die "$1 carries dist.include but $here/dist.sh is missing — update the toolkit"
        fi
        dist_on=0
        return
    fi
    bash "$here/dist.sh" enabled "$1" || rc=$?
    case "$rc" in
        0) dist_on=1 ;;
        1) dist_on=0 ;;
        *) die "could not read dist.include from $1 (dist.sh exit $rc) — nothing was done" ;;
    esac
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
    #
    # Every caller is a publishing step, which runs after the local commit and
    # tag exist, so a failed read is a release stopped midway and the hint can
    # always point at resume.
    local line
    line=$(git -C "$1" ls-remote origin "$2") || {
        printf 'hint: reading origin failed, so nothing was pushed by this step. clear what\n' >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      ls-remote reported above, then run `just resume-release`, which probes\n' >&2
        printf '      each step again and does only what is missing.\n' >&2
        die "git ls-remote origin $2 failed in $1"
    }
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

push_dist() {
    # Publishes the dist branch and its dist-v$V tag. It runs after push_tag and
    # before create_github_release, so the marketplace never names a ref that is
    # not on origin. The branch and the tag are separate pushes, and the tag push
    # names dist-v$V: the release-dist suite's kill points match on both.
    local src tip dist_sha="" landed=0 dist_tag dist_tree parent remote_dist local_dist
    src=$(git rev-parse "$tag^{commit}")
    dist_tag="dist-v$V"
    tip=$(ls_remote_sha . refs/heads/dist)
    if [ -n "$tip" ]; then
        git cat-file -e "$tip" 2>/dev/null \
            || git fetch -q origin dist \
            || die "could not fetch origin's dist branch to check it — nothing was pushed to dist"
        # The message is the record of which release commit the branch was built
        # from, so a match means this release's dist already landed.
        if [ "$(git log -1 --format=%s "$tip")" = "dist v$V from $src" ]; then
            landed=1
            dist_sha="$tip"
        fi
    fi
    if [ "$landed" = 0 ]; then
        dist_tree=$(bash "$here/dist.sh" tree "$src") \
            || die "the dist tree for $tag was refused (see dist: lines above) — nothing was pushed to dist"
        # The pre-flight validated HEAD before the bump. A resume has no such
        # check on this tree, so it validates the tree it is about to publish.
        if [ "$mode" = resume ]; then
            bash "$here/dist.sh" validate "$dist_tree" \
                || die "the dist tree for $tag failed claude plugin validate --strict — nothing was pushed to dist"
        fi
        # The commit is reproducible: dates come from $src and the parent is the
        # branch tip, so the same inputs rebuild the same sha on a resume.
        if [ -n "$tip" ]; then
            parent="$tip"
            dist_sha=$(bash "$here/dist.sh" commit "$src" "$dist_tree" "$V" "$parent") \
                || die "dist.sh could not build the dist commit for $tag — nothing was pushed to dist"
        else
            dist_sha=$(bash "$here/dist.sh" commit "$src" "$dist_tree" "$V") \
                || die "dist.sh could not build the dist commit for $tag — nothing was pushed to dist"
        fi
    fi

    # Probed before anything is pushed: a dist-v$V at a sha this run would not
    # publish is refused, and never moved. Local first, then origin.
    local_dist=$(git rev-parse -q --verify "refs/tags/$dist_tag^{commit}") || local_dist=""
    remote_dist=$(ls_remote_sha . "refs/tags/$dist_tag")
    if [ -n "$local_dist" ] && [ "$local_dist" != "$dist_sha" ]; then
        die "local $dist_tag points at $local_dist, not $dist_sha — refusing to move it"
    fi
    if [ -n "$remote_dist" ] && [ "$remote_dist" != "$dist_sha" ]; then
        die "$dist_tag on origin points at $remote_dist, not $dist_sha — refusing to move a published tag"
    fi

    if [ "$landed" = 1 ]; then
        note "dist: already pushed"
    else
        git push origin "$dist_sha:refs/heads/dist" || {
            printf 'hint: the release commit and tag %s are on origin; dist was not pushed.\n' "$tag" >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      clear what the push reported above, then run `just resume-release`.\n' >&2
            die "push of dist failed"
        }
        acted=1
        note "dist: pushed"
    fi

    if [ -z "$local_dist" ]; then
        git tag "$dist_tag" "$dist_sha"
    fi
    if [ -n "$remote_dist" ]; then
        # A tag created locally here is a local repair, and counts as an action.
        if [ -z "$local_dist" ]; then
            acted=1
        fi
        note "dist tag $dist_tag: already pushed"
        return
    fi
    git push origin "$dist_tag" || {
        printf 'hint: dist is on origin at %s; the dist tag was not pushed.\n' "$dist_sha" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      clear what the push reported above, then run `just resume-release`.\n' >&2
        die "push of $dist_tag failed"
    }
    acted=1
    note "dist tag $dist_tag: pushed"
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
