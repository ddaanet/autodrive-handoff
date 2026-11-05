#!/usr/bin/env bash
# check-frontmatter: every skill, agent and command file git does not ignore,
# read from disk, must open with a YAML frontmatter block that parses to a
# mapping, with a non-blank string `description`. A `name` is required of a
# skill and an agent, and must be a non-blank string when present; a skill's
# `name` must equal its directory, and an agent's need not match its filename.
# A command's `name` is optional and free. Skills are skills/*/SKILL.md; agents
# and commands are the .md files under agents/ and commands/ at any depth. Other
# .md files under a skill are reference files and are not read.
#
# Usage: bash toolkit/check-frontmatter.sh [root]
# The root defaults to the current directory and must lie inside a git work
# tree; a root below the repository's top level reads that subtree alone.
# Exit 0 prints one sign-off line on stdout. Exit 1 prints one stderr line per
# problem, each prefixed `check-frontmatter: <path>: `, and nothing else.
#
# The YAML parse runs under the Python named by python3 on PATH, with PyYAML
# importable. The file list reaches it NUL-delimited on stdin, so no path is
# split. Interpreter remedy: pyyaml is in the dev group of pyproject.toml, `uv
# sync` materializes .venv, and .envrc puts .venv/bin on PATH.

set -euo pipefail
export LC_ALL=C

main() {
    cd -- "${1:-.}" 2>/dev/null || fail_run "cannot enter ${1:-.}"
    listing="$(mktemp "${TMPDIR:-/tmp}/check-frontmatter.XXXXXX")"
    trap 'rm -f "$listing"' EXIT
    git ls-files -z -co --exclude-standard >"$listing" 2>/dev/null \
        || fail_run "not a git work tree: $PWD"
    files=()
    while IFS= read -r -d '' path; do
        is_checked "$path" || continue
        # Not a regular file: a tracked file deleted from disk.
        [ -f "$path" ] || continue
        files+=("$path")
    done <"$listing"
    if [ "${#files[@]}" -eq 0 ]; then
        printf 'check-frontmatter ok (0 skills, 0 agents, 0 commands)\n'
        exit 0
    fi
    if ! python3 -I -c 'import yaml' >/dev/null 2>&1; then
        fail_run "python3 with PyYAML not found on PATH: add pyyaml to the dev group of pyproject.toml, run uv sync, and put .venv/bin on PATH from .envrc"
    fi
    printf '%s\0' "${files[@]}" | python3 -I -c "$program"
}

# is_checked <path>: the path is a file this check reads. In a case pattern `*`
# also matches `/`, so agents/*.md and commands/*.md reach any depth; the
# skills/*/*/* arm comes first so a deeper SKILL.md or reference file is skipped.
is_checked() {
    case $1 in
        skills/*/*/*) return 1 ;;
        skills/*/SKILL.md) return 0 ;;
        agents/*.md) return 0 ;;
        commands/*.md) return 0 ;;
    esac
    return 1
}

# fail_run <reason>: the one-line failure of the whole run.
fail_run() {
    printf 'check-frontmatter: %s\n' "$1" >&2
    exit 1
}

# program: the embedded Python. It reads NUL-delimited paths on stdin, prints
# one stderr line per problem, and signs off on stdout when every file passes.
IFS= read -r -d '' program <<'PY' || true
import sys

import yaml

def block_reasons(raw, path, kind):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return ["not UTF-8"]
    lines = text.split("\n")
    if lines[0] != "---":
        return ["no frontmatter block: line one is not exactly ---"]
    try:
        closing = lines.index("---", 1)
    except ValueError:
        return ["no frontmatter block: no closing --- line"]
    block = "\n".join(lines[1:closing])
    try:
        data = yaml.safe_load(block)
    except Exception as error:
        return ["block is not YAML: " + " ".join(str(error).split())]
    if not isinstance(data, dict):
        return ["block is not a mapping"]
    return field_reasons(data, path, kind)

def field_reasons(data, path, kind):
    reasons = []
    directory = path.decode("utf-8", "replace").split("/")[-2]
    if "description" not in data:
        reasons.append("description is missing")
    elif not isinstance(data["description"], str):
        reasons.append("description is not a string")
    elif not data["description"].strip():
        reasons.append("description is blank")
    if "name" in data:
        if not isinstance(data["name"], str):
            reasons.append("name is not a string")
        elif not data["name"].strip():
            reasons.append("name is blank")
        elif kind == "skills" and data["name"] != directory:
            reasons.append("name %r differs from its directory %r" % (data["name"], directory))
    elif kind in ("skills", "agents"):
        reasons.append("name is missing")
    return reasons

def kind_of(path):
    if path.startswith(b"skills/"):
        return "skills"
    if path.startswith(b"agents/"):
        return "agents"
    return "commands"

def main():
    counts = {"skills": 0, "agents": 0, "commands": 0}
    failed = False
    for path in sys.stdin.buffer.read().split(b"\0"):
        if not path:
            continue
        kind = kind_of(path)
        counts[kind] += 1
        with open(path, "rb") as handle:
            raw = handle.read()
        for reason in block_reasons(raw, path, kind):
            failed = True
            line = b"check-frontmatter: " + path + b": "
            line += reason.encode("utf-8", "backslashreplace") + b"\n"
            sys.stderr.buffer.write(line)
    if failed:
        sys.exit(1)
    print("check-frontmatter ok (%d skills, %d agents, %d commands)" % (
        counts["skills"], counts["agents"], counts["commands"]))

main()
PY

main "$@"
