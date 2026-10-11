#!/usr/bin/env bash
# PreToolUse hook for Write|Edit. The autodrive sentinel is written only by
# handoff-checkpoint, which composes it from the payload's transition fields and
# reads it back through the parser. A direct agent Write/Edit to a file of that
# name is denied outright, in this project or outside it.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# One jq parse, then the basename: this is the Write/Edit hot path, and every
# other file leaves here. One field per line (not @tsv: tab is IFS-whitespace,
# so an empty field would collapse and shift the next).
{ read -r file_path; read -r hook_cwd; } < <(
    jq -r '.tool_input.file_path // "", .cwd // ""'
) || true
[[ "${file_path##*/}" == "autodrive" ]] || exit 0

cwd="$(handoff_root "$hook_cwd")"
[[ -n "$cwd" ]] || exit 0
{ read -r target; read -r expected; } \
    < <(handoff_resolve "$file_path" "$cwd/$HANDOFF_REL_DRIVE")
if [[ "$target" != "$expected" ]]; then
    handoff_deny \
        "write blocked: autodrive outside this project's .claude/. resolved: $target; expected: $expected." \
        "write-guard: blocked autodrive write outside $cwd/.claude/"
fi

handoff_deny \
    "autodrive is written only by handoff-checkpoint; direct Write/Edit is not allowed." \
    "write-guard: autodrive is checkpoint-only"
