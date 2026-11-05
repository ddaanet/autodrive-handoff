#!/usr/bin/env bash
# shellcheck shell=bash  # sourced, never run: check-size.sh and check-refs.sh
# Shared by check-size.sh and check-refs.sh, which source it from their own
# directory and share their shell. Not executable. Holds the one reader of their
# exempt lists (size.exempt, refs.exempt) and the one scope rule both apply.

# read_path_list <file>: parse a path list into the parallel arrays
# list_paths[], list_whys[] and list_lines[], one slot per entry. A line is read
# with its CR stripped; a blank line and a line whose first non-blank is # are
# skipped; blanks around the path are trimmed; a trailing / is dropped from the
# path; and " # reason" after the path is the reason, empty when there is none.
# Returns 1 when the file cannot be read, with the arrays empty.
read_path_list() {
    local lineno=0 line p why
    list_paths=()
    list_whys=()
    list_lines=()
    [ -r "$1" ] || return 1
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
        list_paths+=("$p")
        list_whys+=("$REPLY")
        list_lines+=("$lineno")
    done < "$1"
}

# in_scope_skip <path>: plugin-dev/ and root plans/ as whole leading
# components. Both checks skip these always; no exempt list brings them back.
in_scope_skip() {
    case $1 in
        plugin-dev|plugin-dev/*|plans|plans/*) return 0 ;;
    esac
    return 1
}

# trim <string>: leading and trailing blanks removed, into REPLY.
trim() {
    REPLY=$1
    while [[ $REPLY == [[:blank:]]* ]]; do REPLY=${REPLY#?}; done
    while [[ $REPLY == *[[:blank:]] ]]; do REPLY=${REPLY%?}; done
}
