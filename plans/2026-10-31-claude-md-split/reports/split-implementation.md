# CLAUDE.md split — implementation report

Step 3 of `proposal.md`, done 2026-10-31. Not committed. Every self-check
passes.

## Files changed

Mine:

- `CLAUDE.md`: rewritten as the new root, 959 → 199 lines. Sections: the
  plugin and its flow, components, routing, where documents go,
  `## Conventions`, gates, non-goals and the frame, what this file holds.
  The last line is still `@memory/ddaanet/shared-claude.md`.
- `.claude/rules/bash.md`, `mod.md`, `write-path.md`, `skills.md`,
  `tests.md`, `docs.md`, `legacy.md`: new, created with the Write tool, no
  denial. Each has the block-list `paths:` frontmatter from the brief.
- `TODO.md`: the three edits. The "Split `CLAUDE.md`" item is dropped. The
  line-cap item now exempts only `tests/test_checkpoint_legacy.py`. The
  legacy item says the pass also deletes `.claude/rules/legacy.md`, which the
  grep does not reach.
- `docs/design/sentinel-lock.md:72`: `(`CLAUDE.md`, "Non-goals")` is now the
  link `[non-goal](../design.md#non-goals)`.
- `docs/design.md:125`: "cited throughout `CLAUDE.md`, the skill bodies and
  …" is now "cited in `CLAUDE.md` and the `.claude/rules/` files, the skills
  and …", with the paragraph rewrapped.

In the tree but not mine: the deletion of `TASK.md`,
`docs/design/decisions.md`, `reports/review-d80b311.md`, `memory`, and the
two items at the top of `TODO.md`. The main session added those two items
between my read of `TODO.md` and my edit. I applied my edits by exact-string
replacement, so both items are intact.

## Line counts

| File | Lines |
| --- | --- |
| `CLAUDE.md` | 199 |
| `.claude/rules/bash.md` | 39 |
| `.claude/rules/docs.md` | 34 |
| `.claude/rules/legacy.md` | 52 (15 of them frontmatter) |
| `.claude/rules/mod.md` | 49 |
| `.claude/rules/skills.md` | 26 |
| `.claude/rules/tests.md` | 45 |
| `.claude/rules/write-path.md` | 32 |

`legacy.md`, `mod.md` and `tests.md` are over the rough 40. In `legacy.md`
the broadened `paths:` list takes 13 lines. `mod.md` carries nine
testing-inventory items, the mod-smoke mechanics among them. No line in the
root or the rules files is over 80 characters (counted in characters, since
`∧`/`∨` make a byte count overstate one line).

## Carry items not placed where the inventory named, and why

All 229 Rules-bound and Root-bound items were grepped in their target files
(self-check 2), and none is missing. Four were placed differently or
deliberately not placed:

- inventory-testing, `legacy.md`: "the legacy rows are mutation-checked
  (recorded)". This is merged into `tests.md`'s general rule ("A load-bearing
  row is mutation-checked … recorded in the changelog entry or plan report").
  `legacy.md` does not restate it.
- inventory-components root §6: `release.just`'s `resume-release` and
  `check-version`. Root §6 has only `just release`, its `MARKETPLACE_DIR`
  need and a pointer to `docs/design/release-infrastructure.md`. The
  inventory said a pointer is enough.
- inventory-testing, the six "report only" orphans (unrecorded mutation
  claims: the drive-take owner mutants, the sweep record call, the bats
  harness row, the hold variants, the `continue` effective-todo row, the
  `handoff-approved` bare-name row). None is placed. They went out with the
  test inventory, as the inventory says.
- The inventories' Drop lists (changelog citations, "a name from when it was
  keystrokes", "where 0.15 kept the two halves", "(for tests)" on
  `HANDOFF_POINTER_DIR`, "(leftovers of a retired mechanism)") are dropped.
  The stale "the take is two steps" (R2) is not carried.

## Conflict resolutions applied

- Root §6: three `precommit` dependencies, two exempt `validate-plugin`
  findings, the new-component-directory line naming the `justfile`, and
  `MARKETPLACE_DIR` from `~/code/.envrc` through `source_up_if_exists`.
  `mod-smoke` has no duration.
- Root §1: the compact boundary removes `TASK.md` only (R5); `continue: true`
  carries both refusals (R6); the directive's parts and order are a pointer to
  `the-checkpoint-directive.md` (R7); the checkpoint is the sentinel's one
  composer, and `handoff_drive_arm` rewrites the state line (FR3).
- Root §7 does not mention the two-step take.
- The `bin/handoff-checkpoint` index line keeps the `${CLAUDE_PLUGIN_ROOT}`
  reason. The `references/design.md` line reads "condensed design notes that
  ship with the skill".
- `write-path.md` says composer. `legacy.md` has broadened `paths:`, the
  2026-11-16 date, the grep plus a pointer to the `TODO.md` item, and ends by
  deleting itself. `tests.md` scopes the one-liner rule to `hook-test`,
  `py-test` and `mod-smoke`. `docs.md` carries the index-line format
  verbatim, `(vX.Y.Z)` clause included.

## Judgement calls the brief did not settle

