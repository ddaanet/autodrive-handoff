# Inventory: CLAUDE.md lines 562-925 (the Testing section)

Scope: `CLAUDE.md` lines 562-925. Read-only audit against `tests/`, `justfile`,
`plugin-dev/gates.just`, `docs/changelog/`, `plans/`, `docs/design/`. Method:
every clause bucketed once; coverage claims checked against a named test row;
mutation claims checked against a grep of `docs/changelog/` and `plans/`;
rationale checked against design nodes, code/test comments and non-superseded
changelog entries.

Headline: **0 orphans need a design node**, so `driving-the-transition.md`
(373/400) needs no sentence and no split for this section. 1 fact needs a root
line, 6 are unrecorded mutation claims (`report only`), 11 claims are false or
stale (conflicts), and the rest are homed or carried by a rules file or root
section. The two conflicts the split commit must not copy forward are C1 (three
gates, not two) and C2 (two exempt `validate-plugin` findings, not one; the
proposal's section 6 line "one exempt finding" repeats the error).

## Orphans

- `CLAUDE.md:584-586` "A new component directory the plugin validator reads
  (`agents/`, `commands/`) goes into `check-plugin`'s list when it is created."
  Fact: when adding `agents/` or `commands/`, add the path to the
  `sentinel-guard check-plugin …` pathspec list (`justfile:37`), or the cached
  gate would skip a change there. Searched `justfile`, `docs/design*`,
  `plugin-dev/manual/gates.md`: stated nowhere else, no comment in the justfile.
  Destination: root section 6 (Gates), one line; alternatively a comment above
  `check-plugin` in `justfile`.
- `CLAUDE.md:616-618` "Mutation-checked: dropping the file check, the `armed`
  gate, the owner check, the cwd, the arming, keeping the owner on `pending`."
  Recorded: file check, `armed` gate, cwd, "never arm" in
  `plans/2026-10-08-plugin-becomes-a-mod/reports/step4a-green.md:9-20`.
  Unrecorded: the owner check and keeping the owner on `pending` (the owner
  arrived later, `docs/changelog/2026-10-13-the-armed-sentinel-has-an-owner.md`
  has no mutation line). Destination: `report only`.
- `CLAUDE.md:709-711` "the `|| true` after the trim pipeline is pinned by the
  4000-line row and the record call by the first two rows". The `|| true` half
  is homed by the comment at `tests/report-drive-failure.bats:163-164`. The
  "record call pinned by the first two rows" half is a mutation claim with no
  record (`docs/changelog/2026-10-13-the-sweep-leaves-a-record.md` has no
  mutation line; `...-the-sweep-record-follows-no-link.md:34-38` records other
  mutants). Destination: `report only`.
- `CLAUDE.md:772-773` "the harness row that `make_repo` and `make_gitlore_repo`
  ... leave a decoy `GIT_DIR` repository byte-identical, mutation-checked."
  `docs/changelog/2026-10-13-the-test-harness-sheds-gits-environment.md:46-48`
  records the mutants for the pytest rows (scrub dropped from `make_repo`,
  `run_checkpoint` from raw env); its Superseded blockquote (line 7) is scoped to
  the cause (gitlore's hook running the gate), not the mutants. Nothing records a
  mutation of the bats row `tests/bin-commands.bats:38`. Destination: `report
  only`.
- `CLAUDE.md:882-885` hold mutants "(never hold => the held row alone reds; hold
  whatever the sentinel names => the names-nothing row alone reds)". Nearest
  record is a different pair: `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md:88-93`
  (drop the second disjunct; widen to `K and C`) and
  `plans/2026-09-18-directive-owns-the-procedure/reports/deliverable-review.md:227`.
  The two named mutants and their "alone reds" outcome are unrecorded.
  Destination: `report only`. The `(driven and with-commit)` disjunct half is
  homed at the changelog line above.
- `CLAUDE.md:915-916` "`continue: true` counting the effective todo, a legacy
  file included, the refusal moving nothing" (as a mutation-checked row).
  Searched `plans/2026-10-11-legacy-path-migration/` and
  `plans/2026-10-11-task-and-todo-move-to-root/`: no mutant records it. The other
  legacy mutants are recorded (see Homed). Destination: `report only`.
- `CLAUDE.md:918-919` "and with them `handoff-approved`'s bare-name row in
  `tests/bin-commands.bats`" (mutation-checked). The row exists
  (`tests/bin-commands.bats:203`, its comment at 201-202 gives the reason) and
  was added in `plans/2026-09-18-directive-owns-the-procedure/reports/item-3-2-s1-red.md:4`,
  which records no mutation. Destination: `report only`.

## Conflicts

- C1. `CLAUDE.md:573` "It depends on two cached gates (`plugin-dev/gates.just`
  sentinels ...)" and `:583-586`. `justfile:31` is `precommit: check-plugin
  check-code check-refs`: a third dependency, `check-refs`
  (`plugin-dev/release.just:83-84`, a Markdown-link check with no sentinel, so it
  runs every time). The `justfile:11` comment ("It is two cached gates") and
  `:32` echo are stale in the same way, so the file is self-inconsistent. The
  split's section 6 should say "two cached gates plus `check-refs`".
- C2. `CLAUDE.md:587-590` "failing on any error or warning except the one that
  cannot be fixed: the repo-root `CLAUDE.md` ... warning". `justfile:59-66`
  ("minus two findings that cannot be fixed") and `tests/validate-plugin.bats:5-6`
  ("the two exceptions") say two: also the invalid-JSON error for an empty root
  `.mcp.json` the command sandbox creates. `CLAUDE.md:774-778` itself describes
  the `.mcp.json` row, so the section contradicts itself. The proposal's section
  6 ("`validate-plugin`'s one exempt finding") and its Score table repeat it.
- C3. `CLAUDE.md:665-666` (`load-handoff.bats`) and `:685-687`
  (`load-compact.bats`) "... leaves `armed` for the sweep and spawns nothing".
  No row in `tests/load-handoff.bats`, `tests/load-compact.bats` or
  `tests/sentinel-*.bats` asserts that nothing is spawned (grep `spawn|fork`:
  only comments in `tests/lib.bats:24,81` and `tests/sentinel-reader.bats:11`).
  The clause is a remnant of the loader that once started a watcher. Rows that
  exist: `tests/load-handoff.bats:164,172,202`, `tests/load-compact.bats:176,242`.
- C4. `CLAUDE.md:871-872` places "the ledger-liveness matrix" under
  `tests/test_checkpoint_directives.py`. The matrix (flat-path stray at 139,
  unidentified workspace 148, flat ledger alone 157, several live workspaces 167,
  live ledger scopes the todo file 113) is in
  `tests/test_checkpoint_composition.py`. Likewise `:877-878` "part order pinned
  per skill with the closing line last" in composition: the part-order rows are
  `tests/test_checkpoint_directives.py:196,213,228`; composition pins only
  memory-before-ledger (`:50,:69`) and the closing line's wording (`:199`).
- C5. `CLAUDE.md:640-643` "one file per hook or library part, each sourcing
  `tests/hook-helpers.bash` under a `# shellcheck source-path=...` line".
  `tests/drive-take.bats` does neither: no `source` of `hook-helpers.bash` and no
  `source-path` line (it has its own `setup` at `:11` and `load lock-helpers` at
  `:17`; "hook-helpers.bash" appears only in a comment at `:24`). The three
  `checkpoint-helpers` files are the stated exception at `:756-757`; drive-take is
  an unstated one.
