# Documentation fixes from the two 2026-09-20 reviews

Markdown only. No code, no tests, no suites run, no git operation. Files
touched: `README.md`, `CLAUDE.md`, `docs/design.md`,
`docs/design/the-checkpoint-directive.md`,
`docs/design/rejected-alternatives.md`, `docs/changelog.md`,
`docs/changelog/2026-09-20-the-design-doc-becomes-a-hub.md` (new),
`skills/handoff/SKILL.md`, `skills/precompact/SKILL.md`.

Sources: R1 =
`plans/2026-09-18-directive-owns-the-procedure/reports/deliverable-review.md`;
R2 = `plans/reports/2026-09-20-design-doc-split-review.md`.

## Part A — R1 findings

### R1 Major 1 — `README.md`'s `autodrive` bullet states the old hold rule

Verified against `hold_decision` (`scripts/checkpoint.py:567-578`) and
`docs/design/the-checkpoint-directive.md` §"Held": `(K ∧ M) ∨ (T ∧ C)`, and
`bin/handoff-approved` is the only exit from `held`. `grep -c
"handoff-approved" README.md` was 0 before this pass.

Old:

> It starts out `held` when it would type into a pane still holding an
> unanswered memory question, and your approval releases it to `armed`;
> otherwise it starts `armed`.

New:

> It starts out `held` when typing now would cost you something: it would
> type into a pane still holding an unanswered memory question, or it would
> carry out a transition while a commit your request called for has not been
> made yet. `handoff-approved` is the one command that releases it to
> `armed`, and the agent runs it once you have approved the memory summary,
> or once the commit has landed; otherwise the file starts out `armed` and
> nothing is waited on.

User-facing voice kept: the second disjunct is stated as "a commit your
request called for", which is what `validate_commit_mode`'s `with-commit`
means to a user, and the release is attributed to the agent rather than to
the user, which is what the printed arming instruction actually does.

**Rest of `README.md`, checked for statements the plan invalidated:**

- *The flow description* (the long single-line paragraph, `README.md:128`)
  said "Anything to be typed waits for the turn to end: a `Stop` hook arms
  it…". True but incomplete now that the common driven-plus-commit
  invocation holds. Changed to "…waits for the turn to end — and, when the
  transition is held, for the `handoff-approved` call that releases it: a
  `Stop` hook arms it…". Nothing else in that paragraph is falsified; the
  clause "and `.claude/autodrive` when a rename is wanted" is narrow but
  pre-existing and not touched by this plan.
