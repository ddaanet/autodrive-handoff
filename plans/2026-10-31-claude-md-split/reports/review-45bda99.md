# Review of 45bda99 — the CLAUDE.md split

Reviewed 2026-10-31 against `git show 45bda99:CLAUDE.md` and the seven
`.claude/rules/*.md` files as committed (the working tree equals HEAD for
every file the commit touched, so HEAD line numbers are the commit's). The
`CLAUDE.md` injected into this session's context is not the committed one:
it differs at least at `:67` (the long `handoff-approved` line), `:76`
(`path constants … owner liveness`), `:98` (`each file loaded when …`) and
`:176` (`with resume-release and check-version`), so a triage done against
an in-context copy may see text the commit does not carry; everything below
cites `git show 45bda99:CLAUDE.md`. Two
inputs: a `/code-review medium 45bda99` run (eight findings, triaged below)
and a claim-by-claim check of the root and the rules files against the
scripts, tests, `justfile`, `.envrc`, settings and design nodes. Severity is
mine, by the bar in the brief: high or medium only where a reader following
the text would do the wrong thing.

No high. Four medium. Everything else is low and declined.

## Medium

### M1. `.claude/rules/tests.md:24` — "Every git call goes through `run_git`"

Claim (`tests.md:24-28`):

> Every git call goes through `run_git` (`tests/probe-helpers.bash` in bats,
> `tests/conftest.py` in pytest) under `git_free_env`: …

Contradicted by `tests/conftest.py:68`, `:119`, `:124`, `:126` and
`:128-131`, the repository builders `make_repo` and `make_gitlore_repo`:

```python
subprocess.run(["git", "init", "-q"], cwd=repo, check=True, env=git_free_env())
```

They call git directly with `env=git_free_env()`, not through `run_git`
(`conftest.py:87`). The invariant that holds is the environment, not the
wrapper. Bar: a primary source contradicts the universal, and a reader
editing `conftest.py` (which `tests/**` loads this rule for) either files the
builders as violations or reroutes them. Found by the code review; confirmed.

Fix, in the file's style:

> - Every git call runs under `git_free_env`: git minus its repository-local
>   variables (`git rev-parse --local-env-vars`), since a gate run from
>   inside a git hook inherits `GIT_DIR`, `GIT_INDEX_FILE` and
>   `GIT_WORK_TREE` for the outer repository. `run_git`
>   (`tests/probe-helpers.bash` in bats, `tests/conftest.py` in pytest) is
>   the wrapper the rows use; the repository builders in `conftest.py` pass
>   the same env to `subprocess.run` directly.

### M2. `.claude/rules/tests.md:16-20` — the shared-helper homes read as a closed list and are not

Claim (`tests.md:16-19`):

> A helper two or more files call goes in the shared helper for its suite:
> `tests/hook-helpers.bash` (with `setup` and `teardown`) for the hook files,
> `tests/checkpoint-helpers.bash` (`setup`, `make_repo`) for the three bash
> files around the checkpoint, `tests/conftest.py` for pytest.

Contradicted by the sourcing graph: `tests/lock-helpers.bash` is loaded by
`tests/checkpoint-helpers.bash:22`, `tests/drive-take.bats:17` and
`tests/sentinel-lock.bats:4`, so it is a shared helper that crosses both
bats suites; `tests/probe-helpers.bash` is loaded by
`tests/checkpoint-helpers.bash:21` and is where `run_git` lives
(`probe-helpers.bash:15`). Neither is a home the sentence names. Bar: the
repo's own list rule (a list in prose reads as complete; a helper both bats
suites need has no home under this text, and `hook-helpers.bash` is
unreachable from the checkpoint files). Found by the code review; confirmed.

Fix, in the file's style:

> - A helper two or more files call goes in a shared helper:
>   `tests/hook-helpers.bash` (with `setup` and `teardown`) for the hook
>   files, `tests/checkpoint-helpers.bash` (`setup`, `make_repo`) for the
>   three bash files around the checkpoint (`load`ing
>   `tests/probe-helpers.bash`, where `run_git` lives),
>   `tests/lock-helpers.bash` (`load`ed) for what both bats suites share,
>   `tests/conftest.py` for pytest. A helper only one file calls stays in
>   that file. …