- C6. `CLAUDE.md:678-681` `tests/load-handoff-cwd.bats` covers a cwd holding a
  newline or ending in a space for "`load-handoff.sh` and
  `report-drive-failure.sh`, at the project root and in a linked worktree". The
  `report-drive-failure.sh` rows are project-root newline only
  (`tests/load-handoff-cwd.bats:120,144`) and drift (`:100,110`); none for a
  trailing space or a linked worktree. Worktree and space rows are loader-only
  (`:43,55,72,82`).
- C7. `CLAUDE.md:668-675` `tests/load-handoff-legacy.bats` "the root file
  shadowing a legacy one (also one with no body)". No such row in that file: the
  root-beside-bodyless-legacy row is `tests/lib-frame-legacy.bats:95`
  (function level only); `load-handoff-legacy.bats:292` and
  `load-compact.bats:163` are legacy-with-no-body and no root file.
- C8. `CLAUDE.md:633` "About 35 s and a few haiku turns". `justfile:109-112`
  (comment over `mod-smoke`) says "~1 min". `plans/2026-10-08-plugin-becomes-a-mod/reports/step4b-strip.md:37`
  recorded 33-35 s on one box. A volatile figure; drop it from the split.
- C9. `CLAUDE.md:921` "The justfile recipes are one-liners that delegate."
  True of `hook-test`, `py-test`, `mod-smoke` (`justfile:102,106,113`); false of
  `check-plugin`, `check-code`, `validate-plugin` (`justfile:35-45,47-57,68-82`),
  which are multi-line shebang bodies. The rule is meant for test recipes; say so.
- C10. `CLAUDE.md:829-832` "`is_empty_body` itself and its CLI's exit codes
  (whitespace-only, a `#!/bin/sh` body, `#tag`, seven `#`, the indent boundary
  ...)". The parenthetical lists `is_empty_body` unit rows
  (`tests/test_checkpoint_writes.py:325`); the CLI rows
  (`:348`) are headings-only 1, body 0, retired `--is-empty-body` 2, unknown flag
  2, no flag 2.
- C11. `CLAUDE.md:811-812` (schema bullet) "the `skill` enum (`autoname`
  accepted, the retired names rejected)". Retired names rejected is
  `tests/test_checkpoint_schema.py:196`; `autoname` accepted is in
  `tests/test_checkpoint_rename.py:138`, not schema (`test_checkpoint_schema.py:174` accepts
  `handoff` and `precompact` only).

Also noted, not a conflict with `CLAUDE.md`: the rows
`tests/test_checkpoint_legacy.py` (1563 lines) exceed the 400-line cap on
purpose, its docstring (`:1-4`) says so ("goes in one pass"); `tests/mod/handoff.test.ts:127`
(lock-busy plan) and `tests/drive-take.bats` lock/symlink/resolver rows exist
with no CLAUDE.md mention.

## Rules-bound

### `bash.md`

- `CLAUDE.md:642-643` bats files that source a helper carry
  `# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash` (and
  `source=checkpoint-helpers.bash` for the three of `:756-757`) so shellcheck
  follows it.
