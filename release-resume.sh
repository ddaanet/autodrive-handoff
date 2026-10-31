# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # globals shared with release.sh's shell
#
# Sourced by release.sh, never run on its own. The resume preflight: it decides
# whether there is a release to finish, and which hint explains a refusal when
# there is not.
#
# It runs in release.sh's shell, so release.sh's `set -euo pipefail` and its
# die/note helpers apply here, and this function reads and sets the run's
# globals (`V`, `tag`) directly rather than through arguments or output.

resume_preflight() {
    V=$(jq -r .version "$manifest")
    tag="v$V"
    # Resume only ever finishes a release whose commit and tag already landed
    # locally. No tag means no release was started at this version, and tagging
    # HEAD on a guess would tag whatever work landed since.
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || {
        # The refusal above is already decided — everything below only picks
        # which hint explains it, so a failed probe must never turn this into a
        # harder refusal. Capture rule as in release_preflight (release-tags.sh),
        # applied to BOTH listings: this is a `|| { … }` group, where `set -e` is in force (the
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
            # guard in release-tags.sh's release_preflight: an empty local tag
            # set says nothing about what is published. Naming the bump form rather than falling through to
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
