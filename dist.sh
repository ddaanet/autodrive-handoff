#!/usr/bin/env bash
# The dist branch's one script. Run from a plugin repo's root, or given the
# root (paths), it reads the dist.include allowlist and does the jobs release.sh
# and dogfood.sh need:
#
#   enabled <commit>                     exit 0 when <commit> carries dist.include
#   tree <commit>                        print the sha of a tree holding exactly the listed paths,
#                                        refused when a Markdown reference in it leaves it
#   validate <tree>                      claude plugin validate --strict on that tree, extracted
#   commit <src> <tree> <ver> [<parent>] print a commit of <tree>, author and committer copied from <src>
#   paths <root>                         print <root>/dist.include's paths, NUL-delimited
#
# The allowlist is one path per line, relative to the root. Blank lines and
# lines starting with # are skipped; a trailing / is stripped. Paths are
# literal: absolute paths, .. components, leading or trailing blanks, and the
# glob or escape characters * ? [ ] \ are refused.
#
# A refusal prints one dist: line per problem on stderr and exits 1; stdout
# carries only the result. `paths` exits 3, silently, when dist.include is
# absent: that is "not opted in", not a refusal. Warnings go to stderr,
# dist:-prefixed, and exit 0; they send the plugin to directory review, they do
# not block it. Warnings are computed on the result tree only.
set -euo pipefail
unset CDPATH   # else a `cd` may echo its target into a $(...) capture
export GIT_LITERAL_PATHSPECS=1

main() {
    local cmd="${1:-}"
    problems=0
    [ $# -eq 0 ] || shift
    case "$cmd" in
        enabled) cmd_enabled "$@" ;;
        tree) cmd_tree "$@" ;;
        validate) cmd_validate "$@" ;;
        commit) cmd_commit "$@" ;;
        paths) cmd_paths "$@" ;;
        *) die "unknown subcommand '$cmd': expected enabled, tree, validate, commit or paths" ;;
    esac
}

cmd_enabled() {
    [ $# -eq 1 ] || die "usage: dist.sh enabled <commit>"
    local commit
    commit="$(git rev-parse --verify --quiet "$1^{commit}")" || die "'$1' is not a commit"
    [ -n "$(git ls-tree --full-tree "$commit" -- dist.include)" ]
}

cmd_tree() {
    [ $# -eq 1 ] || die "usage: dist.sh tree <commit>"
    local commit manifest_sha="" i p path mode sha size meta entry included
    local count tree
    commit="$(git rev-parse --verify --quiet "$1^{commit}")" || die "'$1' is not a commit"
    command -v jq >/dev/null 2>&1 || die "jq is not on PATH; tree reads the license from plugin.json"
    make_tmp
    [ -n "$(git ls-tree --full-tree "$commit" -- dist.include)" ] \
        || die "no dist.include in $commit: the plugin is not opted in"
    git cat-file blob "$commit:dist.include" > "$tmp/allow"
    read_allowlist "$tmp/allow" "$tmp/listed"

    listed=()
    while IFS= read -r -d '' p; do
        listed+=("$p")
    done < "$tmp/listed"
    count=${#listed[@]}
    matched=()
    i=0
    while [ "$i" -lt "$count" ]; do
        matched+=(0)
        i=$((i + 1))
    done

    # Every entry of the commit, recursive, with sizes. An entry is in the
    # result when it equals a listed path or sits under one.
    git ls-tree --full-tree -r -l -z "$commit" > "$tmp/ls"
    : > "$tmp/info"
    : > "$tmp/files"
    while IFS= read -r -d '' entry; do
        meta="${entry%%$'\t'*}"
        path="${entry#*$'\t'}"
        read -r mode _ sha size <<<"$meta"
        included=0
        i=0
        while [ "$i" -lt "$count" ]; do
            p="${listed[$i]}"
            if [[ "$path" == "$p" || "$path" == "$p/"* ]]; then
                matched[i]=1
                included=1
            fi
            i=$((i + 1))
        done
        [ "$included" -eq 1 ] || continue
        case "$mode" in
            160000) problem "$path is a gitlink (submodule) in $commit; a gitlink cannot ship in the dist tree" ;;
            120000) problem "$path is a symlink in $commit; a symlink cannot ship in the dist tree" ;;
            *)
                printf '%s %s\t%s\0' "$mode" "$sha" "$path" >> "$tmp/info"
                printf '%s\t%s\t%s\0' "$sha" "$size" "$path" >> "$tmp/files"
                if [ "$path" = ".claude-plugin/plugin.json" ]; then
                    manifest_sha="$sha"
                fi
                ;;
        esac
    done < "$tmp/ls"

    i=0
    while [ "$i" -lt "$count" ]; do
        if [ "${matched[$i]}" -eq 0 ]; then
            problem "dist.include lists '${listed[$i]}', which matches nothing in $commit"
        fi
        i=$((i + 1))
    done
    if [ -z "$manifest_sha" ]; then
        problem "the dist tree has no .claude-plugin/plugin.json"
    elif ! git cat-file blob "$manifest_sha" | jq -e . >/dev/null 2>&1; then
        problem ".claude-plugin/plugin.json is not valid JSON"
    fi
    [ "$problems" -eq 0 ] || exit 1

    GIT_INDEX_FILE="$tmp/index" git update-index -z --index-info < "$tmp/info"
    tree="$(GIT_INDEX_FILE="$tmp/index" git write-tree)"
    check_refs "$tree"
    warn_result "$tmp/files" "$manifest_sha"
    printf '%s\n' "$tree"
}

