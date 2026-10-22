#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR  # follow the sourced siblings (needs -x)
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
# A plugin that carries dist.include (see dist.sh) also publishes its shipped
# paths as the `dist` branch and a `dist-vX.Y.Z` tag, and its marketplace entry
# follows that branch. Such a release needs `claude` on PATH for validation.
#
# Run from the plugin root (the directory holding .claude-plugin/plugin.json);
# `just release` does that for you. Requires bash, jq, git, gh, and
# MARKETPLACE_DIR pointing at the claude-plugins repo.
#
# The flow's functions live in sibling files sourced below, from this script's
# own directory: release-preflight.sh (checks before any side effect),
# release-tags.sh (release history, and the version this run publishes),
# release-publish.sh (commit, tag, pushes, dist, GitHub release) and
# release-marketplace.sh (the marketplace entry). They share this shell, so the
# `set` line at the top and the globals set here hold in all of them.

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
# 1 when the commit being released carries dist.include (dist_opted_in).
dist_on=0

# shellcheck source=release-preflight.sh
source "$here/release-preflight.sh"
# shellcheck source=release-tags.sh
source "$here/release-tags.sh"
# shellcheck source=release-publish.sh
source "$here/release-publish.sh"
# shellcheck source=release-marketplace.sh
source "$here/release-marketplace.sh"

common_preflight
if [ "$mode" = "release" ]; then
    release_preflight
    dist_preflight
    bump_commit_tag
else
    resume_preflight
    dist_opted_in "$tag^{commit}"
fi
push_branch
push_tag
if [ "$dist_on" = 1 ]; then
    push_dist
fi
create_github_release
bump_marketplace
if [ "$mode" = "resume" ] && [ "$acted" = 0 ]; then
    note "release $tag is already complete (nothing to do)"
else
    note "Release $tag complete"
fi