1. **Root §1 is about 45 lines, not about 30.** The 15-fact floor, the
   components inventory's §1 items (the three states, the hold rule,
   `kind: null`, the loaders starting no continuation) and R5–R7 did not fit
   in 30 lines at 80 columns. To keep the root under 200, §1 absorbed the
   scope line's README pointer, and the scope sentence moved to §8.
2. **Component lines were shortened to fit one physical line where
   possible.** 19 lines fit on one, 12 wrap to two. One cost: the
   `bin/handoff-approved` line reads "leaves `held`" rather than "the one
   command that leaves `held`". Each line names its node, as the proposal
   asks, even though §3 maps most of the same files.
3. **The routing table is copied verbatim** (checked with `diff` against
   `HEAD:CLAUDE.md` lines 494–511) but de-indented two spaces, because it
   became a top-level list. Its lead-in now reads "What you are touching →
   what to read first, under `docs/design/`:", since the hub sentence moved to
   §4.
4. **`bash.md` adds the `source=../scripts/_lib.sh` form.** The old
   CLAUDE.md gave only `source=_lib.sh`, but `bin/handoff-approved:21` and the
   bats files use `source=../scripts/_lib.sh`, so a rule naming only the first
   form would be wrong for `bin/` and `tests/`.
5. **`bash.md` turns "call `handoff_frame` directly, never through `run`"
   into a rule:** a function that answers in caller-scope variables is called
   directly, with `handoff_frame` as the example.
6. **`tests.md` says "a hook with many rows splits across files named after
   it"** (as `report-drive-failure-*.bats` do). It does not claim every bats
   file sources `hook-helpers.bash`, because `drive-take.bats` does not (C5).
7. **`mod.md` names the four recorded mod mutants.** It keeps "driving inside
   `Stop`, continuing after a rejection, dropping the consume-once reset,
   skipping the fast path" as a closed list, recorded in
   `plans/2026-10-08-plugin-becomes-a-mod/reports/step4a-green.md`. It also
   states the rule for new rows.
8. **`docs/design.md:125` also changes "the skill bodies" to "the skills".**
   No `skills/*/SKILL.md` cites an FR label; only
   `skills/handoff/references/design.md` does (FR3, FR4). Without the change
   the reworded sentence would still be false. It is the same sentence the
   brief named.
9. **`sentinel-lock.md` uses a Markdown link rather than a backticked
   path.** The node already links to `../design.md` on line 3, and
   `check-refs` resolves the new link.
10. **`legacy.md` `paths:` has 13 entries covering the 16 files**
    `grep -rli legacy scripts bin hooks skills tests` returns, using
    `scripts/load-*.sh` and `tests/*legacy*`. It does not widen to
    `scripts/*.sh`.
11. **`docs.md` keeps the `(vX.Y.Z)` clause, as the brief says.**
    inventory-components C3 found that no line of `docs/changelog.md` has ever
    used it. That remains open for whoever owns the changelog convention.

## Self-checks

1. `wc -l`: see the table above. Root 199 (< 200); rules files 26–52.
2. Coverage: a script grepped one distinctive phrase per carry item in its
   target file (whitespace-normalised, so a wrapped phrase still matches).
   229 checks, 0 missing. By inventory: inventory-rest 27 in rules files, 42
   in the root and 2 inbound references; inventory-components 44 in rules
   files and 48 in the root; inventory-testing 46 in rules files and 20 in the
   root. A bullet that carries several facts got one check per fact.
   Inbound references were re-grepped over tracked files outside
   `docs/changelog/`, `plans/` and `plugin-dev/`. The three "see CLAUDE.md
   conventions" comments (`scripts/_lib.sh:17`, `scripts/checkpoint.py:44`,
   `scripts/_checkpoint_plan.py:316`) still resolve to `## Conventions`. No
   other reference names a section that moved.
3. `tail -n 1 CLAUDE.md` → `@memory/ddaanet/shared-claude.md`.
   `grep -n '^## Conventions' CLAUDE.md` → `133:## Conventions`.
4. `just precommit` (unsandboxed): exit 0. `check-plugin: cached (inputs
   unchanged)`, `check-code: cached (inputs unchanged)`, then `check-refs:
   resolves: 261 references in 33 files, 326 exempt files skipped; shipped
   stays shipped: 2 references from 6 shipped files`. The cached gates skip
   because none of their inputs changed. I did not force them. Run after the
   last gate-input edit. One later edit to `CLAUDE.md` §1 (naming which
   boundary takes `clear` and which `compact`) touches no gate input or
   Markdown link; `wc -l`, the width check and the coverage grep were re-run
   after it.
5. `claude plugin validate --strict --json .` (unsandboxed) exits 1, as
   `--strict` does on any warning. Its contents are `CLAUDE.md` and
   `hooks/hooks.json`, with nothing under `.claude/rules/`. The one warning
   is the exempt `CLAUDE.md at the plugin root is not loaded as project
   context …`, and there are no errors (no empty `.mcp.json` existed during
   the unsandboxed run). `just validate-plugin` exits 0.

Not done, by the brief: no commit, and no re-probe with the real rules files.
