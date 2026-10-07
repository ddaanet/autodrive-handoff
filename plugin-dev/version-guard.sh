#!/usr/bin/env bash
# PreToolUse hook (Write|Edit) for the plugin manifest.
# Refuses any edit that changes plugin.json's .version. Once a plugin has
# released, the release recipe owns the version: a manual edit desyncs the
# manifest from the latest tag and is only caught at release time. Before a
# first release there is no tag to desync from, and the version the initial
# release publishes is the maintainer's own committed hand edit -- the hook
# refuses there too, because it governs agent edits and not the
# maintainer's. The two cases differ only in the deny wording below.
#
# Mechanical: agent is not involved.
set -euo pipefail

input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
[[ -n "$file_path" ]] || exit 0

# CLAUDE_PROJECT_DIR, not the payload `cwd`: `cwd` tracks the Bash tool's
# persistent shell and drifts with a `cd` or an /add-dir. Locating the
# manifest from a drifted cwd finds nothing and exits 0 -- a silent, total
# bypass. install.sh wires the hook command around CLAUDE_PROJECT_DIR for
# the same reason. No fallback to the payload cwd: that reintroduces it.
project="${CLAUDE_PROJECT_DIR:-$PWD}"
manifest="${project%/}/.claude-plugin/plugin.json"
[[ -f "$manifest" ]] || exit 0

