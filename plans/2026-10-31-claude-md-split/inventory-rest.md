# Inventory of CLAUDE.md lines 1-93, 531-561 and 926-959

Scope: the title and "## Layout" intro (1-93), "## Conventions" (531-561),
"## Frame assembly" and "## Non-goals" (926-957), plus the closing
`@memory/ddaanet/shared-claude.md` import at line 959. Checked against the
proposal (`proposal.md`), `docs/design.md`, `docs/design/*.md`,
non-superseded `docs/changelog/` entries, `README.md`, `TODO.md` and the code.
Sibling conflicts C1-C7 (`inventory-components.md`) are not repeated; C2 is
cited where line 58-59 repeats it.

Finding in one line: the proposal's claim holds. Frame assembly and Non-goals
are fully held by `docs/design.md#non-goals` and the design nodes (one stale
clause excepted, see R2), and no design-node edit is needed for this range.

## Orphans

None strong. Every rationale or "never X because Y" in the range either has a
home or is assigned by the proposal to a rules file or root section. Three
facts have **no source other than CLAUDE.md**, so they are lost if the rules
file or root section the proposal assigns them to is not written. They are
listed here so the split commit checks them, not because the proposal omits
them.

O1. `CLAUDE.md:540-542` "Changing either's path or shape is a breaking change
and requires a version bump." Only home besides CLAUDE.md: three code comments
that point back at it, `scripts/_lib.sh:16-17`, `scripts/checkpoint.py:44` and
`scripts/_checkpoint_plan.py:316` ("see CLAUDE.md conventions"). No design node
or changelog entry states the rule (`grep -rni "breaking\|version bump"
docs/design docs/design.md` finds nothing). Destination: root section 5,
heading `Conventions` kept (the proposal already says so).

