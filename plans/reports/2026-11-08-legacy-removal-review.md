# Review of fee2ff5 (legacy-path fallback removal), /code-review medium

I ran the `code-review` skill at level medium on fee2ff5 against fee2ff5^ and checked each finding against the tree. Nothing was fixed or committed.

## What the review checked and found clean

- No reference to a deleted symbol, test or file is left: `legacy`, `handoff-task.md`, `handoff-todo.md`, `Half`, `read_half`, `legacy_fate`, `legacy_reports`, `move_legacy`, `HANDOFF_LEGACY_*`, `FRAME_*` notes and `Boundary` are gone from scripts, tests, skills, docs, README and CLAUDE.md. Every `boundary` grep hit is the word, not the class.
- `check_target` (scripts/_checkpoint_plan.py:49) still refuses a symlink or a directory at the root name, for every action, before any write. Each plan path goes through it.
- `compose_directives` (scripts/checkpoint.py:331) is called with the matching positional order (`skill, root, commit_mode, memory, ending`) at line 110. `commit_directive(*, memory)` has no stale callers.
- The renumbered parts 1 to 5 in docs/design/the-checkpoint-directive.md match the order `compose_directives` emits: memory, then todo boundary or SDD nudge, then the commit act, then arming or closing.
- pytest (372 passed), the frame and loader bats suites, and ruff pass. The reviewer saw no mypy output, so mypy is unverified.

## Findings

### 1. TODO.md:3 — an unrelated open item was deleted (medium, needs my human partner's confirmation)
- Defect: the commit drops "My human partner moves this directory to `/Users/david/code/autodrive-handoff` at a handoff boundary (fix `core.hookspath`, rebuild `.venv`, `direnv allow`)", which has nothing to do with the legacy removal.
- Failure scenario: the repo still lives at /Users/david/code/handoff, so the move has not happened. With the item gone, the next session has no record of the move, or of the hookspath, venv and direnv steps that go with it. The implementer's report (plans/reports/2026-11-08-legacy-removal.md, "Notes / unsure") says the deletion was already in the working tree, uncommitted, and rode into this commit. It may have been my human partner's intentional edit. Confirm before restoring it.

### 2. Commit message / deleted TODO item — removal lands before the stated 2026-11-16 date (needs confirmation, not a code defect)
- Defect: the deleted TODO item said "not before 2026-11-16: my human partner keeps the fallbacks one month past 2026-10-16". The commit is dated 2026-11-08 and says "the 2026-11-16 hold is lifted", and nothing in the repo records my human partner lifting it.
- Failure scenario: if the hold was not actually lifted, any repo still holding a `.claude/handoff-*.md` frame silently loses it 8 days early. Check the source of "lifted" before release.

### 3. .claude/rules/write-path.md:17 — the rule still describes a printed git line that no longer exists (medium)
- Defect: "No git work (NFR1). A git line the agent needs is printed, never run." The only printed git line was `legacy_unstage_directive`'s `git rm --cached`, which this commit removed. The commit act names no git verb on purpose (docs/design/the-checkpoint-directive.md, part 3: "It names no git verb for the commit").
- Failure scenario: an editor working under this rule reads it as a sanctioned pattern and adds a printed git command to the checkpoint output, which contradicts the directive design. The fix is to leave only "No git work (NFR1)."

### 4. tests/test_checkpoint_root_files.py:116 — the docstring now narrates history (low)
- Defect: "The plan used to reach the write or the unlink, which raised on the directory." It no longer says what the test guards today.
- Failure scenario: a reader cannot tell the test's current purpose, which is that a directory at the name is refused during resolution, before any write or unlink.

### 5. tests/load-handoff.bats:196-198 — the title and comment name the removed "frame notes" (low)
- Defect: the comment "the frame's notes follow it" and the test title "its note precedes the frame notes" refer to `handoff_frame_notes`, which this commit deleted.
- Failure scenario: a reader looks for a frame-notes mechanism that no longer exists and misreads which ordering the assertion pins.

### 6. scripts/load-handoff.sh:86 / README.md — no upgrade note for users who still have legacy files (low, declined)
- Defect: a user who upgrades while still holding `.claude/handoff-*.md` gets "No task frame or todo." with no pointer to the old files.
- Why declined: the deleted TODO item records my human partner's call that the removal involves no version and no note, and this commit removes the file table's legacy row from the README rather than an upgrade note. Raise it only if that call changes.

### 7. docs/design/the-checkpoint-directive.md:37 — one line overruns the wrap width (low, cosmetic)
- Defect: "still asking for the memory approval. The closing line is the one where this is not already implied by the" was left unwrapped after the edit.
- Failure scenario: none functional; future diffs of the paragraph are noisier.