- `CLAUDE.md:638-639` `bats run` captures exit codes and output without the
  `set +e` dance; `tests/bats-best-practices.md` is the reference.
- `CLAUDE.md:650-651` call `handoff_frame` directly, never through `run`, since
  it answers in variables.

### `mod.md`

- `CLAUDE.md:591-595` the rig stubs every mods API call the mod makes and logs
  them in order; the kit rejects an unstubbed call, "including `process.run`,
  `fs.*` and the clock". The enumeration is stated only in
  `plans/2026-10-08-plugin-becomes-a-mod/plan.md:28-29`; carry it (the changelog
  `2026-10-16-a-prompt-queued-into-the-arming-turn.md:103-104` has the principle).
- `CLAUDE.md:604-606` no expected log contains a prompt-box read and the rig
  stubs none, so a restored one fails as an unstubbed call (also homed:
  `docs/design/driving-the-transition.md:157,348`).
- `CLAUDE.md:606-607` fixtures are the plans `drive-take.sh` prints, through the
  generated `tests/mod/fixtures.ts`.
- `CLAUDE.md:619-621` regenerate `fixtures.ts` with `python3
  tests/gen_mod_fixtures.py`, never by hand.
- `CLAUDE.md:621-623` every prose line a fixture submits is `CONTINUATION`.
- `CLAUDE.md:635-637` run `just mod-smoke` when the mod, a loader or the
  sentinel's shape changes (the design node `driving-the-transition.md:361` says
  "the mod or a loader" only; "sentinel's shape" is carried here alone).
- `CLAUDE.md:623-634` mod-smoke mechanics a mod editor needs: `live` marker
  deselected from precommit, real `claude -p --model haiku`, fixed
  `--session-id`, armed sentinel written by one allowed `printf` call (a sentinel
  predating the prompt is swept), allowlisted env, `-rs`.
- `CLAUDE.md:923-924` a new mod row goes in `tests/mod/handoff.test.ts`; a new
  plan shape is a fixture JSON plus a regeneration.
- `CLAUDE.md:602-604` the load-bearing mod rows are mutation-checked, not
  observed passing: driving inside `Stop`, continuing after a rejection, dropping
  the consume-once reset, skipping the fast path (recorded, see Homed).

### `write-path.md`

- `CLAUDE.md:768-770` `bin/handoff-approved` output pinned whole against
  `closing_directive()` itself so the producers cannot drift (also the comment at
  `tests/bin-commands.bats:219-223`).
- `CLAUDE.md:793-794` the checkpoint tests drive `scripts/checkpoint.py`
  end-to-end via subprocess.
- `CLAUDE.md:865-866` `CONTINUATION` imported from `checkpoint.py` rather than
  restated; the sentinel read back through `handoff_drive_read`.
- `CLAUDE.md:871-875` the memory part is byte-identical under both commit modes
  (a test-side restatement of the directive rule).

### `tests.md`

- `CLAUDE.md:641-644` helper placement: `tests/hook-helpers.bash` holds `setup`,
  `teardown` and helpers two or more bats files call; a helper only one file
  calls stays there (comment `tests/hook-helpers.bash:3-4`).
- `CLAUDE.md:756-757` the three bash neighbours share `setup` and `make_repo`
  through `tests/checkpoint-helpers.bash` (comment `:5-9` there).
- `CLAUDE.md:795-807` `tests/conftest.py` holds what two or more checkpoint test
  files use; import by name because pytest's `pythonpath` carries `tests/`;
  a helper only one file uses is in that file (docstring `conftest.py:11-14`).
- `CLAUDE.md:805-807` `_session_id` is not `autouse`; each
  `tests/test_checkpoint_*.py` applies it with a module-level `pytestmark` (all
  13 do; docstring `conftest.py:16-18`).
- `CLAUDE.md:798-803` `run_git` and `git_free_env`: git minus repository-local
  variables (`git rev-parse --local-env-vars`), for builders and runner, since a
  gate run from a git hook inherits `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`
  (docstring `conftest.py:73-79`; the changelog's Superseded note names only the
  gitlore cause, the generic hook cause stands).
- `CLAUDE.md:770-773` every git call in `tests/*.bats`/`*.bash` goes through
  `run_git` in `tests/probe-helpers.bash` (comment `:9-14` there).
- `CLAUDE.md:784-793` lock rows: ordering rows hold the lock from a background
  process (`tests/lock_holder.py`, via `tests/lock-helpers.bash`) and change the
  sentinel only after the actor reports through `HANDOFF_LOCK_BLOCKED_FILE`;
  contention rows use wait 0.05 s and assert byte-identical sentinel and the
  fail-closed report, plus a link at the lock; **no lock row sleeps or polls**;
  each actor's rows are with the actor (also `docs/design/sentinel-lock.md:109-128`).
- `CLAUDE.md:739-740` each state gate is paired with the positive over the same
  fixture.
- `CLAUDE.md:739-755`, `:918-919` the load-bearing rows are mutation-checked, as
  listed per file; `own` argument of the prompt marker's read is the residual
  bound (homed at `docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md:130-132`).
- `CLAUDE.md:921-924` new scenarios go into existing `.bats`/`test_*.py` files,
  not new just recipes; justfile recipes delegate (see C9).
