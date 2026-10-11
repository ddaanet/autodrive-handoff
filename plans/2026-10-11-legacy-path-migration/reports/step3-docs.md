# Step 3 (Docs) report

Docs only. Nothing under `scripts/`, `bin/`, `tests/` or `hooks/` touched, no
staging, no commit. Every behaviour claim was written from `git diff scripts/`
(the final code, after the step 2 review-fix wave), not from the plan.

## Files changed (15, this report included)

1. `README.md`
2. `CLAUDE.md`
3. `TODO.md`
4. `docs/changelog.md`
5. `docs/changelog/2026-10-11-legacy-paths-are-read-and-moved.md` (new)
6. `docs/changelog/2026-10-11-task-and-todo-move-to-the-root.md`
7. `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md` (one
   Superseded blockquote, not in the task list; see item 3)
8. `docs/design.md`
9. `docs/design/decisions.md`
10. `docs/design/rejected-alternatives.md`
11. `docs/design/the-write-path.md`
12. `docs/design/driving-the-transition.md`
13. `docs/design/the-checkpoint-directive.md`
14. `plans/2026-10-11-legacy-path-migration/plan.md`
15. this report

## Per item

1. **README.** The upgrade note leads with the automatic behaviour (loader
   reads the old file when the root file has no body, says so; the next
   checkpoint moves the todo and replaces or removes the task; a root file with
   a body wins and the old file is reported ignored each start), then the
   `git rm --cached --ignore-unmatch -q -- :/…` line under a commit-requesting
   wrap-up and its absence otherwise, then the two `git mv` lines as the
   manual route. "Nothing reads the old paths" is gone. One clause added to the
   checkpoint description (moves or removes a file at an old path). No version
   claim about retirement.
2. **New changelog entry plus index line** (newest first, no version). Covers:
   why (the release pulled for want of an upgrade path, the earlier "no
   migration code" call and which half of it failed), root wins, body-based
   decision at both ends, shadowing by existence, no advice to delete, the
   loader (flags, `handoff_frame_notes`, age, spawn count, the "edit it there"
   todo note), the checkpoint per action, write-before-unlink, the two
   refusals, the cross-device fallback, apply-time failure now possible, one
   name per language and what the grep misses, conditional retirement stated
   exactly (the fallback goes once no sibling repository still has
   `.claude/handoff-*.md`), NFR1, the `:/` decision and the silent failure
   from a subdirectory, the ordering ahead of the clause-file refusal, the
   unstaged deletion after `without-commit`, and the endless "ignored" note.
3. **Superseded blockquotes** in `2026-10-11-task-and-todo-move-to-the-root.md`
   atop "What was decided without being asked" (scoped to item 5 only) and atop
   "Moving an existing frame"; bodies untouched. One extra, scoped to the
   refusal "prints alone" claim, atop "The refusal prints alone" in
   `2026-09-18-the-directive-owns-the-procedure.md`, because the repo rule
   requires a pointer wherever a later change reverses a section and that claim
   is reversed by the clause-file ordering.
4. **Rejection reversed.** `rejected-alternatives.md` and the `design.md`
   index line: "Reading the old paths as a fallback" is now "A fallback for the
   old paths that retires by version, by tripwire or by nothing" (what stays
   rejected), the foreign-`TODO.md` rejection split into its own entry
   unchanged, plus two new rejections (advising deletion of a shadowed file; a
   bare pathspec or `git -C` in the printed line). New decision "The old paths
   are read and moved, and the bridge retires by a condition" in `decisions.md`
   with its hub index line. `design.md` FR5, FR6 (still retired, qualified to
   the root file), FR9 (order opens with the legacy reports) and NFR1 (a
   legacy move is a filesystem act, the git line is printed never run).
5. **Design nodes.** `the-write-path.md`: the legacy bridge in the seam
   section, the all-or-nothing sentence qualified (payload and file failures
   found in resolution; a filesystem failure while applying can follow the
   first half), the per-action rule and the refusals, the git line and its
   `:/` reason and the unstaged consequence. `driving-the-transition.md`: the
   loader notes on both channels, the age, `load-compact.sh`'s appended
   fragments. `the-checkpoint-directive.md`: part list renumbered with the
   legacy reports first and the git line leading the commit act, the "Once
   everything above is done" sentence scoped to the commit sentence, and the
   clause-file refusal rewritten from "prints alone" to "prints last".
