# Deliverable Review: the directive owns the procedure

**Date:** 2026-09-20
**Plan:** `plans/2026-09-18-directive-owns-the-procedure`
**Design record:** `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md`
**Outline:** `plans/2026-09-18-directive-owns-the-procedure/outline.md`
**Commit range:** `411f2c7~1..6866a4e`
**Methodology:** `edify:deliverable-review` — two-layer review (delegated
per-file, then cross-cutting in the reviewing session).

Report only. Nothing was fixed; no commit, no staging, no branch change.
Deliverables were read as they stand in the working tree, which carries four
later, already-gated, out-of-plan changes (the refusal-text fix, the `main`
move, the `docs/design.md` → `docs/design/` split, two `memory/` wikilinks).
Those are excluded from the findings; the plan's design-doc prose now lives in
`docs/design/the-checkpoint-directive.md`, `docs/design/decisions.md` and
`docs/design/rejected-alternatives.md`.

## Inventory

| Type | File | +/− in range |
|------|------|--------------|
| Code | `scripts/checkpoint.py` | 95 / 43 |
| Code | `scripts/_checkpoint_lib.py` | 66 / 18 |
| Code (shell) | `bin/handoff-approved` | 24 / 3 |
| Code (shell) | `scripts/_lib.sh` | 3 / 2 |
| Test | `tests/test_checkpoint.py` | 325 / 10 |
| Test | `tests/checkpoint.bats` | 47 / 0 |
| Agentic prose | `skills/handoff/SKILL.md` | 15 / 33 |
| Agentic prose | `skills/precompact/SKILL.md` | 99 / 115 |
| Human docs | `CLAUDE.md` | 119 / 45 |
| Human docs | `docs/design.md` (now `docs/design/*`) | 136 / 43 |
| Human docs | `docs/changelog/2026-09-18-*.md` | 145 / 0 |
| Human docs | `docs/changelog/2026-09-17-*.md` (supersede note) | 13 / 0 |
| Human docs | `docs/changelog.md` (index line) | 1 / 0 |
| Out of scope | `inbox/README.md`, `memory` gitlink | 19 / 0, 1 / 1 |

~1100 lines added → Layer 1 ran with two opus reviewers (code+test,
prose+config), dispatched sequentially.

**Design conformance:** every item in the outline's "Per-file changes" list is
present and behaves as specified. The hold rule `(K ∧ M) ∨ (T ∧ C)` is
implemented exactly, computed once, and feeds both the sentinel state and the
choice of ending. The part order, the refusal-prints-alone rule, the one
producer per closing-line path, and the removal of the tense clause and the
stale closing lines all landed. One deliverable was never in scope and is
missing: `README.md`.

## Critical Findings

None.

## Major Findings

**1. `README.md:193-196` — the user-facing hold rule is now false for the most
common driven invocation, and `handoff-approved` is undocumented.**

The `autodrive` bullet says: "It starts out `held` when it would type into a
pane still holding an unanswered memory question, and your approval releases it
to `armed`; otherwise it starts `armed`." That is the old rule, the first
disjunct alone. The plan added `(T ∧ C)`: under a typed transition with
`with-commit` and *clean* memory the sentinel is written `held` with no memory
question anywhere, and the release is the agent's own `handoff-approved` call
after the commit — not a user approval.

Failure scenario: a user runs "handoff, clear, and commit" with clean memory —
by the design record's own account the most common invocation. The transition is
held. The agent's reply ends on an instruction to run `handoff-approved`. The
user consults `README.md`, which tells them a hold means an unanswered memory
question, and finds no mention of `handoff-approved` at all (`grep -c
"handoff-approved" README.md` → 0). Nothing in the user-facing documentation
explains the state they are looking at or the command that leaves it.

This is a scope gap rather than an execution error: the outline's documentation
list names `docs/design.md`, the changelog entry and `CLAUDE.md`, and omits
`README.md`, although `CLAUDE.md` records that "`README.md` has the user-facing
version of this".

