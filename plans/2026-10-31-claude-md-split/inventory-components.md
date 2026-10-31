# Inventory: CLAUDE.md lines 94-530 (component bullets)

Scope: the section "### Skills, manifest, hooks, mod". Method: every sentence
read against the code (`scripts/`, `bin/`, `hooks/`, `skills/`), all of
`docs/design.md` and `docs/design/*.md`, the `docs/changelog/` entries (checked
for `Superseded` scope), `plugin-dev/` and `memory/`. A home was confirmed by
opening the cited line, never from a filename.

Headline: the range is almost entirely a third copy. No sentence that is a
rationale, residual bound or host constraint lacks a home except the ones the
proposal already assigns to a rules file or a root section. There is **no orphan
that needs a new sentence in `driving-the-transition.md`**. Two conflicts need a
correction before the section is deleted (`.envrc`, FR3's "only"), and three
points in the proposal itself are wrong or incomplete (end of Conflicts).

## Orphans

None that lack an assigned destination. Three borderline items, none strong
enough to count:

1. `CLAUDE.md:465` "(`${CLAUDE_PLUGIN_ROOT}` is not available in the agent's
   Bash)". Host constraint, and the reason the shim exists. Its only home is
   `docs/changelog/2026-06-12-gitlore-aware-handoff.md:25` ("verification showed
   `CLAUDE_PLUGIN_ROOT` is absent from the agent's Bash while every plugin's
   `bin/` is on PATH"), about the retired `handoff-memory-probe` shim. That
   paragraph is not under a `Superseded` blockquote (lines 3-9 supersede the
   commit path and state "the probe-as-PATH-shim rationale ... unchanged"), so
   it counts as homed. It is a weak home: no design node and no code comment says
   it (`bin/handoff-checkpoint:1-4` says only that `bin/` is on PATH). Optional
   destination, one clause: `docs/design/the-write-path.md`, section "One
   channel, one writer", at "a PATH-resident shim (`bin/`)" (line 68), "because
   `CLAUDE_PLUGIN_ROOT` is unset in the agent's Bash". Not counted in Counts.
2. `CLAUDE.md:300` "`HANDOFF_POINTER_DIR` (`/tmp/claude`, overridable for tests)".
   The override is `scripts/_lib.sh:70`; "for tests" is intent. Why a literal
   directory and not `$TMPDIR` is `scripts/_lib.sh:63-69`. Drop "for tests".
3. `CLAUDE.md:512-514` `... — hook (vX.Y.Z)`, "the version only when the entry
   maps onto one release". Not an orphan, a dead convention: see Conflicts C3.

The ten facts the proposal says have no docs home map, within this range, as
follows. Each is rules-bound, root-bound or already homed, so none is an orphan:
`source-path` (bash.md), `mapfile` (bash.md; also code comment
`scripts/_lib_drive.sh:229-233`), the `$` rule (mod.md; also memory, see
Conflicts C7), 2000 words (skills.md), the Corrected blockquote (docs.md),
`inbox/README.md` (homed there, `inbox/README.md:1-25`), `marker_unsettled`
(homed: `docs/design/queued-prompts.md:46-54`, `scripts/report-drive-failure.sh:296-311,351-357`),
push targets (root 5).

## Conflicts

C1. **`.envrc` does not export `MARKETPLACE_DIR`.** Highest value.
- `CLAUDE.md:488-489`: "`.envrc` — exports `MARKETPLACE_DIR` (sibling
  `claude-plugins` repo), which `just release` requires; `direnv allow` once per
  clone."
- `/Users/david/code/handoff/.envrc:1-12`: `source_up_if_exists`,
  `PATH_add .gitlore/bin`, the `VIRTUAL_ENV` export, `PATH_add plugin-dev/bin`.
  No `MARKETPLACE_DIR`. The export is in the parent `/Users/david/code/.envrc`
  (`export MARKETPLACE_DIR="$HOME/code/claude-plugins"`), pulled in by
  `source_up_if_exists`; commit `674137f` "inherit MARKETPLACE_DIR from parent
  .envrc" removed the local one. The need is real:
  `plugin-dev/release-preflight.sh:174-175` dies with "MARKETPLACE_DIR not set
  (set in .envrc ...)".
- The same stale claim is in `docs/design/release-infrastructure.md:28-29`
  ("path from `$MARKETPLACE_DIR`, set in `.envrc`"). Root section 6 must state
  the true setup (inherited from a parent `.envrc` that this repo sources) and
  that sentence needs the same correction, not deletion.

C2. **FR3 / "one writer of the sentinel" is not what the code does.**
- Proposal `write-path.md` row: "one writer of the sentinel". `CLAUDE.md:58-59`
  (out of range) and `docs/design.md:139-140` (FR3): ".claude/autodrive is
  written only by the checkpoint."