- `CLAUDE.md:640-641` one test file per hook or library part (see C5).
- `CLAUDE.md:778-779` `version-guard.sh` is tested in the toolkit, not here
  (true: `claude-plugin-dev/tests/version-guard-decision-test.sh`, `-wording-`,
  `-git-`).
- `CLAUDE.md:775-776` `validate-plugin.bats` runs the real recipe under a stub
  `claude` printing a fixture (comment `tests/validate-plugin.bats:13-17`).

### `legacy.md`

- `CLAUDE.md:890-891` `tests/test_checkpoint_legacy.py` is the whole legacy
  migration, one file whatever its length, deleted in one pass when the fallback
  is retired (docstring `:1-4`; the file is 1563 lines).
- `CLAUDE.md:656-660`, `:668-677`, `:685-690` the legacy test rows form a
  deletion manifest. Whole files: `tests/lib-frame-legacy.bats`,
  `tests/load-handoff-legacy.bats`, `tests/test_checkpoint_legacy.py`
  (all match `tests/*legacy*`). Rows inside other files, not reached by that
  glob and found only by `grep -rni legacy tests/`: `tests/load-compact.bats`
  (34 legacy mentions, rows 68-175), `tests/lib-frame.bats:169-198`,
  `tests/hook-helpers.bash:96-110` (legacy and shadowed note constants),
  `tests/test_checkpoint_root_files.py:8,111`, `tests/test_checkpoint_directives.py:170,180`.
  The proposal's `legacy.md` row names only `tests/*legacy*`.
- `CLAUDE.md:741-749` the legacy rows are mutation-checked (recorded, see Homed).

### `docs.md`, `skills.md`

- None in this range.

## Root-bound

### Section 6 (Gates)

- `CLAUDE.md:564-565` bats for shell hooks, pytest for Python, `claude plugin
  test` for the mod.
- `CLAUDE.md:565-568` pytest runs off the uv venv direnv activates; `.envrc`
  exports `VIRTUAL_ENV` and prepends its `bin`; recipes call bare `pytest`, no
  `uv run`.
- `CLAUDE.md:568-569` `uv sync` materializes the venv; `uv.lock` committed,
  `.venv/` gitignored (verified: `.gitignore:22-23`, `git ls-files uv.lock`).
- `CLAUDE.md:569-571` `claude` is sandbox-excluded; every `claude` call,
  `just precommit`, `just validate-plugin`, `just mod-smoke` needs
  `dangerouslyDisableSandbox` (source: user-level `excludedCommands`, not in
  repo settings).
- `CLAUDE.md:573-583` `just precommit`: two cached gates `check-plugin` and
  `check-code` with their inputs and checks (verified `justfile:35-57`), plus
  `check-refs` (C1); `PLUGIN_DEV_GATE_FORCE=1` forces both; needs the
  direnv-activated venv.
- `CLAUDE.md:584-586` new validator-read component directory into
  `check-plugin`'s list (orphan, see above); `release` depends on `precommit`
  through `prerelease` (`justfile:84`).
- `CLAUDE.md:587-590` `just validate-plugin` is `claude plugin validate --strict
  --json` minus the exempt findings (C2: two, not one).
- `CLAUDE.md:624-637` `just mod-smoke` and when to run it (also mod.md).
- `CLAUDE.md:638` `just hook-test` is `bats tests/*.bats` alone; `CLAUDE.md:780`
  `just py-test` is `pytest`.
- `CLAUDE.md:591` `claude plugin test` runs `tests/mod/handoff.test.ts`.

### Section 8 (What this file holds)

- `CLAUDE.md:921-924` the substance of "a test's coverage lives in the test
  file, no test inventory" is what section 8 replaces this whole section with;
  the three rules sentences there go to `tests.md`/`mod.md` (above).

### Sections 1-5, 7

- None in this range.

## Homed

Home = test row `file:line` (name abbreviated), code/comment, design node, or
non-superseded changelog/plan record. A `bats` line number is the `@test` line.

### `claude plugin test` (`CLAUDE.md:591-607`)

- `:594-595` exact `command.run`/`prompt.submit` sequence per kind -> `tests/mod/handoff.test.ts:82` (compact), `:94` (clear), `:106` (rename).
- `:595` `Stop` drives nothing -> `handoff.test.ts:19`.
- `:595-596` aborted turn (no `Stop`) drives nothing -> `handoff.test.ts:26`.
- `:596` recorded cwd consumed once -> `handoff.test.ts:33`.
- `:596-597` project-root fast path -> `handoff.test.ts:42`.
- `:597` worktree/subdir fall-through -> `handoff.test.ts:64`.
- `:597` empty stdout -> `handoff.test.ts:72`.
- `:597` FR-G -> `handoff.test.ts:112`.
- `:597-598` malformed plan -> `handoff.test.ts:119`.
- `:599` Stop with no session id writes `failFile` -> `handoff.test.ts:176`.
- `:599-600` link at `failFile` not written through -> `handoff.test.ts:189`.
- `:600` stop-on-first-failure with the `failFile` write -> `handoff.test.ts:137`, `:158`.
- `:600-602` no live test reaches the rejection path -> `docs/design/driving-the-transition.md:365-373`.
- `:602-604` mutation-checked: drive inside `Stop`, continue after rejection, drop consume-once reset, skip fast path -> `plans/2026-10-08-plugin-becomes-a-mod/reports/step4a-green.md:9-15` (the record also lists a prompt-read bail, since removed).
- `:604-606` no prompt-box read, rig stubs none -> `docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md:97-104`, `driving-the-transition.md:157,348`.
- `:606-607` fixtures are what `drive-take.sh` prints -> `tests/mod/rig.ts:1-3`, `tests/gen_mod_fixtures.py:1-7`.

