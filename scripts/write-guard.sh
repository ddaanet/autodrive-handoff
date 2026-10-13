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

# The verdict is never on the path as given. `autodrive/`, `autodrive/.` and
# `x/../autodrive` all normalise onto the sentinel under a last component that
# is not its name, and resolving follows symlinks, so the sentinel's own
# resolved name need not be `autodrive` either. Three paths settle it, each
# NUL-terminated: where the write lands, where this project's sentinel lands,
# and the given path normalised without following links.
#
# What this does not catch is the sentinel reached by a path that does not
# mention its name: through a symlink called something else, or a case variant
# on a case-insensitive filesystem.
handoff_root_read "$hook_cwd"
cwd="$HANDOFF_ROOT"
# Without the root, whether this write lands on the sentinel cannot be judged,
# and the path already names it: refuse rather than let it through.
if [[ "$HANDOFF_ROOT_BRANCH" == "unresolved" ]]; then
    handoff_deny \
        "autodrive write refused: $HANDOFF_UNRESOLVED_MSG, so whether this path is the sentinel cannot be judged." \
        "write-guard: $HANDOFF_UNRESOLVED_MSG; autodrive write refused"
fi
[[ -n "$cwd" ]] || exit 0
{ IFS= read -r -d '' target; IFS= read -r -d '' expected; IFS= read -r -d '' lexical; } < <(
    python3 -I -c 'import os, sys
given, sentinel = sys.argv[1:]
for p in (os.path.realpath(given), os.path.realpath(sentinel),
          os.path.normpath(os.path.abspath(given))):
    sys.stdout.write(p + "\0")' "$file_path" "$cwd/$HANDOFF_REL_DRIVE"
) || true

if [[ -n "$target" && "$target" == "$expected" ]]; then
    handoff_deny \
        "autodrive is written only by handoff-checkpoint; direct Write/Edit is not allowed." \
        "write-guard: autodrive is checkpoint-only"
fi

# Anywhere else, a write whose name is the sentinel's at either end is another
# project's. Trailing whitespace is dropped from the name first, so a variant a
# tool might trim is denied rather than guessed at.
for name in "${target##*/}" "${lexical##*/}"; do
    name="${name%"${name##*[![:space:]]}"}"
    if [[ "$name" == "autodrive" ]]; then
        handoff_deny \
            "write blocked: autodrive outside this project's .claude/. resolved: $target; expected: $expected." \
            "write-guard: blocked autodrive write outside $cwd/.claude/"
    fi
done
