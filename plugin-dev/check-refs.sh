#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR  # follow the sourced sibling (needs -x)
# Refuses broken Markdown references. Run from anywhere inside a plugin repo, as
# a dependency of its `precommit`; `dist.sh tree` runs it again, with --tree, on
# the tree it builds.
#
#   check-refs.sh                       both checks, the shipped set from dist.include
#   check-refs.sh --shipped <path>...   both checks, the shipped set given here
#   check-refs.sh --tree <tree>         every reference in <tree> resolves inside it
#
# A reference is an inline link or image, [text](target) or ![alt](target), or
# a reference definition, [label]: target, whose target is relative. A target
# with a scheme (https:, mailto:), a pure #anchor, an absolute /path, a
# footnote, an escaped \[bracket\], and anything inside a fenced code block, an
# inline code span or an HTML comment are not references; neither is a
# backticked path. The #fragment is dropped,
# <angle brackets> and a trailing "title" are read, and %XX escapes decoded. A
# target is resolved from the directory of the file that holds it.
#
# The files read are the Markdown files on disk that git does not ignore,
# tracked or not (`git ls-files -co --exclude-standard`), always from disk:
# never a file under plugin-dev/, the vendored toolkit, nor one inside a
# submodule. Two checks:
#
#   resolves               the target exists: git lists it, tracked or
#                          untracked but not ignored, and it is on disk; or it
#                          is a directory holding such a file, or lies inside a
#                          submodule and is on disk. A target above the root
#                          leaves the repository. A file under an exempt path is
#                          skipped: the paths listed in refs.exempt at the root,
#                          one per line with # comments, or, with no such file,
#                          docs/changelog and plans, whose dated records stay
#                          true about a file deleted later.
#   shipped stays shipped  with a dist.include, or --shipped, a reference from
#                          a shipped file reaches a shipped file that exists.
#                          No exemption applies. The set is read by
#                          `dist.sh paths`; a path is shipped when it equals a
#                          listed path or lies under one, and the root is.
#                          An untracked target passes here; the dist build,
#                          reading the commit, refuses it until committed.
#
# Every offending reference is one line on stderr, `docs/a.md:12: target —
# reason`, and the exit is 1. A pass prints one line naming the checks that ran
# and their counts.
#
# Bounds: an indented (four-space) code block is read as prose, since a list
# item's continuation looks the same; a backtick that never closes hides the
# rest of its paragraph, as an inline code span would.
set -euo pipefail
unset CDPATH   # else a `cd` may echo its target into a $(...) capture
export GIT_LITERAL_PATHSPECS=1

main() {
    local tree="" mode=disk
    have_shipped=0
    shipped=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --tree)
                [ $# -eq 2 ] || die "usage: check-refs.sh --tree <tree>"
                mode=tree
                tree="$2"
                shift 2 ;;
            --shipped)
                shift
                [ $# -gt 0 ] || die "--shipped needs at least one path"
                have_shipped=1
                while [ $# -gt 0 ]; do
                    shipped+=("$(trim_slash "$1")")
                    shift
                done ;;
            *) die "unknown argument '$1': expected --shipped <path>... or --tree <tree>" ;;
        esac
    done
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bad=0
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    if [ "$mode" = tree ]; then
        check_tree "$tree"
    else
        check_disk
    fi
}