- `scripts/_lib_drive.sh:370-404` (`handoff_drive_arm`, called by
  `bin/handoff-approved:362` and `scripts/drive-take.sh:102`) rewrites line 1;
  `docs/design/driving-the-transition.md:59` says "Both writers rename a file
  into place: the checkpoint, and `handoff_drive_arm`";
  `docs/design/the-checkpoint-directive.md:123-126`. The sweep and the loaders
  also remove it.
- What holds is "the checkpoint is the only composer of its content, and the
  only thing an agent's Write/Edit may not touch is the file (write-guard)".
  `write-path.md` should say composer, and name `handoff_drive_arm` as the one
  other rewriter of line 1. Within the range, `CLAUDE.md:306-308` and `466-468`
  are correct.

C3. **The changelog index format is unexercised.**
- `CLAUDE.md:512-514`: "`- [<date> — Title](changelog/<file>.md) — hook
  (vX.Y.Z)`, the version only when the entry maps onto one release".
- `docs/changelog.md`: none of its 103 lines carries a `(vX.Y.Z)` (grep
  `v0\.[0-9]` and `([vV]\?[0-9]\+\.[0-9]\+` find none), and its header
  (`docs/changelog.md:1-9`) states no format. `docs.md` should carry the real
  format, `- [<date> — Title](changelog/<file>.md) — <hook sentence>`, and drop
  the version clause or say it has never been used.

C4. **`skills/handoff/references/design.md` is a drifted mirror, and it ships.**
- `CLAUDE.md:119-120`: "condensed design notes; the full rationale is in
  `docs/design.md`."
- `skills/handoff/references/design.md:26`: "Goal (if task-scoped) | last user
  prompts" under "derivable from state". `docs/design.md:111-117` and
  `docs/design/decisions.md:91` say the last-N-prompts category was withdrawn and
  the frame reads no transcript. The file is also a fourth copy of the design
  (116 lines, `skills/` is in `dist.include`). Low severity; the section 2 index
  line should not call it a mirror, or the file should be on the cleanup list.

C5. **Legacy `paths:` in the proposal miss the files the bridge touches.**
`scripts/_checkpoint_plan.py`, `scripts/_lib_frame.sh` and `scripts/load-*.sh`
are listed. `grep -rli legacy scripts bin hooks skills tests` also hits
`scripts/_lib.sh:26-34`, `scripts/checkpoint.py` (`compose_directives:362-366`,
`gone`), `scripts/_checkpoint_lib.py` (`legacy_unstage_directive`,
`commit_directive`'s `legacy_paths`), `scripts/_lib_drive.sh`,
`tests/hook-helpers.bash`, `tests/lib-frame*.bats`,
`tests/test_checkpoint_directives.py`, `tests/test_checkpoint_legacy.py` and
`tests/test_checkpoint_root_files.py`, of which `tests/*legacy*` matches only
some. `legacy.md` must say the pass starts from the grep, not from its `paths:`.

C6. **Inbound references: the proposal's list is one short.** Step 3 names
`scripts/_lib.sh:17` and `scripts/checkpoint.py:44`. `scripts/_checkpoint_plan.py:316`
("(see CLAUDE.md conventions)") is the same citation and is not listed. All three
point at the paths rule, which stays in root section 5.

C7. **The memory step is already done.** The proposal's Memory section proposes
writing three host facts to the ddaanet tier "if the mod-authoring skill does
not already carry them". They are in memory already:
`memory/ddaanet/cc-mods-driving-commands.md:15-33` (no `command.run` from
`classic.Stop`, `$.clock.after` included, timers die under `-p`, `$` only to
top-level function declarations) and `memory/cc-queued-prompt-hooks.md`
(`prompt_id`, CC 2.1.301). Questions 5 is moot; no `gitlore:commit` for it.

## Rules-bound

### `bash.md` (`scripts/**/*.sh`, `bin/*`, `tests/**/*.bats`, `tests/**/*.bash`)
- 253-255: `# shellcheck source-path=SCRIPTDIR source=_lib.sh` above every `source`.
- 254-255: `# shellcheck disable=SC2034` for variables only sourcing scripts read.
- 255: `_lib.sh` is the one file callers source.
- 265-267: a part is never sourced by a caller; the nested form
  `source-path=SCRIPTDIR/../scripts source=<part>` is what lets shellcheck follow
  into it from `bin/` and `tests/` (a bare `SCRIPTDIR` resolves against the
  top-level script). Not stated in any code comment.
- 288-299: every cwd-scoped hook anchors on `handoff_root_read`, never on the raw
  `.cwd` nor `CLAUDE_PROJECT_DIR` (also `docs/design/scoping.md:5-9`).
- 291-292: resolver answers NUL-terminated; a `$(...)` capture strips a trailing
  newline.
- 224-225, 321, 340, 361: NUL-terminated reads (`read -r -d ''`) for every field
  that is any string.
- 334-336: `read` loop, not `mapfile` (bash 3.2); arrays expanded as
  `${A[@]+"${A[@]}"}`.

### `mod.md` (`hooks/**`, `tests/mod/**`, `tests/gen_mod_fixtures.py`, `scripts/drive-take.sh`, `scripts/load-*.sh`, `scripts/_lib_drive.sh`)
- 121-123: every `${CLAUDE_PLUGIN_ROOT}` path in `hooks.json` double-quoted; the
  validator warns otherwise (the reason is stated nowhere else).
- 132-134: never drive from `Stop` (`$.command.run` refused from its call
  context, `$.clock.after` included; timers die under `-p`); drive inline from
  `turn.complete`.
- 147-149: a hooks module may pass `$` only to top-level functions (static check
  at load). Also in memory, C7.
- 161-162: `drive-take.sh` stdout is pinned by `tests/mod/fixtures/*.json`.
- 474-476: `tests/mod/fixtures.ts` is rendered from `fixtures/*.json` by
  `gen_mod_fixtures.py` because a hooks-module test can neither read files nor
  import JSON; `test_mod_fixtures.py` fails when they disagree (regenerate, never
  hand-edit).
- Candidates the proposal does not name, all homed in design: the mod never reads
  the sentinel (130-149, `driving-the-transition.md:113`); never reads the prompt
  box (137-140, `:157-164`).

### `write-path.md` (`scripts/*checkpoint*.py`, `bin/handoff-*`, `tests/test_checkpoint_*.py`)
- 381: the checkpoint is the one write path for `TASK.md`/`TODO.md` (FR1); see C2
  for "one writer of the sentinel".
- 401-405: NFR1, no git work; the git line is printed, never run.
- 442-443: schema and write-time errors go through `lib.err` (names the field,
  exits 2).
- 460-461, 470-471: `closing_directive()` text is repeated by
  `bin/handoff-approved` byte for byte (`handoff-approved:367-371`).
- 406-412: `_checkpoint_payload.py` reads the payload only; the two readers of the
  environment (`validate_root`, `require_session_id`) live in `checkpoint.py`.

### `skills.md` (`skills/**`)
- 106: `skills/handoff/SKILL.md` stays <= 2000 words (now 1723).
- 97-100, 108-110: the markdown templates and the seam live only in
  `handoff/SKILL.md`; `precompact` defers to it (also `scripts/_lib_frame.sh:34-36`).
- 105, 101-102: a skill states none of what the checkpoint prints; the only tool
  calls ahead of the checkpoint are the memory writes.
- 111-116: `autoname` payload is exactly `{"skill","rename"}`, no tool call to
  decide.
- 117-118: `pending` makes no tool call and writes nothing.
- 108-109: `precompact` carries no `rename` and no `task` (schema-forbidden).

### `tests.md` (`tests/**`)
- 378-380: `HANDOFF_LOCK_BLOCKED_FILE` is the one test-only seam; ordering rows
  block on it instead of sleeping.
- 128-129: the hook `timeout`s are asserted against the lock's default wait
  (`tests/test_drive_lock.py:256-278`).

### `docs.md` (`docs/**`, `plans/**`, `inbox/**`)
- 490-493: `docs/design.md` is the hub; read the node before making a claim.
- 512-520: changelog entries never edited after the fact; a reversal heads the
  section with `> **Superseded <date>** (see [<title>](<sibling>.md))`; index line
  format (see C3); a design change adds a file plus its index line and rewrites the
  invalidated design prose in the same pass.
- 521-525: `plans/` are write-time records; a wrong claim is corrected in place
  with `> **Corrected at review, <date>.**` quoting the original, naming what was
  wrong, the evidence and what stands.
- 526-529: inbox triage (act and delete, or promote to `plans/`; never the repo
  root; a brief's recommendation is input); `inbox/README.md` already says it.

### `legacy.md` (`scripts/_checkpoint_plan.py`, `scripts/_lib_frame.sh`, `scripts/load-*.sh`, `tests/*legacy*`; see C5)
- 269-271, 439-441: `HANDOFF_LEGACY_REL_*` are the one marker, one name per
  language (`_lib.sh:26-34`, `_checkpoint_plan.py:321-326`).
- 168-174, 183-187, 284-286: the loaders read a half from its legacy path when the
  root file has no body and say so through `handoff_frame_notes`, one producer.
- 272-283: `handoff_frame` legacy arguments and flags; root wins by body,
  shadowing by existence; a symlink at any of the four paths is absent.
- 419-441: plan-layer migration (`read_half`, `legacy_fate`, `move_legacy`):
  `keep` moves a legacy todo, a write/`edit`/`clear` removes it unless the root
  file has a body before and after, a symlink to a file at the legacy path is
  refused, the legacy file is unlinked only after the root file is written.
- 452-456: `legacy_unstage_directive` (`git -C <root> rm --cached
  --ignore-unmatch -q -- <path> ...`), only for paths this call moved or removed.
  Lives in `_checkpoint_lib.py`, outside the proposal's `paths:` (C5).
- The retirement condition is not in this range; proposal question 6 stands.

## Root-bound

### Section 1 (what the plugin is, the flow)
- 130-136, 167-179: the chain checkpoint -> sentinel -> mod drive -> loader; the
  loaders start no continuation, the mod submits it.
- 150-166: the states `armed`/`held`/`pending`, FR-G (empty `before`), `kind: null`.
- 328-336: sentinel grammar words (state on line 1 with owner, kind on line 2).
- 400-402: `held` iff `(names a command and memory owed) or (driven and
  with-commit)`.
- 196-197, 131-134: mod needs Claude Code >= 2.1.287 (`--safe-mode`, older, or
  organization-managed without the plugin listed).
- 460-462 / 213-216 wording: `typed`, `CONTINUATION` (`checkpoint.py:276`).

### Section 2 (component index): one line each, with the design node
- 96 plugin.json; 97-120 four skills and `references/design.md` (see C4);
  121-129 hooks.json; 130-149 `hooks/handoff.ts` (driving-the-transition.md);
  150-166 drive-take; 167-190 loaders (driving); 191-252 report-drive-failure
  (driving, queued-prompts, scoping); 253-336 `_lib.sh` and its three parts
  (scoping, sentinel-lock, driving); 337-347 write-guard (the-write-path.md
  "What is guarded"); 348-351 session-pointer (scoping); 352-355 worktree_root
  (scoping); 356-367 inject-checkpoint-root (scoping, queued-prompts); 368-380
  `_drive_lock.py` (sentinel-lock); 381-463 the checkpoint modules
  (the-write-path, the-checkpoint-directive); 464-473 `bin/*`; 474-476
  gen_mod_fixtures.

### Section 3 (routing table)
- 490-511: the touch-to-node table, unchanged. All nine nodes it names exist
  (`docs/design/`). It is the only touch-to-read map; `docs/design.md:209-233`
  maps by question, not by file.

### Section 4 (where documents go)
- 490-493 hub, 512-520 changelog, 521-525 plans, 526-529 inbox: one line each; the
  editing rules go to `docs.md`.

### Section 5 (Conventions; keep the heading, `_lib.sh:17`, `checkpoint.py:44`, `_checkpoint_plan.py:316` cite it)
- 482-487: a `release X.Y.Z` acknowledgement names both push targets up front
  ("bumps `handoff` (tag + GH release) and `claude-plugins` (marketplace
  entry)"), since auto-mode's permission harness reads only the current message.
  Homed nowhere else (grep of docs, memory, plans finds none).
- 477-478: `plugin-dev/` is read-only (also the always-loaded
  `memory/ddaanet/shared-claude.md`, "Never hand-edit a vendored subtree").
- 486-487: `version-guard.sh` (wired in `.claude/settings.json`) refuses agent
  edits to `plugin.json`'s `.version` (`plugin-dev/version-guard.sh:1-8`).
- 518-520: a design change lands with its changelog entry and the design prose it
  invalidates, in one pass.

### Section 6 (Gates)
- 479-482: `release.just` (`release`, `resume-release`, `check-version`) and
  `prerelease` = `precommit` (homed `plugin-dev/release.just:47-52,70-80`,
  `justfile:16-19`); no prose needed beyond a pointer.
- 488-489: direnv and `MARKETPLACE_DIR`, corrected per C1.

### Section 7 (non-goals, frame assembly)
- Nothing in this range.

### Section 8 (what this file holds)
- Nothing in this range; the range itself is what section 8 forbids.

## Homed

### `.claude-plugin/plugin.json`
- 96 -> the file itself.

### `skills/handoff/SKILL.md`
- 97-99 protocol, driven or not -> `skills/handoff/SKILL.md:25-96`, `docs/design/the-skills.md:5-16`
- 99-100 single source of truth for templates and seam -> `scripts/_lib_frame.sh:34-36`
- 100-102 three steps, memory writes the only calls before the checkpoint -> `skills/handoff/SKILL.md:19-24`
- 102-105 three fields, one heredoc call, follow what it prints -> `skills/handoff/SKILL.md:25-104`, `docs/design/the-checkpoint-directive.md:5-12`
- 103 "does the ask imply a commit" -> `docs/design/decisions.md:113-124`, `skills/handoff/SKILL.md:44-59`

### `skills/precompact`, `autoname`, `pending`, `references/design.md`
- 107-110 same three steps, `compact` carries focus -> `skills/precompact/SKILL.md:13-107`, `the-skills.md:9-15`
- 108-109 no `rename`, no `task`, schema-forbidden -> `scripts/_checkpoint_payload.py:121-124,245-248`
- 109-110 defers templates to handoff -> `skills/precompact/SKILL.md:66-70`
- 111-113 autoname payload and every other field forbidden -> `skills/autoname/SKILL.md:25-40`, `_checkpoint_payload.py:90-94`, `the-skills.md:79-83`
- 114-115 forbidden fields keep the memory directive from composing -> `scripts/checkpoint.py:72`, `the-skills.md:81-84`
- 115-116 stays a skill (a command cannot run from its own handler); rename sentinel -> `the-skills.md:84-89`
- 117-118 pending lists the frame from context -> `skills/pending/SKILL.md:8-26`, `the-skills.md:21-25`
- 119-120 condensed notes -> `skills/handoff/references/design.md:1-5` (see C4)

### `hooks/hooks.json`
- 121-122 modules plus six command hooks -> `hooks/hooks.json:3-71`, `docs/design.md:206`
- 123-127 hook-to-script mapping -> `hooks/hooks.json:7-70`
- 127-129 10 s timeout = default wait + 5 s, asserted -> `sentinel-lock.md:90-93`, `tests/test_drive_lock.py:256-278`

### `hooks/handoff.ts`
- 130-131 `Stop` records cwd and session id only -> `hooks/handoff.ts:15-19`, `driving-the-transition.md:84-86`
- 131-132 interrupt fires no `Stop`; aborted turn arms nothing -> `driving-the-transition.md:98-101`, `handoff.ts:3-4`
- 132-134 drives inline; host refuses `command.run` from `Stop`, timers die under `-p` -> `driving-the-transition.md:88-97`, `handoff.ts:3-6`
- 134-136 fast path, spawn `drive-take.sh`, empty stdout -> `handoff.ts:33-37`, `driving-the-transition.md:146-149`
- 137-140 no prompt-box read, drives over typed text -> `driving-the-transition.md:157-164`, `tests/mod/handoff.test.ts` rows
- 140-142 `/`-line is `command.run`, prose is `prompt.submit({asUser:true})` -> `handoff.ts:75-80`, `driving-the-transition.md:153-156`
- 142-143 first rejection writes `failFile`, toasts, ends sequence -> `handoff.ts:48-56`, `driving-the-transition.md:167-172`
- 143-144 `Stop` with no session id writes `failFile` -> `handoff.ts:40-46`, `driving-the-transition.md:129-133`
- 144-147 `failFile` stat first, no write through a link, residual -> `handoff.ts:59-72`, `driving-the-transition.md:169-174`
- 147 never reads the sentinel -> `handoff.ts:5-7`, `driving-the-transition.md:113`

### `scripts/drive-take.sh`
- 150-153 takes only this session's `armed`, via `handoff_drive_read` -> `drive-take.sh:82-98`, `driving-the-transition.md:111-128`
- 152-153 every session sharing the root ends turns here -> `drive-take.sh:83-86`, `handoff.ts:8-9`
- 153-155 `pending` ownerless, removal for `rename` -> `drive-take.sh:100-105`, `driving-the-transition.md:134-137`
- 154-156 one JSON line shape; empty stdout cases -> `drive-take.sh:2-9,37,91,98`, `driving-the-transition.md:124-135`
- 156-158 FR-G -> `drive-take.sh:110-117`, `driving-the-transition.md:138-142`, `docs/design.md:174-177`
- 158-159 malformed removed, `kind: null`; unresolved root -> `drive-take.sh:24-29,72-80`, `scoping.md:45-46`
- 159-161 no session id, or failed reader -> `drive-take.sh:63-71,92-97`, `driving-the-transition.md:68-72,129-133`
- 161-162 stdout pinned by fixtures -> `driving-the-transition.md:121-122` (mod.md)
- 162-166 holds the lock, re-test, fail-closed plan -> `drive-take.sh:39-59`, `sentinel-lock.md:74-77`, `tests/mod/fixtures/lock-busy.json`

### `scripts/load-handoff.sh`, `scripts/load-compact.sh`
- 167-171 frame in memory, `additionalContext` plus `systemMessage` -> `load-handoff.sh:86-151`
- 170-174 always reports the four frame states -> `load-handoff.sh:128-138`, `driving-the-transition.md:202-206`
- 172-174 legacy notes order, age from files that count -> `load-handoff.sh:102-126`, `driving-the-transition.md:210-217`
- 175-178 on `clear` consumes `pending` `clear` first under the lock -> `load-handoff.sh:55-78`, `driving-the-transition.md:187-200`
- 178-179 lock not taken: frame injected, note on both channels -> `load-handoff.sh:58-60,140-142`, `sentinel-lock.md:83-88`
- 179 starts no continuation -> `load-handoff.sh:11-13`, `driving-the-transition.md:189-191`
- 180-183 compact loader consumes only `pending` `compact` -> `load-compact.sh:195-224`, `driving-the-transition.md:195-198`
- 183-186 `todo re-injected` / `No todo`, legacy fragments, same bytes without one -> `load-compact.sh:237-258`, `driving-the-transition.md:206-208,215-217`
- 186-188 lock not taken: injects, names the sentinel -> `load-compact.sh:185-194,252-257`, `sentinel-lock.md:83-88`
- 188-190 silent when nothing pending -> `load-compact.sh:158-161,183,219`, `driving-the-transition.md:207-208`

### `scripts/report-drive-failure.sh`
- 191-193 consumes `autodrive.failed`, reports on both channels -> `report-drive-failure.sh:260-289`, `driving-the-transition.md:222-228`
- 193-194 clears a stranded `pending` -> `report-drive-failure.sh:278-286`, `driving-the-transition.md:227-231`
- 194-198 sweeps `armed` (Esc, mod not loaded), note names the mod, prints lines -> `report-drive-failure.sh:345-375`, `driving-the-transition.md:236-277`
- 198-201 prompt queued fires the hook before `Stop` with the turn's `prompt_id` (2.1.301) -> `queued-prompts.md:6-13`
- 201-205 queued test: armed, owner, non-empty id equal to marker; marker path; never written -> `report-drive-failure.sh:296-312`, `queued-prompts.md:26-28`
- 205-209 `rename` left, `clear`/`compact` swept, recorded, reported, directive note, no lines -> `report-drive-failure.sh:333-344`, `queued-prompts.md:30-44`
- 209-212 no `prompt_id` swept, note names a typed-ahead prompt -> `report-drive-failure.sh:351-357`, `queued-prompts.md:46-57`
- 212-214 ordinary prompt forks nothing -> `report-drive-failure.sh:296-304`, `queued-prompts.md:26-27`
- 214-216 cancelling vs sparing, marker at the checkpoint -> `queued-prompts.md:21-24,39-44`
- 216-217 unparsable file swept without lines -> `report-drive-failure.sh:371-374`, `driving-the-transition.md:273-274`
- 217 `link` as its own state, unread -> `report-drive-failure.sh:223-224`, `driving-the-transition.md:57-58`
- 217-218 `unread`, reported, never swept -> `report-drive-failure.sh:218-222,329-332`, `driving-the-transition.md:68-72`
- 218-220 `locked`, left in place, failure record kept -> `report-drive-failure.sh:203-209,272-275,325-328`, `sentinel-lock.md:78-82`
- 220-222 `held` exempt, dead owner's replaced by next checkpoint -> `report-drive-failure.sh:239-246,319-323`, `driving-the-transition.md:254-259`
- 222-226 other session's `armed`, liveness window 600 -> `report-drive-failure.sh:235-250`, `_lib.sh:72-88`, `driving-the-transition.md:243-252`
- 226-227 link at `autodrive.failed` removed unread -> `report-drive-failure.sh:268-271`, `driving-the-transition.md:231-234`
- 227-232 drift once per episode, ANSI reset, `%q` paths -> `report-drive-failure.sh:80-129,382-385`, `scoping.md:48-66`, `changelog/2026-07-31-session-root-drift.md:80-86`
- 232-235 marker dir 0700, trust test, no-follow read, replace write -> `scoping.md:61-66`, `_lib_files.sh:262-287`
- 234-235 no marker forks nothing -> `report-drive-failure.sh:121-127`
- 235-237 typed-ahead cause, `marker_unsettled` states -> `report-drive-failure.sh:296-311,354-357`, `queued-prompts.md:46-54`
- 238-240 lock from read to exit, `record_sweep` included, only when a file is on disk -> `report-drive-failure.sh:191-206`, `sentinel-lock.md:28-29,37-38`
- 241-249 sweep record: fields, newest first, 50, never consumed, symlink left alone, `mktemp`, `os.replace` -> `report-drive-failure.sh:135-177`, `driving-the-transition.md:279-293`
- 250-252 only trace of who took a sentinel -> `_lib.sh:54-59`, `driving-the-transition.md:279-284`

### `scripts/_lib.sh` and its parts
- 253-255 shellcheck forms -> rules-bound (`bash.md`), forms visible at every `source` line
- 256-260 what `_lib.sh` keeps, three parts sourced last -> `_lib.sh:199-207`
- 260-265 contents of the three parts; a part is never sourced by a caller -> `_lib_frame.sh:1-7`, `_lib_drive.sh:1-6`, `_lib_files.sh:1-6`
- 267-268 `HANDOFF_REL_*` constants -> `_lib.sh:16-61`
- 269-271 `HANDOFF_LEGACY_REL_*` and the Python mirror -> `_lib.sh:26-34`, `_checkpoint_plan.py:321-326`
- 272-286 `handoff_frame` variables, flags, symlinks, rc, has-body -> `_lib_frame.sh:9-80`, `the-write-path.md:30-63`
- 284-286 `handoff_frame_notes` one producer -> `_lib_frame.sh:91-118`, `the-write-path.md:56-58`
- 287 `handoff_deny` -> `_lib.sh:187-197`
- 288-299 `handoff_root_read`, four labels, `unresolved` and each caller's answer -> `_lib.sh:136-185`, `scoping.md:23-46`
- 300 `HANDOFF_POINTER_DIR` -> `_lib.sh:63-70`
- 301-307 `handoff_drive_read`, link refused, rc 2; `handoff_drive_arm` atomic -> `_lib_drive.sh:186-404`, `driving-the-transition.md:50-72`
- 308-312 `handoff_read_regular` statuses, `O_NOFOLLOW`; `handoff_replace` -> `_lib_files.sh:216-260`
- 312-318 `marker_dir_ok`, `handoff_write_marker`, shared by two markers -> `_lib_files.sh:262-287`, `scoping.md:91-93`
- 318-322 `handoff_read_marker` statuses -> `_lib_files.sh:289-316`
- 323-328 `handoff_lock_take`, fd 9, rc 1/2, `create` only without a regular file -> `_lib.sh:90-134`, `sentinel-lock.md:30-54`
- 328 `handoff_owner_live`, `handoff_drive_has_source` -> `_lib.sh:72-88`, `_lib_drive.sh:360-368`
- 328-334 state line, owner rules, kind fixes the shape, counts -> `_lib_drive.sh:195-216,286-356`, `driving-the-transition.md:13-48`
- 333-334 command literals pinned to a slot, no prose line starts with `/` -> `_lib_drive.sh:148-184`, `driving-the-transition.md:46-48`
- 334-336 `read` loop, not `mapfile`, expansion form -> `_lib_drive.sh:229-233` (also `bash.md`)

### Other scripts
- 337-339 write-guard denies the sentinel only, plus an unresolved root -> `write-guard.sh:31-53`, `the-write-path.md:221-228`, `scoping.md:41-43`
- 339-342 one jq parse, substring test, NUL-terminated, three paths -> `write-guard.sh:11-26,41-47`, `the-write-path.md:229-239`
- 343-346 checkpoint-only vs cross-project; symlink caught only when the path names it -> `write-guard.sh:49-65`, `the-write-path.md:236-243`
- 346-347 `TASK.md`/`TODO.md` not guarded -> `the-write-path.md:225-227`
- 348-351 `session-pointer.sh` sweep, names, 7 days, `-maxdepth 1`, 0700 -> `session-pointer.sh:89-116`, `scoping.md:98-107`
- 352-355 `worktree_root.py`, containment wins -> `worktree_root.py:53-96`, `scoping.md:34-36`
- 356-359 `inject-checkpoint-root.sh` substring match, `export` rewrite, why -> `inject-checkpoint-root.sh:131-136,182-191`, `scoping.md:68-76`
- 359-365 prompt marker, written only here, failure silent -> `inject-checkpoint-root.sh:138-140,170-180`, `queued-prompts.md:15-24`, `scoping.md:86-96`
- 365-367 NFR2 negative path -> `inject-checkpoint-root.sh:134-136`, `docs/design.md:191-194`, `scoping.md:93-96`
- 368-373 `_drive_lock.py` flock, `locked`, `create`/`wait`, 75 -> `_drive_lock.py:1-60,203-250,325-330`, `sentinel-lock.md:21-39`
- 373-377 bounded wait, fail closed, checkpoint exits 2, hook timeouts -> `_drive_lock.py:134-145`, `sentinel-lock.md:41-95`, `checkpoint.py:237-262`
- 377-380 0600, `O_NOFOLLOW`, never deleted; test-only FIFO seam -> `_drive_lock.py:147-149,253-263,293-311`, `sentinel-lock.md:97-119`

### Checkpoint modules
- 381-382 root from `HANDOFF_ROOT` -> `checkpoint.py:120-136`, `the-write-path.md:121-134`
- 383-388 payload validation, tagged union, `.claude/` created, `check_sentinel_target` -> `checkpoint.py:51-117,237-296`, `sentinel-lock.md:66-70`
- 388-393 read-plan-write under the lock, `cannot write`, read-back removes -> `checkpoint.py:92-112,179-234`, `sentinel-lock.md:59-70`
- 393-397 legacy reports first, `compose_directives`, closing line last -> `checkpoint.py:343-381`, `the-checkpoint-directive.md:5-43`
- 397-399 `CLAUDE_CODE_SESSION_ID` checked before any write -> `checkpoint.py:77-82,139-144`
- 399-402 hold decision -> `checkpoint.py:163-176`, `the-checkpoint-directive.md:75-107`
- 402-405 NFR1; git line printed, relative paths, `-C` -> `checkpoint.py:14-18`, `docs/design.md:185-190`, `the-write-path.md:181-200`
- 406-412 payload module -> `_checkpoint_payload.py:1-10,22-31,59-87`, `the-write-path.md:255-262`
- 413-418 `validate_task`/`validate_todo`, FR13, `rename` rules, `autoname` -> `_checkpoint_payload.py:115-134,238-267,305-342,345-379`, `the-write-path.md:202-219`
- 419-423 plan layer, `FilePlan`, `apply_plan` -> `_checkpoint_plan.py:36-80,145-231`
- 423-434 legacy migration, refusals, unlink after write (legacy.md) -> `_checkpoint_plan.py:83-143,212-231`, `the-write-path.md:149-179`
- 434-437 `write_replacing`, mode kept -> `_checkpoint_plan.py:234-267`, `the-write-path.md:172-178`
- 437-439 `has_body_after`, refuses `continue: true` with nothing -> `_checkpoint_plan.py:193-209`, `checkpoint.py:147-160`, `the-write-path.md:99-102`
- 439-441 Python constants mirror `_lib.sh` -> `_checkpoint_plan.py:315-326`
- 442-446 `err`, `is_empty_body`, `ATX_HEADING` -> `_checkpoint_lib.py:27-60`, `the-write-path.md:30-37`
- 446-450 `memory_directive` gated on `.gitmodules`, couples to the skill name -> `_checkpoint_lib.py:63-105`, `the-checkpoint-directive.md:130-141`
- 450-459 `commit_directive`, `-C`, quoting, no literal-pathspec -> `_checkpoint_lib.py:108-164`, `the-write-path.md:186-196`, `the-checkpoint-directive.md:29-38`
- 460-463 `arming_directive`, `closing_directive`, `ledger_path`, `sdd_directive`, `todo_boundary` -> `_checkpoint_lib.py:167-260`, `the-checkpoint-directive.md:39-68,155-159`
- 464-465 shim execs `checkpoint.py` -> `bin/handoff-checkpoint:1-8`; `CLAUDE_PLUGIN_ROOT` absent -> `changelog/2026-06-12-gitlore-aware-handoff.md:25` (weak, Orphans 1)
- 466-469 `handoff-approved` leaves `held`, owner kept, exits 2 -> `bin/handoff-approved:1-8,323-363`, `the-checkpoint-directive.md:75-126`
- 470-471 prints status fact, blank line, closing line, byte for byte -> `bin/handoff-approved:365-385`, `the-checkpoint-directive.md:58-68`
- 471-473 holds the lock, exits 2 naming it -> `bin/handoff-approved:326-337`, `sentinel-lock.md:73`

### Tooling and documents
- 474-476 fixtures generator and its reason -> `tests/gen_mod_fixtures.py:1-6,23`
- 477-478 vendored toolkit, `VERSION`, read-only -> `release-infrastructure.md:5-18`, `memory/ddaanet/shared-claude.md` (vendored subtree rule)
- 479-483 `release.just` owns bumps, depends on `prerelease`, `resume-release`, `check-version` -> `release-infrastructure.md:19-31`, `plugin-dev/release.just:47-80`, `justfile:16-19`
- 486-487 `version-guard.sh` -> `plugin-dev/version-guard.sh:1-8`, `.claude/settings.json:3-11`
- 488 `.envrc` -> see C1 (not homed correctly)
- 490-493 hub contents, nodes before claims -> `docs/design.md:3-17`
- 494-511 routing table -> root 3 (no other copy)
- 512-514 changelog index -> `docs/changelog.md:1-9` (format: C3)
- 514-516 never edited after the fact -> `docs/design.md:7-10`, `docs/changelog.md:3-6`
- 521-525 plans/ -> only in CLAUDE.md (docs.md)
- 526-529 inbox -> `inbox/README.md:1-25`

## Counts

Facts counted at clause level (a bullet carries several). Totals are approximate
to a few facts either way, because clause boundaries are a judgement.

| Bucket | Count |
| --- | --- |
| Homed (code, design node, code comment or changelog), one line each in the audit trail | 129 (133 audit lines, 4 of which only point at rules, root or C1) |
| Rules-bound | 37 lines: bash 8, mod 6, write-path 5, skills 6, tests 2, docs 4, legacy 6 (one fact can sit in two files; 2 of the 37 are notes, not carry items) |
| Root-bound | 17 lines across sections 1 to 6 (section 7 and 8: none) |
| Orphans | 0 strong, 3 borderline (not counted) |
| Conflicts | 7 (C1 and C2 need a correction in code-adjacent docs; C3 and C4 are drift; C5 to C7 are errors in the proposal) |
| Drop (history only) | 2: `CLAUDE.md:300` "for tests"; `CLAUDE.md:349` "(leftovers of a retired mechanism)" once `handoff-root-*` is retired from the sweep |

Orphans whose destination is a design node, per node (current `wc -l`):

| Node | Lines now | Orphans landing |
| --- | --- | --- |
| `docs/design/driving-the-transition.md` | 373 / 400 | 0 |
| `docs/design/queued-prompts.md` | 79 | 0 |
| `docs/design/sentinel-lock.md` | 128 | 0 |
| `docs/design/scoping.md` | 114 | 0 |
| `docs/design/the-write-path.md` | 262 | 0 strong, 1 optional clause (Orphans 1) |
| `docs/design/the-checkpoint-directive.md` | 159 | 0 |
| `docs/design/the-skills.md` | 89 | 0 |
| `docs/design/release-infrastructure.md` | 34 | 0 added, 1 sentence corrected (C1) |
| `docs/design.md` | 381 | 0 added, FR3 wording to correct (C2) |

Conclusion for the sequencing in the proposal: step 1's design-node commit is
two small edits to existing sentences (C1, C2) plus, optionally, one clause in
`the-write-path.md`. `driving-the-transition.md` needs no new line, so no split
of it is forced by this range.