cmd_validate() {
    [ $# -eq 1 ] || die "usage: dist.sh validate <tree>"
    command -v claude >/dev/null 2>&1 \
        || die "claude is not on PATH; validate runs claude plugin validate --strict"
    local tree rc=0
    tree="$(git rev-parse --verify --quiet "$1^{tree}")" || die "'$1' is not a tree"
    make_tmp
    mkdir "$tmp/plugin"
    git archive "$tree" | tar -x -C "$tmp/plugin" || die "could not extract $tree"
    # claude's stdout goes to stderr: this script's stdout carries nothing here.
    (cd "$tmp/plugin" && claude plugin validate --strict "$tmp/plugin") 1>&2 || rc=$?
    exit "$rc"
}

cmd_commit() {
    [ $# -eq 3 ] || [ $# -eq 4 ] || die "usage: dist.sh commit <source-commit> <tree> <version> [<parent>]"
    local src tree version an ae ad cn ce cd msg parent=""
    src="$(git rev-parse --verify --quiet "$1^{commit}")" || die "'$1' is not a commit"
    tree="$(git rev-parse --verify --quiet "$2^{tree}")" || die "'$2' is not a tree"
    version="$3"
    an="$(git log -1 --format=%an "$src")"
    ae="$(git log -1 --format=%ae "$src")"
    ad="$(git log -1 --date=raw --format=%ad "$src")"
    cn="$(git log -1 --format=%cn "$src")"
    ce="$(git log -1 --format=%ce "$src")"
    cd="$(git log -1 --date=raw --format=%cd "$src")"
    msg="dist v$version from $src"
    if [ $# -eq 4 ]; then
        parent="$(git rev-parse --verify --quiet "$4^{commit}")" || die "'$4' is not a commit"
        GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" GIT_AUTHOR_DATE="$ad" \
            GIT_COMMITTER_NAME="$cn" GIT_COMMITTER_EMAIL="$ce" GIT_COMMITTER_DATE="$cd" \
            git commit-tree "$tree" -p "$parent" -m "$msg"
    else
        GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" GIT_AUTHOR_DATE="$ad" \
            GIT_COMMITTER_NAME="$cn" GIT_COMMITTER_EMAIL="$ce" GIT_COMMITTER_DATE="$cd" \
            git commit-tree "$tree" -m "$msg"
    fi
}

cmd_paths() {
    [ $# -eq 1 ] || die "usage: dist.sh paths <root>"
    local root="$1" p
    [ -f "$root/dist.include" ] || exit 3
    make_tmp
    read_allowlist "$root/dist.include" "$tmp/listed"
    while IFS= read -r -d '' p; do
        if [ ! -e "$root/$p" ] && [ ! -L "$root/$p" ]; then
            problem "dist.include lists '$p', which matches nothing in $root"
        fi
    done < "$tmp/listed"
    [ "$problems" -eq 0 ] || exit 1
    cat "$tmp/listed"
}

# check_refs <tree>: check-refs.sh's shipped check over the built tree, where
# every file is shipped, so a Markdown reference must resolve inside the tree.
# Each line it refuses with becomes one dist: line.
check_refs() {
    local refs_sh line
    refs_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-refs.sh"
    [ -f "$refs_sh" ] || die "check-refs.sh is missing beside dist.sh; run just update-plugin-dev"
    if ! bash "$refs_sh" --tree "$1" >/dev/null 2>"$tmp/refs"; then
        while IFS= read -r line; do
            problem "$line"
        done < "$tmp/refs"
        [ "$problems" -gt 0 ] || problem "check-refs.sh failed on $1 and said nothing"
        exit 1
    fi
}

die() {
    printf 'dist: %s\n' "$1" >&2
    exit 1
}

problem() {
    printf 'dist: %s\n' "$1" >&2
    problems=$((problems + 1))
}

make_tmp() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
}

# read_allowlist <file> <out>: writes the normalised paths to <out>,
# NUL-delimited, and reports each refused line with problem(). A refused line
# is not matched against the tree, so it yields one refusal, not two.
read_allowlist() {
    local line n=0 p cr=$'\r'
    : > "$2"
    if grep -q "$cr" "$1"; then
        problem "dist.include has CRLF line endings (a carriage return); save it with LF"
        exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        case "$line" in
            ''|'#'*) continue ;;
            [[:blank:]]*|*[[:blank:]])
                problem "dist.include line $n '$line' has a leading or trailing blank"
                continue ;;
            /*)
                problem "dist.include line $n '$line' is absolute; listed paths are relative to the root"
                continue ;;
        esac
        case "/$line/" in
            */../*)
                problem "dist.include line $n '$line' has a .. component"
                continue ;;
        esac
        case "$line" in
            *'*'*|*'?'*|*'['*|*']'*|*\\*)
                problem "dist.include line $n '$line' has a glob or escape character (* ? [ ] or backslash); listed paths are literal"
                continue ;;
        esac
        p="${line%/}"
        case "/$p/" in
            */./*) problem "dist.include line $n '$line' has a . component"; continue ;;
            */.git/*) problem "dist.include line $n '$line' names .git"; continue ;;
        esac
        case "$p" in
            *//*|*/) problem "dist.include line $n '$line' has an empty component"; continue ;;
        esac
        printf '%s\0' "$p" >> "$2"
    done < "$1"
    [ "$problems" -eq 0 ] || exit 1
}

