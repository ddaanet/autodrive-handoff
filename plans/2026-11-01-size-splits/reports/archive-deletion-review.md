# Review of f21110fc (delete the frozen changelog archive)

Medium-effort review of `f21110fc^..f21110fc`, done by hand: the `code-review`
skill takes a diff, PR, branch or path target, not a single commit.

## What was checked

- **Citations.** I took every record linked from the removed lines of `docs/design.md` and `docs/design/*.md` (35 distinct records) and compared each one's `DATE Title` with the first heading of `git show changelog-archive:docs/changelog/<file>`. All 35 match. The comment citations in `bin/`, `scripts/` and `tests/` (2026-07-17, 2026-07-22, 2026-07-27, 2026-08-10, 2026-09-18) match too.
- **Tag.** `changelog-archive` is a commit at ff2a353 (= f21110fc^), which still holds the archive.
- **Leftover links.** `git grep` for `../changelog`, `changelog.md` and `(changelog/` outside `plans/` and `plugin-dev/` finds nothing. Every remaining `changelog` mention names the tag. Each design node that cites a record has the header sentence. The two nodes without one (`release-infrastructure.md`, `sessions-sharing-a-root.md`) cite no record. `dist.include` and `README.md` never referenced the archive. `docs/changelog/` on disk holds only a sandbox `.claude/.cc-writes` mask and has no tracked files.
- **Prose about the archive.** No passage outside `plans/` still describes it as being in the tree. The reworded passages are `.claude/rules/docs.md`, `CLAUDE.md`, `docs/design.md` and the shipped `skills/handoff/references/design.md`. `TASK.md` still says `size.exempt` holds the archive's two entries, but that is uncommitted session state and outside this commit.
- **Gates run.**
  - `just check-refs check-size`: 88 references resolve, "shipped stays shipped" passes, `size.exempt` has 1 entry.
  - `ruff check`, `ruff format --check`, `docformatter --check`: clean.
  - `shellcheck` on the touched shell files: clean.
  - `pytest`: 520 passed.
  - The touched bats files `bin-commands.bats` and `inject-checkpoint-root.bats`: 34 passed.

## Findings

### 1. docformatter's rewrap split two file names at their hyphen (medium)

- `tests/conftest.py:9` now reads `tests/inject-checkpoint-root.bats and tests/bin- commands.bats;`. The path has a space in the middle of a line, so it names no file and a grep for `bin-commands.bats` misses it. Before this commit the hyphen fell at the end of a line, which read as a wrap. After the reflow it is a space inside the name.
- `scripts/checkpoint.py:23-24`: `load-compact.sh` was whole before this commit and is now split as `load-` / `compact.sh`, so a `git grep load-compact.sh` no longer finds this list of the sentinel parser's users. Strictly this one is low.
- Source: compare `git show f21110fc^:scripts/checkpoint.py` with the current file. docformatter breaks lines at hyphens.
- Fix: reword each sentence so that the hyphenated name does not land at a wrap point. Then re-run `docformatter --check scripts/*.py tests/*.py`, since docformatter will re-break any name it finds at a line end.

## Declined (low)

- Several rewritten comment lines run well past the file's wrap width: `bin/handoff-checkpoint:5`, `scripts/load-handoff.sh:85`, `tests/bin-commands.bats:10`, `tests/checkpoint-helpers.bash:4,13`, `tests/inject-checkpoint-root.bats:8`. This is cosmetic, and no gate checks it.
- The shipped `skills/handoff/references/design.md:5,70` tag URLs return 404 until the tag is pushed. This is already tracked in `TODO.md:9`, and pushing the tag needs my human partner's go.
- Citations are written two ways: design nodes use `DATE Title`, code comments use `the changelog-archive tag's DATE record, "Title"`. A reader can find the record either way.


## Fix

Finding 1 and its `load-compact.sh` companion are fixed in ef9343e (`just precommit` passed); the lows are declined.

END OF REPORT