Proposed fix: extend the `autodrive` bullet to state both hold reasons — an
unanswered memory question, or a typed transition this turn owes a commit — and
name `handoff-approved` as the one command that releases either, run by the
agent rather than the user. Verified by reading `README.md:185-205` and
`scripts/checkpoint.py:567-578`.

## Minor Findings

### Correctness / robustness

2. **`scripts/checkpoint.py:589-592`** (with `scripts/_lib.sh`'s
   `handoff_drive_read`) — when the sentinel is held and
   `CLAUDE_CODE_SESSION_ID` is unset, `compose_sentinel` writes the line
   `"held "`, the bash read-back rejects it as "line 1 state \`held\` must name
   the session holding it", the sentinel is unlinked and the run exits 2 — with
   `handoff-task.md` and the manifest already on disk and none of the printed
   procedure reaching the agent. The message blames the composer, naming nothing
   the agent can act on. `_build_restart_transition` (line 281-288) already
   treats the same unset variable as a named schema error; the held path does
   not. Not new in kind, but the plan's `(T ∧ C)` disjunct newly routes the
   common driven-plus-commit invocation through it. Fix: validate
   `CLAUDE_CODE_SESSION_ID` before any write, the way the restart branch does,
   and name the variable. *Verified independently:* reproduced with `env -u
   CLAUDE_CODE_SESSION_ID HANDOFF_ROOT=<tmp> python3 scripts/checkpoint.py` over
   a `clear: true` / `with-commit` payload — rc 2, `.claude/` left holding
   `checkpoint-manifest` and `handoff-task.md`, no `autodrive`.

3. **`bin/handoff-approved:73-83`** — the `case "$DRIVE_KIND"` has no `*)` arm.
   A held sentinel of any other kind prints the status fact, prints no closing
   line, and exits 0. Unreachable through the checkpoint today (`restart` is the
   near-miss and can never hold: `validate_commit_mode` returns `""` for it and
   no memory directive is composed), but it is a silent fall-through in the one
   script that has no test oracle for an unexpected kind. Fix: add a `*)` arm
   that errors naming the kind. *Verified:* read the file; no default arm.

4. **`scripts/_checkpoint_lib.py:208`** — `closing_directive` derives the
   boundary by `else` (`"Clear" if skill == "handoff" else "Compaction"`, twice),
   so any skill string other than `"handoff"` silently yields the precompact
   wording. Unreachable via `compose_directives` (it returns `[]` for the other
   two skills), but `tests/checkpoint.bats` calls this function directly as a
   standalone oracle, where a typo in the helper would pass. Fix: raise on an
   unknown skill. *Verified:* read lines 196-211.

### Agentic prose

5. **`skills/precompact/SKILL.md:110-111`** — "The normal case … is one
   checkpoint call, and its output is the one line you end on." In that cell the
   output is not the line; it is ``Once everything above is done, end on one
   line: `Ready to /compact`.`` The line to end on is the quoted span inside it.
   An agent reading the sentence literally ends its reply on the whole
   instruction, anchor included. Fix: say the output is one part naming the line
   to end on. *Verified:* read `_checkpoint_lib.py:196-211` and the skill line.

6. **`skills/precompact/SKILL.md:130-131`** — the anti-pattern "Padding the
   closing line into a summary of the session" uses a term the body no longer
   introduces (`grep -n "closing" skills/precompact/SKILL.md` → line 131 only).
   The prohibition still reaches its target once the checkpoint's output is in
   front of the agent; the cost is a moment of ambiguity. Fix: "the line the
   checkpoint tells you to end on". *Verified by grep.*

7. **`skills/handoff/SKILL.md:13-14`** — the preamble still says
   "`handoff-checkpoint` handles the writes, the staging and the transition file
   — this skill's job is deciding what goes in them", enumerating the pre-plan
   three artifacts. The plan's point is that the checkpoint now also owns the
   procedure after the call. Fix: add "and what is left to do after the call".

8. **`skills/handoff/SKILL.md:87`** — "Both keys are required" follows a JSON
   block listing seven keys; "Both" has no antecedent. A misread costs one
   rejected payload and a retry. *Pre-existing:* `git diff 411f2c7~1..6866a4e --
   skills/handoff/SKILL.md | grep -c "Both keys are required"` → 0, so the plan
   did not introduce it. Recorded because the file is in scope. Fix: name the
   two keys.

