#!/usr/bin/env bash
# check-size: every file git does not ignore, read from disk, must hold at most
# `cap` bytes, or `hub_cap` when it is a SKILL.md at any depth. A file's size is
# all of its bytes, whitespace and newlines included, as `wc -c` counts them.
# Exemptions are listed one per line in the root size.exempt, each with a reason.
#
# Usage: bash toolkit/check-size.sh   (no arguments, from anywhere in the tree)
# Exit 0 prints one sign-off line on stdout. Exit 1 prints one stderr line per
# failure, and a hint after any overage.

main() {
    export LC_ALL=C
    if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        fail_run "not inside a git work tree"
    fi
    cd "$root" || fail_run "cannot enter $root"
    scan_listing
    count_kept
    read_exempt
    judge
}

cap=20000
hub_cap=10000

# GNU coreutils stat answers --version; BSD/macOS stat rejects it. The flavour is
# chosen here, once, and count_kept runs the argv it names.
if stat --version >/dev/null 2>&1; then
    stat_cmd=(stat -c %s --)
else
    stat_cmd=(stat -f %z --)
fi

# scan_listing: one listing of the tree, sorted by path, and the scope skips in
# order. Fills kept[] (files that reach the count) and the skip counts.
scan_listing() {
    local rec info path listed=0
    kept=()
    skipped_builtin=0
    skipped_binary=0
    skipped_symlink=0
    skipped_unreadable=0
    while IFS= read -r -d '' rec; do
        listed=$((listed + 1))
        info=${rec%%$'\t'*}
        path=${rec#*$'\t'}
        if [ -L "$path" ]; then
            skipped_symlink=$((skipped_symlink + 1))
        elif [ ! -f "$path" ]; then
            continue
        elif [ ! -r "$path" ]; then
            printf 'check-size: unreadable file skipped: %s\n' "$path" >&2
            skipped_unreadable=$((skipped_unreadable + 1))
        else
            case $info in
                *'w/-text'*) skipped_binary=$((skipped_binary + 1)); continue ;;
            esac
            if is_builtin "$path"; then
                skipped_builtin=$((skipped_builtin + 1))
            else
                kept+=("$path")
            fi
        fi
    done < <(git ls-files -z -co --exclude-standard --eol | sort -z -t $'\t' -k2)
    if [ "$listed" -eq 0 ]; then
        fail_run "no files listed"
    fi
}

# is_builtin <path>: plugin-dev/ and root plans/ as whole leading components,
# and uv.lock or package-lock.json as the basename at any depth.
is_builtin() {
    case $1 in
        plugin-dev|plugin-dev/*|plans|plans/*) return 0 ;;
    esac
    case ${1##*/} in
        uv.lock|package-lock.json) return 0 ;;
    esac
    return 1
}