### `tests/drive-take.bats` (`:608-618`)

- `:608-609` stdout equals fixtures, `@ROOT@` substituted -> `tests/drive-take.bats:1-7`, rows `:106,114,125,135,191`.
- `:610-611` no file, `pending`, `held`, `armed` by another session print nothing, untouched -> `:100,143,151,163`.
- `:611-612` no session id, failed reader helper: file left, `kind: null` plan -> `:173,257`.
- `:612-613` a take arms once and leaves `pending` ownerless -> `:181,114`.
- `:613` `rename` removes the file -> `:125`.
- `:613-614` FR-G stays `pending` -> `:135`.
- `:614` malformed discarded with `kind: null` -> `:191`.
- `:614-616` worktree cwd takes the worktree's file, leaves the project's, newline-ending included -> `:223,232,243`.
- `:616-618` mutation: file check, `armed` gate, cwd, arming -> `step4a-green.md:16-20`; owner check and keep-owner-on-`pending`: orphan above.

### `tests/test_mod_fixtures.py` (`:619-623`)

- `:619-620` `fixtures.ts` equals what the generator renders -> `tests/test_mod_fixtures.py:12`.
- `:621-623` every prose line tied to `CONTINUATION` -> `tests/test_mod_fixtures.py:19`.

### `just mod-smoke` (`:624-637`)

- `:624-625` recipe and `live` marker, deselected from `precommit` -> `justfile:113`, `pyproject.toml:28-40`.
- `:625-627` real `claude -p --model haiku`, `--plugin-dir`, fixed `--session-id`, throwaway repo -> `tests/test_mod_live.py:1-15,41,90-130`.
- `:627-630` first turn writes armed sentinel via one allowed `printf`; a predating sentinel is swept -> `test_mod_live.py:5-9,127`.
- `:630-633` transcript checks: `custom-title`, different session's first prompt and sentinel gone, `isCompactSummary` + focus + continuation -> `test_mod_live.py:47,56,73`.
- `:633-634` env allowlisted -> `test_mod_live.py:allowed_env` (comment above it).
- `:634-635` `-rs` so a skip is not a pass -> `justfile:110-112`.
- `:636-637` it found the `Stop` call-context refusal -> `driving-the-transition.md:357-361`.

### `just hook-test` and shared helper (`:638-644`)

- `:638` `bats tests/*.bats` alone -> `justfile:102`.
- `:638-639` `bats run` captures status and output without toggling errexit -> `tests/hook-helpers.bash:8-9`.
- `:640-641` synthetic tool-event payloads, one file per hook or library part -> `hook-helpers.bash:7-9` (but C5).
- `:641-644` helper holds `setup`/`teardown` and shared helpers; one-file helper stays -> `hook-helpers.bash:1-4`.

### bats files (`:645-737`)

