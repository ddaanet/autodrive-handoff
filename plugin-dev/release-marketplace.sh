# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # globals shared with release.sh's shell
#
# Sourced by release.sh, never run on its own. The last step of a release and
# its only write outside the plugin repo: bumping, or creating, the plugin's
# entry in marketplace.json, then committing and pushing it.
#
# It runs in release.sh's shell, so release.sh's `set -euo pipefail` and its
# die/note helpers apply here, and these functions read and set the run's
# globals (`V`, `tag`, `dist_on`, `acted`, `marketplace_*`, `plugin_name`)
# directly rather than through arguments or output.

bump_marketplace() {
    local mp_tmp repo_slug mp_branch mp_remote_head mp_local_head committed=0
    mp_tmp=$(mktemp)
    if [ "$marketplace_entry_exists" = 1 ]; then
        # An opted-in plugin's entry follows the dist branch: only .source.ref is
        # added, the rest of the source is left as it is.
        jq --arg n "$plugin_name" --arg v "$V" --argjson dist "$dist_on" '
          (.plugins[] | select(.name == $n) | .version) = $v
          | if $dist == 1 then (.plugins[] | select(.name == $n) | .source.ref) = "dist" else . end
        ' "$marketplace_json" > "$mp_tmp"
    else
        # The slug builds the `url` source's https clone url. A `github` source
        # clones over SSH, which a user without a GitHub SSH key cannot use.
        # Strip a trailing .git, then everything up to the host separator,
        # leaving `owner/repo` for both git@host:owner/repo and
        # https://host/owner/repo.
        repo_slug=$(git remote get-url origin | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')
        jq --arg v "$V" --arg repo "$repo_slug" --argjson dist "$dist_on" --slurpfile m "$manifest" '
          .plugins += [{
            name: $m[0].name,
            source: ({ source: "url", url: ("https://github.com/" + $repo + ".git") }
              + (if $dist == 1 then { ref: "dist" } else {} end)),
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
    #
    # Compared as JSON values, not bytes: jq always writes 2-space JSON, so a
    # byte comparison reads a marketplace.json kept in any other style as
    # changed and rewrites it wholesale, committing a whole-file diff for a
    # file already at $V. A jq failure (a file the earlier jq already read, so
    # not expected) reads as "differs", which falls through to the rewrite.
    if jq -en --slurpfile a "$mp_tmp" --slurpfile b "$marketplace_json" '$a == $b' >/dev/null; then
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
