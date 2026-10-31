# CLAUDE.md split — proposal

Brief: TASK.md of 2026-10-31. `CLAUDE.md` is 959 lines against the 400-line
cap. This proposes where each part goes. No text has moved.

## Why it grew

| Date       | Lines | What happened                                         |
| ---------- | ----- | ----------------------------------------------------- |
| 2026-07-23 | 421   | first time over the cap                               |
| 2026-09-21 | 1241  | peak, TUI-driving era                                 |
| 2026-10-10 | 458   | the mod rewrite deleted the TUI machinery (not a trim) |
| 2026-10-30 | 959   | +501 in 20 days, over 44 commits                      |

Almost every 🐛 and ♻️ commit since 2026-10-10 touched `CLAUDE.md`, mostly
adding 3 to 14 lines: the edge case it fixed (a symlink, a newline in a path,
a lock not taken, an unresolved root) went into the component's bullet, and
the test that pins it went into the test file's bullet. Each file split added
one paragraph per new file (a19ff32, +104/−60). So `CLAUDE.md` became a
**third copy of each mechanism** (code, `docs/design/*.md`, `CLAUDE.md`) and a
**hand-kept index of the test suite**, updated at the code's own granularity.

Two sections hold 801 of the 959 lines:

- *Skills, manifest, hooks, mod* (lines 94–530, 437 lines): one bullet per
  file, describing behaviour down to error branches. `_lib.sh` alone takes 84
  lines, `report-drive-failure.sh` 62.
- *Testing* (lines 562–925, 364 lines): what each test file covers, row by
  row, plus which rows are mutation-checked.

Both are open-ended lists in prose, so they read as complete, and each review
mines them for drift: 8466357 "correct two claims in CLAUDE.md's bats list".
Doc drift is fixed without a re-review, so the lists only grow. Nothing caps
what `CLAUDE.md` may hold, and the line-cap item in `TODO.md` exempts it. The
September fix (mechanism prose into design nodes) worked, then the file grew
back because no rule stopped it.

## Where each part goes

The test, per part: needed before any file is opened → root `CLAUDE.md`;
needed while editing one area → a `.claude/rules/` file with `paths:`; found
by a symptom → memory; already held by code, a design node or a changelog
entry → deleted.

### Root `CLAUDE.md` after the split (target under 200 lines)

1. **What the plugin is and the flow** (~30, from the 93-line intro): the
   checkpoint → sentinel → mod drive → loader chain, the two boundaries and
   their skills, `TASK.md`/`TODO.md` as plain tracked files, the words the
   code uses that a reader cannot guess (`typed`, `armed`/`held`/`pending`,
   FR-G, `CONTINUATION`), Claude Code >= 2.1.287. Changelog citations and the
   history of names go.
2. **Component index** (~35): one line per component, path, role and design
   node. For example: `` `scripts/report-drive-failure.sh` — UserPromptSubmit:
   failure report, sweep, drift note → driving-the-transition.md,
   queued-prompts.md ``.
3. **Routing table** (~20): the existing "What you are touching → what to
   read first", unchanged.
4. **Where documents go** (~8): `docs/design.md` hub, `docs/changelog/`,
   `plans/`, `inbox/`, one line each; the rules file holds the editing rules.
5. **Conventions**, the always-on rules (~15): `TASK.md`/`TODO.md` path or shape change is
   breaking and needs a version bump; `TODO.md` holds open items only;
   `plugin-dev/` is read-only; a `release X.Y.Z` acknowledgement names both
   push targets (prompt-triggered, so no `paths:` rule would load for it);
   `version-guard.sh` refuses `.version` edits; a design change lands with
   its changelog entry and the design prose it invalidates.
6. **Gates** (~20): `just precommit` and its two cached gates with
   `PLUGIN_DEV_GATE_FORCE=1`; `uv sync` and direnv; every `claude` call needs
   `dangerouslyDisableSandbox`; `validate-plugin`'s one exempt finding;
   `just mod-smoke` and when to run it; `hook-test`, `py-test`.
7. **Non-goals and frame assembly** (~5): one pointer each.
   `docs/design.md#non-goals` already holds all four non-goals, and the
   design nodes hold the no-transcript stance.
8. **What this file holds** (~4): the rule that keeps it from regrowing — one
   line per component, no mechanism prose, no test inventory; a behaviour
   goes in its design node, a test's coverage in the test file.