### M3. `.claude/rules/tests.md:34-35` — "Each actor's lock rows sit with that actor's tests"

Claim (`tests.md:34-35`):

> Each actor's lock rows sit with that actor's tests.

Contradicted by `tests/sentinel-lock.bats`, which holds the sweep's lock rows
(`:68`, `:88`, `run_report_failure`) and both loaders' (`:181`
`run_load_handoff`, `:197` and `:214` `run_load_compact`), none of them in
`report-drive-failure*.bats` or `load-*.bats`; and by
`docs/design/sentinel-lock.md:123-126`, which places the rows:

> They are in `tests/drive-take.bats`, `tests/sentinel-lock.bats`,
> `tests/bin-commands.bats` and `tests/test_checkpoint_readback.py`, and
> `tests/test_drive_lock.py` covers the lock itself.

Bar: a reader adding a loader or sweep lock row follows the sentence into
`load-handoff.bats` or `report-drive-failure.bats`, splitting that actor's
lock rows across two files against the design node. Mine.

Fix, in the file's style (replace the one sentence):

> The take's, the approval's and the checkpoint's lock rows sit with that
> actor's tests; the sweep's and both loaders' sit in
> `tests/sentinel-lock.bats`.

### M4. `.claude/rules/mod.md:23-24` — "`drive-take.sh` is the one reader"

Claim (`mod.md:23-24`):

> The mod reads neither the sentinel nor the prompt box: `drive-take.sh` is
> the one reader, and its stdout is the plan the mod runs.

Contradicted by `scripts/load-compact.sh:50`, `scripts/load-handoff.sh:63`,
`scripts/report-drive-failure.sh:212` and `bin/handoff-approved:59`, which all
read the sentinel through `handoff_drive_read`; the old root said only that
the mod never reads it (`45bda99~1:CLAUDE.md`, "It never reads the
sentinel"). `scripts/load-*.sh` are in this file's `paths:`, so the rule
loads exactly when an agent edits a loader whose body contradicts it. Bar: a
primary source contradicts the universal, loaded where it misleads. Found by
the code review; confirmed.

Fix, in the file's style:

> - The mod reads neither the sentinel nor the prompt box: its one reader is
>   `drive-take.sh`, whose stdout is the plan the mod runs.

## Declined (low)

- **Code review #1, `TODO.md:3` "re-probed against the real files" vs the
  report's "no re-probe".** The report (`split-implementation.md:176`) is a
  write-time statement by the implementer, who was told not to re-probe; the
  TODO line is the main session's. The failure scenario (block-list `paths:`
  never verified) is refuted by this review: all seven files loaded, see
  "Checks passed".
- **Code review #5, `bash.md:14-16` omits `disable=SC1091`.** Probe:
  `shellcheck -x` 0.10.0 exits 0 on a copy of `tests/hook-helpers.bash` with
  ` disable=SC1091` stripped (control with it: 0). The disable is redundant;
  the rule as written produces a passing file.
- **Code review #6, `tests.md:8` vs coverage prose in `tests.md`/`mod.md`.**
  `tests.md:36-37` and `:44-45` are change-together conventions, not
  inventory. `mod.md:40-42`'s four named rows are a closed record the
  implementer kept knowingly (judgement call 7). Low; the regrowth risk is
  real but nothing here prescribes the opposite of `CLAUDE.md:194-196`.
