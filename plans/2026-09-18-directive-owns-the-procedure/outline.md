# Outline — the directive owns the procedure

## Problem

`skills/handoff/SKILL.md` steps 2–3 and `skills/precompact/SKILL.md` steps 4–5
state, in prose, a cross product the agent must locate itself in: commit or
not × held or armed × driven or prepared. `checkpoint.py` already holds every
input to that product and already prints the memory half of it. Three defects
follow from the split:

- **The closing line is stale.** "Ready to commit, then /clear" predates the
  agent making the commit itself, in-turn, after the checkpoint. By the time
  it is printed it is never true.
- **Commit-before-arm is prose.** A driven `with-commit` boundary with clean
  memory is written `armed`. If the commit fails and the agent stops to report
  it, `Stop` fires and the transition runs over uncommitted work.
- **The tense clause is a drifted copy.** "Under `with-commit`, memory bodies
  state present-tense truth" conditions a rule `gitlore:memory-writing` §2
  states unconditionally, and that
  `docs/changelog/2026-07-25-commit-awareness.md` already recorded as needing
  no mode. The memory directive interpolates gitlore's approval clause, which
  opens by invoking that skill — so how memory is written is owned downstream
  and the skill bodies need say nothing about it.

## Approach

Both skills reduce to three steps:

1. Durable learnings surfaced? Write them to memory.
2. Decide the payload; run `handoff-checkpoint`. No other tool call.
3. Follow what it prints, in order.

Everything after the call — memory approval, the commit, the release, the
closing line — is printed by the checkpoint for the one cell the call is in.

### Composition (boundary skills only; `autoname` and `restart` still print nothing)

Inputs: `M` a memory directive was emitted · `C` mode is `with-commit` ·
`K` the sentinel types anything (`transition.cmds`) · `T` the transition is
typed (`transition.typed`).

Output order, each part present only under its condition:

1. memory directive — `M` (unchanged text, see wording note)
2. todo boundary / SDD nudge — as today
3. **commit act** — `C`
4. arming instruction — held
5. **closing line** — not held

**Hold rule:** `held` iff `(K and M) or (T and C)`.

The first disjunct is today's rule. The second is scoped to *typed*
transitions rather than to `K`: what the hold protects under `C` is work from
a transition that would run over a failed commit, and an untyped handoff's
only keystroke is `/rename`, whose misfire costs nothing. Holding it would add
a `handoff-approved` call to every "handoff and commit" — the most common
invocation — and a forgotten call there silently loses the title.
*Alternative, rejected by default:* one predicate, `K and (M or C)`. Simpler
to state; pays the extra call and the forget-risk above for no protected
state.

**Closing line** has one producer per path. Not held: the checkpoint prints
it as the last act. Held: `handoff-approved` prints it, derived from
`DRIVE_KIND` — it runs a turn or more after the checkpoint's output, and
already prints a line of this shape. Content: prepared → "Ready to /clear" /
"Ready to /compact"; driven → the transition is armed and the turn ends.

**Wording note.** The `with-commit` memory directive ends "Nothing further is
needed from you", which a commit act printed two parts later contradicts. It
keeps the clause saying this turn's commit carries the memory and loses that
sentence. The load-bearing negative — `with-commit` output never mentions the
trigger file — is untouched. All new agent-facing text is drafted under
`craft:directive-writing`: acts, no mechanism, no identifier the reader
should not reach for. The commit act names no git verb — the ask may be
"amend" or "ci" — it says to make the commit the request asked for.

## Per-file changes

- `scripts/_checkpoint_lib.py` — `commit_directive()`, `closing_directive(skill, typed)`;
  drop the "Nothing further" sentence from `memory_directive`.
- `scripts/checkpoint.py` — `compose_directives` returns the ordered parts;
  `compose_sentinel` takes the hold decision as an input rather than deriving
  it from `memory`, and no longer appends the arming text itself;
  `print_output` joins a list. The read-back is unchanged.
- `bin/handoff-approved` — the final `printf` becomes the closing line, per
  kind.
- `tests/test_checkpoint.py` — commit act present/absent pair on both skills;
  part ordering; the hold matrix gains two rows over one fixture, each
  mutation-checked: typed + `C` + clean memory → `held` (drop the second
  disjunct ⟹ this row alone reds), untyped handoff + `C` + clean memory →
  `armed` (widen to `K and C` ⟹ this row alone reds); closing line printed iff
  not held, per boundary; `autoname`/`restart` still print nothing. The 24
  rows asserting empty stdout split: non-boundary rows stand, boundary rows
  assert stdout is exactly the closing line, through one helper.
- `tests/checkpoint.bats` — `handoff-approved`'s line per kind.
- `skills/handoff/SKILL.md`, `skills/precompact/SKILL.md` — the three-step
  shape; tense clauses and the commit-placement paragraphs removed; step 3's
  matrix removed; anti-patterns stay (prohibitions are not deferrable).
- `docs/design.md`, `docs/changelog/2026-09-18-*.md` + index line,
  `CLAUDE.md` — the hold rule, the composition order, the three-step skill
  descriptions, the tense half of 2026-09-17's entry superseded, and
  `gitlore.memoryApprovalClauseFile` named as the third gitlore coupling
  beside the two IPC filenames.

## Phases

1. **tdd** — commit act + part ordering (`_checkpoint_lib.py`, `checkpoint.py`).
2. **tdd** — hold rule, with both mutation checks.
3. **tdd** — closing line: checkpoint side, then `handoff-approved` (bats).
4. **inline** — both skill bodies. Depends on 1–3.
5. **inline** — design doc, changelog, `CLAUDE.md`. Prose dispatch runs opus.

## Boundaries

**IN:** the five items above; resolving the open decision in
`.claude/handoff-todo.md` (it dissolves — drop it at the next checkpoint).

**OUT:** the sentinel grammar and `handoff_drive_read` (no new state, no new
kind); `stop-drive.sh`, the walker, the loaders; `autoname`/`restart`
behaviour; the memory directive's approval flow and gitlore's clause; the two
dangling wikilinks in the ddaanet tier.

## Open question

The hold rule's scope, as argued above — `(K and M) or (T and C)` by default.