### Documentation accuracy

9. **`CLAUDE.md:916`** — "`tests/test_checkpoint.py` (171 tests)". The collected
   count is 172. The plan's item 5.3 moved this number from 140 to 171, one
   short. *Verified independently:* `direnv exec . pytest tests/test_checkpoint.py
   --collect-only -q` → `172 tests collected`, and `git diff tests/test_checkpoint.py`
   shows the later out-of-plan change adds assertions but no new test function,
   so 172 was already the count at `6866a4e`.

10. **`docs/design/the-checkpoint-directive.md:15`** — "the memory directive,
    when the memory submodule is dirty" states one of three conditions;
    `memory_directive` also requires the `gitlore-memory` submodule to be
    registered in `.gitmodules` and materialized. The "gitlore seam" section at
    l.111-113 states the full condition, so the two halves of the node disagree.
    Fix: "when the `gitlore-memory` submodule is registered and dirty".
    *Verified:* read `_checkpoint_lib.py:97-111` and both passages.

11. **`docs/design/rejected-alternatives.md:108`** — 107 characters, against the
    repo's 80-column reflow convention for docs. It is the only over-long line
    this plan introduced (`awk 'length>80'` also flags 14, 71 and 154, all
    pre-existing bare-link lines). *Verified by `awk` and by locating the line in
    the plan's `docs/design.md` hunk.*

### Test coverage and specificity

12. **`tests/test_checkpoint.py:2276-2288`** — `test_handoff_parts_print_in_order`
    asserts `memory < todo < commit` and stops; its fixture (`handoff_payload`
    defaults to `clear: False`, plus dirty memory) is *held*, so no closing line
    exists to order. The four-part chain ending on the closing line is pinned on
    the precompact side only. On the handoff side `commit < closing` is never
    asserted — only `commit < arming`. Fix: add a handoff row over an armed
    `with-commit` fixture asserting `commit_index < closing_index` and
    `out.endswith(closing)`. *Verified:* read the fixture defaults at
    `test_checkpoint.py` `handoff_payload`, and rows 2276-2330 and 2429-2441.

13. **`tests/test_checkpoint.py:2237-2247`** — no row asserts the sentinel state
    for untyped precompact + `with-commit` + clean memory (the FR-G marker cell,
    `¬K ∧ ¬T ∧ C`). `test_with_commit_prints_the_commit_act[precompact_payload]`
    exercises that payload but asserts only the commit act. Covered in spirit by
    the types-nothing row and the untyped-handoff row. Fix: add
    `first_line == "armed"` to that parametrization. *Verified by reading the row.*