check_disk() {
    local root f idx=0 rc=0 files=0 refs=0 skipped=0 sfiles=0 srefs=0
    local in_shipped is_exempt n raw res st
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git work tree"
    cd "$root"
    load_exempt
    if [ "$have_shipped" -eq 1 ]; then
        for f in "${shipped[@]}"; do
            [ -e "$f" ] || die "--shipped names '$f', which does not exist under $root"
        done
    elif [ -f dist.include ]; then
        bash "$here/dist.sh" paths "$root" > "$tmp/shipped" || rc=$?
        [ "$rc" -eq 0 ] || exit 1   # dist.sh has said why, on stderr
        while IFS= read -r -d '' f; do
            shipped+=("$f")
        done < "$tmp/shipped"
        have_shipped=1
    fi

    # One listing serves twice: the files to read, and the targets that
    # exist. A target exists when git lists it and it is on disk, or it is a
    # directory holding such a file, or it lies inside a listed directory (a
    # submodule, a nested repo), where the disk decides. So an ignored target
    # is refused, an untracked one the author is about to add is not, and the
    # match is exact-case on a case-folding filesystem too.
    git ls-files -z -co --exclude-standard > "$tmp/files"
    : > "$tmp/members"
    : > "$tmp/dirs"
    : > "$tmp/refs"
    names=()
    while IFS= read -r -d '' f; do
        if [ -d "$f" ] && [ ! -L "$f" ]; then
            printf '%s\n' "${f%/}" >> "$tmp/dirs"
            continue
        elif [ -e "$f" ] || [ -L "$f" ]; then
            printf '%s\n' "$f" >> "$tmp/members"
        fi
        case "$f" in
            plugin-dev/*) continue ;;
            *.md|*.markdown) ;;
            *) continue ;;
        esac
        # Not a regular file: a tracked file deleted from disk.
        [ -f "$f" ] || continue
        in_shipped=0
        if [ "$have_shipped" -eq 1 ] && is_shipped "$f"; then in_shipped=1; fi
        is_exempt=0
        if under_any "$f" ${exempt[@]+"${exempt[@]}"}; then is_exempt=1; fi
        if [ "$is_exempt" -eq 1 ]; then
            skipped=$((skipped + 1))
        else
            files=$((files + 1))
        fi
        [ "$in_shipped" -eq 0 ] || sfiles=$((sfiles + 1))
        [ "$is_exempt" -eq 0 ] || [ "$in_shipped" -eq 1 ] || continue
        names+=("$f")
        # shellcheck disable=SC2094  # reads $f, appends to $tmp/refs
        extract "$(dir_of "$f")" < "$f" \
            | sed "s/^/$idx	$in_shipped	$is_exempt	/" >> "$tmp/refs"
        idx=$((idx + 1))
    done < "$tmp/files"

    classify "$tmp/members" "$tmp/dirs" "$tmp/refs" > "$tmp/classified"
    while IFS=$'\t' read -r idx in_shipped is_exempt n raw res st; do
        f="${names[$idx]}"
        [ "$is_exempt" -eq 1 ] || refs=$((refs + 1))
        [ "$in_shipped" -eq 0 ] || srefs=$((srefs + 1))
        if [ "$st" = disk ] && { [ -e "$res" ] || [ -L "$res" ]; }; then
            st=ok
        fi
        case "$st" in
            up) report "$f" "$n" "$raw" "leaves the repository" ;;
            ok)
                if [ "$in_shipped" -eq 1 ] && ! is_shipped "$res"; then
                    report "$f" "$n" "$raw" "is not shipped"
                fi ;;
            *)
                # check-ignore refuses the literal-pathspec magic exported above.
                if GIT_LITERAL_PATHSPECS=0 git check-ignore -q -- "$res" 2>/dev/null; then
                    report "$f" "$n" "$raw" "is ignored by git"
                else
                    report "$f" "$n" "$raw" "does not exist"
                fi ;;
        esac
    done < "$tmp/classified"

    [ "$bad" -eq 0 ] || exit 1
    local shipped_line="skipped (no dist.include)"
    if [ "$have_shipped" -eq 1 ]; then
        shipped_line="$srefs references from $sfiles shipped files"
    fi
    printf 'check-refs: resolves: %s references in %s files, %s exempt files skipped; shipped stays shipped: %s\n' \
        "$refs" "$files" "$skipped" "$shipped_line"
}

# check_tree <tree>: the shipped check over a built tree, where every file is
# shipped. Reads blobs and paths from the object store, never from disk.
check_tree() {
    local tree entry meta path type sha files=0 refs=0 n raw res
    tree="$(git rev-parse --verify --quiet "$1^{tree}")" || die "'$1' is not a tree"
    git ls-tree -r -z --full-tree "$tree" > "$tmp/files"
    while IFS= read -r -d '' entry; do
        meta="${entry%%$'\t'*}"
        path="${entry#*$'\t'}"
        read -r _ type sha <<<"$meta"
        [ "$type" = blob ] || continue
        case "$path" in
            *.md|*.markdown) ;;
            *) continue ;;
        esac
        files=$((files + 1))
        git cat-file blob "$sha" | extract "$(dir_of "$path")" > "$tmp/refs"
        while IFS=$'\t' read -r n raw res; do
            refs=$((refs + 1))
            case "$res" in
                ..|../*) report "$path" "$n" "$raw" "leaves the repository" ;;
                *)
                    if ! in_tree "$tree" "$res"; then
                        report "$path" "$n" "$raw" "is not in the tree"
                    fi ;;
            esac
        done < "$tmp/refs"
    done < "$tmp/files"
    [ "$bad" -eq 0 ] || exit 1
    printf 'check-refs: in the tree: %s references in %s files\n' "$refs" "$files"
}

# in_tree <tree> <path>: the normalised path names an entry of the tree.
in_tree() {
    case "$2" in
        .) return 0 ;;
        ..|../*) return 1 ;;
    esac
    git rev-parse --verify --quiet "$1:$2" >/dev/null
}

# load_exempt: sets exempt=() from refs.exempt, or to the defaults.
load_exempt() {
    local line
    exempt=()
    if [ ! -f refs.exempt ]; then
        exempt=(docs/changelog plans)
        return
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in
            ''|'#'*) continue ;;
        esac
        exempt+=("$(trim_slash "$line")")
    done < refs.exempt
}

# is_shipped <path>: the root holds every shipped path, so it counts as one.
is_shipped() {
    [ "$1" != . ] || return 0
    under_any "$1" ${shipped[@]+"${shipped[@]}"}
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

trim_slash() {
    local p="$1"
    while [ "$p" != / ] && [[ "$p" == */ ]]; do p="${p%/}"; done
    printf '%s' "$p"
}

dir_of() {
    case "$1" in
        */*) printf '%s' "${1%/*}" ;;
    esac
}

report() {
    printf '%s:%s: %s — %s\n' "$1" "$2" "$3" "$4" >&2
    bad=$((bad + 1))
}

die() {
    printf 'check-refs: %s\n' "$1" >&2
    exit 1
}

# shellcheck source=check-refs-parse.sh
source "$(dirname "${BASH_SOURCE[0]}")/check-refs-parse.sh"

main "$@"
