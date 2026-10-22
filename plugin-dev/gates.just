# Gate sentinels for a consumer's own gate recipes. Opt-in: nothing here is
# imported by release.just, so a plugin that does not import this file is
# unaffected. Imported into a plugin's justfile via:
#
#     import 'plugin-dev/gates.just'
#
# A gate is a pure function of its declared inputs, so re-running it over an
# untouched tree only reprints the last verdict. A recipe that opens with the
# prolog below and guards on its inputs skips itself when they have not moved:
#
#     precommit:
#         #!{{ plugin_dev_gate_prolog }}
#         sentinel-guard precommit .claude-plugin hooks scripts tests
#         just format
#         hash-sentinel
#         shellcheck scripts/*.sh
#         plugin-dev/run-bats.sh tests/*.bats
#         record-sentinel
#
# The functions the prolog defines, for a recipe body to call:
#
#   sentinel-guard <gate> <pathspec>...   first line of the body; exits the
#                                         recipe 0, reporting "cached", when the
#                                         inputs match the last recorded pass
#   hash-sentinel                         after a formatter that may rewrite
#                                         inputs, before the checks; re-takes
#                                         the hash record-sentinel records
#   record-sentinel                       last line of the body; records the pass
#   check-sentinel <gate> <pathspec>...   the guard without the exit, for a body
#                                         that wants to branch on it
#   gate-inputs-hash                      the cksum the others compare
#
# Environment:
#
#   PLUGIN_DEV_GATE_FORCE=1   run the checks whatever the sentinel says; any
#                             non-empty value does, `0` included
#   PLUGIN_DEV_GATE_DIR=dir   keep sentinels there instead of in the gitdir
#   PLUGIN_DEV_GATE_TOOLS     tool versions to fold into the hash: one shell
#                             command per line, each printing a version. Empty
#                             by default. Set it in the justfile with
#                             `export PLUGIN_DEV_GATE_TOOLS := "bats --version\njq --version"`
#
# One guard per recipe body. `check-sentinel` sets shell variables
# `record-sentinel` reads back, so a second gate in the same body would clobber
# the first's, and the prolog refuses it. Give each gate its own recipe.
#
# The pathspecs are an allow-list the consumer declares, and a gate caches
# correctly only while every check it runs reads inside it. The justfile and the
# vendored `plugin-dev` tree are always hashed too, as absolute paths apart from
# the list, so an exclude in the list never subtracts from them. A pathspec that
# matches no file is refused. See plugin-dev/manual/gates.md before choosing one.