# Absolutise in shell rather than with `realpath -m`: BSD/macOS realpath
# has no -m, so both substitutions come back empty, `[[ "" == "" ]]` is
# true, and the guard fires on every file instead of just the manifest.
# The manifest path is built here rather than supplied, so symlink
# resolution buys nothing. tool_input.file_path is whatever the model
# emitted and is not always absolute, and a relative one may be meant
# against either root, so a match on either counts.
abspath() {
    local root="$1" p="${2#./}"
    case "$p" in
      /*) printf '%s\n' "$p" ;;
      *)  printf '%s\n' "${root%/}/$p" ;;
    esac
}
[[ "$(abspath "$project" "$file_path")" == "$manifest" \
   || "$(abspath "$PWD" "$file_path")" == "$manifest" ]] || exit 0

current="$(jq -r '.version // ""' "$manifest" 2>/dev/null || echo "")"
[[ -n "$current" ]] || exit 0  # manifest unparseable; let the edit through.

tool_name="$(jq -r '.tool_name // ""' <<<"$input")"

proposed=""
case "$tool_name" in
  Write)
    proposed="$(jq -r '.tool_input.content // ""' <<<"$input" \
      | jq -r '.version // ""' 2>/dev/null || echo "")"
    ;;
  Edit)
    # Apply the edit to the manifest and re-read .version from the result,
    # instead of pattern-matching new_string for a "version" key. The
    # shortest edit that bumps the version is old_string "1.2.3" ->
    # new_string "9.9.9", which repeats no key to match, and it is the
    # form an agent reaches for first.
    old_string="$(jq -r '.tool_input.old_string // ""' <<<"$input")"
    new_string="$(jq -r '.tool_input.new_string // ""' <<<"$input")"
    if [[ -n "$old_string" ]]; then
      replace_all="$(jq -r 'if .tool_input.replace_all then "true" else "false" end' <<<"$input")"
      # jq's split/1 splits on a literal string, not a regex, so JSON
      # punctuation in old_string matches as written -- which a bash
      # ${text/pat/rep} would not, its pattern being a glob. `empty` when
      # old_string is absent from the manifest: that edit fails anyway.
      patched="$(jq -rn --arg t "$(cat "$manifest")" --arg o "$old_string" \
                        --arg n "$new_string" --argjson all "$replace_all" '
        ($t | split($o)) as $parts
        | if ($parts | length) < 2 then empty
          elif $all then ($parts | join($n))
          else $parts[0] + $n + ($parts[1:] | join($o))
          end')"
      proposed="$(jq -r '.version // ""' <<<"$patched" 2>/dev/null || echo "")"
    fi
    ;;
  *) exit 0 ;;
esac

[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0

# A claude process started from inside a git hook can inherit GIT_DIR (and
# friends), which overrides the -C below and redirects the listing at
# whatever repo the enclosing git invocation was using -- measured: GIT_DIR
# alone does this, GIT_WORK_TREE and GIT_COMMON_DIR do not. Cleared by a
# hardcoded list rather than `unset $(git rev-parse --local-env-vars)`:
# that discovery call is itself a git invocation, and would fail right
# along with a genuinely absent or failing git (below), clearing nothing
# when it matters most. This list is git's stable repo-local discovery
# vars; a future git adding another one is a gap here, not a silent one.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE \
      GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_GRAFT_FILE GIT_SHALLOW_FILE

# Whether this plugin has ever released, to pick the deny wording below.
# 2>/dev/null on the listing: on a CLAUDE_PROJECT_DIR that is not a git
# repository at all (the common case pre-release), git's "not a git
# repository" is an expected outcome here, not a diagnostic. This hook is
# silent on stderr whatever it decides, and the toolkit's own test suite
# asserts that against a non-repo project directory.
# A CLAUDE_PROJECT_DIR that is not itself a repo but sits inside one
# lists the enclosing repo's tags instead; that only changes the wording
# below, never the deny decision already established above. Same semver
# filter release.sh's semver_tags uses, duplicated rather than sourced:
# release.sh runs its flow at top level and isn't written to be sourced.
#
# A failed listing (git absent, killed, not a repo, ...) is not the same
# answer as an empty one (a repo with no matching tags): the two take
# opposite wordings below, so folding a failure into an empty string would
# answer "never released" for a listing that told us nothing. But every
# status here still has to be absorbed -- the deny is already decided
# above, and a hook that exits non-zero for any reason other than 2 is a
# non-blocking error to Claude Code, so the just-refused edit proceeds.
# Absorbing a status after the deny is fail-closed -- the worst outcome is
# the wrong wording on a refusal that still refuses; propagating one is
# fail-open, exiting non-2 with no stdout so the edit goes through. So the
# listing is read inside an `if` condition and the filter's status is bound
# to its own capture with `||`, both places where errexit is suspended;
# every outcome -- listing failure, filter no-match, and any other filter
# exit -- is turned into a plain variable rather than a status left on the
# table. No pipe is used for either, which also sidesteps pipefail entirely
# instead of reasoning through it (the older piped form's `|| true` did
# have to).
if listing="$(git -C "$project" tag --list 'v*' --sort=-v:refname 2>/dev/null)"; then
  listing_failed=0
else
  listing_failed=1
fi

release_tags=""
if [[ "$listing_failed" -eq 0 ]]; then
  # The `||` keeps the status bound to the capture it belongs to, in one
  # statement: grep_status is assigned on every path and there is no `$?`
  # for a later edit to displace. The earlier `if`/`else` form read `$?` as
  # the first statement of an errexit-live branch body, where inserting a
  # single line above it both clobbered the status and exited the hook
  # non-2 with no stdout -- measured, and a total bypass of the refusal.
  grep_status=0
  release_tags="$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$listing")" || grep_status=$?
  # 0 == matched, 1 == no match (an empty-but-successful listing); both are
  # answers. Anything else is a real filter failure, folded into "listing
  # failed" so it takes the same restrictive wording rather than a third,
  # untested path.
  [[ "$grep_status" -le 1 ]] || { listing_failed=1; release_tags=""; }
fi

if [[ "$listing_failed" -eq 0 && -z "$release_tags" ]]; then
read -r -d '' agent_reason <<EOF || true
plugin.json version edit refused: $current -> $proposed.

This plugin has never been released -- no vX.Y.Z tag exists yet, so the
manifest is not tracking a previous release. It holds $current, which is
what the initial release will publish, verbatim. Which version a plugin
first ships as is the maintainer's call and their edit to make.

Do not bypass this guard, modify the recipe, or alter version state by
other means.
EOF
else
# Also reached when the listing itself failed: "don't know" takes the
# restrictive, steady-state wording rather than the permissive one.
read -r -d '' agent_reason <<EOF || true
plugin.json version edit refused: $current -> $proposed.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

The release recipe owns this version -- invoke it instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.
EOF
fi

human_msg="version-guard: blocked plugin.json version edit ($current -> $proposed)"

# stdout and exit 0, not stderr and exit 2. Claude Code parses a hook's
# stdout as JSON, and only on exit 0. `permissionDecision: "deny"` there
# blocks the call exactly as exit 2 does, and additionally delivers
# systemMessage; on exit 2 the JSON is handed to the model as raw stderr
# text and the human channel never fires at all.
jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
