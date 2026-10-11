#!/usr/bin/env bash
# PreToolUse hook for Write|Edit. The autodrive sentinel is written only by
# handoff-checkpoint, which composes it from the payload's transition fields and
# reads it back through the parser. A direct agent Write/Edit to a file of that
# name is denied outright, in this project or outside it.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# One jq parse and a substring test: this is the Write/Edit hot path, and
# every path that does not mention the sentinel's name leaves here. The two
# fields are NUL-terminated and read whole, since a path is any JSON string
# and one holding a newline would otherwise be judged on its first line while
# the tool writes to all of it.
{ IFS= read -r -d '' file_path; IFS= read -r -d '' hook_cwd; } < <(
    jq -j '(.tool_input.file_path // ""), "\u0000", (.cwd // ""), "\u0000"'
) || true
[[ "$file_path" == *autodrive* ]] || exit 0

# The verdict is on the resolved path, never the one given: the tool
# normalises what it is handed, so `autodrive/`, `autodrive/.` and
# `x/../autodrive` all land on the sentinel. Trailing whitespace is dropped
# from the name before the test, so a variant the tool might trim is denied
# rather than guessed at.
#
# What this does not catch is the sentinel reached under a name that does not
# contain its own: a symlink called something else, or a case variant on a
# case-insensitive filesystem.
cwd="$(handoff_root "$hook_cwd")"
[[ -n "$cwd" ]] || exit 0
{ IFS= read -r -d '' target; IFS= read -r -d '' expected; } \
    < <(handoff_resolve "$file_path" "$cwd/$HANDOFF_REL_DRIVE") || true
name="${target##*/}"
name="${name%"${name##*[![:space:]]}"}"
[[ "$name" == "autodrive" ]] || exit 0

if [[ "$target" != "$expected" ]]; then
    handoff_deny \
        "write blocked: autodrive outside this project's .claude/. resolved: $target; expected: $expected." \
        "write-guard: blocked autodrive write outside $cwd/.claude/"
fi

handoff_deny \
    "autodrive is written only by handoff-checkpoint; direct Write/Edit is not allowed." \
    "write-guard: autodrive is checkpoint-only"