[private]
plugin_dev_gate_prolog := "/usr/bin/env bash\nset -euo pipefail\n" + "gate_builtins=(" + quote(justfile()) + " " + quote(source_directory()) + ")\n" + '''
# The inputs every gate hashes whatever its pathspecs say: the justfile and the
# vendored toolkit tree, as absolute paths just reports. A literal name would be
# resolved against the directory the recipe runs in, and match nothing under
# `[working-directory]`, in a module, or for a file named `Justfile`.
# Recipe name, then input pathspecs. The recipe name is the gate name: it
# keys the sentinel file and heads the report. Leaves the recipe when the
# inputs are unchanged -- `exit`, not `return`, because a shebang recipe is one
# script and the checks follow on the next line.
sentinel-guard () {
    if check-sentinel "$@"; then
        echo "$1: cached (inputs unchanged)"
        exit 0
    fi
}

# Run after the checks, never before. A hash that cannot be computed leaves no
# sentinel: a partial hash would match itself on the next run if the failure is
# deterministic, skipping a tree nothing checked. Say so loudly; a cache that
# quietly stopped caching is the failure nobody hears about.
#
# The pass is recorded only against the hash `check-sentinel` took before the
# checks started, or `hash-sentinel` re-took after a formatter. A peer session editing an input mid-run moves the hash, and
# recording the new one would seal in a pass for a tree nothing checked. The
# checks themselves passed -- the body is a script under errexit and got here --
# so the recipe keeps their verdict and only the sentinel is withheld.
record-sentinel () {
    if [ -z "${sentinel:-}" ]; then
        echo "record-sentinel: no sentinel-guard ran earlier in this recipe body" >&2
        exit 1
    fi
    hash=$(gate-inputs-hash) || hash=""
    if [ -z "$hash" ] || [ -z "${guard_hash:-}" ]; then
        rm -f "$sentinel"
        echo "gate: could not hash inputs; the pass was NOT recorded" >&2
        return
    fi
    if [ "$hash" != "$guard_hash" ]; then
        rm -f "$sentinel"
        echo "gate: inputs changed while the checks ran; the pass was NOT recorded" >&2
        return
    fi
    printf '%s\n' "$hash" > "$sentinel"
}

# Optional, between a formatter and the checks. A formatter placed after the
# guard is skipped on a cached run, but its edits move the inputs away from the
# hash the guard took, so `record-sentinel` would refuse the pass. Re-taking the
# hash here records the formatted tree instead, in the same run. The checks
# start after this line, so the hash still describes the tree they read; only
# the formatter, which is not a check, saw the tree before it. A hash that
# cannot be computed empties `guard_hash`, and `record-sentinel` then refuses.
hash-sentinel () {
    if [ -z "${sentinel:-}" ]; then
        echo "hash-sentinel: no sentinel-guard ran earlier in this recipe body" >&2
        exit 1
    fi
    guard_hash=$(gate-inputs-hash) || guard_hash=""
}

# Gate name, then input pathspecs. Sets `sentinel_dir`, `sentinel`, `gate_cwd`,
# `gate_inputs` and `guard_hash` for `record-sentinel`.
#
# The sentinel lives under the gitdir, not the working tree: bookkeeping that
# showed up in `git status` -- or in its own input hash -- would invalidate the
# gate on every run. Its path and the pathspecs are relative to the directory
# the guard ran in, and a recipe body may `cd` before it records, so both are
# pinned here: `sentinel` is absolute and `gate_cwd` is where the hash looks.
#
# `PLUGIN_DEV_GATE_DIR` puts it somewhere else, for a caller that runs a recipe
# without meaning its verdict: a test that drives the real recipe with its
# checks stubbed out would otherwise overwrite the real pass.
#
# Every refusal is an explicit `exit`: this runs as the condition of an `if` in
# `sentinel-guard`, where bash suspends errexit, so a failing command would
# otherwise be skipped and the function would carry on.
check-sentinel () {
    if [ -n "${sentinel:-}" ]; then
        echo "check-sentinel: gate '$1' follows gate '${sentinel##*/}' in one recipe body; each gate needs its own recipe" >&2
        exit 1
    fi
    if [ "$#" -lt 2 ]; then
        echo "check-sentinel: usage: <gate> <pathspec>... -- a gate needs a name and at least one pathspec" >&2
        exit 1
    fi
    case "$1" in
        ''|.|..|*/*)
            echo "check-sentinel: gate name '$1' must be a plain name, it becomes a file name" >&2
            exit 1
            ;;
    esac
    sentinel_dir=${PLUGIN_DEV_GATE_DIR:-$(git rev-parse --git-path plugin-dev/gates)}
    if [ -z "$sentinel_dir" ]; then
        echo "check-sentinel: no sentinel directory -- not in a git repository, or git failed" >&2
        exit 1
    fi
    case "$sentinel_dir" in
        /*) ;;
        *) sentinel_dir=$PWD/$sentinel_dir ;;
    esac
    mkdir -p "$sentinel_dir" || exit 1
    sentinel="$sentinel_dir/$1"; shift
    # A pathspec that matches nothing is a typo that would cache forever. An
    # exclude has no files of its own to match.
    for spec in "$@"; do
        case "$spec" in
            :\!*|:^*|:/\!*|:/^*) continue ;;
            :\(*\)*)
                magic=${spec#:(}
                case ",${magic%%)*}," in *,exclude,*) continue ;; esac
                ;;
        esac
        # Stops at the first file rather than listing them all.
        IFS= read -r -d '' _ < <(git ls-files -z --cached --others --exclude-standard -- "$spec") || {
            echo "check-sentinel: pathspec '$spec' matches no file" >&2
            exit 1
        }
    done
    gate_cwd=$PWD
    gate_inputs=("$@")
    # Taken before the checks run, and on every path -- a forced run and a
    # first run reach `record-sentinel` too. It is what `record-sentinel`
    # compares against, so a pass describes the tree the checks read rather
    # than whatever the tree became while they ran. Empty means unhashable.
    guard_hash=$(gate-inputs-hash) || guard_hash=""
    [ -z "${PLUGIN_DEV_GATE_FORCE:-}" ] || return 1
    [ -f "$sentinel" ] || return 1
    [ -n "$guard_hash" ] || return 1
    recorded=$(cat "$sentinel")
    [ "$recorded" = "$guard_hash" ]
}

# Names as well as contents, so a rename or deletion counts; each regular
# file's execute bit, since a hook that loses it stops running, followed
# through a symlink to its target; a symlink's own target path, since pointing
# it elsewhere changes what a check reads even when the contents match, and a
# directory or dangling link has no contents to show it; the tool
# versions `PLUGIN_DEV_GATE_TOOLS` lists, for a consumer that does not pin them;
# `--others --exclude-standard` so a brand-new file is hashed before it is
# added -- when a stale pass hurts most -- while ignored files stay out. A
# gitlink path, or a tracked file since deleted, is hashed by name only: it is
# not a regular file, so nothing inside it, nor its commit, reaches the hash.
#
# Contents go through `cksum`, one process over the whole list. Its line holds
# the file's checksum, size and name, so a name and a content cannot run
# together into the bytes of another tree. A file it cannot read fails it, and
# `xargs` and `pipefail` carry that to the caller. Residual bounds: a file name
# holding a newline can imitate a `cksum` line, and `$(readlink)` drops trailing
# newlines, so two link targets that differ only by them hash alike.
#
# Every component fails explicitly rather than leaning on errexit: this runs in
# a command substitution inside a condition, where bash suspends errexit, so an
# unguarded version command that died would drop out of the stream and the
# gate would keep caching against a hash that no longer covers it.
gate-inputs-hash () {
    {
        # The group heads a pipeline, so it is a subshell: `exit` fails the
        # pipeline and pipefail carries that to the caller, and the `cd` is not
        # the recipe's.
        cd "${gate_cwd:-.}" || exit 1
        if [ -n "${PLUGIN_DEV_GATE_TOOLS:-}" ]; then
            while IFS= read -r tool_cmd; do
                [ -n "$tool_cmd" ] || continue
                printf 'tool: %s\n' "$tool_cmd"
                bash -c "$tool_cmd" 2>&1 || exit 1
            done <<< "$PLUGIN_DEV_GATE_TOOLS"
        fi
        # Two listings, so an exclude in the caller's pathspecs subtracts from
        # theirs alone and never from the built-ins.
        {
            git ls-files -z --cached --others --exclude-standard -- "${gate_inputs[@]}" || exit 1
            git ls-files -z --cached --others --exclude-standard -- "${gate_builtins[@]/#/:(literal)}" || exit 1
        } | LC_ALL=C sort -zu \
            | {
                  regular=()
                  while IFS= read -r -d '' file; do
                      mode='?'
                      link=''
                      if [ -L "$file" ]; then link=$(readlink -- "$file") || exit 1; fi
                      if [ -f "$file" ]; then
                          regular+=("$file")
                          if [ -x "$file" ]; then mode=x; else mode=-; fi
                      fi
                      printf '%s %s\0%s\0' "$mode" "$file" "$link"
                  done
                  [ "${#regular[@]}" -eq 0 ] \
                      || printf '%s\0' "${regular[@]}" | xargs -0 cksum --
              } || exit 1
    } | cksum
}
'''
