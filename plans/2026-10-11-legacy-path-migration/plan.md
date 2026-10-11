# Legacy-path fallback and migration (0.16.1)

> **Amended 2026-10-11, after the step 1 red review.** The Checkpoint
> contract said the root file is current "whenever it exists"; the loader
> decides by body. Both now decide by body (a body-less root file counts as
> absent), so the loader's "the next checkpoint moves it" note is true. Also:
> the shadowed note ends at "has a body." (no advice to delete), and a
> body-less legacy file behind a root file with a body counts as shadowed.
> Taken as the stated defaults; my human partner had not objected.

## Context

0.16.0 moved the frame from `.claude/handoff-task.md` and
`.claude/handoff-todo.md` to `TASK.md` and `TODO.md` in the root. A repository
upgraded across that line has its frame under the old names, and nothing reads
them (`README.md` upgrade note: two `git mv` lines by hand). My human partner's
call: the loader reads both names, and the checkpoint performs the migration.
The 0.15.0 files were gitignored and force-added, so in most repositories they
are tracked.

## Decisions (settled)

- **Root wins.** When both a legacy file and its root file exist, the root file
  is the frame. The legacy file is never overwritten, merged or removed by the
  migration, and **the agent is told it is there**: the loader's
  `additionalContext` and the checkpoint's stdout each name it and say it is
  ignored. A project's own `TODO.md` makes this case real.
- **Retirement is conditional, not versioned.** The fallback goes once no
  sibling repository still has `.claude/handoff-*.md`. No tripwire, no version
  in code, docs or tests. `TODO.md` carries one item with the condition and the
  check `ls /Users/david/code/*/.claude/handoff-*.md`.
- **One marker.** `LEGACY_RELS` (task and todo legacy paths) is the single
  constant both the loader and the checkpoint read, so removal is one deletion
  pass. Its comment names the condition.
- **Ships as 0.16.1.** The README keeps the two `git mv` lines as the manual
  route, states the automatic behaviour first, and drops "Nothing reads the old
  paths".
- **NFR1 holds.** The checkpoint renames on the filesystem and does no git
  work.

> **Corrected at review, 2026-10-11.** The "One marker" decision says
> "`LEGACY_RELS` (task and todo legacy paths) is the single constant both the
> loader and the checkpoint read". That was wrong: Python cannot read a bash
> constant, and `scripts/checkpoint.py` already mirrored `HANDOFF_REL_*` by
> hand. Evidence: the code carries `HANDOFF_LEGACY_REL_TASK` and
> `HANDOFF_LEGACY_REL_TODO` twice, in `scripts/_lib.sh` and in
> `scripts/checkpoint.py`, each commented as the other's mirror. It is one name
> per language, found by `grep -rni legacy scripts/ tests/`. What still stands:
> one marker, whose comment names the retirement condition, and one deletion
> pass.

## Contracts

**Loader** (`handoff_frame` in `scripts/_lib.sh`, read by `load-handoff.sh` and
`load-compact.sh`). Per half: the root file when it has a body; else the legacy
file when it has a body. `FRAME_TASK`/`FRAME_TODO` stay as they are. New
variables say which halves came from a legacy path and which legacy files are
shadowed by a root file that has a body. The `systemMessage` and the
`additionalContext` each say, per affected half: loaded from the legacy path
and the next checkpoint moves it; or the legacy file exists and is ignored.
Both channels, asserted whole, as the existing four frame states are. "Has a
body" is `is_empty_body` as before; a headings-only root file does not shadow a
legacy file with a body.

**Checkpoint** (`scripts/checkpoint.py`, helpers in `_checkpoint_lib.py`).
Migration is part of plan resolution, not a pre-write: nothing moves unless
both halves resolve.

- Effective current content of a half is the root file when it has a body
  (`is_empty_body`, the loader's own predicate), else the legacy file.
  `keep` keeps it, `edit` applies to it, a content string replaces it.
- Legacy present and root absent or without a body: the plan includes a rename
  to the root name, replacing a body-less root file (a content write simply
  writes the root file and removes the legacy one).
- Root with a body and legacy present, whether or not the legacy file has a
  body: root wins, legacy untouched, reported as ignored. A write that leaves
  the root file without a body while a legacy file exists is judged by the root
  file after the write: the legacy file is removed as `clear` does, and stdout
  says so, so it cannot come back as the frame.
- `clear`, and `precompact` removing `TASK.md`, also remove a legacy task or
  todo file that would otherwise be read. If the root file is absent and the
  legacy file is present, the removal covers it; if both exist, `clear` removes
  both (the half is being emptied) and says so.
- A rejected payload leaves legacy and root files byte-identical.
- Stdout reports each move, each ignored legacy file and each legacy removal,
  ahead of the directive parts, and never changes the closing line being last.
- `commit_directive` (under `with-commit`, when a move or legacy removal
  happened): additionally runs
  `git rm --cached --ignore-unmatch -q -- <legacy paths>`, so a tracked old
  path is staged as deleted and git records a rename; an untracked one is a
  no-op.

> **Corrected at review, 2026-10-11.** The last bullet of the Checkpoint
> contract prints `git rm --cached --ignore-unmatch -q -- <legacy paths>`. The
> paths are the bare relative form, which is relative to the agent's Bash
> working directory and matched nothing from a subdirectory of the root, exit
> 0, with `--ignore-unmatch -q` hiding the miss (step 2 review, F1). The line
> printed is `git rm --cached --ignore-unmatch -q -- :/<legacy path> …`, one
> `:/` pathspec per path, run verbatim from a subdirectory and checked to stage
> the deletion. What still stands: printed only under `with-commit`, naming only
> the legacy files this call moved or removed, a no-op over an untracked one,
> and no git work done by the checkpoint.

## Steps

Each step is a red slice reviewed, then a green slice; tests live in the
existing files (`tests/hook-test.bats`, `tests/checkpoint.bats`,
`tests/test_checkpoint.py`).

1. **Loader.** bats rows: legacy only per half, both halves legacy, root
   shadows legacy (agent-visible note on both channels), headings-only root
   with a legacy body, neither. Then `handoff_frame` and both loaders.
2. **Checkpoint migration.** pytest rows: rename on `keep`, on `edit`, on a
   content write, on `clear`; a headings-only root file beside a legacy body
   is replaced by the move (`keep`, `edit` and content write); both-exist
   leaves legacy untouched with the notice; a content write leaving the root
   body-less removes a beside-it legacy file and says so; `precompact` removes a legacy task file; rejection leaves every
   file as it was; stdout order with the closing line last; `with-commit`
   directive names the `git rm --cached --ignore-unmatch` act, `without-commit`
   does not. Mutation-check the load-bearing rows: dropping the
   root-wins rule, migrating before validation, the closing line moving.
3. **Docs.** README upgrade note; a `docs/changelog/` entry and index line
   stating the retirement condition; `docs/design/the-write-path.md` and
   `docs/design/driving-the-transition.md` (loader) prose the change
   invalidates; the `TODO.md` item above; the stale marketplace description
   stays a separate item.
4. **Gate.** `just precommit`, then `just mod-smoke` (the loader changed).

## Out of scope

Release (a separate request), the marketplace description, migrating any other
repository, removing the fallback.
