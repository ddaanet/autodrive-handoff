#!/usr/bin/env bash
# PreToolUse hook for Write|Edit. The autodrive sentinel is written only by
# handoff-checkpoint, which composes it from the payload's transition fields and
# reads it back through the parser. A direct agent Write/Edit to a file of that
# name is denied outright, in this project or outside it.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# One jq parse, then the basename: this is the Write/Edit hot path, and every
# other file leaves here. The two fields are NUL-terminated and read whole: a
# path is any JSON string, and one holding a newline would otherwise be judged
# on its first line while the tool writes to all of it.
#
# The basename is the filter, so what it does not catch is a write that reaches
# the sentinel under another name: through a symlink, or through a case variant
# on a case-insensitive filesystem.
{ IFS= read -r -d '' file_path; IFS= read -r -d '' hook_cwd; } < <(
    jq -j '(.tool_input.file_path // ""), "\u0000", (.cwd // ""), "\u0000"'
) || true
[[ "${file_path##*/}" == "autodrive" ]] || exit 0

cwd="$(handoff_root "$hook_cwd")"
[[ -n "$cwd" ]] || exit 0
{ IFS= read -r target; IFS= read -r expected; } \
    < <(handoff_resolve "$file_path" "$cwd/$HANDOFF_REL_DRIVE")
if [[ "$target" != "$expected" ]]; then
    handoff_deny \
        "write blocked: autodrive outside this project's .claude/. resolved: $target; expected: $expected." \
        "write-guard: blocked autodrive write outside $cwd/.claude/"
fi

handoff_deny \
    "autodrive is written only by handoff-checkpoint; direct Write/Edit is not allowed." \
    "write-guard: autodrive is checkpoint-only"