- `:645-646` `lib.bats` covers `handoff_root_read` and labels -> `tests/lib.bats:7,13,19,28,51,60,68,75,83,101`.
- `:646-648` worktree ending in a newline; loaders' and guard's rows in `load-handoff-cwd.bats` -> `lib.bats:110`, `load-handoff-cwd.bats:72,82,93`.
- `:648-649` resolver crash and what each hook says; `handoff_deny`; `handoff_read_regular` -> `lib.bats:137,146,154,161,169,179,191,205,211,218,224,236`.
- `:650-651` `handoff_frame` called directly -> `tests/lib-frame.bats:6-12` (comment).
- `:651-653` which file counts, headings-only/whitespace-only not, `#tag`/shebang yes, reset, nothing printed -> `lib-frame.bats:14,25,35,45,54,64,76,87,100,111,130`.
- `:653-655` unreadable root/legacy file is no body; library exits 1 or 2, raises, missing, each via a copied `_lib.sh` beside a stub -> `lib-frame.bats:156,169,186,222,228,235,244,251` (copy mechanism `:200-221`).
- `:656-660` legacy fallback in `handoff_frame` -> `tests/lib-frame-legacy.bats:16,30,44,59,77,95,114,127,141,154,169,185`.
- `:661-662` `handoff_drive_read` shape matrix and `handoff_drive_arm` -> `tests/lib-drive.bats:24-262,273-341`.
- `:663-665` four frame states, both channels whole -> `tests/load-handoff.bats:34,49,62,75` (plus `:89,100`).
- `:664-666` `clear` consume: own kind, `pending` only, leaves `armed` -> `load-handoff.bats:116,164,172,202`; "spawns nothing": C3.
- `:666-667` clear with nothing to inject still consumes and says so -> `load-handoff.bats:130`.
- `:668-677` legacy fallback in `load-handoff.sh`, both halves, root shadowing -> `tests/load-handoff-legacy.bats:22,151,164,181,199` (bodyless-legacy variant: C7).
- `:669-672` root-file symlink refusal in both loaders; symlinked `TODO.md` lets legacy todo load, no ignored note -> `load-handoff-legacy.bats:70,80,91,102,116,129,140`.
- `:673-675` headings-only root not shadowing -> `:214,227`; age from files that count -> `:306`; legacy file's age only when its half came from it -> `:263,276`.
- `:676-677` worktree's legacy file read -> `:244,330`; note order pinned, both channels whole -> `:199` (`assert_notes` `:15-19`).
- `:678-684` cwd with newline/space at root and worktree -> `tests/load-handoff-cwd.bats:19,31,43,55`; fields after the cwd pinned -> `:134,144` (comment `:121-123`); worktree newline in both loaders and guard -> `:72,82,93`; drift marker against a newline cwd -> `:100,110`; rationale comment `:5-11` (report-drive-failure scope: C6).
- `:685-690` `load-compact.bats`: own kind, leaves `armed`, `todo re-injected`, `No todo` -> `tests/load-compact.bats:19,36,176,242`; legacy paths: each half `:68,94`, both `:106`, root shadowing `:118,148`, headings-only root `:133`, symlinked legacy todo `:81`, no-body legacy `:163`.
- `:691-696` write guard: trailing slash, `/.`, `..`, newline dir -> `tests/write-guard.bats:84,94`; symlink/alias, this project and across -> `:107,116,125,136,26`; allowed `TASK.md` `:57`, `TODO.md` `:66`, `autodrive.md` `:75`, file under a dir named `autodrive` `:151`.
- `:697-698` pointer sweep -> `tests/session-pointer.bats:76,84`.
- `:699-701` reader helper failure leaves the file in both loaders and the sweep; sentinel as symlink -> `tests/sentinel-reader.bats:22,31,40,77,84,94,101,112,124`.
- `:702-703` lock in sweep and loaders; unparsable sentinel swept, no lines -> `tests/sentinel-lock.bats:39,63,151,162,177,191,114` (comment `:109-113`).
- `:704-709` failure file, stranded `pending`, sweep note and lines -> `tests/report-drive-failure.bats:17,82,293`; record: line per removal `:130,140,149`, newest 50 `:165`, unwritable `:181`, failing `mktemp` `:192`, symlinked record `:207,243,257`, old fixed temp name `:267`, none written through.
- `:709-710` `|| true` after the trim pipeline pinned by the 4000-line row -> `report-drive-failure.bats:163-167`; record-call half: orphan above.
- `:712-718` other sessions: held untouched fresh/stale/missing `tests/report-drive-failure-other-session.bats:76,89,99`; armed other-live untouched `:12`; stale/missing/no `transcript_path` swept `:22,36,45`; own aborted turn swept `:56`; `HANDOFF_OWNER_LIVE_SECS` `:65`.
- `:719-731` queued prompt: rename spared, clear/compact cancelled -> `tests/report-drive-failure-queued.bats:34,57,78`; fresh-id twins `:47,68,89`; whitespace id `:160,172`; no `prompt_id` `:102`; no marker `:118,134`; missing pointer dir `:147`; other session's armed `:216,227`; held/pending/malformed `:241,254`; sweep writes no marker `:194`; symlinked marker `:266`.
- `:732-734` marker trust: symlinked and group/world-writable dir -> `tests/report-drive-failure-trust.bats:13,23`.
- `:735-737` drift episodes, quoted cwd, no `find` forked -> `tests/report-drive-failure-drift.bats:14,49,57,65,91,155,166`.
- `:739-741` each state gate paired with the positive over the same fixture -> `docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md:140-143`, `report-drive-failure-queued.bats:36-37` (comment).
- `:741-749` legacy mutants: root-wins dropped, shadowing by body, flag reset, task-shadowed note in `load-compact.sh`, legacy read from `$CLAUDE_PROJECT_DIR` -> `plans/2026-10-11-legacy-path-migration/reports/step1-green.md:30-37`, `step1-red-fixes.md:43-52`, `step1-red-review.md:35-55`; legacy symlink refusal -> `docs/changelog/2026-10-13-a-legacy-symlink-is-not-read.md:47-48`; root symlink refusal -> `...-a-root-symlink-is-not-read.md:47-52`.
- `:741-742` loader, guard and sweep gates mutation-checked -> `plans/2026-10-08-plugin-becomes-a-mod/reports/step4b-strip.md:20-27`, `plans/2026-10-11-task-and-todo-move-to-root/reports/step5-green.md:16-36`, `docs/changelog/2026-10-13-an-unresolved-root-is-reported.md:47`.
- `:750-753` queued-prompt mutants: owner test, `prompt_id` test, kind test, `armed` test, `marker_dir_ok`, sweep marker write, `handoff-prompt-*` glob -> `docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md:144-150`.
- `:753-755` `own` argument is the residual bound -> `...2026-10-16-a-prompt-queued-into-the-arming-turn.md:130-132`.
- `:756-757` three files share `setup` and `make_repo` -> `tests/checkpoint-helpers.bash:3-9`; sourced by `inject-checkpoint-root.bats`, `bin-commands.bats`, `validate-plugin.bats`.
- `:758-767` `inject-checkpoint-root.bats`: whitespace/newline root round-trips `tests/inject-checkpoint-root.bats:65,77`; marker for both calls `:154,166`; later call replaces `:175`; other command writes nothing `:186`; no `session_id`/`prompt_id`, crashed resolver `:196,212`; symlinked marker replaced `:228`; unwritable marker, output byte-identical `:242`; id with space/newline `:275`.
- `:766-767` dropping the marker write reds the writer rows -> `docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md:146-147`.
- `:768-770` `handoff-approved` output pinned, one row per kind, against `closing_directive()` -> `tests/bin-commands.bats:226,237,248` (comment `:219-223`); unreadable not malformed `:176`; shim `:269,278`.
- `:770-773` harness row, `run_git` in `probe-helpers.bash`, decoy `GIT_DIR` byte-identical -> `bin-commands.bats:38`, `tests/probe-helpers.bash:9-14`; its mutation: orphan above.
- `:774-779` `validate-plugin.bats`: empty `.mcp.json` error and `CLAUDE.md` warning pass `tests/validate-plugin.bats:65`; spaced root `:71`; same finding on another entry `:89,108`; non-empty/absent `.mcp.json` `:96,102`; other finding on an exempt file `:114`.

