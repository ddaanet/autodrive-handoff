# Outline — the directive owns the procedure

## Problem

`skills/handoff/SKILL.md` steps 2–3 and `skills/precompact/SKILL.md` steps 4–5
state, in prose, a cross product the agent must locate itself in: commit or
not × held or armed × driven or prepared. `checkpoint.py` already holds every
input to that product and already prints the memory half of it. Three defects
follow from the split:

- **The prepared `with-commit` closing line is stale.** "Ready to commit,
  then /clear" (and its `/compact` twin) predates the agent making the commit
  itself, in-turn, after the checkpoint. In that cell it is never true by the
  time it is printed. The `without-commit` and driven lines are accurate, but
  they sit in the same prose matrix, so they move with it.
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

Memory moves ahead of the decision because nothing in it keys on the commit
answer once the tense clause is gone. That dependency is what placed it
inside the deciding step in `5b5db11`.

Everything after the call — memory approval, the commit, the
`handoff-approved` call, the closing line — is printed by the checkpoint for
the one cell the call is in.

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

The arming instruction's text is reworded to refer to everything printed
above it. Today's "Once that is done" points at the memory directive, which
no longer directly precedes it, and under `T and C` with clean memory may be
absent.

**Hold rule:** `held` iff `(K and M) or (T and C)`. Settled at proof,
2026-09-18.

The first disjunct is today's rule. The second is scoped to *typed*
transitions rather than to `K`: what the hold protects under `C` is work from
a transition that would run over a failed commit, and an untyped handoff's
only keystroke is `/rename`, whose misfire costs nothing. Holding it would add
a `handoff-approved` call to every "handoff and commit" — the most common
invocation — and a forgotten call there silently loses the title.
*Alternative, rejected:* one predicate, `K and (M or C)`. `T` implies `K` and
an untyped precompact types nothing, so the two differ in exactly one cell:
untyped handoff + `with-commit` + clean memory. There the uniform predicate
pays the extra call and the forget-risk above for no protected state — the
first disjunct's reason (a `/rename` typed into a pane showing the approval
question) does not transfer, since clean memory asks nothing. A forgotten
call is silent: a same-session `held` is exempt from the sweep and
`report-watcher-failure.sh` reports no `held`.

**Closing line** has one producer per path. Not held: the checkpoint prints
it as the last act. Held: `handoff-approved` prints it, derived from
`DRIVE_KIND` — it runs a turn or more after the checkpoint's output, and
already prints a line of this shape. Content: prepared → "Ready to /clear" /
"Ready to /compact"; driven → the transition is armed and the turn ends.
`DRIVE_KIND` alone decides it on the held path: a held `rename` is always an
untyped handoff (`autoname` never holds), a held `compact` or `clear` is
always driven. Both producers print the same kind of text, an instruction to
end the reply on the named line. `handoff-approved` keeps its status fact
(what is armed and that it runs at the end of the turn) ahead of that
instruction, so the held `rename` path still tells the agent the turn must
end for the title to land.

**Wording note.** The `with-commit` memory directive ends "Nothing further is
needed from you", which a commit act printed two parts later contradicts. It
keeps the clause saying this turn's commit carries the memory and loses that
sentence. The load-bearing negative — `with-commit` output never mentions the
trigger file — is untouched. All new agent-facing text is drafted under
`craft:directive-writing`: acts, no mechanism, no identifier the reader
should not reach for. The commit act names no git verb — the ask may be
"amend" or "ci" — it says to make the commit the request asked for.

**The refusal prints alone.** `memory_directive`'s clause-file refusal
(`gitlore.memoryApprovalClauseFile` unset or its file missing) counts as `M`
today. When the memory part is that refusal, the checkpoint prints it alone
and no commit act, arming instruction or closing line follows. Sentinel state
is unchanged, since the retry recomposes it.

## Per-file changes

- `scripts/_checkpoint_lib.py` — `commit_directive()`,
  `closing_directive(skill, typed)`; drop the "Nothing further" sentence from
  `memory_directive`; reword `arming_directive()` to refer to everything
  above it.