14. **`tests/test_checkpoint.py:2262-2267`** — `test_commit_act_names_no_git_verb`
    pins "no git verb" by three substring absences (`git commit`, `--amend`,
    `git add`). A reword naming a verb another way ("stage and commit", "`git
    ci`") would pass; the test reads stronger than it is. Fix: assert the exact
    expected sentence, which the design record quotes verbatim, or narrow the
    docstring to the three spellings actually at risk. *Verified by reading.*

15. **`scripts/_checkpoint_lib.py:196-211` / `bin/handoff-approved:75-81`** —
    the two `closing_directive` arms punctuate differently: untyped emits
    ``…one line: `Ready to /clear`.`` (period outside the backticks), typed emits
    ``…one line: `Clear armed — it runs when this turn ends.` `` (period inside).
    An agent relaying the quoted span literally ends one boundary on an
    unpunctuated fragment and the other on a sentence. Both producers agree, so
    nothing is broken. Fix (if wanted): settle one convention and mirror it in
    the three shell literals.

16. **`bin/handoff-approved:68`** — a comment line the plan added runs to 117
    characters inside a paragraph otherwise wrapped near 76. Cosmetic.

## Gap Analysis

| Outline requirement | Status | Reference |
|---|---|---|
| `commit_directive()`, no git verb | covered | `_checkpoint_lib.py:178-186`; `test_commit_act_names_no_git_verb` |
| `closing_directive(skill, typed)` | covered | `_checkpoint_lib.py:196-211` |
| "Nothing further is needed from you" dropped | covered | `_checkpoint_lib.py:146-153`; `test_with_commit_memory_text_drops_nothing_further` |
| `arming_directive()` reworded to "everything above" | covered | `_checkpoint_lib.py:189-193`; `test_arming_text_refers_to_everything_above` |
| `compose_directives` returns ordered parts | covered | `checkpoint.py:637-664` |
| `compose_sentinel` takes the hold decision as input | covered | `checkpoint.py:581-606`, `main` line 86-89 |
| `print_output` joins a list, one blank line per gap | covered | `checkpoint.py:667-676`; `test_parts_are_separated_by_one_blank_line` |
| Refusal printed alone | covered | `checkpoint.py:651-652`; held and armed rows both present |
| `bin/handoff-approved` status fact + closing line per kind | covered | `bin/handoff-approved:64-83`; three bats rows vs `closing_directive()` |
| Hold rule `(K ∧ M) ∨ (T ∧ C)`, one computation | covered | `hold_decision` at `checkpoint.py:567-578` |
| Both mutation-checked hold rows | covered | delegated reviewer re-ran both mutations; each reds only its own rows |
| Six empty-stdout rows split via one helper | covered | `assert_stdout_is_closing` at `test_checkpoint.py:2066-2076`; four `*_closing_only` rows |
| Three-step skill bodies, matrix and tense clause removed | covered | both `SKILL.md`; 1791 / 1128 words, under the 2000 cap |
| Changelog entry + index line + 2026-09-17 supersede note | covered | correctly scoped to three things, two standing claims true |
| `docs/design.md` prose (now the design nodes) | covered | `the-checkpoint-directive.md`, `decisions.md`, `rejected-alternatives.md` |
| `CLAUDE.md` hold rule, order, coupling edit, test count | covered except the count | finding 9 |
| `README.md` user-facing hold rule | **missing, and never in scope** | finding 1 |
| Dogfood run after phase 4 | not evidenced in the plan's reports | open question Q4 |

Excess: none. Nothing was produced beyond the outline's items. `MemoryPart` and
`Ending` are each justified by a value that has to travel with a flag, and both
are defined below their users per the entry-points-first convention.

## Summary

**Critical 0 · Major 1 · Minor 15.**

The implementation conforms to its design record closely. The hold rule, the
part order, the refusal rule and the one-producer-per-path rule are implemented
exactly as specified and are backed by tests that were confirmed load-bearing by
mutation rather than by observation. No vacuous test rows were found; no stale
directive text survives anywhere in the production artifacts (`Ready to commit`,
`Nothing further is needed`, `Once that is done` all return zero matches outside
`plans/` and `docs/changelog/`). The one Major finding is a documentation scope
gap rather than a defect in what was built: the user-facing `README.md` was never
in the plan's file list and still states the pre-plan hold rule.

## Open questions

No interactive layer was available, so these were not asked. Each carries the
default I would act on.

**Q1. Is `README.md` in scope for this plan's follow-up?** The outline's
Boundaries section lists neither `README.md` under IN nor under OUT, so its
omission looks unconsidered rather than decided. *Default: yes — amend the
`autodrive` bullet to state both hold reasons and to name `handoff-approved`.*

**Q2. Should the held path validate `CLAUDE_CODE_SESSION_ID`?** The restart
branch does; the held branch does not, and the plan widened the set of calls
that reach it. *Default: yes — a named schema error before any write, matching
`_build_restart_transition`.*

**Q3. Should `bin/handoff-approved` gain a `*)` error arm?** Unreachable today,
but the script is the one place with no oracle for an unexpected kind.
*Default: yes — cheap, and it keeps the file's "one rewrite, read at once"
character.*

**Q4. Was the outline's dogfood step run, and did it cover the two named cells
(typed + `with-commit` + clean memory, and prepared + `with-commit`)?** No
report under `plans/.../reports/` records it; commit `17d9acc` ("handoff frame
after the directive-owns-the-procedure run") is circumstantial evidence that a
live handoff ran. *Default: treat it as run for the prepared cell and
unconfirmed for the typed one — the typed cell is exactly the one the new `T ∧ C`
disjunct changed, and it is the cell Q1 is about.*

**Q5. Closing-line punctuation.** The untyped arm puts the period outside the
backticks, the typed arm inside. *Default: leave it — both producers agree, and
changing it touches three shell literals and a bats oracle for no functional
gain.*

**Q6. Should `skills/handoff/SKILL.md` gain precompact's "padding the closing
line into a summary" anti-pattern?** *Default: no — precompact's stated reason
is that the compaction is about to produce a summary, which does not transfer to
a clear.*

## Files reviewed, and by whom

| File | Reviewer |
|---|---|
| `scripts/checkpoint.py` | delegated (`reports/deliverable-review-code-test.md`) + this session |
| `scripts/_checkpoint_lib.py` | delegated (code-test report) + this session |
| `bin/handoff-approved` | delegated (code-test report) + this session |
| `tests/test_checkpoint.py` | delegated (code-test report) + this session (spot rows) |
| `tests/checkpoint.bats` | delegated (code-test report) + this session (plan diff) |
| `skills/handoff/SKILL.md` | delegated (`reports/deliverable-review-prose.md`) + this session |
| `skills/precompact/SKILL.md` | delegated (prose report) + this session |
| `CLAUDE.md` | delegated (prose report) + this session |
| `docs/changelog/2026-09-18-*.md` | delegated (prose report) + this session |
| `docs/changelog/2026-09-17-*.md` (supersede note) | delegated (prose report) + this session |
| `docs/changelog.md` | delegated (prose report) + this session |
| `docs/design/the-checkpoint-directive.md` | delegated (prose report) + this session |
| `docs/design/decisions.md` | delegated (prose report) |
| `docs/design/rejected-alternatives.md` | delegated (prose report) + this session |
| `README.md` | this session (cross-cutting; not in either delegation) |
| `skills/handoff/references/design.md` | this session (cross-cutting; clean) |
| `skills/autoname/SKILL.md`, `skills/restart/SKILL.md` | this session (cross-cutting; clean) |
| `hooks/hooks.json` | this session (hook count claim; clean) |

Every delegated finding above was re-checked in this session against the code
or by re-running the cited command before being relayed.

## Findings dropped at verification

None were dropped as wrong. Two were downgraded or re-labelled:

- The prose reviewer raised as an "unverified suspicion" that
  `docs/design/the-checkpoint-directive.md:96-98` ("`held` is the one state that
  outlives the turn that wrote it") is now true of the state's purpose rather
  than of every instance, since a `T ∧ C` hold is released inside the same turn.
  Confirmed as accurate but **not recorded as a finding**: the sentence's actual
  subject is why `held` carries an owner, which is unaffected, and the claim
  remains true of the case the owner exists for.
- `skills/handoff/SKILL.md:87` ("Both keys are required") was raised as a plain
  Minor; verified as **pre-existing** (`git diff` over the plan range shows no
  hunk there) and recorded as such, so it is not attributed to this plan.

Everything else — the session-id refusal, the missing `*)` arm, the 171/172
count, the over-long line, the three test gaps, the punctuation asymmetry, the
two skill wording items — was reproduced or re-read in this session before
entering the report.

## Tree state at end of review

```
$ git status --short | grep -v '^??'
M  .claude/handoff-todo.md
 M CLAUDE.md
 M README.md
 M docs/design.md
 m memory
 M scripts/_checkpoint_lib.py
 M scripts/_lib.sh
 M scripts/checkpoint.py
 M tests/test_checkpoint.py
 M tests/test_tui_conformance.py
```

Identical to the state at the start of the review: the four documented
out-of-plan changes and nothing else. The only files created are the three
reports under `plans/2026-09-18-directive-owns-the-procedure/reports/`
(`deliverable-review.md`, `deliverable-review-code-test.md`,
`deliverable-review-prose.md`), which are untracked.