### pytest (`:780-807`)

- `:780-783` resolver branch matrix, submodule `inside`, `.git` file read as git reads it -> `tests/test_worktree_root.py:29-134` (`:108` submodule, `:123` newline+space, `:134` `gitdir:` not first).
- `:784-785` the lock itself via `locked` and `handoff_lock_take` -> `tests/test_drive_lock.py:1-7,61-196`.
- `:785-793` ordering/contention rows, `lock_holder.py`, `HANDOFF_LOCK_BLOCKED_FILE`, 0.05 s, link at the lock, none sleeps or polls, per-actor placement -> `docs/design/sentinel-lock.md:109-128`, `test_drive_lock.py:206-255`.
- `:793-794` end-to-end via subprocess -> `tests/conftest.py:1-12`.
- `:795-799` conftest holds builders, payload builders, `run_checkpoint` (`with_session_id=False`), `run_git`, `drive_state`, ledger/memory fixtures, `git_free_env` -> `conftest.py:63,72,87,113,136,140,166,184,242,254`.
- `:799-807` `git_free_env` cause, import by name, `_session_id` without `autouse`, module-level `pytestmark` -> `conftest.py:11-18,72-79`; `pytestmark` in all 13 `tests/test_checkpoint_*.py`.

### `tests/test_checkpoint_*.py` (`:808-916`)

- `:809-811` `HANDOFF_ROOT` refusals, drifted cwd writes nothing -> `tests/test_checkpoint_schema.py:33,60,76`.
- `:811-815` each field missing, unknown literal, `rename` under `precompact`/`handoff`, not a string -> `test_checkpoint_schema.py:101,114,128,143,159,213,230,329,346`; retired names `:196`; `autoname` accepted: C11.
- `:814-816` `precompact` rejects `task` by key presence, removes the task file; message names the field -> `test_checkpoint_schema.py:253,282,302,315`.
- `:817-822` action vocabulary, extra key, `edit` strings, malformed JSON, `null`/absent, superfluous key under all three skills, `bogus` -> `tests/test_checkpoint_fields.py:113,169,176,214,229,253` (docstrings `:105-168,177-185`).
- `:823-826` content as given incl. headings-only/whitespace/empty -> `tests/test_checkpoint_writes.py:36,45,100,122,140`; `clear` `:57,77`; `keep` `:267`.
- `:826-829` `edit`: absent `:180`, ambiguous `:200`, file missing `:220`, successful `:150`, striking last item `:166`, failures leave bytes and no sentinel `:180-250`.
- `:829-832` `is_empty_body` -> `test_checkpoint_writes.py:325`; CLI exit codes `:348` (C10); each predicate half mutation-checked -> `docs/changelog/2026-09-14-a-heading-is-not-a-leading-hash.md:67`.
- `:833-837` symlink (relative/absolute/dangling), directory, non-UTF-8 and unreadable todo under `edit`, mode, umask -> `tests/test_checkpoint_root_files.py:72,99,115,135,149,169,184`.
- `:837-839` mutation: refusal dropped, `write_text` restored, mode copy dropped -> `docs/changelog/2026-10-13-root-files-are-not-followed-through-symlinks.md:58-66`.
- `:840-844` task shape: 1000 boundary `tests/test_checkpoint_task_shape.py:51`, headings `:77`, characters `:101`, list marker named by line `:154`, accepted lines `:176`, both facts `:184`, nothing written `:204`.
- `:845-850` rename: root with no `.claude/` `tests/test_checkpoint_rename.py:86`; `.claude` file/sentinel dir refused `:103`; `autoname` rows `:138,163,176,195,206`.
- `:851-860` transition matrix `tests/test_checkpoint_transition.py:30,45,61,76,89,106,120,134,148`; line breaks `:272`; `continue` boolean `:212,223,234,244`; continuation constant `:173`.
- `:861-866` `continue: true` bodyless shapes `tests/test_checkpoint_sentinel.py:76` (six shapes `:29-41`); legal `:91,119,130`; sentinel bytes `:149,168,187,203,220,237,254`.
- `:867-875` memory directive, handoff words, byte-identical, commit act, gitlink -> `tests/test_checkpoint_directives.py:65,76,104,124,135,148,164,187`; part order `:196,228`; harness isolation `:294,304` (ledger matrix: C4).
- `:874-875` mutants: commit act ignoring `memory` both ways, memory part differing by mode -> `docs/changelog/2026-10-30-memory-commits-go-through-the-skill.md:102-104`, `plans/2026-10-30-gitlore-d70-adoption/reports/green.md:25-40`.
- `:876-879` composition per skill -> `tests/test_checkpoint_composition.py:36,50,69,113,130,199,230` (C4 for placement of ledger matrix and order rows).
- `:880-885` arming, hold rule, owner, session-id check on both paths -> `tests/test_checkpoint_hold.py:36,75,96,144,161,186,197,210,229,248,288`; `(driven and with-commit)` disjunct mutant -> `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md:88-93`.
- `:886-889` lock wait, `edit` planned under it, fail-closed, read-back failures -> `tests/test_checkpoint_readback.py:30,61,117,142,162,195,210,227`.
- `:890-914` legacy rows -> `tests/test_checkpoint_legacy.py:252` (mtime), `:1521,1542` (cross-device), `:239` (edit/content/keep over legacy), `:374,413,432,465,491,559,607,621,675,730,760,824,891,922,963,1075,1126,1150,1168,1185,1238,1296,1328,1377,1404,1421`; `git rm --cached` run-through-shell rows `:963` (`UNSTAGE_ROOTS`, docstring `:972-985`).
- `:911-916` legacy mutants: root-wins `step2-green.md:46-50`; migrate before validation, reports after closing line `step2-green.md:48-49`; legacy unlinked before root write `step2-review-fixes-red.md:54`; `-C` dropped, quoting dropped `docs/changelog/2026-10-13-the-unstage-line-runs-from-the-root.md:91-92`; root file read on `keep`, symlink check disabled `step2-review-fixes-green.md:74-77`; rename replaced by copy+unlink `step2-red-fixes.md` (mutant "move by `write_bytes` + unlink", loses mtime); the `continue` mutant: orphan above.