- `scripts/checkpoint.py` — `compose_directives` returns the ordered parts;
  `compose_sentinel` takes the hold decision as an input rather than deriving
  it from `memory`, and no longer appends the arming text itself;
  `print_output` joins a list; a refusal from `memory_directive` is printed
  alone. The read-back is unchanged.
- `bin/handoff-approved` — the final `printf` keeps its status fact and gains
  the closing-line instruction, per kind, in the same form the checkpoint
  prints.
- `tests/test_checkpoint.py` — commit act present/absent pair on both skills;
  part ordering; the hold matrix gains two rows over one fixture, each
  mutation-checked: typed + `C` + clean memory → `held` (drop the second
  disjunct ⟹ this row alone reds), untyped handoff + `C` + clean memory →
  `armed` (widen to `K and C` ⟹ this row alone reds); closing line printed iff
  not held, per boundary; the clause-file refusal printed alone under
  `with-commit` with a typed transition; `autoname`/`restart` still print
  nothing. The 24
  rows asserting empty stdout split: non-boundary rows stand, boundary rows
  assert stdout is exactly the closing line, through one helper.

  > **Corrected at review, 2026-09-18.** "The 24 rows asserting empty stdout"
  > is a miscount. `grep -n 'stdout == ""' tests/test_checkpoint.py` finds six:
  > two non-boundary (`test_restart_never_holds_even_with_dirty_memory`,
  > `test_autoname_against_dirty_memory_no_directive_at_all`) and four boundary
  > (`test_not_gitlore_managed_silent`, `test_gitlore_clean_memory_silent`,
  > `test_submodule_registered_not_materialized_silent`,
  > `test_flat_path_ledger_alone_precompact_silent`). 24 is what a wider
  > pattern returns once it also matches `"…" not in result.stdout`. The split
  > itself stands, over six rows.
- `tests/checkpoint.bats` — `handoff-approved`'s line per kind (new coverage:
  no existing row asserts that line's text).
- `skills/handoff/SKILL.md`, `skills/precompact/SKILL.md` — the three-step
  shape; tense clauses and the commit-placement paragraphs removed; step 3's
  matrix removed; anti-patterns stay (prohibitions are not deferrable).
- `docs/design.md`, `docs/changelog/2026-09-18-*.md` + index line,
  `CLAUDE.md` — the hold rule, the composition order, the three-step skill
  descriptions. The changelog entry explains the reversal of `5b5db11`'s
  placement. 2026-09-17's entry takes a `> **Superseded**` blockquote scoped
  to three things: the ordering reason ("after the commit answer because that
  answer sets the tense"), the tense clause restored to precompact, and the
  commit placement's home in skill prose ("It now sits in Step 2"). What
  stands, and the blockquote says so: memory before the checkpoint, and the
  commit after the checkpoint and before arming — same rule, new carrier.
  `CLAUDE.md` alone owes the coupling edit (`docs/design.md` already names
  `gitlore.memoryApprovalClauseFile`; "Couples only to the two IPC filenames"
  is the stale sentence), plus the `tests/test_checkpoint.py` count and the
  `compose_sentinel` paragraph stating the old `held` condition.

## Phases

1. **tdd** — commit act + part ordering (`_checkpoint_lib.py`, `checkpoint.py`).
2. **tdd** — hold rule, with both mutation checks.
3. **tdd** — closing line: checkpoint side, then `handoff-approved` (bats).
4. **dispatched, opus** — both skill bodies. Depends on 1–3.
5. **dispatched, opus** — design doc, changelog, `CLAUDE.md`.

The four silent boundary rows all run `without-commit`, so they stay green
through phases 1–2 and change in phase 3 alone, which owns the exact-stdout
helper.

**Dogfood.** The plugin runs from this tree via `--plugin-dir`, so the first
handoff in a fresh session after phase 4 is the live run. Cover typed +
`with-commit` + clean memory, and prepared + `with-commit`. Surprises patch
this plan.

## Boundaries

**IN:** the five items above.

**OUT:** the sentinel grammar and `handoff_drive_read` (no new state, no new
kind); `stop-drive.sh`, the walker, the loaders; `autoname`/`restart`
behaviour; the memory directive's approval flow and gitlore's clause; the two
dangling wikilinks in the ddaanet tier.
