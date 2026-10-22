# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # globals shared with release.sh's shell
#
# Sourced by release.sh, never run on its own. The release-history reads and
# the two mode-specific preflights built on them: release_preflight decides the
# version a release publishes (bump or first release), and resume_preflight
# decides whether there is a release to finish.
#
# It runs in release.sh's shell, so release.sh's `set -euo pipefail` and its
# die/note helpers apply here, and these functions read and set the run's
# globals (`V`, `tag`, `first_release`, `bump`, `bump_arg`) directly rather
# than through arguments or output.

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
    # word of the `set` line at the top of release.sh.
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
    # the `set -o pipefail` line at the top of release.sh — a failed
    # `git tag --list` returns 1 here directly, rather than relying on pipefail
    # to carry a mid-pipeline failure past semver_tags.
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
    # exempts only the gitlore submodule — never
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