### Conventions (`:921-925`)

- `:921-922` tests live under `tests/`; the justfile recipes delegate (C9) -> `justfile:102-113`.
- `:923-924` a new mod row goes in `handoff.test.ts`, a new plan shape is a fixture JSON plus regeneration -> `tests/mod/fixtures/README.md:1-30`, `tests/test_mod_fixtures.py:1-16`.

## Counts

Entries per bucket (each entry is one bullet above; a bullet may carry several
clauses of one fact):

| Bucket     | Entries |
| ---------- | ------- |
| Orphans    | 7       |
| Conflicts  | 11      |
| Rules-bound| 32      |
| Root-bound | 11      |
| Homed      | 104     |
| Drop       | 0 (the "About 35 s" figure is filed under C8) |

Orphans by destination:

| Destination                    | Count | Entries |
| ------------------------------ | ----- | ------- |
| root section 6 (Gates)         | 1     | new component directory (`:584-586`) |
| `report only` (unrecorded mutation checks) | 6 | drive-take owner and ownerless-`pending` mutants; sweep record call; bats harness row; hold variants; `continue` effective-todo; `handoff-approved` bare-name row |
| design node                    | 0     | none |
| rules file, memory, test comment | 0   | none |

Orphans destined to a design node, per node (current `wc -l`, cap 400 hard):

| Node | Orphans landing | Lines now |
| ---- | --------------- | --------- |
| `docs/design/driving-the-transition.md` | 0 | 373 |
| `docs/design/sentinel-lock.md` | 0 | 128 |
| `docs/design/queued-prompts.md` | 0 | 79 |
| `docs/design/the-write-path.md` | 0 | 262 |
| `docs/design/the-checkpoint-directive.md` | 0 | 159 |
| `docs/design/the-skills.md` | 0 | 89 |
| `docs/design/scoping.md` | 0 | 114 |
| `docs/design/decisions.md` | 0 | 330 |
| `docs/design/rejected-alternatives.md` | 0 | 341 |
| `docs/design/release-infrastructure.md` | 0 | 34 |
| `docs/design.md` | 0 | 381 |

Rules-bound by target: `bash.md` 3, `mod.md` 9, `write-path.md` 4, `tests.md` 13,
`legacy.md` 3, `docs.md` 0, `skills.md` 0 (32 total; `tests.md` also takes the
test-placement and lock-row rules the proposal lists).

Notes for the split commit:

- The one rules-file carry whose only statement is in a plan file, not a design
  node, comment or changelog: the `process.run`, `fs.*`, clock enumeration of
  what the kit rejects unstubbed (`mod.md`).
- `legacy.md` should name the legacy rows outside `tests/*legacy*` (see
  Rules-bound); the proposal's glob misses them and `grep -rni legacy tests/`
  finds them.
- Superseded blockquotes met and judged: `2026-10-13-the-test-harness-sheds-gits-environment.md:7`
  (scoped to gitlore's hook cause; generic git-hook cause and the mutants stand),
  `2026-10-13-the-armed-sentinel-has-an-owner.md:5,68,105`,
  `2026-10-08-the-plugin-becomes-a-mod.md:3` (prompt-box read, not relied on).
  No cited home sits under a covering Superseded blockquote.