- **Code review #7, `docs.md:14-16` `(vX.Y.Z)` never used** (`grep -c
  '(v[0-9]' docs/changelog.md` → 0). The clause is conditional ("only when
  the entry maps onto one release"); the index has never triggered it rather
  than contradicting it. Open as inventory-components C3 for the changelog
  owner; carried on the brief's instruction.
- **Code review #8, the report.** First half: `split-implementation.md:27-29`
  is a list of what was in the tree ("the deletion of `TASK.md`,
  `docs/design/decisions.md`, …"), ambiguous but not a claim that
  `decisions.md` was deleted (`git show --stat 45bda99` lists no
  `decisions.md`). Second half refuted: the committed `CLAUDE.md:67` reads
  "`bin/handoff-approved` — leaves `held`", the short form, exactly as
  judgement call 2 says.
- **`legacy.md:31-35`, "`keep` moves a legacy todo; a content write, an
  `edit` result or `clear` removes it unless the root file has a body before
  and after".** `_checkpoint_plan.py:159-191`: an `edit` sourced from the
  legacy file (`use_legacy`) gets fate `moved`, not `removed`, when the
  result has a body; and `keep` over a root file with a body leaves the
  legacy file `ignored`, not moved. The legacy file is unlinked in both
  readings (`apply_plan`); only the report word differs, and the bridge is
  deleted in two weeks. No wrong action follows.
- **`mod.md` `paths:` omit three files it names:** `tests/test_mod_fixtures.py`,
  `tests/test_mod_live.py`, `tests/drive-take.bats`. Each carries its own
  docstring or header; `tests/mod/**` loads the regeneration rule where the
  fixtures are edited, and `test_mod_fixtures.py` fails in `precommit` with
  the regeneration command. The rule loads where the wrong action would
  happen.
- **`scripts/_drive_lock.py` matches no rules file**, so "change them
  together" (`tests.md:36-37`) does not load for an edit of the lock's
  default wait; `tests/test_drive_lock.py:260-266` fails in `precommit`
  naming both. The harness catches it.
- **`CLAUDE.md:65-66`, "since `${CLAUDE_PLUGIN_ROOT}` is unset in the agent's
  Bash".** No in-repo primary source states the env fact; the shim's own
  header (`bin/handoff-checkpoint:2-4`) gives the PATH reason (every
  installed plugin's `bin/` is on PATH, so the skill invokes it by bare
  name). Unsourced, not contradicted.
- **`TODO.md:4`, "and not otherwise".** `probes.md` tested Read and a Bash
  `cat` of a matching file and a Read of a non-matching one; Write and Edit
  of a matching path were not probed, so the memory draft overstates its
  evidence. The `gitlore:memory-writing` step is where that gets narrowed.
- **`docs.md:10-11`, "a routing table"** names `docs/design.md`'s
  "Architecture — Where the argument lives" list (`design.md:206-235`). It
  is one; the name is the reader's to match.

## Checks passed

Rules files load on a matching Read, observed in this session (each file
appeared as a system-reminder once, on the first matching access): `bash.md`
on Read of `scripts/write-guard.sh`; `skills.md` on Read of
`skills/pending/SKILL.md`; `tests.md` on Read of `tests/lock_holder.py`;
`legacy.md` and `write-path.md` on a Bash `sed` of
`scripts/_checkpoint_lib.py` and `scripts/_checkpoint_plan.py`; `mod.md` on a
Bash `sed` of `hooks/handoff.ts`; `docs.md` on a Bash `cat` of
`plans/2026-10-31-claude-md-split/probes.md`; and, from a fresh Haiku
subagent whose one call was a Read of `bin/handoff-approved`, `bash.md`
(`bin/*`) and `write-path.md` (`bin/handoff-*`) seen, the other five not
seen. The block-list `paths:` form works; `**` matches zero directories
(`scripts/**/*.sh` → `scripts/write-guard.sh`). Bash-path detection was
uneven across compound commands in this session, so the Read evidence is the
one relied on.

`legacy.md` `paths:` cover all 16 files `grep -rli legacy scripts bin hooks
skills tests` returns, and nothing else under `scripts/`, `bin/`, `hooks/`,
`skills/` or `tests/` holds the word.

Root `CLAUDE.md`, verified against primary sources:

- Flow (`:5-17`): `classic.Stop` records cwd and session id, `turn.complete`
  drives inline through `drive-take.sh`, lines routed to `$.command.run` for
  a `/`-line else `$.prompt.submit` (`hooks/handoff.ts:15-28,76-80`);
  loaders consume only a `pending` sentinel of their own kind and start no
  continuation (`load-handoff.sh:70-74`, `load-compact.sh:68-71`);
  `checkpoint.py` runs no git (NFR1; `legacy_unstage_directive` prints).
- Payload (`:19-30`): skill set and `task`/`rename` forbidden under
  `precompact` (`_checkpoint_payload.py:51,121-123,245-248`); FR13 1000
  characters and no list item (`:306-342`); `clear` bool under `handoff`,
  `compact` bool-or-string under `precompact`, both required
  (`:171-197`); `continue` required, refused when not `typed` (`:201-216`);
  refused under `handoff` when neither file would have a body, handoff-only
  (`checkpoint.py:106-107,147-160`); `CONTINUATION` (`checkpoint.py:276`);
  `compact: false` → `Transition("compact", [], typed=False)`, a kind line
  alone, which `load-compact.sh:68` gates on.
- Sentinel (`:32-38`): states and owner (`_lib_drive.sh:77-93`); hold rule
  `(bool(transition.cmds) and memory) or (transition.typed and commit)`
  (`checkpoint.py:176`); `kind: null` plans (`drive-take.sh:26-95`);
  `handoff_drive_arm` is the only post-checkpoint state writer
  (`drive-take.sh:102`, `bin/handoff-approved:82`); `write-guard.sh` denies.
- Directive (`:40-50`): memory directive on a dirty `gitlore-memory`
  submodule, pointing at `gitlore:commit`, same text under both commit modes
  (`_checkpoint_lib.py:63-106`); sweep note names `--safe-mode`, `< 2.1.287`,
  managed settings (`report-drive-failure.sh:359`).
- Components (`:56-98`): `plugin.json` has no minimum-version field;
  `hooks.json` has six command hooks (1 + 2 + 3); `bin/handoff-checkpoint`
  execs `scripts/checkpoint.py`; `_lib.sh` defines `handoff_owner_live`,
  `handoff_lock_take`, `handoff_root_read`, `handoff_deny` and sources the
  three parts (`:78-207`); `gen_mod_fixtures.py` renders `fixtures.ts`;
  `.envrc` exports `VIRTUAL_ENV`, prepends its `bin`, and
  `source_up_if_exists` reaches `~/code/.envrc:4` (`MARKETPLACE_DIR`).
- Routing (`:102-121`) is byte-identical to `45bda99~1:CLAUDE.md:494-511`
  minus two spaces of indent; every node named exists under `docs/design/`;
  `ledger_path` is in `the-checkpoint-directive.md:155`.
- Gates (`:153-178`): `precommit: check-plugin check-code check-refs`
  (`justfile:31`); the two cached gates use `sentinel-guard` and
  `PLUGIN_DEV_GATE_FORCE` (`plugin-dev/gates.just:35,63`); `check-refs` has
  no guard (`plugin-dev/release.just:83-84`); `validate-plugin`'s two
  exemptions (`justfile:59-81`); `mod-smoke` is `pytest -m live … -rs`,
  deselected by `addopts` (`pyproject.toml:32-40`); `hook-test` and
  `py-test` are one-liners; `claude *` is in `excludedCommands`
  (`~/.claude/settings.json:139`); `version-guard.sh` wired in
  `.claude/settings.json`; `prerelease: precommit`.
- Anchors: `docs/design.md#requirements` (`:123`), `#non-goals` (`:315`),
  `docs/design/the-write-path.md#the-seam` (`:5`); the seam paragraph says
  no session id, transcript or file list (`:25-27`).