### `.claude/rules/` files, each with `paths:`

A rule without `paths:` loads at launch like `CLAUDE.md`, so it would move
lines without saving any. Each file below is scoped.

| File            | `paths:`                                                                 | Holds                                                                                                                                               |
| --------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash.md`       | `scripts/**/*.sh`, `bin/*`, `tests/**/*.bats`, `tests/**/*.bash`          | the `source-path` forms and why the nested one differs, SC2034, `_lib.sh` the only sourced file, bash 3.2 (`read` loop, `${A[@]+"${A[@]}"}`), NUL-terminated reads, hooks anchor on `handoff_root_read` |
| `mod.md`        | `hooks/**`, `tests/mod/**`, `tests/gen_mod_fixtures.py`, `scripts/drive-take.sh`, `scripts/load-*.sh`, `scripts/_lib_drive.sh` | `$` passed only to top-level functions, no driving from `Stop`, the rig stubs every call, fixtures regenerated never hand-edited, `just mod-smoke` when the mod, a loader or the sentinel's shape changes, `${CLAUDE_PLUGIN_ROOT}` quoted in `hooks.json` |
| `write-path.md` | `scripts/*checkpoint*.py`, `bin/handoff-*`, `tests/test_checkpoint_*.py`  | one writer of the sentinel, no git work (NFR1), errors through `lib.err`, `handoff-approved` repeats `closing_directive()` byte for byte |
| `skills.md`     | `skills/**`                                                              | ≤2000 words, templates live only in `handoff/SKILL.md`, the loaders and other skills do not restate them, a skill states none of what the checkpoint prints |
| `tests.md`      | `tests/**`                                                               | scenarios go into existing files, no new recipes; the helper placement rule (two or more users → shared helper); `_session_id` through `pytestmark`; `git_free_env`; no lock row sleeps (`HANDOFF_LOCK_BLOCKED_FILE`); load-bearing rows are mutation-checked |
| `docs.md`       | `docs/**`, `plans/**`, `inbox/**`                                        | changelog entries never edited after the fact, the Superseded and Corrected blockquotes, the index line format, inbox triage |
| `legacy.md`     | `scripts/_checkpoint_plan.py`, `scripts/_lib_frame.sh`, `scripts/load-*.sh`, `tests/*legacy*` | the legacy bridge: root wins by body, shadowing by existence, one name per language, retirement date as in `TODO.md`; removed whole by the legacy pass |

Estimated 15 to 40 lines each.

### Deleted, with where the content already lives

- The behaviour prose in each component bullet: in `docs/design/*.md` and the
  code. A grep of 24 sampled terms found 10 facts with no docs home. Two stay
  in root (`claude` needing `dangerouslyDisableSandbox`, the push targets);
  seven are editing conventions with a rules file above (`source-path`,
  `mapfile`, the `$` rule, `pytestmark`, the 2000 words, the Corrected
  blockquote, `inbox/README.md`); one is an identifier whose behaviour the
  design node already states (`marker_unsettled`: queued-prompts.md
  describes the note).
- The test inventory and the mutation-check lists: the test files are the
  inventory, and the mutation records are in 52 changelog and plan files.
- The `plugin-dev/` bullet (11 lines): `release-infrastructure.md` and the
  ddaanet memory `claude-plugin-dev.md`. The push-targets sentence stays in
  root.
- Non-goals and Frame assembly prose: `docs/design.md` and the design nodes.

### Memory

Little of `CLAUDE.md` is found by a symptom, so this bucket is small. The
candidates are host facts that matter to any mod author, not only this repo:
`$.command.run` is refused from a `Stop` hook's call context (`$.clock.after`
included) and timers die under `-p`; a hooks module may pass `$` only to
top-level functions; a prompt queued into a running turn fires
`UserPromptSubmit` with that turn's `prompt_id` (Claude Code 2.1.301). If the
mod-authoring skill does not already carry them, they go into the ddaanet tier
through `gitlore:commit`, each keyed on its error text. They stay in this
repo's design nodes either way.

## Constraints on where the files can go

- `dist.include` ships `skills`, `hooks`, `scripts` and `bin` whole. A nested
  `CLAUDE.md` in any of them would ship to plugin users, and
  `validate-plugin` exempts the root `CLAUDE.md` warning alone, so it would
  likely fail the gate too. Nested `CLAUDE.md` is possible only for `tests/`,
  `docs/`, `plans/`. `.claude/rules/` ships nowhere, and
  `.claude/settings.json` is tracked, so files under `.claude/rules/` are
  trackable.
- A path-scoped rule loads on Read, Write or Edit of a matching file, or a
  `cat`/`head` of one; the docs do not say that a Glob or Grep hit loads it.
  After `/compact` it
  reloads only on the next matching access. That fits editing conventions;
  it is why the flow and the component index stay in root.
- Not documented: whether a general-purpose subagent gets path-scoped rules
  when it touches matching files. Bulk edits here are dispatched, so a
  convention moved into a rule might never reach whoever makes the edit.
  Probe before the split commit: one general-purpose subagent reads a
  `scripts/*.sh` file and reports whether the stub rule's text is in its
  context. If it is not, a dispatch brief names the rules file to read.
- One stub `.claude/rules/` file answers two questions. Can the agent create
  it at all? The sandbox denies writes to `.claude/skills`, `.claude/hooks`
  and `~/.claude/rules`, the denial list shown was truncated, and auto mode's
  classifier has denied agent self-configuration writes before. If not, my
  human partner creates the files. And does `validate-plugin` report no new
  finding with the directory present?

## Sequencing

1. Inventory (subagent, output file): every sentence of the component and
   testing bullets that has no home in a design node, the code or a rules
   file. Anything that belongs in a design node lands there in a commit of
   its own, before the split, so the split loses nothing.
   `driving-the-transition.md` is at 373 lines against the design docs'
   hard cap of 400, so a few sentences landing there may force that node to
   be split at a seam first.
2. Subagent and validator probes.
3. Split commit: the new root, the rules files, and the inbound references
   it forces. Nothing else. A grep found these:
   `docs/design/sentinel-lock.md:72` cites `CLAUDE.md`'s "Non-goals" (repoint
   it to `docs/design.md#non-goals`); `docs/design.md:125` says the FR labels
   are cited throughout `CLAUDE.md` (reword it); the two `TODO.md` items on
   the split and the line cap; and the legacy-removal item, whose deletion
   pass starts from `grep -rni legacy scripts/ tests/` and must now name
   `.claude/rules/legacy.md`, which that grep does not reach.
   `scripts/_lib.sh:17` and `scripts/checkpoint.py:44` cite "CLAUDE.md
   conventions" for the path rule, which stays in root, so section 5 keeps
   the heading `Conventions`.
4. Memory facts, if any, through `gitlore:commit`.

## Questions

1. Venue: `.claude/rules/` with `paths:` for every area, or nested
   `CLAUDE.md` for `tests/`, `docs/`, `plans/`? Default: `.claude/rules/`
   everywhere, one mechanism that ships nowhere.
2. Test inventory: delete it, or move it to a `tests/README.md`? Default:
   delete. A moved copy keeps the drift and only moves it.
3. Component prose: delete it after step 1 has given each orphan sentence a
   home? Default: yes.
4. The line cap: once the root is under 400, take `CLAUDE.md` off the
   line-cap exemption in `TODO.md` and drop the "Split `CLAUDE.md`" item?
   Default: yes, and the root states the rule in its section 8.
5. Memory: write the three host facts to the ddaanet tier if the
   mod-authoring skill lacks them? Default: yes, after the split.
6. Currency: `CLAUDE.md` says the legacy bridge "goes once no sibling
   repository still has `.claude/handoff-*.md`". That condition held on
   2026-10-16, while `TODO.md` says not before 2026-11-16, so a reader
   following `CLAUDE.md` would delete the bridge now. Fix it in the split
   (`legacy.md` takes the date)? Default: yes.

## Score (claude-md-improver rubric)

| Criterion            | Score | Note                                                                   |
| -------------------- | ----- | ---------------------------------------------------------------------- |
| Commands/workflows   | 18/20 | gates, venv, sandbox and smoke all present and correct                 |
| Architecture clarity | 12/20 | complete, but the map is buried in 437 lines of mechanism prose        |
| Non-obvious patterns | 13/15 | present; the prohibitions are mixed into prose and do not stand out    |
| Conciseness          | 2/15  | a third copy of the design plus a test inventory                       |
| Currency             | 10/15 | legacy retirement condition contradicts `TODO.md`; list drift recurs   |
| Actionability        | 10/15 | rules exist but have to be found among descriptions                    |
| **Total**            | 65    | C                                                                      |