- *What the agent's reply ends on* — `README.md` never states it (`grep -n
  "Ready to\|ends on"` → no hits outside the requirements list). Nothing to
  fix.
- *Who asks for the memory approval* — the gitlore paragraph
  (`README.md:130-142`) says the agent drafts a message and asks the user to
  approve, and that a transition in the same turn waits for the answer. That
  is the first disjunct and is still exactly right. Not touched.

### R1 5 — `skills/precompact/SKILL.md`, "its output is the one line you end on"

Old: `checkpoint call, and its output is the one line you end on.`
New: `checkpoint call, and its output is one part, naming the line to end on.`

### R1 6 — the "closing line" term the body never introduces

Old anti-pattern: `Padding the closing line into a summary of the session.`
New: `Padding the line the checkpoint tells you to end on into a summary of
the session.` (Re-wrapped the following clause onto the same bullet.)

### R1 7 — `skills/handoff/SKILL.md` preamble

Old:

> `handoff-checkpoint` handles the writes, the staging and the transition
> file — this skill's job is deciding what goes in them.

New:

> `handoff-checkpoint` handles the writes, the staging and the transition
> file, and prints what is left to do after the call — this skill's job is
> deciding what goes in them, then following what it prints.

### R1 8 — "Both keys are required" has no antecedent

Confirmed in the file: the payload block above it lists seven keys, and the
paragraph's subject is `task` and `todo` (the tagged-union pair). Old: `Both
keys are required, each carrying content as a string or an object naming an
action.` New: `` `task` and `todo` are both required, each carrying content as
a string or an object naming an action. `` The following sentence was
re-wrapped so no line exceeds 80 columns.

### R1 10 — `the-checkpoint-directive.md:15` states one of three conditions

Old: `the memory directive, when the memory submodule is dirty;`
New: ``the memory directive, when the `gitlore-memory` submodule is registered
and dirty;`` — consistent with the node's own gitlore section and with
`memory_directive`'s gate.

### R1 11 — the 107-column line at `rejected-alternatives.md:108`

Rewrapped in place ("There it would hold a sentinel whose only line is
`/rename`, protecting no state — …"). No word changed. That file's remaining
over-80 lines (14, 71, 155) are pre-existing bare-link lines.

### R1 findings skipped, as instructed

9 (the `CLAUDE.md` test count — the parent session owns it), 15 and 16
(punctuation asymmetry, a comment width — both in `scripts/`/`bin/`), and
every code/test finding (2, 3, 4, 12, 13, 14).

## Part B — R2 findings

### Already applied before this pass (verified, not redone)

- **R2 2** — hub requirements name their node: `docs/design.md` carries
  `**[The write path](design/the-write-path.md).**`, `**The driven
  transition** — argued in [Driving the TUI]…`, `**Constraints** — argued in
  [The write path]… and [Scoping]…`, FR9's `See [The checkpoint
  directive]…`, and the FR12 paragraph's pointer. All five present.
- **R2 3** — both broken "below" references repointed
  (`the-skills.md:13` now "the driven-transition machinery (a `kind` in the
  same sentinel, the same walker)"; `the-write-path.md:123-124` now "with
  `drive_when_idle.py` and `_watcher_lib.py`, in [Driving the
  TUI](driving-the-tui.md)").
- **R2 4** — `the-skills.md:24` reads "nowhere else in the design".
- **R2 5** — `docs/design.md:17` reads `Last updated: 2026-09-20.`
- **R2 6** — the `CLAUDE.md` hub-section enumeration now includes
  "Relationship to `/ddaa:handoff`, Changelog and References".
- **R2 8** — `rejected-alternatives.md:45-46` bolds both names.

### R2 Major 1 — `CLAUDE.md`'s `docs/design/` bullet keyed on symbols

The bare eight-filename list was replaced with a routing list, node per
sub-bullet, symbols first and the node last, sentence "Read the node before
making a claim about, or changing, what it argues." kept verbatim. Eight
nodes in seven sub-bullets (decisions and rejected alternatives share one,
since neither has symbols); +17 lines on a file loaded every session, which
is why the two index nodes are folded and the ids are given as ranges.

Every symbol was grepped in the node named. Evidence, `grep -qF` in
`docs/design/`:

| row → node | verified present |
|---|---|
| `the-write-path.md` | `checkpoint.py`, `_checkpoint_lib.py`, `bash-post.sh`, `write-stage.sh`, `write-guard.sh`, `handoff-checkpoint`, `checkpoint-manifest`, `handoff-task.md`, `handoff-todo.md` — all ok |
| `the-skills.md` | `"skill"`, `clear`, `compact`, `continue`, `commit` — ok; `skills/*/SKILL.md` as a path is **not** in the node (see note) |
| `driving-the-tui.md` | `drive_when_idle.py`, `stop-drive.sh`, `load-handoff.sh`, `load-compact.sh`, `load-restart.sh`, `.claude/autodrive`, `wait_for_idle`, `line_landed`, `submit_*` — all ok |
| `the-checkpoint-directive.md` | `bin/handoff-approved`, `closing_directive`, `ledger_path`, `handoff_drive_arm`, `held`, `with-commit`, `gitlore-memory-message`, `gitlore-commit-memory` — all ok |
| `scoping.md` | `worktree_root.py`, `handoff_root_read`, `handoff_match_target`, `inject-checkpoint-root.sh`, `session-pointer.sh`, `report-watcher-failure.sh`, `HANDOFF_ROOT` — all ok |
| `release-infrastructure.md` | `plugin-dev/`, `release.just`, `version-guard.sh`, `MARKETPLACE_DIR` — all ok |

FR/NFR ids are grouped by the **hub's** own Requirements section rather than
by a grep of the node — across all eight nodes there is exactly one FR/NFR
citation (`NFR1` in `the-checkpoint-directive.md`), so the hub's group links
are the evidence: FR1–FR9 under the write path with FR9 and FR12 overridden
to the checkpoint directive, FR-G/FR-H under driving the TUI, NFR1–NFR3
under "Constraints". The rows follow that: FR1–FR8 + NFR1–NFR3 → write path,
FR-G/FR-H → driving the TUI, FR9/FR12 → the checkpoint directive. NFR1–NFR3
is carried on the write-path row only, although the hub also links
Constraints to `scoping.md`; splitting the range across two rows cost more
lines than the routing it bought.

**Symbols from R2's suggested rows that were dropped, with the grep that
dropped them** (`grep -l` across `docs/design/*.md` and `docs/design.md`):
`is_empty_body`, `hold_decision`, `compose_directives`, `memory_directive`,
`commit_directive`, `arming_directive`, `handoff_spawn_detached`,
`session-end.sh`, `just release` — **no match in any node or in the hub**.
`handoff_drive_read` matches only `scoping.md:17`, and there only as the
name of a caller-scope-globals idiom, not as the sentinel parser — so it was
dropped rather than routed to `driving-the-tui.md`, which argues the
sentinel's shape and states without naming the function. `_watcher_lib.py`
matches only `the-write-path.md` (the Python-port paragraph), so the
driving-the-TUI row names the predicates it does argue (`line_landed`,
`wait_for_idle`, `submit_*`) instead. This is a real gap in the nodes
rather than in the routing: six of the checkpoint directive's own function
names are argued by behaviour and never spelled. Worth a later pass; not
fixed here, since it would mean authoring prose into the nodes.

The one row entry not literally present is `skills/*/SKILL.md` on the
`the-skills.md` row. The node argues those files under their skill names
(`/handoff:precompact`, `/handoff:autoname`, `/handoff:restart`, the
boundary/skill table), and the path is the token an agent about to edit one
is actually holding. Kept deliberately.

### R2 Minor 7 — the hub's routing table became a bulleted list

`docs/design.md` §Architecture. Same eight links, same order, same question
text byte-for-byte; `| node | … |` table replaced by `- [Node](path) —
Question?` wrapped at 80. The seven rows of 103–195 columns are gone; the
hub grew from 326 to 336 lines.

### R2 Minor 9 — deliberately not done

Subheadings in `driving-the-tui.md`. Left as instructed and recorded as
deferred in the changelog entry, with the reason (inserting headings breaks
the line-multiset conservation the pure-move check rests on).

## Part C — the changelog entry

New file `docs/changelog/2026-09-20-the-design-doc-becomes-a-hub.md` (143
lines, all ≤80 columns), in the shape of the recent entries: defect first in
running prose, then `## A pure move, checked twice`, `## What the review then
changed`, `## Alternatives weighed`, `## Deferred`.

