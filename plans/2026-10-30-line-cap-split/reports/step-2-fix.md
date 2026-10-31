# Step 2 fix: findings 1 and 2 of the review of `a19ff32`

Commit: `8466357` (`📝 move a stranded helper comment; correct two claims in CLAUDE.md's bats list`). Three paths staged: `CLAUDE.md`, `tests/report-drive-failure-queued.bats`, `tests/report-drive-failure-trust.bats`.

## Changes

- Finding 1: the 3-line `# <directory> — an armed rename …` comment moved, byte for byte, from the end of the queued file to directly above `seed_marker_in_untrusted_dir()` in the trust file, as in `a19ff32^:tests/hook-test.bats`. The blank line before it in the queued file went too, so that file ends `}\n` like the others.
- Finding 2a: `tests/sentinel-lock.bats` bullet now names the malformed-sentinel row. The row (`report-drive-failure (malformed sentinel: discarded and reported)`) seeds a `clear` with one command line, and asserts the file is discarded and the message has no "Type in order" lines. So "with none" = no lines offered.
- Finding 2b: `tests/load-compact.bats` bullet drops "the same fallback rows as `load-handoff-legacy.bats`" and names what its `@test`s hold.

## CLAUDE.md sentences

2a before:

    - `tests/sentinel-lock.bats` covers the sentinel's lock in the sweep and the
      loaders.

2a after:

    - `tests/sentinel-lock.bats` covers the sentinel's lock in the sweep and the
      loaders, and a sentinel that does not parse swept with no lines offered.

2b before:

    … `No todo`) and its legacy paths, the same
    fallback rows as `load-handoff-legacy.bats`, a dropped task-shadowed note
    among them.

2b after:

    … `No todo`) and its legacy paths: each half
    alone and both from the old path, the root todo or task shadowing a legacy
    one, a headings-only root todo not shadowing it, a symlinked legacy todo
    and legacy files with no body.

## Checks

- `bats tests/report-drive-failure-queued.bats tests/report-drive-failure-trust.bats`: 22 tests, 0 `not ok`.
- `shellcheck -x tests/*.bats tests/*.bash`: rc 0, no output.
- Verbatim checker, last two lines:

      blocks: old 22, new 22
      verbatim: OK

- `just precommit`: `precommit: check-plugin check-code passed` (pytest: 520 passed, 3 deselected).
- Left alone: ` D TASK.md`, ` M TODO.md`, ` M memory`, the untracked mask dotfiles and the untracked plan files.
