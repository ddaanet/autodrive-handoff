import 'plugin-dev/release.just'
import 'plugin-dev/gates.just'

# Tool versions the gates' cached passes are keyed on, beyond what uv.lock pins
# (ruff, mypy, ty, docformatter, pytest): the system tools every check shells
# out to, and the claude binary that validates the plugin and runs the mod tests.
export PLUGIN_DEV_GATE_TOOLS := "bats --version\nshellcheck --version\njq --version\ngit --version\npython3 --version\nclaude --version"

# autodrive-handoff plugin — dev recipes
#
# `precommit` is the gate that runs before every commit: two cached gates, then
# two uncached ones. The cached pair is split because the cheap plugin checks
# read `skills/` and `.claude-plugin/`,
# which the slow code checks never do: a skill edit must not pay for the
# bats and pytest runs. `check-plugin` lints the manifests + settings, validates
# the plugin, runs the mod tests and shellchecks; `check-code` lints/type-checks
# the Python (mypy AND ty — ty catches Any-narrowing holes mypy launders
# through; its version is locked, so gating it can't break the build
# spontaneously) and runs the hook + pytest suites. Each skips itself while the
# files it reads are unchanged; `PLUGIN_DEV_GATE_FORCE=1 just precommit` runs
# them regardless, as before a release. `check-refs` (Markdown links) and
# `check-size` (the byte caps, with `size.exempt`) and `check-frontmatter` (each
# skill's frontmatter is YAML and obeys the field rules) come from the toolkit
# and run on every call, since they read files no cached gate's inputs cover.
#
# `prerelease` is the gate the imported `release` recipe depends on.
# Here it is exactly `precommit`; widen it if the release ever needs
# checks too slow or too costly to fire on every commit.

# Default: list recipes
_default:
    @just --list

# Run the commit gate: the plugin and code checks, the link, size and frontmatter checks
precommit: check-plugin check-code check-refs check-size check-frontmatter
    @echo "precommit: check-plugin check-code check-refs check-size check-frontmatter passed"

# Manifests, settings, plugin validation, mod tests, shellcheck; skipped while its inputs are unchanged
check-plugin:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard check-plugin .claude-plugin .claude/settings.json .gitignore bin hooks scripts skills tests
    jq . .claude-plugin/plugin.json > /dev/null
    jq . hooks/hooks.json > /dev/null
    jq . .claude/settings.json > /dev/null
    just validate-plugin
    claude plugin test
    shellcheck -x bin/* scripts/*.sh tests/*.bats tests/*.bash
    record-sentinel

# Python lint + type checks and the bats + pytest suites; skipped while its inputs are unchanged
check-code:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard check-code .gitignore bin hooks scripts tests pyproject.toml uv.lock
    ruff check scripts tests
    ruff format --check scripts tests
    docformatter --check scripts/*.py tests/*.py
    mypy
    ty check
    plugin-dev/run-bats.sh tests/*.bats
    pytest
    record-sentinel

# `claude plugin validate --strict`, minus two findings that cannot be fixed,
# each dropped only on the entry whose `file` is the one it belongs to: the
# warning that the repo-root CLAUDE.md is not loaded (it is this repo's own
# agent instructions, not context the plugin ships), and the invalid-JSON error
# for an empty root .mcp.json, which the command sandbox creates as a placeholder
# and which is gitignored. That one is dropped only while the file is empty. The
# same finding on any other file, and any other error or warning, fails the
# gate. The entries' paths are the validator's, absolute and physical, so the
# root is `pwd -P` of the directory the recipe runs in.
validate-plugin:
    #!/usr/bin/env bash
    root=$(pwd -P)
    empty_mcp=$([ -f .mcp.json ] && [ ! -s .mcp.json ] && echo true || echo false)
    claude plugin validate --strict --json . | jq -e --arg root "$root" --argjson empty_mcp "$empty_mcp" '
      [.manifest, .contents[]] | map(
        .file as $file
        | (.errors[] | select(
            ($empty_mcp and $file == $root + "/.mcp.json" and .path == "json"
              and (.message | startswith("Invalid JSON syntax"))) | not)),
          (.warnings[] | select(
            ($file == $root + "/CLAUDE.md" and .path == "root"
              and (.message | startswith("CLAUDE.md at the plugin root"))) | not))
      ) | length == 0' > /dev/null

# Gate the imported `release` recipe depends on
prerelease: precommit

# Ruff + docformatter over the Python (lint/format only, no type check).
lint:
    ruff check scripts tests
    ruff format --check scripts tests
    docformatter --check scripts/*.py tests/*.py

# Both type checkers, strict mypy + ty. Both gate precommit.
typecheck:
    mypy
    ty check

# ty (preview) alone — for reading ty's diagnostics in isolation.
ty:
    ty check

# Run the hook + rename test suites (bats) against synthetic tool-event input
hook-test:
    bats tests/*.bats

# Run the Python unit tests (pytest) — worktree_root.py, checkpoint.py, the mod fixtures
py-test:
    pytest

# Smoke-test the mod against a live `claude -p`: an armed sentinel in a
# throwaway repo, then the session transcripts say whether the transition ran.
# Not in `precommit`: needs a real claude (sandbox-excluded) and spends a few
# haiku turns, ~1 min. `-rs` so a skip is never mistaken for a pass.
mod-smoke:
    pytest -m live tests/test_mod_live.py -v -rs