Numbers quoted, each verified in this session:

- `git show HEAD:docs/design.md | wc -l` → 1248; 400-line soft cap from
  `CLAUDE.md`'s `craft:plan-contracts` citation; 2036 lines named in
  `CLAUDE.md`'s `docs/changelog/` bullet as what the earlier append-only rule
  produced.
- "the 2026-09-18 run alone added 136 lines and removed 43" — R1's inventory
  table, `docs/design.md` row.
- `wc -l` after this pass: hub 336; nodes 130 / 78 / 200 / 129 / 61 / 34 /
  224 / 160. The entry quotes these, not the splitter's pre-fix figures.
- decisions + rejected = 384 lines against the 400 cap. The splitter's report
  says 381 and R2 says 377; both are stale against the current files, which
  is why the entry quotes the measured 384.
- 53 differing lines (9 heading levels, 41 changelog-link repoints, 3
  cross-references) and 84 links / 0 broken — both from the two independent
  checks, agreeing.
- 21 decision lead-ins, 30 rejected names — R2's bold-span diff.

Index line added at the top of `docs/changelog.md`, format `- [2026-09-20 —
The design doc becomes a hub](changelog/2026-09-20-the-design-doc-becomes-a-hub.md)
— <hook>`, no version suffix, one physical line like every other entry.