# count_kept: one batched stat over the kept files, in listing order, so the
# output lines pair with kept[] by position. The names reach xargs NUL-delimited
# and stat gets them after `--`, so no name is split or read as an option. xargs
# may run stat more than once for a long list; its output stays in order.
count_kept() {
    local i=0 line out nkept=${#kept[@]}
    counts=()
    if (( nkept == 0 )); then
        return 0
    fi
    if ! out="$(printf '%s\0' "${kept[@]}" | xargs -0 "${stat_cmd[@]}")"; then
        fail_run "counting failed: stat exited with an error"
    fi
    while IFS= read -r line; do
        counts[i]=$line
        i=$((i + 1))
    done <<<"$out"
    if (( i != nkept )); then
        fail_run "counting failed: $i counts for $nkept files"
    fi
}

# read_exempt: parse the root size.exempt into ex_paths[] (accepted entries)
# and refusals (stderr lines). Entries are checked against kept[] and counts[].
read_exempt() {
    local lineno=0 line p why k exact matched repeat lim nkept=${#kept[@]}
    ex_paths=()
    refusals=""
    [ -e size.exempt ] || return 0
    if [ ! -r size.exempt ]; then
        fail_run "cannot read size.exempt"
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line=${line%$'\r'}
        trim "$line"
        [ -n "$REPLY" ] || continue
        [[ $REPLY != '#'* ]] || continue
        case $line in
            *' #'*) p=${line%% #*}; why=${line#* #} ;;
            *) p=$line; why= ;;
        esac
        trim "$p"
        p=${REPLY%/}   # a directory entry may end in /, as in dist.include
        trim "$why"
        why=$REPLY
        if [ -z "$why" ]; then
            refuse "$lineno" "$p" "no reason after the hash"
            continue
        fi
        if is_builtin "$p"; then
            refuse "$lineno" "$p" "a built-in is always skipped"
            continue
        fi
        repeat=0
        for ((k = 0; k < ${#ex_paths[@]}; k++)); do
            if [ "${ex_paths[k]}" = "$p" ]; then
                repeat=1
                break
            fi
        done
        if (( repeat )); then
            refuse "$lineno" "$p" "already listed on an earlier line"
            continue
        fi
        exact=-1
        matched=0
        for ((k = 0; k < nkept; k++)); do
            if [ "${kept[k]}" = "$p" ]; then
                exact=$k
                matched=1
                break
            fi
            case ${kept[k]} in
                "$p"/*) matched=1 ;;
            esac
        done
        if (( ! matched )); then
            refuse "$lineno" "$p" "matches no listed file"
            continue
        fi
        if (( exact >= 0 )); then
            cap_for "${kept[exact]}"
            lim=$REPLY
            if (( counts[exact] <= lim )); then
                refuse "$lineno" "$p" "a file entry must be over its cap"
                continue
            fi
        fi
        ex_paths+=("$p")
    done < size.exempt
}

# refuse <line> <path> <why>: one refusal line, the failure is the caller's.
refuse() {
    refusals+="size.exempt:$1: $2 — $3"$'\n'
}

# trim <string>: leading and trailing blanks removed, into REPLY.
trim() {
    REPLY=$1
    while [[ $REPLY == [[:blank:]]* ]]; do REPLY=${REPLY#?}; done
    while [[ $REPLY == *[[:blank:]] ]]; do REPLY=${REPLY%?}; done
}

# cap_for <path>: the cap that applies to the path, into REPLY.
cap_for() {
    if [ "${1##*/}" = SKILL.md ]; then
        REPLY=$hub_cap
    else
        REPLY=$cap
    fi
}

# under_any <path> <prefix>...: the path equals a prefix or lies under one.
under_any() {
    local p="$1" s
    shift
    for s in "$@"; do
        if [ "$s" = . ] || [ "$p" = "$s" ] || [[ "$p" == "$s/"* ]]; then
            return 0
        fi
    done
    return 1
}

# judge: print refusals and overages, then the sign-off or the failure.
judge() {
    local i p n lim label overage="" hubs=0 failed=0 nkept=${#kept[@]}
    for ((i = 0; i < nkept; i++)); do
        p=${kept[i]}
        n=${counts[i]}
        cap_for "$p"
        lim=$REPLY
        label=""
        if (( lim == hub_cap )); then
            hubs=$((hubs + 1))
            label=" (SKILL.md hub)"
        fi
        if (( n > lim )) && ! under_any "$p" ${ex_paths[@]+"${ex_paths[@]}"}; then
            overage+="oversized-file: $p: $n bytes > $lim$label"$'\n'
        fi
    done
    if [ -n "$refusals" ]; then
        printf '%s' "$refusals" >&2
        failed=1
    fi
    if [ -n "$overage" ]; then
        printf '%s' "$overage" >&2
        printf '%s\n' "hint: split each file along a seam; do not shave prose or docstrings to fit" >&2
        failed=1
    fi
    if (( failed )); then
        exit 1
    fi
    printf 'check-size: cap %s bytes: %s files; hub cap %s: %s SKILL.md; size.exempt: %s entries, each with a reason and still needed; skipped: %s plans/plugin-dev/lockfiles, %s binary, %s symlinks, %s unreadable\n' \
        "$cap" "$nkept" "$hub_cap" "$hubs" "${#ex_paths[@]}" \
        "$skipped_builtin" "$skipped_binary" "$skipped_symlink" "$skipped_unreadable"
}

# fail_run <reason>: the one-line failure of the whole run.
fail_run() {
    printf 'check-size: %s\n' "$1" >&2
    exit 1
}

main "$@"