- The three "see CLAUDE.md conventions" comments (`scripts/_lib.sh:17`,
  `scripts/checkpoint.py:44`, `scripts/_checkpoint_plan.py:316`) still
  resolve to `## Conventions` (`:133-137`).

Rules files, verified against primary sources:

- `bash.md`: `source-path=SCRIPTDIR source=_lib.sh` on every `scripts/`
  source; `source=../scripts/_lib.sh` from `bin/handoff-approved:21` and the
  test helpers; the nested `SCRIPTDIR/../scripts source=<part>` form
  (`_lib.sh:202-206`); SC2034 on sourced-only variables; no `mapfile`
  (`_lib_drive.sh:112`); NUL-terminated reads in every hook;
  `handoff_root_read` answers into variables (`_lib.sh:168`);
  `tests/bats-best-practices.md` exists.
- `mod.md`: `${CLAUDE_PLUGIN_ROOT}` double-quoted on all six hooks; the
  `Stop` and timer refusals (`driving-the-transition.md:90-96`); the static
  `$` check (`plans/2026-10-08-plugin-becomes-a-mod/reports/step1-mod-live-smoke.md:67`);
  rig rejects unstubbed calls, no `prompt.read` stub (`tests/mod/rig.ts`);
  `drive-take.bats:4,42` pins stdout to `tests/mod/fixtures/`;
  `test_mod_fixtures.py:6,15,27` compares and ties prose lines to
  `CONTINUATION`; the four named mutants are rows of
  `step4a-green.md:9-15` and the four tests exist in `handoff.test.ts`;
  `test_mod_live.py:1-16,41,105,120-128` matches the mod-smoke description.
