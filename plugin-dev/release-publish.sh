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
    # it stands at HEAD: the release commit changes .version and takes the root
    # TASK.md and TODO.md as they are on disk, so the tree push_dist ships
    # differs from this one in that string, and in those two files only where
    # dist.include lists them.
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
        # common_preflight has already established is on main or dev and clean
        # but for its exemptions; with no commit to take them, a dirty TASK.md
        # or TODO.md stays dirty for the next one.
        git tag -a "$tag" -m "Release $V"
        acted=1
        note "tag: $tag created locally (manifest already at $V)"
        return
    fi
    local prev
    prev=$(jq -r .version "$manifest")
    tmp=$(mktemp "${TMPDIR:-/tmp}/release-publish.XXXXXX")
    jq --arg v "$V" '.version = $v' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
    git add "$manifest"
    # The handoff files clean_pathspecs exempts in the plugin repo ride this
    # commit as they are on disk: present, their content; absent, deleted. The
    # list is every one that differs from HEAD on disk or in the index, and an
    # untracked one git does not ignore. `update-index --add --remove` stages
    # what the disk holds whatever the index held before — a staged blob the
    # worktree since put back, a `git rm`, a `git rm --cached` of an ignored
    # file — where `git add` of a path neither on disk nor in the index fails.
    local handoff=() p
    while IFS= read -r -d '' p; do
        handoff+=("$p")
    done < <(git diff -z --name-only HEAD -- ':(literal)TASK.md' ':(literal)TODO.md'
             git diff -z --name-only --cached HEAD -- ':(literal)TASK.md' ':(literal)TODO.md'
             git ls-files -z -o --exclude-standard -- ':(literal)TASK.md' ':(literal)TODO.md')
    if [ "${#handoff[@]}" -gt 0 ]; then
        git update-index --add --remove -- "${handoff[@]}" \
            || rollback_bump "$prev" "could not stage the handoff files" "${handoff[@]}"
    fi
    # A consumer's pre-commit hook can refuse this commit. Dying here with the
    # bump written and staged strands it: nothing committed, nothing tagged, and
    # a dirty manifest that then blocks BOTH a re-run and --resume on
    # common_preflight's "uncommitted changes" — which names neither the gate nor
    # the leftover. rollback_bump puts the manifest back, so satisfying the gate
    # and re-running is the whole recovery.
    git commit -m "release: $V" \
        || rollback_bump "$prev" "commit gate refused the release commit" "${handoff[@]+"${handoff[@]}"}"
    git tag -a "$tag" -m "Release $V"
    acted=1
    note "manifest + tag: $tag created locally"
}