6. **CLAUDE.md.** Layout flow sentence; a new paragraph after the `TODO.md`
   one (legacy files, the bridge, the retirement condition, the one marker per
   language); `load-handoff.sh`, `load-compact.sh`, `_lib.sh` (`handoff_frame`
   signature and the four flags, `handoff_frame_notes`, `HANDOFF_LEGACY_REL_*`),
   `checkpoint.py` and `_checkpoint_lib.py` bullets; "Frame assembly"; the
   `tests/hook-test.bats` and `tests/test_checkpoint.py` Testing bullets (new
   rows described from the real test names, mutation checks taken only from
   what the green reports say was run; "refusal printed alone" corrected).
7. **TODO.md.** Added the retirement item (condition, the `ls` check, the
   `grep` pass, README and docs) and the `checkpoint.py` split item. Existing
   items left alone, none marked done.
8. **plan.md.** Two `> **Corrected at review, 2026-10-11.**` blockquotes: "One
   marker" (one name per language) after the Decisions list, and the bare
   `git rm --cached … -- <legacy paths>` (it is the `:/` form) after the
   Checkpoint contract. Nothing else edited.

## Plan versus code (the code won)

- **One marker:** one name per language, `HANDOFF_LEGACY_REL_*` in `_lib.sh` and
  again in `checkpoint.py`, not one `LEGACY_RELS`.
- **Git act:** `:/<rel>` pathspecs, not bare relative paths.
- **Task half:** never moved. `plan_task` always passes `carried=False`, so a
  legacy task file is reported `removed` or `ignored`. The loader's note for a
  task from legacy says "the next checkpoint moves it to TASK.md", which is
  inaccurate for the task (it replaces it). The plan's Amended blockquote calls
  the loader's note true; that holds for the todo only. The docs describe the
  checkpoint's behaviour and the changelog entry records the gap. A third
  Corrected blockquote in `plan.md` was not added, since the task named two;
  the parent decides, and the loader wording is frozen code.
- **Todo-from-legacy loader note** adds "edit it there until the next
  checkpoint moves it" (step 1 review F1, option a); the plan does not have it.
- **Beyond the plan, in code:** refusal of a legacy symlink to a file, refusal
  of a directory at the root name, the `EXDEV` copy fallback, the root file
  read only when a legacy file exists, write-before-unlink order, `edit`
  result written (not renamed) when sourced from legacy so its mtime is the
  write's while the report still says "moved".
- **Code comments overclaim:** `_lib.sh` and `checkpoint.py` say `grep -rni
  legacy scripts/ tests/` "lists all of it". It does not list `Half`, the
  `plans` list in `main` and `compose_directives`, `Boundary`, the `move`
  member of `FilePlan.act`, or the `Sequence` import in `_checkpoint_lib.py`.
  The docs and the TODO item say so; the comments are frozen and unchanged.
- **Stale-by-reading, now true again:** `load-compact.sh:44-45` ("the checkpoint
  removes the task file at this boundary, so one with a body was written by
  hand") holds again, since `precompact` removes a legacy task file as well.

## Docs over 400 lines

None of `docs/` is over 400 (largest: `docs/design.md` 347 lines). `CLAUDE.md`
went from 482 to about 558 lines; it was over the cap before this step, and
nothing was trimmed. `scripts/checkpoint.py` (about 800) is the TODO split
item, not a docs matter.

## Not done, and why

- `rumdl` is not wired into the justfile, so lines were wrapped by hand at 80.
  Link-only lines and the changelog index line (one physical line per entry, by
  the file's own convention) run past 80, as neighbours do.
- `just precommit` and `just mod-smoke` not run (step 4). Link targets in every
  edited doc were checked to exist (0 broken).
- The TODO item "Say so in the step 3 docs" is satisfied by the changelog entry,
  the write-path node and README; left in place as instructed, for the parent
  to drop.
- Not touched: `skills/*/SKILL.md` (no mention of the old paths),
  `docs/changelog/2026-07-27-one-channel-one-writer.md` (its "only `clear`
  removes" sits inside an existing superseded blockquote).
