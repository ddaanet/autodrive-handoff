#!/usr/bin/env bash
# The file-safety primitives: no-follow reads, replacing writes, markers.
# Part of _lib.sh. Source-only; no shebang
# execution. Reached through _lib.sh, which sources it after its own
# definitions, so callers source _lib.sh and never this file:
#   # shellcheck source-path=SCRIPTDIR source=_lib.sh
#   source "$(dirname "$0")/_lib.sh"

# <path> [own]. Print a status line, then on `ok` the file's bytes, opened with
# O_NOFOLLOW so the check and the read are one step: no link put at the name
# at any moment is followed. The status is `ok`, `absent`, `link` (the last
# component is a link, dangling or not), `other` (not a regular file, or
# unreadable) or, with `own`, `foreign` (a regular file another user owns).
# Nothing printed means python3 failed, which is no answer about the file:
# handoff_drive_read returns 2 on it, and the other callers skip what they
# would have done with the bytes. Read it
# as `{ IFS= read -r status; …; } < <(handoff_read_regular …)`, so the bytes
# follow on the same stream and a NUL in them survives a `read -d ''`.
handoff_read_regular() {
    python3 -I -c '
import errno, os, stat, sys
try:
    fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
except FileNotFoundError:
    print("absent")
    sys.exit(0)
except OSError as e:
    print("link" if e.errno == errno.ELOOP else "other")
    sys.exit(0)
st = os.fstat(fd)
if not stat.S_ISREG(st.st_mode):
    print("other")
elif sys.argv[2] == "own" and st.st_uid != os.geteuid():
    print("foreign")
else:
    try:
        sys.stdout.write("ok\n")
        sys.stdout.flush()
        with os.fdopen(fd, "rb") as f:
            sys.stdout.buffer.write(f.read())
            sys.stdout.flush()
    except BrokenPipeError:
        # A caller that stops reading early, as the record trim does.
        os._exit(0)
' "$1" "${2:-any}"
}

# <source> <destination>. rename(2) through os.replace: a link at the
# destination is replaced, never followed. `mv` stats the destination, and a
# link to a directory there would receive the file inside it.
handoff_replace() {
    python3 -I -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' "$1" "$2"
}

# The per-session markers in $HANDOFF_POINTER_DIR (the drift marker, and the
# prompt marker the checkpoint leaves) are used only in a directory that is no
# link, is this user's and is writable by no one else. The directory is shared
# by every local user, so it and every name in it may be a link someone else
# planted: each marker is read with handoff_read_regular (no link followed) and
# written with handoff_write_marker. Where the directory fails the test there is
# no marker at all.
marker_dir_ok() {
    [[ -d "$HANDOFF_POINTER_DIR" && ! -L "$HANDOFF_POINTER_DIR" && -O "$HANDOFF_POINTER_DIR" ]] \
        && [[ -z "$(find "$HANDOFF_POINTER_DIR" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]]
}

# <path> <value>. Write <value>, NUL-terminated, to <path>: a mktemp sibling
# renamed over the name (handoff_replace), so a link at the name is replaced and
# never written through. The sibling is named `<path>.XXXXXX`, which matches the
# marker's own glob, so session-pointer.sh sweeps an orphan. Returns 1, leaving
# no sibling behind, when any step fails.
handoff_write_marker() {
    local path="$1" value="$2" tmp
    tmp="$(mktemp "$path.XXXXXX" 2>/dev/null)" || return 1
    if ! printf '%s\0' "$value" > "$tmp" \
        || ! handoff_replace "$tmp" "$path"; then
        rm -f "$tmp"
        return 1
    fi
}

# <path>. Read a per-session marker in $HANDOFF_POINTER_DIR into the caller's
# scope, the handoff_drive_read idiom: MARKER_STATUS is `absent` when the
# directory does not exist (nothing was ever written there, so there is no
# marker), `nodir` when it exists and fails marker_dir_ok (nothing is read),
# else handoff_read_regular's status with `own` (`ok`, `absent`, `link`,
# `other`, `foreign`), or empty when python3 failed; MARKER_VALUE is the bytes,
# NUL-terminated and read whole so a value holding a newline or edge whitespace
# survives, and is empty unless the status is `ok`. Always returns 0. The drift
# marker and the prompt marker are read through here, so neither can skip the
# directory test or the no-follow open.
# shellcheck disable=SC2034  # assigned for the caller's scope
handoff_read_marker() {
    MARKER_STATUS="" MARKER_VALUE=""
    if [[ ! -e "$HANDOFF_POINTER_DIR" && ! -L "$HANDOFF_POINTER_DIR" ]]; then
        MARKER_STATUS="absent"
        return 0
    fi
    if ! marker_dir_ok; then
        MARKER_STATUS="nodir"
        return 0
    fi
    {
        IFS= read -r MARKER_STATUS || true
        if [[ "$MARKER_STATUS" == ok ]]; then
            IFS= read -r -d '' MARKER_VALUE || true
        fi
    } < <(handoff_read_regular "$1" own)
}