rollback_bump() {
    # $1=the version the manifest held, $2=the error to die with, rest=the
    # handoff paths bump_commit_tag staged. Restores the manifest from HEAD and
    # unstages those paths back to HEAD in the index, whatever was staged in
    # them before the run; their content on disk is untouched. Nothing is
    # committed or tagged yet, so the tree is clean but for its exemptions and
    # the same command runs again.
    local prev="$1" why="$2"
    shift 2
    git checkout HEAD -- "$manifest"
    [ "$#" -eq 0 ] || git reset -q HEAD -- "$@"
    printf 'hint: the manifest was rolled back to %s and nothing was tagged.\n' "$prev" >&2
    printf '      fix what was reported above, then run the same command again.\n' >&2
    die "$why"
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

push_target() {
    # Both modes, after published_tags_check and before move_main. Reads
    # origin's main and sets push_commit, the commit main is moved to and
    # pushed: the release commit while origin's main is inside it; HEAD once
    # origin's main has moved past it and HEAD holds both, which is the merge
    # the refusal below names. The tag fixes the release's content, so all
    # publishing needs is the release commit inside the main that is pushed;
    # what HEAD carries beyond it lands on main with the merge. remote_head is
    # left for push_branch.
    push_commit="$release_commit"
    remote_head=$(ls_remote_sha . "refs/heads/$main_branch")
    [ -n "$remote_head" ] || return 0
    git cat-file -e "$remote_head" 2>/dev/null \
        || git fetch -q --no-tags origin "$main_branch" \
        || die "could not fetch origin's $main_branch to check it — nothing was pushed"
    if git merge-base --is-ancestor "$release_commit" "$remote_head" \
        || git merge-base --is-ancestor "$remote_head" "$release_commit"; then
        return
    fi
    if git merge-base --is-ancestor "$remote_head" HEAD; then
        push_commit=$(git rev-parse HEAD)
        return
    fi
    # Refused before move_main and before any push, so no pre-push hook runs on
    # a push that cannot land. The merge the hint names reads origin/<main>,
    # which the probe above leaves stale whenever the object was already here.
    git fetch -q --no-tags origin "+refs/heads/$main_branch:refs/remotes/origin/$main_branch" \
        || die "could not fetch origin's $main_branch — nothing was pushed"
    printf "hint: origin's %s has commits %s lacks, and nothing is public yet. Merge them\n" "$main_branch" "$tag" >&2
    printf '      into %s, then finish the release:\n' "$branch" >&2
    printf '      git merge origin/%s\n' "$main_branch" >&2
    printf '      just resume-release\n' >&2
    die "release $tag not pushed: origin's $main_branch has commits $branch lacks"
}

published_tags_check() {
    # Both modes, after the release commit exists and before push_target.
    # push_tag and push_dist refuse a release tag origin holds at another sha,
    # but only once main is pushed, and main would then carry a release that is
    # not the one origin's tag names. The same refusal here leaves nothing
    # pushed, and comes before push_target's merge hint: another clone's release
    # is not this one to merge. A tag origin holds at the local sha is a
    # resume's, and passes; one absent locally is left to push_dist, which
    # builds it.
    local tags=("$tag") t local_sha remote_sha
    if [ "$dist_on" = 1 ]; then
        tags+=("dist-v$V")
    fi
    for t in "${tags[@]}"; do
        local_sha=$(git rev-parse -q --verify "refs/tags/$t") || continue
        remote_sha=$(ls_remote_sha . "refs/tags/$t")
        if [ -n "$remote_sha" ] && [ "$remote_sha" != "$local_sha" ]; then
            die "$t on origin points at $remote_sha, not $local_sha — refusing to publish it; nothing was pushed"
        fi
    done
}

move_main() {
    # Both modes, after push_target and before push_branch. Brings local main to
    # push_commit when it lacks it, as a fast-forward: a non-fast-forward fetch
    # is refused, so main is never rewound. Nothing is pushed here. A clone with
    # no local main gets it created by the same fetch; probing an absent ref
    # with merge-base would print a git `fatal:`.
    local verb="moved to" fetch_out what="$tag"
    [ "$push_commit" = "$release_commit" ] || what="$branch"
    if ! git rev-parse -q --verify "refs/heads/$main_branch" >/dev/null; then
        verb="created at"
    elif git merge-base --is-ancestor "$push_commit" "refs/heads/$main_branch"; then
        return
    fi
    # Not `-q`: it silences git's `[rejected] … (non-fast-forward)` line, which
    # the hint below sends the reader to. Captured so a success prints nothing.
    # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
    fetch_out=$(git fetch . "$push_commit:refs/heads/$main_branch" 2>&1) || {
        printf '%s\n' "$fetch_out" >&2
        printf 'hint: local %s cannot fast-forward to %s; nothing was pushed.\n' "$main_branch" "$what" >&2
        printf '      clear what git reported above, then run `just resume-release`.\n' >&2
        die "could not move $main_branch to $what — nothing was pushed"
    }
    acted=1
    note "branch $main_branch: $verb $what"
}

push_branch() {
    # Pushes push_commit to main unless origin's main, as push_target read it,
    # already contains the release commit. The push names a commit, never the
    # branch: from dev at the release commit, later dev commits are not
    # published; once HEAD is the merge of a moved origin main, every commit
    # HEAD holds past the release commit is.
    if [ -n "$remote_head" ] && git merge-base --is-ancestor "$release_commit" "$remote_head"; then
        note "branch $main_branch: already pushed"
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
    git push origin "$push_commit:refs/heads/$main_branch" || {
        printf 'hint: the release commit and tag %s are local; nothing was pushed.\n' "$tag" >&2
        printf '      clear what the push reported above, then run `just resume-release`.\n' >&2
        printf '      gitlore refuses the push while a memory store is diverged: `/gitlore:resolve`\n' >&2
        printf '      in Claude Code clears it. Repeat the pair if the push is refused again.\n' >&2
        die "push of $main_branch failed"
    }
    acted=1
    # Name the revision uploaded, not just the branch: a commit made after it
    # stays local, and a bare "pushed" reads as if it went too.
    local subject
    subject=$(git log -1 --format=%s "$push_commit")
    [ "${#subject}" -le 60 ] || subject="${subject:0:59}…"
    note "branch $main_branch: pushed $(git rev-parse --short "$push_commit") $subject ($(git log -1 --format=%cr "$push_commit"))"
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
    local tip dist_sha="" landed=0 dist_tag dist_tree parent remote_dist local_dist
    dist_tag="dist-v$V"
    tip=$(ls_remote_sha . refs/heads/dist)
    if [ -n "$tip" ]; then
        git cat-file -e "$tip" 2>/dev/null \
            || git fetch -q origin dist \
            || die "could not fetch origin's dist branch to check it — nothing was pushed to dist"
        # The message is the record of which release commit the branch was built
        # from, so a match means this release's dist already landed.
        if [ "$(git log -1 --format=%s "$tip")" = "dist v$V from $release_commit" ]; then
            landed=1
            dist_sha="$tip"
        fi
    fi
    if [ "$landed" = 0 ]; then
        dist_tree=$(bash "$here/dist.sh" tree "$release_commit") \
            || die "the dist tree for $tag was refused (see dist: lines above) — nothing was pushed to dist"
        # The pre-flight validated HEAD before the bump. A resume has no such
        # check on this tree, so it validates the tree it is about to publish.
        if [ "$mode" = resume ]; then
            bash "$here/dist.sh" validate "$dist_tree" \
                || die "the dist tree for $tag failed claude plugin validate --strict — nothing was pushed to dist"
        fi
        # The commit is reproducible: dates come from $release_commit and the parent is the
        # branch tip, so the same inputs rebuild the same sha on a resume.
        if [ -n "$tip" ]; then
            parent="$tip"
            dist_sha=$(bash "$here/dist.sh" commit "$release_commit" "$dist_tree" "$V" "$parent") \
                || die "dist.sh could not build the dist commit for $tag — nothing was pushed to dist"
        else
            dist_sha=$(bash "$here/dist.sh" commit "$release_commit" "$dist_tree" "$V") \
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