# warn <text>: one dist: warning on stderr. Every warning ends the same way.
warn() {
    printf 'dist: warning: %s; the plugin goes to directory review, it is not blocked\n' "$1" >&2
}

# warn_result <files> <manifest-sha>: the result tree's warnings. <files> is
# NUL-delimited records of "sha TAB size TAB path".
warn_result() {
    local rec sha rest size path n=0 readme_sha="" license_root=0 words
    while IFS= read -r -d '' rec; do
        n=$((n + 1))
        sha="${rec%%$'\t'*}"
        rest="${rec#*$'\t'}"
        size="${rest%%$'\t'*}"
        path="${rest#*$'\t'}"
        case "$path" in
            */*) ;;
            LICENSE*) license_root=1 ;;
        esac
        if [ "$path" = "README.md" ]; then
            readme_sha="$sha"
        fi
        if [ "$size" -gt 262144 ]; then
            case "$path" in
                *.png|*.jpg|*.jpeg|*.gif|*.webp|*.woff|*.woff2|*.ttf|*.otf) ;;
                *) warn "$path is $size bytes, over 256 KiB" ;;
            esac
        fi
    done < "$1"
    if [ "$n" -gt 512 ]; then
        warn "the tree has $n files, over 512"
    fi
    if [ -z "$readme_sha" ]; then
        warn "the tree has no root README.md"
    else
        words="$(git cat-file blob "$readme_sha" | wc -w | tr -d ' ')"
        if [ "$words" -lt 40 ]; then
            warn "README.md has $words words, under 40"
        fi
    fi
    if [ "$license_root" -eq 0 ] \
        && ! git cat-file blob "$2" | jq -e '(.license // "") != ""' >/dev/null 2>&1; then
        warn "no LICENSE file at the root and no license in plugin.json"
    fi
}

main "$@"