### Item 9 — the hub's own `## Changelog` section

Nothing owed. It is a two-line pointer at `changelog.md` with no per-entry
content, and `Last updated: 2026-09-20` is already correct (R2 5 was applied
before this pass).

## Verification

**`awk 'length>80'` over every file touched, against the pre-pass baseline.**
No new over-80 line. What remains, all pre-existing:

- `README.md:103, 132, 148, 187` — 82/82/316/108. `:148` and `:187` are
  unwrapped paragraphs in a file that wraps elsewhere; `:187` is the
  `handoff-task.md` bullet. My `autodrive` edit is wrapped at 80.
- `README.md:128` — the flow paragraph, one physical line of 1795 columns
  (was 1708). Pre-existing shape; my clause lengthened it rather than
  introducing it. Rewrapping it is a whole-paragraph reflow this pass had no
  mandate for.
- `CLAUDE.md` — 30 lines, every one of them at the same offset as before (the
  new bullet shifted line numbers by +17: old `:802` is now `:819`).
- `docs/design.md:8, 153, 326, 330` — the last two are old `:319, :323`,
  shifted by the routing list. The seven table rows of 103–195 columns are
  gone.
- `docs/design/rejected-alternatives.md:14, 71, 155` — bare link lines;
  `:155` is old `:154`. The 107-column line R1 flagged is fixed.
- `skills/handoff/SKILL.md:3` (frontmatter `description`) and `:83` (the
  `todo` line of the JSON payload block) — neither can wrap.
  `skills/precompact/SKILL.md:3` and `:84` are the same two.
- `docs/changelog.md` — every index line is one physical line by convention,
  including the new one.
- The new changelog entry — zero lines over 80.

**Link check.** `/tmp/claude/dsr/links2.py` (the review's `links.py` with the
file list widened to `docs/design.md`, `docs/design/*.md`, `docs/changelog.md`
and the new entry; resolves every relative target and every `#anchor` against
GitHub-style heading slugs):

```
checked 153 relative links, 0 broken
```

**Word counts, skill bodies (cap ~2000).**

```
before:  1791 skills/handoff/SKILL.md   1128 skills/precompact/SKILL.md
after:   1808 skills/handoff/SKILL.md   1136 skills/precompact/SKILL.md
```

## Things in the two reports that did not hold up

1. **R2's suggested routing rows are largely unverifiable as written.** The
   report states "(all verified present in the named node)", and nine of its
   proposed symbols appear in no node at all (`is_empty_body`,
   `hold_decision`, `compose_directives`, `memory_directive`,
   `commit_directive`, `arming_directive`, `handoff_spawn_detached`,
   `session-end.sh`, `just release`), while two more resolve to a different
   node than proposed (`handoff_drive_read` → `scoping.md` only,
   `_watcher_lib.py` → `the-write-path.md` only). Its FR/NFR groupings are
   right, but by the hub's links rather than by anything in the nodes — the
   report's own finding 2 establishes that the nodes carry exactly one FR/NFR
   citation between them, which contradicts the parenthetical.
2. **Two stale line counts for the combined decisions node.** The splitter
   says 381, R2 says 377; the files measure 383 before this pass and 384
   after the `rejected-alternatives.md` rewrap. The argument (at the cap on
   arrival) is unaffected.
3. **R1 finding 11's claim that `awk` flags only 14, 71 and 154 in
   `rejected-alternatives.md`** is correct as stated, and worth noting is that
   all three are bare link lines, so that file is now clean of wrappable
   overages.

Nothing else in either report failed verification. R1's Major 1, R1 5-8, 10,
11 and R2's Major 1 and Minor 7 were the only open items in scope, and all
are applied.