- `skills.md`: `grep -n 'gitlore:commit\|handoff-approved' skills/*/SKILL.md`
  empty; bodies 273/1591/190/961 words excluding frontmatter; `precompact`
  defers to `../handoff/SKILL.md` (`precompact/SKILL.md:66-68`); memory
  writes the only tool calls before the checkpoint (`handoff/SKILL.md:22-27`,
  `precompact/SKILL.md:19-23`); autoname's payload (`autoname/SKILL.md:25`)
  and "no tool call" (`:15`); pending's description.
- `tests.md`: `pythonpath = ["scripts", "tests"]`; 13/13
  `tests/test_checkpoint_*.py` carry `pytestmark`; `_session_id` not
  autouse (`conftest.py:16,57`); `git_free_env` via `--local-env-vars`
  (`conftest.py:72-110`, `probe-helpers.bash:9-20`);
  `HANDOFF_LOCK_BLOCKED_FILE` FIFO (`lock-helpers.bash:31-34`,
  `lock_holder.py:9-13`); 0.05 s waits in every contention row;
  `test_drive_lock.py:260-266` reads `hooks/hooks.json` timeouts;
  `validate-plugin.bats:14-17` stubs `claude`; `version-guard` tests live in
  `claude-plugin-dev/tests/version-guard-*-test.sh`.
- `write-path.md`: `lib.err` prints the field and `SystemExit(2)`
  (`_checkpoint_lib.py:27-30`); `_checkpoint_payload.py` reads no
  environment; `validate_root`/`require_session_id` in `checkpoint.py:120,139`;
  `bin/handoff-approved:95-105` case arms equal `closing_directive()`'s three
  outputs byte for byte; `bin-commands.bats:214-222` pins against
  `closing_directive` itself; `conftest.py:184-199` `run_checkpoint` is a
  subprocess, `:221-222` reads back through bash `handoff_drive_read`;
  `CONTINUATION` imported in three `test_checkpoint_*.py` files.
- `legacy.md`: `HANDOFF_LEGACY_REL_*` in `_lib.sh:32-34` and
  `_checkpoint_plan.py:325-326`; symlink refusals (`read_half:95-102`),
  loaders treat a symlink as absent (`_lib_frame.sh:42-53`);
  `handoff_frame_notes` the one producer (`_lib_frame.sh:97`); unlink after
  the root write (`apply_plan:212-231`); `git -C <root> rm --cached
  --ignore-unmatch -q -- <paths>` (`legacy_unstage_directive:160-164`); the
  2026-11-16 date (`decisions.md:63`, `TODO.md`).
- `docs.md`: `Superseded <date> (see […])` and `Corrected at review,
  <date>.` forms match existing uses; `inbox/README.md` says what the rule
  says.

Other files the commit touched: `docs/design.md:125-130` is true (the rules
files cite FR1, FR3, NFR1, NFR3; `skills/handoff/references/design.md` cites
FR3 and FR4; no `SKILL.md` cites a label, hence "the skills");
`docs/design/sentinel-lock.md:72`'s link resolves (`check-refs` passed in
the implementer's run and the anchor exists); `TODO.md`'s legacy item names
`.claude/rules/legacy.md`, which `grep -rni legacy scripts/ tests/` does
not reach; the line-cap item exempts only `tests/test_checkpoint_legacy.py`.

Nothing an agent needs before opening a file was found missing from the
root: the old file's always-on facts (`claude` needs
`dangerouslyDisableSandbox`, the two push targets, the breaking-change rule
on the two files' paths, open items only, `plugin-dev/` read-only, the
`mod-smoke` trigger, one session per root) are all in `CLAUDE.md`; every
prohibition in the deleted component prose (`never`/`must not` grep of
`45bda99~1:CLAUDE.md:94-530`) is mechanism already stated in its design node
or the code.