O2. `CLAUDE.md:538-539` "Keep the skill body lean (≤2000 words)". The number
appears in no design node and no test or recipe enforces it. `NFR3`
(`docs/design.md:195`) states only the direction ("Skill bodies get shorter,
not longer"). The only other mentions are
`docs/changelog/2026-09-17-memory-moves-inside-the-deciding-step.md:52` ("the
open question of the ≤2000-word guideline") and plans. Current sizes:
`skills/handoff/SKILL.md` 1723 words, `precompact` 1061. Destination: `skills.md`.

O3. `CLAUDE.md:552-556` the *reason* the nested `source-path` differs: "a bare
`SCRIPTDIR` resolves against the top-level script's directory, so from `bin/`
and `tests/` shellcheck would silently skip the part". `scripts/_lib.sh:198-206`
carries the two forms but no comment gives the reason (verified by reading
those lines; `grep -rn SCRIPTDIR docs` finds nothing). Destination: `bash.md`;
or a two-line comment above `_lib.sh:202`, which would be a code-adjacent home
that survives a rules file being dropped. The claim itself was not re-probed
here (it is a shellcheck behaviour, not repo code).

## Conflicts

R1. **FR3 "written only by the checkpoint" (repeat of C2).**
- `CLAUDE.md:58-59`: "The sentinel is written **only** by the checkpoint (FR3),
  and a direct agent Write/Edit to it is denied by `write-guard.sh`".
- `docs/design/driving-the-transition.md:59-60`: "Both writers rename a file
  into place: the checkpoint, and `handoff_drive_arm`", against line 44-45 of
  the same node, "`checkpoint.py` is the file's one writer". The node
  contradicts itself; `scripts/_lib_drive.sh` (`handoff_drive_arm`, called from
  `drive-take.sh:102` and `bin/handoff-approved`) rewrites line 1.
- Same fix as C2: say "sole composer; `handoff_drive_arm` is the one other
  rewriter, of line 1". Line 44-45 of the node needs the same word change.

R2. **Non-goals: "the take is two steps" is stale.**
- `CLAUDE.md:944-947`: "A later checkpoint replaces an earlier session's
  sentinel, `TASK.md`/`TODO.md` are last-writer-wins, the take is two steps, and
  a `.claude/` shared between roots is unsupported".
- `scripts/drive-take.sh:52` takes the sentinel's lock before reading and holds
  it to exit, and `docs/design/sentinel-lock.md:26-28` ("`drive-take.sh` from its
  read to its exit"); the take is one step against the checkpoint, the sweep and
  the loaders. `docs/design.md:313-343` (Non-goals) and
  `driving-the-transition.md:315-336` ("Sessions sharing a root") both list the
  other three limits and **omit** the two-step take.
- Origin: `docs/changelog/2026-10-14-cross-session-limits-documented.md:17`
  ("The take is not atomic") predates the lock (`2026-10-16-the-sentinel-takes-a-lock.md`)
  and carries no Superseded blockquote. Dropping the clause when Non-goals
  becomes a pointer corrects it; the changelog entry is write-time and stays.

R3. **The legacy bridge's retirement condition, in four places.**
- `CLAUDE.md:83-84`: "It is a bridge that goes once no sibling repository still
  has `.claude/handoff-*.md`".
- `TODO.md:7`: "Remove the legacy-path fallback, not before 2026-11-16: my human
  partner keeps the fallbacks one month past 2026-10-16, when no sibling
  repository had `.claude/handoff-*.md` any more."
- The same unqualified condition is in `docs/design/decisions.md:62` ("it goes
  once no sibling repository still has `.claude/handoff-*.md`") and
  `scripts/_lib.sh:29-30` ("It goes once no sibling repository still has a
  `.claude/handoff-*.md`"). The proposal's Question 6 covers CLAUDE.md only; the
  other two carry the same wrong-looking timing. `legacy.md` takes the date;
  `decisions.md:62-64` wants one clause ("not before 2026-11-16") in the same
  pass, since it is the design node. The `_lib.sh` comment can stay (condition
  necessary, date a grace period) or take the same clause.
- Also `TODO.md:7` names pieces of the bridge that lack the word `legacy`
  (the `Half` record and `move` member of `FilePlan.act`, the `plans` list and
  `Boundary` in `checkpoint.py`, `legacy_unstage_directive` and the `root` and
  `legacy_paths` parameters of `commit_directive`); `CLAUDE.md:84-86` says the
  grep "starts the one deletion pass" and names none. `legacy.md` should point
  at that `TODO.md` item for them (extends C5).

R4. **`.gitignore` still lists the retired gitlore file handshake.**
- `CLAUDE.md:29-30` and `33-34`: "the plugin writes no file for gitlore ... no
  shim for the file handshake it replaced".
- `.gitignore:8-13`: "The checkpoint's IPC to gitlore, written on the memory
  directive's instruction and consumed by gitlore's own hooks" over
  `.claude/gitlore-memory-message` and `.claude/gitlore-commit-memory`. No code,
  skill or test outside `plans/` and `docs/changelog/` names either file
  (`grep -rn` over the tree). The comment is false today. Delete the two
  entries and the comment in the split's neighbouring cleanup, or in a commit of
  its own; it is outside the CLAUDE.md edit.

R5 (minor, imprecise rather than incompatible). `CLAUDE.md:72` "only
`{"action": "clear"}` and the compact boundary remove one" against
`docs/design/the-write-path.md:145-146` "removed by `{"action": "clear"}` and,
for the task file, by the compact boundary". The compact boundary removes
`TASK.md` only; `TODO.md` survives it by design. Say "for the task file".

R6 (minor, omission). `CLAUDE.md:51-52` "`true` is legal only when the
transition is carried out" against `docs/design/the-skills.md:46-50` and
`scripts/checkpoint.py:155` (`has_body_after`): at the clear boundary
`continue: true` is also refused when neither file would have a body. A root
section 1 that keeps the sentence should add the second clause or drop the
rule to the design node.

R7 (minor, omission). `CLAUDE.md:29-32` "After the memory part it prints the
commit act" against `scripts/checkpoint.py:352-355` and
`docs/design/the-checkpoint-directive.md:23-24`: the todo boundary (`handoff`)
or SDD ledger nudge (`precompact`) sits between the memory part and the commit
act. Not an issue if section 1 drops the order and points at the node.

## Rules-bound

`legacy.md` (the five legacy-bridge facts, `CLAUDE.md:77-87`)
- `77-78` the two legacy paths `.claude/handoff-task.md`, `.claude/handoff-todo.md`
  (drop "where 0.15 kept the two halves"; `git grep` shows v0.15.0 is the last
  tag with legacy-only layout, and the sentence names a version while the next
  clause says the retirement names none).
- `78-82` loaders read the legacy file when the root file has no body; the
  checkpoint moves or removes it inside plan resolution; a root file with a body
  wins and its legacy file is reported ignored, never touched.
- `82-83` both ends decide by body, shadowing by the legacy file's existence.
- `84-86` `grep -rni legacy scripts/ tests/` starts the pass; one name per
  language (`HANDOFF_LEGACY_REL_*` in `_lib.sh:32-34` and
  `_checkpoint_plan.py:325-326`). Add R3's list and C5's wider grep.
- `83-84`, `86-87` retirement condition and "names no version" (corrected per R3,
  with the 2026-11-16 date).

`bash.md`
- `534-537` hooks anchor on `handoff_root_read`, never the raw `.cwd` nor
  `CLAUDE_PROJECT_DIR` (also `docs/design/scoping.md:5-10`).
- `549-550` `_lib.sh` the one sourced helper, callers source it alone, it sources
  three parts.
- `550-552` top-level `# shellcheck source-path=SCRIPTDIR source=_lib.sh` form.
- `552-556` nested form `SCRIPTDIR/../scripts` and why (O3).
- `556-560` `SC2034` for sourced-only vars; the three Python modules are
  imported, not sourced, so the convention does not apply.

`mod.md`
- `533` `${CLAUDE_PLUGIN_ROOT}` in `hooks.json` (the proposal adds "quoted";
  all six commands in `hooks/hooks.json:12-65` are).

`skills.md`
- `538-539` ≤2000 words, rationale to references or `docs/design.md` (O2).
- `543-545` both templates live in `SKILL.md`, loaders do not restate them (also
  `scripts/_lib_frame.sh:34-37`).
- `31-32` "so the skills state none of it" (the checkpoint's printed procedure;
  `grep gitlore:commit\|handoff-approved skills/*/SKILL.md` is empty, which
  `skills.md` can name as the check).

`write-path.md`
- `12` no git work (NFR1).
- `58-59` sole composer of the sentinel plus the write-guard (reworded per R1).

`docs.md`, `tests.md`: nothing in this range.

## Root-bound

Section 1 (flow and words) must keep, in ~30 lines:
- `1-4` scope line: conventions for editing the plugin's skill, hook, mod or
  script (this is section 8's "what this file is", not section 1).
- `8-22` the chain as one arrow sequence: skill → one `handoff-checkpoint` call,
  JSON on stdin → `checkpoint.py` writes `TASK.md`, `TODO.md`, `.claude/autodrive`
  → turn ends → `classic.Stop` records cwd and session id, `turn.complete` runs
  `drive-take.sh` and the lines through `$.command.run`/`$.prompt.submit` → the
  loader's `SessionStart(clear|compact)` consumes `pending` and injects the frame
  → `SessionStart(startup)` in a fresh session. Keep the file names and the
  hook event names; they are what a reader greps for.
- `13` `TASK.md` and `TODO.md` are plain tracked files, nothing stages them.
- `40-42` two boundaries, two skills (`handoff` for `/clear`, `precompact` for
  `/compact`), `autoname` a third `skill` value (`60-61`); the `skill` field
  keys the directive composition.
- `43-47` which skill carries `task` (only `handoff`) and `todo` (both); the
  continuation is a fixed prompt that points at the files.
- `47-53` the payload fields `clear`/`compact`/`continue`, required, and the
  words a reader cannot guess: `CONTINUATION` (`checkpoint.py:276`), `typed`
  (= driven; drop "a name from when it was keystrokes").
- `56-58` FR-G: `compact: false` writes a two-line marker that runs nothing.
- `58-59` one composer of the sentinel and the write-guard (R1 wording).
- `90-92` Claude Code >= 2.1.287; the mod does not load under `--safe-mode` or on
  older Claude Code, and the sweep note says so. Also in `README.md:108`.
- `22` `README.md` has the user-facing version.
- `32-34` needs a gitlore that ships `gitlore:commit` (one clause).
- `77-78` a one-line mention that `.claude/handoff-*.md` are legacy files read as
  a fallback, so the word means something before `legacy.md` loads.
- FR/NFR labels: `docs/design.md:125` says they are cited throughout CLAUDE.md.
  Section 1 uses FR3, FR-G, FR13, NFR1 and should point once at
  `docs/design.md#requirements`, or the design.md sentence is reworded as the
  proposal's step 3 says.
Can go from the intro because homed: `24-32` the directive's parts and order
(`the-checkpoint-directive.md:12-70`), `54-56` composer reads its sentinel back
(`driving-the-transition.md:43-44`), `67-75` the todo paragraph
(`decisions.md:9-27`, `the-write-path.md:15-36`), `78-88` beyond one line
(`the-write-path.md:50-75`, `decisions.md:48-67`), and every `See docs/changelog/...`
(`35-38`, `62-65`, `73-75`, `87-88`).

Section 5, `Conventions`
- `540-542` path or shape of `TASK.md`/`TODO.md` is a breaking change and needs a
  version bump (O1). Keep the heading `Conventions`: `_lib.sh:17`,
  `checkpoint.py:44`, `_checkpoint_plan.py:316` cite it.
- `546-548` `TODO.md` holds open items only (also `_lib.sh:20`,
  `the-write-path.md:19`).

Section 7, non-goals and frame assembly (~5)
- `926-940` one pointer for the frame: `docs/design/the-write-path.md#the-seam`
  (header plus inlined files, no transcript, no file list).
- `942-957` one pointer: `docs/design.md#non-goals`. Concurrent sessions in one
  root is the only one that changes what an agent does (one session per root, or
  a worktree each); keep that clause with the pointer.

Section 8
- `1-4` the scope line becomes "what this file holds".

Outside the numbered sections
- `959` `@memory/ddaanet/shared-claude.md`: the import that loads the shared
  conventions into every session. It must be the last line of the new root, or
  the split loses the ddaanet tier's rules. Not in any of the proposal's
  sections 1-8.

Inbound references forced by this range (proposal step 3 lists the first two
and the last; the `_checkpoint_plan.py` one is C6):
`docs/design/sentinel-lock.md:72` cites CLAUDE.md "Non-goals";
`docs/design.md:125` "cited throughout `CLAUDE.md`"; `scripts/_lib.sh:17`,
`scripts/checkpoint.py:44`, `scripts/_checkpoint_plan.py:316` cite "CLAUDE.md
conventions". `docs/design/scoping.md:51` mentions the *project* CLAUDE.md as
context that follows cwd, not this file's content, and needs nothing.

## Homed

Intro (1-93)
- `8-10` skill decides content; one `handoff-checkpoint` call, schema-validated JSON on stdin → `docs/design.md:134-138` (FR1, FR2); `skills/handoff/SKILL.md:25`
- `10-12` checkpoint writes `TASK.md`, `TODO.md`, `.claude/autodrive` → `scripts/checkpoint.py`; `the-write-path.md:6-25`, `:138-146`
- `12` FR5 write semantics → `docs/design.md:144-153` (FR5, FR6 retired text "written as given"); `the-write-path.md:144-146`
- `12` no git work (NFR1) → `docs/design.md:185-190`
- `13` both plain tracked files, nothing stages them → `the-write-path.md:6-9`; `decisions.md:9-21, 22-33`; `docs/design.md:154-156` (FR7 retired)
- `13-16` `classic.Stop` records cwd and session id, `turn.complete` drives → `hooks/handoff.ts:3-5, 15-21`; `driving-the-transition.md:82-100`
- `15-17` `drive-take.sh` takes only this session's sentinel, prints the plan → `scripts/drive-take.sh:2-9, 83-90`; `driving-the-transition.md:77-81`
- `17-18` lines run through `$.command.run` / `$.prompt.submit` → `hooks/handoff.ts:76-80`; `driving-the-transition.md:151-154`
- `18-21` loader consumes `pending` and injects the frame → `driving-the-transition.md:185-201`; `scripts/load-handoff.sh:79-90`
- `19-21` frame = header + each file with a body, legacy fallback → `scripts/_lib_frame.sh:9-19`; `the-write-path.md:27-36, 50-60`
- `21-22` `SessionStart(startup)` injects into a fresh session → `hooks/hooks.json:51-55`; `scripts/load-handoff.sh:2-3`
- `24-25` checkpoint prints the procedure for the one cell → `the-checkpoint-directive.md:7-13`; `docs/design.md:160-166` (FR9)
- `25-29` memory directive lists dirty files, sends to `gitlore:commit`, which owns format and approval → `the-checkpoint-directive.md:128-140`; `scripts/_checkpoint_lib.py:75`
- `28` same text under both commit modes → `the-checkpoint-directive.md:143-145`
- `29` plugin writes no file for gitlore → `the-checkpoint-directive.md:138-140` (but see R4: `.gitignore:8-13` disagrees)
- `29-32` commit act under `with-commit`, names the memory gitlink; then `handoff-approved` or the closing line → `the-checkpoint-directive.md:14-45, 145-150`; `scripts/checkpoint.py:343-376`
- `32` skills state none of it → `the-checkpoint-directive.md:12`; verified empty grep over `skills/*/SKILL.md`
- `32-34` needs a gitlore that ships `gitlore:commit`, no shim → `the-checkpoint-directive.md:150-152`; `README.md:62-64`
- `40-43` two boundaries, `skill` keys composition → `the-skills.md:5-17`; `checkpoint.py:343-376`
- `43-45` `task` only under `handoff`, FR13 bound → `docs/design.md:167-169`; `_checkpoint_payload.py:238-262, 342`
- `44-45` `precompact` forbids the key and removes `TASK.md`, because the summary carries the task → `decisions.md:69-75`; `the-write-path.md:14-16`; `_checkpoint_payload.py:246-251`
- `45-47` both carry `todo`; continuation fixed and carries nothing → `the-skills.md:46-62`; `decisions.md:72-75`
- `47-51` `clear`/`compact`/`continue` required, no default → `the-skills.md:74-76`; `_checkpoint_payload.py:160-215`
- `51-53` `true` legal only when carried out; fixed `CONTINUATION` → `the-skills.md:46-62`; `_checkpoint_payload.py:201-218`; `checkpoint.py:199, 276` (R6: second refusal omitted)
- `54-56` composer reads the sentinel back through `handoff_drive_read` → `driving-the-transition.md:43-44`; `checkpoint.py:300-317`
- `56-58` `compact: false` writes the two-line marker (FR-G) → `docs/design.md:174-177`; `driving-the-transition.md:14-20` (kind table, "compact (prepared)"); `_checkpoint_payload.py:190-193`
- `58-59` direct Write/Edit to the sentinel denied → `scripts/write-guard.sh:2, 19`; `driving-the-transition.md:44-45`; "written only by the checkpoint" is C2/R1
- `60-61` `autoname` a third `skill` value on the same call → `the-skills.md:79-86`; `_checkpoint_payload.py:43-54`
- `61-62` no restart skill or kind; `/restart` is a built-in → `the-skills.md:17-20`; `driving-the-transition.md:23-27`
- `67-69` `TODO.md` scratch list edited all session, wrap-up folds the remainder (FR4) → `docs/design.md:141-143`; `the-write-path.md:18-20`
- `69-70` file is the ledger, tracker a cache, plugin names none → `decisions.md:278-282`; changelog `2026-07-22-a-place-for-the-todo-list.md`
- `70-71` an existing `TODO.md` is shared → `decisions.md:26-27`; `the-write-path.md:22-24`
- `71-72` neither file guarded, gitignored or staged by a hook → `decisions.md:9-21`; `.gitignore` lists neither (verified); `git ls-files` tracks both
- `72` only `clear` and the compact boundary remove one → `the-write-path.md:144-146` (R5)
- `72-73` what counts as empty is the loader's → `docs/design.md:149-153` (FR6 retired); `the-write-path.md:30-36`
- `78-80` loaders read legacy when root has no body; checkpoint moves or removes → `the-write-path.md:50-75`; `decisions.md:48-58`
- `80-82` root file with a body wins, legacy reported ignored, never touched → `the-write-path.md:52-56`; `decisions.md:56-58`
- `82-83` decide by body, shadow by existence → `decisions.md:57-58`
- `84-86` the grep and one name per language → `decisions.md:63-64`; `_lib.sh:26-34`; `_checkpoint_plan.py:321-326`
- `86-87` retirement names no version → `decisions.md:62-63`
- `90-92` CC >= 2.1.287; `plugin.json` has no minimum field; README and sweep note → `driving-the-transition.md:262-272`; `scripts/report-drive-failure.sh:19, 359`; `README.md:79, 108`; `.claude-plugin/plugin.json` (verified no field)

Conventions (531-561)
- `533` `${CLAUDE_PLUGIN_ROOT}` in `hooks.json` → `hooks/hooks.json:12-65` (implemented; rationale "for portability" has no stated home, rules-bound to `mod.md`)
- `534-537` hooks anchor on `handoff_root_read` → `docs/design/scoping.md:5-10`; `scripts/_lib.sh:141-153`
- `538-539` lean skill body → `docs/design.md:195` (NFR3, direction only; the number is O2)
- `540-541` output paths, plain tracked files → `docs/design.md:141-143` (FR4); `the-write-path.md:6-9`
- `543-545` templates in `SKILL.md`, loaders do not restate → `scripts/_lib_frame.sh:34-37`; `skills/handoff/SKILL.md:105-170`
- `546-548` open items only → `scripts/_lib.sh:20`; `the-write-path.md:19`; `docs/changelog/2026-07-22-a-place-for-the-todo-list.md:12-15` (done half is git history); `docs/design.md:104-107`
- `549-550` `_lib.sh` the one sourced helper, three parts → `scripts/_lib.sh:2-4, 198-207`; verified no other sourced file in `scripts/` or `bin/`
- `550-552` top-level `source-path` form → `scripts/_lib.sh:4`; `tests/hook-helpers.bash:5`
- `556-557` `SC2034` for sourced-only vars → `scripts/_lib.sh:18, 23, 31` (the pattern, not a stated reason)

Frame assembly (926-940)
- `928` neither loader touches the transcript → `docs/design.md:111-117`; `decisions.md:91-93`; `scripts/load-handoff.sh:81-85`; `grep -i transcript` over both loaders and `_lib_frame.sh` matches only that comment
- `928-930` header plus inlined files, task first, either alone, no body left out → `scripts/_lib_frame.sh:9-19, 73`; `the-write-path.md:6-12, 27-36`
- `930-932` legacy fallback, shadowed legacy file named not read → `the-write-path.md:50-60`; `decisions.md:56-58`
- `932-933` assembled by `handoff_frame()` → `scripts/_lib_frame.sh:38`
- `933-934` `load-handoff.sh` on `startup|clear`, says when a half or the whole is missing → `hooks/hooks.json:51`; `scripts/load-handoff.sh:127-137`; `driving-the-transition.md:195-199`
- `934-935` `load-compact.sh` on `compact`, task file gone by construction → `hooks/hooks.json:61`; `scripts/load-compact.sh:79-89`; `driving-the-transition.md:200-204`
- `936-937` no session id, files-touched list or verbatim transcript → `the-write-path.md:26-28`; `docs/design.md:95, 111-117`
- `937-938` working set is the harness's `gitStatus` → `the-write-path.md:27-28`; `docs/design.md:95`; `load-handoff.sh:83-84`
- `938-939` verbatim exchanges manufactured false continuity → `decisions.md:91-93`; `docs/changelog/2026-07-17-task-frame-drops-transcript.md:8-` (no Superseded blockquote)

Non-goals (942-957)
- `944-945` a later checkpoint replaces an earlier session's sentinel; `TASK.md`/`TODO.md` last-writer-wins → `docs/design.md:332-337`; `driving-the-transition.md:323-328`
- `945` the take is two steps → stale, see R2
- `946-947` `.claude/` shared between roots unsupported; ownerless `pending` can cross → `docs/design.md:338-341`; `driving-the-transition.md:329-333`; `scoping.md:10-14`
- `947` one session per root or a worktree each → `docs/design.md:339-341`; `driving-the-transition.md:334-336`
- `948` pointer to `#sessions-sharing-a-root` → target exists, `driving-the-transition.md:315`
- `950-951` not summarising; extraction deterministic; `/compact`, Session Memory → `docs/design.md:315-320`; `decisions.md:5-7`
- `952-955` not validating the templates; JSON envelope plus length and no list → `docs/design.md:325-328`
- `956-957` no cross-session thread management; auto-memory → `docs/design.md:321-324`
- The proposal's claim "`docs/design.md#non-goals` already holds all four" is true: design.md has these four and two more (`/ddaa:handoff` replacement, claude.ai portability).

## Drop

- `35-38`, `62-65`, `73-75`, `87-88`, `939-940` `See docs/changelog/...` citations (5): the entries are reachable through `docs/changelog.md` and the design nodes cite them.
- `53` "a name from when it was keystrokes": history; `driving-the-transition.md:9-10` states it.
- `60-61` "rather than a template in its skill body": history of the earlier shape.
- `78` "where 0.15 kept the two halves": a version in a file that says the retirement names none.

## Counts

Facts counted at clause level; totals are approximate to a few either way.
Some facts sit in two buckets (homed and also rules-bound or root-bound).

| Bucket | Count |
| --- | --- |
| Homed (audit lines above, excluding the stale `945`) | 66 |
| Rules-bound | 16: legacy 5, bash 5, mod 1, skills 3, write-path 2, docs 0, tests 0 |
| Root-bound | 25: section 1 keeps 15 items, section 5 two, section 7 two, section 8 one, `959` import one, inbound-reference note four, FR-label pointer one (items overlap with the homed list) |
| Orphans | 0 strong; 3 with no other source (O1 version-bump rule, O2 2000-word number, O3 `source-path` reason), all already assigned by the proposal |
| Conflicts | 7: R1 (C2 repeat), R2 stale "take is two steps", R3 legacy condition and date in four places, R4 `.gitignore` handshake entries, R5 to R7 minor omissions |
| Drop | 8: 5 changelog citations, 3 history clauses |

Orphans whose destination is a design node, per node (current `wc -l`):

| Node | Lines now | Orphans landing |
| --- | --- | --- |
| `docs/design/driving-the-transition.md` | 373 / 400 | 0 added; 1 wording fix at lines 44-45 (R1, same sentence length) |
| `docs/design/decisions.md` | 330 | 0 added; 1 clause at line 62-64 (R3, about 6 words) |
| `docs/design/queued-prompts.md` | 79 | 0 |
| `docs/design/sentinel-lock.md` | 128 | 0; line 72 cites CLAUDE.md "Non-goals", repoint to `docs/design.md#non-goals` |
| `docs/design/scoping.md` | 114 | 0 |
| `docs/design/the-write-path.md` | 262 | 0 |
| `docs/design/the-checkpoint-directive.md` | 159 | 0 |
| `docs/design/the-skills.md` | 89 | 0 |
| `docs/design/release-infrastructure.md` | 34 | 0 |
| `docs/design.md` | 381 | 0; line 125 reworded (proposal step 3) |

Conclusion for sequencing step 1: nothing in this range lands in a design node
as a new line, so `driving-the-transition.md` is not pushed toward its 400-line
cap by it. The pre-split commit for this range is three small corrections:
`driving-the-transition.md:44-45` (R1, with C2), `decisions.md:62-64` (R3) and
`.gitignore:8-13` (R4); plus optionally a comment above `scripts/_lib.sh:202`
for O3.
