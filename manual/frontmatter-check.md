# The frontmatter check

Part of the claude-plugin-dev manual; [README.md](../README.md) is the rest.

`just check-frontmatter` refuses a skill, agent or command whose frontmatter is
missing, not YAML, or breaks the toolkit's field rules, which the sections below
give. It is opt-in: a plugin that does not wire it is unaffected, and `release`,
`precommit` and `prerelease` keep their contract.

`claude plugin validate` does not replace it: it passes `description: a: b` and
`description: [x`, which are not valid YAML, with exit 0 (verified against CC
2.1.316).

## What it reads

Every file git lists that is not ignored, tracked or not, read from disk and not
from the index, below the directory it runs in (the root argument, default the
current directory, which must lie inside a git work tree):

- `skills/*/SKILL.md`
- every `.md` file under `agents/`, at any depth
- every `.md` file under `commands/`, at any depth

Another `.md` file under a skill is a reference file and is not read. A file git
lists that is gone from disk is skipped.

## What it refuses

Each problem is one stderr line, `check-frontmatter: <path>: <reason>`, with the
path relative to the root. Every file is checked. Within a file, a block refusal
is reported alone and the field refusals follow once the block parses; any
refusal exits 1.

| Refusal | Cause |
| --- | --- |
| `no frontmatter block` | line one is not exactly `---`, or no later line is |
| `not UTF-8` | the file does not decode as UTF-8 |
| `block is not YAML` | PyYAML `safe_load` fails on the block, including a value it cannot build, such as `2026-13-45` |
| `block is not a mapping` | the block parses to a list, a scalar, or nothing |
| `description is missing` | the block has no `description` key |
| `description is not a string` | the value is a number, a list, a mapping or empty (`description:` alone) |
| `description is blank` | the value is a string of whitespace only |
| `name is not a string` | `name` is present and is not a string, empty included |
| `name is blank` | `name` is a string of whitespace only |
| `name is missing` | a skill or an agent has no `name` key |
| `name ... differs from its directory ...` | a skill's `name` is not exactly the name of the directory holding its `SKILL.md`; the line shows both |

Line one must be exactly `---`. A file saved with CRLF line endings or a
byte-order mark on line one has no block, and is refused as such.

## What it does not refuse

- A command with no `name`, or with a `name` that differs from its file name.
- An agent whose `name` differs from its file name.
- Any other field, in any value that is valid YAML.

`description` is required in every kind, and `name` in a skill and an agent with
a skill's matching its directory, as this toolkit's policy. The Claude Code
validator warns on a missing `description` in all three kinds and says nothing
about a missing or differing `name` (verified against CC 2.1.316). Claude Code's
skill docs make `name` optional and default it to the directory, so this is
stricter: the name in the file is the name the skill goes by.

In a plugin, a skill's `name` is the last segment of its command (`skills.md`;
runtime not probed), so changing a differing `name` to its directory renames the
command. Renaming the directory to the `name` passes the check and keeps the
command. Whether a runtime loads a file the check passes or refuses was not
probed.

## Wiring it

Add `check-frontmatter` beside `check-refs` and `check-size`:

```just
precommit: check-refs check-size check-frontmatter
```

It runs uncached, for the reason `check-size` does: it reads files by pathspec
no sentinel's inputs cover whole.

## Setup

The YAML parse runs under the first interpreter that imports PyYAML:
`.venv/bin/python3` under the git top level of the checked root, then the
`python3` on PATH. A shell or hook that does not load direnv therefore still
runs the check. A plugin with no skill, agent or command needs no parser and
signs off with zeros whatever `python3` is. Otherwise:

1. Add `pyyaml` to the dev group of `pyproject.toml`:

    ```toml
    [dependency-groups]
    dev = ["pyyaml>=6"]
    ```

2. Run `uv sync`, which materializes `.venv`.

Activating `.venv` from `.envrc` is not needed by this check. Without a
PyYAML-capable interpreter in either place the check exits 1 with one line
naming these two steps. It needs `bash`, `git` and `mktemp` besides.

## The report

A pass prints one line on stdout and exits 0. The counts are the files read, by
kind, zeros included:

```text
check-frontmatter ok (3 skills, 1 agents, 4 commands)
```

A run it cannot complete, such as a root that does not exist, a root outside a
git work tree, or no PyYAML, ends with one `check-frontmatter: <reason>` line on
stderr and exit 1.
