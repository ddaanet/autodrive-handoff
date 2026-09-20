# Deliverable review — prose artifacts ("the directive owns the procedure")

Scope: AGENTIC-PROSE and HUMAN-DOCS artifacts of the
`411f2c7~1..6866a4e` plan, read as they stand in the working tree
(2026-09-20). Report only; nothing was edited outside this file.

Behaviour claims below are grounded in `scripts/checkpoint.py`
(`main`, `hold_decision`, `build_transition`, `compose_directives`,
`print_output`), `scripts/_checkpoint_lib.py` (`memory_directive`,
`commit_directive`, `arming_directive`, `closing_directive`,
`todo_boundary`, `sdd_directive`) and `bin/handoff-approved`.

## /Users/david/code/handoff/skills/handoff/SKILL.md

No Critical or Major findings.

1. **Minor** — `skills/handoff/SKILL.md:87`. "Both keys are required, each
   carrying content as a string or an object naming an action." follows a
   JSON block listing six keys (`skill`, `commit`, `rename`, `clear`,
   `continue`, `task`, `todo`), and "Both" has no antecedent in the
   rendered text. An agent could read it as "only two of these keys are
   required" and omit `clear` or `commit`, which `checkpoint.py` rejects
   (`_build_handoff_transition` → `err("clear", 'required when skill is
   "handoff"')`; `validate_commit_mode`). The failure is one wasted retry,
   not a wrong write. Proposed fix: name the two keys — "`task` and `todo`
   are both required…". Evidence: the paragraph is unchanged by this plan
   (`git diff 411f2c7~1..6866a4e -- skills/` shows no hunk there), so it
   predates the change and is reported only because the file is in scope.

2. **Minor** — `skills/handoff/SKILL.md:13-14`. "`handoff-checkpoint`
   handles the writes, the staging and the transition file — this skill's
   job is deciding what goes in them." The plan's whole point is that the
   checkpoint now also owns the *procedure* after the call, and the
   preamble still enumerates only the three artifacts. A reader skimming
   the preamble forms the pre-plan model and may be surprised by Step 3.
   Proposed fix: extend the list to "…and what is left to do after the
   call". Evidence: `compose_directives` (checkpoint.py:637) returns the
   commit act, the arming instruction and the closing line.

Checked and correct (see `## Clean` for the full list): the body reduces to
exactly the three steps the design record names (lines 18, 24, 101); no
residual cross-product prose; no tense clause; no "Ready to commit, then
/clear"; no "A driven transition whose directive needs an answer is written
but not armed…"; anti-patterns intact and renumbered (line 197 now says
Step 2); `.claude/gitlore-commit-memory` does not appear anywhere under
`skills/`; 1791 words, under the 2000-word cap.

## /Users/david/code/handoff/skills/precompact/SKILL.md

No Critical or Major findings.

1. **Minor (determinism)** — `skills/precompact/SKILL.md:110-111`. "The
   normal case — nothing durable, clean memory, no commit — is one
   checkpoint call, and its output is the one line you end on." In that
   cell the checkpoint's output is *not* the line to end on; it is
   `closing_directive("precompact", typed=False)`, which prints:

   ```
   Once everything above is done, end on one line: `Ready to /compact`.
   ```

   The line to end on is the quoted `Ready to /compact` inside it. An agent
   taking the sentence literally ends its reply on the whole instruction,
   including the "Once everything above is done" anchor — a visible,
   plausible misread, since the sentence is the last thing in Step 3 and
   contradicts the part order Step 3 just described. Proposed fix: say the
   output is one part, an instruction naming the line to end on — e.g.
   "…is one checkpoint call, whose single part names the line you end on."
   Evidence: `scripts/_checkpoint_lib.py:196-211`; `compose_directives`
   with `memory.text == ""`, no ledger, `commit_mode ==
   "without-commit"`, `ending.held == False` yields `[closing_directive]`.

2. **Minor** — `skills/precompact/SKILL.md:130-131`. The anti-pattern
   "Padding the closing line into a summary of the session." uses the term
   *closing line*, which the body no longer introduces anywhere (it lives
   only in the checkpoint's output now). A reader who has not yet run the
   checkpoint has no referent. The prohibition still reaches its target
   once the output is in front of the agent, so the cost is a moment of
   ambiguity, not a wrong act. Proposed fix: "Padding the line the
   checkpoint tells you to end on into a summary of the session."
   Evidence: `grep -n "closing" skills/precompact/SKILL.md` returns only
   line 131.

Checked and correct: three steps (lines 15, 21, 102); the tense clause and
the old steps 4–5 matrix are gone; the "before I compact" / FR-G paragraph
survives at 37-41; the seam deferral to `../handoff/SKILL.md` survives at
67-70; anti-patterns intact including the `rename`-field prohibition; no
`.claude/gitlore-commit-memory`; 1128 words.

## /Users/david/code/handoff/CLAUDE.md

1. **Minor** — `CLAUDE.md:916`. "`tests/test_checkpoint.py` (171 tests)".
   The collected count is 172. A reader treating the number as a
   completeness check (the file's own convention elsewhere: 49, 30, 11)
   would conclude a test went missing. Proposed fix: 172. Evidence:
   `direnv exec . pytest tests/test_checkpoint.py --collect-only -q` →
   `172 tests collected`. (Flagged by the dispatcher; recorded here for
   completeness, not re-derived beyond the one collect.)

No other numeric or factual claim in CLAUDE.md has rotted. Verified
against the code and the suite:

- "declares eleven hooks" (`CLAUDE.md:137`) — `hooks/hooks.json` has 11
  hook entries across 6 event keys.
- `tests/test_watcher_lib.py` (49), `tests/test_drive_when_idle.py` (30),
  `tests/test_tui_conformance.py` (11) — all exact (the last collected
  with `-m ""` to defeat the `live` deselect).
- The hold rule paragraph (`CLAUDE.md:587-598`) matches
  `hold_decision` (checkpoint.py:567-578) line for line, including the
  `(K ∧ M) ∨ (T ∧ C)` spelling and the scoping rationale for the second
  disjunct.
- The `compose_directives` paragraph (`CLAUDE.md:616-625`) matches the
  code's part order and the refusal-prints-alone branch
  (checkpoint.py:637-664).
- The `_checkpoint_lib.py` paragraph (`CLAUDE.md:692-706`) matches
  `commit_directive`, `arming_directive`, `closing_directive` and the
  `MemoryPart(text, refusal)` shape; "All three open 'Once everything
  above is done'" is true of all three functions.
- The `bin/handoff-approved` paragraph (`CLAUDE.md:536-544`) matches the
  script: status fact, blank line (`printf '…\n\n'`), then a literal
  per-kind `case` arm; "it must match `closing_directive()` byte for byte"
  is pinned by three bats rows (`tests/checkpoint.bats:221,232,243`).
- Both skill bullets (`CLAUDE.md:83-95`, `108-117`) describe the
  three-step shape the SKILL.md files actually have.
- The `tests/test_checkpoint.py` "printed procedure (2026-09-18)"
  paragraph names rows that exist: `test_typed_with_commit_clean_memory_
  is_held`, `test_untyped_handoff_with_commit_clean_memory_is_armed`,
  `test_handoff_parts_print_in_order`, `test_precompact_parts_print_in_
  order`, `test_clause_refusal_is_followed_by_no_commit_or_arming`,
  `test_refusal_prints_alone_when_not_held`,
  `test_with_commit_prints_the_commit_act`,
  `test_without_commit_prints_no_commit_act`, and the six `*_closing_only`
  rows that replaced the empty-stdout assertions.
- The coupling edit the outline said CLAUDE.md alone owed is present
  (`CLAUDE.md:700-702`, "and the `gitlore.memoryApprovalClauseFile`
  config key").

## /Users/david/code/handoff/docs/changelog/2026-09-18-the-directive-owns-the-procedure.md

No findings.

Every behavioural claim checks out against the code:

- l.30-35 three steps — matches both SKILL.md bodies.
- l.40 "`autoname` and `restart` still print nothing" —
  `compose_directives` returns `[]` for any skill outside
  `("handoff", "precompact")` (checkpoint.py:649-650).
- l.42-53 part order and conditions — matches
  `compose_directives` exactly, including "mutually exclusive" arming vs
  closing.
- l.44-47 commit act text and the no-git-verb reason — matches
  `commit_directive()` (`_checkpoint_lib.py:178-186`).
- l.48-50 the arming reword — matches `arming_directive()` ("Once
  everything above is done, run `handoff-approved` (Bash, no arguments).").
- l.60-64 the hold rule and "`hold_decision` computes it once, and the same
  value selects between the arming instruction and the closing line" —
  matches `main()` (checkpoint.py:85-89), where one `held` feeds both
  `compose_sentinel` and `Ending`.
- l.68-69 "An untyped handoff types only `/rename`" —
  `_build_handoff_transition` returns
  `Transition("rename", [f"/rename {title}"], typed=False)`.
- l.88-100 one producer per path, `handoff-approved`'s status fact then
  blank line then literal text picked from `DRIVE_KIND` — matches
  `bin/handoff-approved:64-83`.
- l.102-109 the "Once everything above is done" anchor and the untyped
  precompact + dirty memory case it exists for — that cell is
  `K=false, T=false` so `hold_decision` is false, the sentinel is armed,
  and the closing line follows the memory directive directly, as claimed.
- l.113-118 the refusal prints alone and "the sentinel state is
  unchanged" — `main()` passes `memory=bool(memory.text)` to
  `hold_decision`, so the refusal text still counts as `M`; only
  `compose_directives` short-circuits.
- l.119-124 "Nothing further is needed from you" is gone from
  `memory_directive`'s `with-commit` branch, and that branch still never
  names the trigger file (`_checkpoint_lib.py:146-153`).
- l.126-130 the dropped "written but not armed" sentence — absent from
  both SKILL.md bodies.

## /Users/david/code/handoff/docs/changelog/2026-09-17-memory-moves-inside-the-deciding-step.md

No findings.

The `> **Superseded 2026-09-18**` blockquote (lines 3-14) supersedes
exactly the three things the outline (`outline.md:150-155`) names — the
ordering reason, the tense clause restored to precompact, and the commit
placement's home in skill prose — and asserts exactly the two things the
outline says still stand (memory before the checkpoint; the commit after
the checkpoint and before arming, same rule, new carrier). Both standing
claims are true of the code: memory writes precede the call because
`memory_directive` keys on the dirty submodule at call time, and
`compose_directives` orders the commit act ahead of the arming
instruction. The blockquote is scoped (it does not demolish the entry's
own account of the zero-tool-calls contradiction, which still stands), and
the entry body below it is untouched, per the never-edit-after-the-fact
rule.

## /Users/david/code/handoff/docs/changelog.md

No findings.

The 2026-09-18 entry sits at the top of the list, above 2026-09-17, so
newest-first holds. Its form is
`- [2026-09-18 — The directive owns the procedure](changelog/2026-09-18-the-directive-owns-the-procedure.md) — <hook>`,
matching the required `- [<date> — Title](changelog/<file>.md)` shape and
its siblings. No `(vX.Y.Z)` suffix, which is correct: the change is
unreleased (HEAD is `6866a4e`, with no release commit or tag after it), and
CLAUDE.md scopes the version to entries that map onto one release. The
hook's content agrees with the record: the three defects, the three-step
reduction, `(K ∧ M) ∨ (T ∧ C)`, the rejected uniform `K ∧ (M ∨ C)` and its
single differing cell, the refusal printing alone, and the reversal of the
2026-09-17 placement. Link target resolves.

## /Users/david/code/handoff/docs/design/the-checkpoint-directive.md

No Critical or Major findings.

1. **Minor** — `docs/design/the-checkpoint-directive.md:15`. "the memory
   directive, when the memory submodule is dirty" states one of three
   conditions. `memory_directive` returns empty text unless the
   `gitlore-memory` submodule is *registered* in `.gitmodules`, *has a
   `.git`* (materialized), and its worktree is dirty
   (`_checkpoint_lib.py:97-111`). A reader debugging a boundary that
   printed no memory part in an unregistered repo would look for a bug.
   The "gitlore seam" section further down (l.111-113) states the full
   condition, so the cost is a moment's confusion, not a wrong model.
   Proposed fix: "when the `gitlore-memory` submodule is registered and
   dirty", matching l.111.

Checked and correct: the five-part list and its conditions match
`compose_directives`; the "Once everything above is done" paragraph
(l.27-35) and its untyped-precompact justification match the code; the
one-producer-per-path paragraph (l.37-47) matches `bin/handoff-approved`
and the three bats rows; the hold rule as stated at l.63-65 matches
`hold_decision`; the FR-G exemption at l.76-79 matches
`_build_precompact_transition`'s empty `cmds` for `compact: false`; the
refusal paragraph (l.49-54) matches the `memory.refusal` branch and the
fact that `compose_sentinel` still runs; the trailing bare changelog link
at l.58-59 follows this repo's node convention (`grep -n
'^\[.*\](\.\./changelog' docs/design/*.md` shows the same form in every
node).

## /Users/david/code/handoff/docs/design/decisions.md

No findings.

- l.43-54 "The agent supplies one fact; the code owns the branch" now says
  the commit answer changes "whether the checkpoint prints a commit act and
  holds a typed transition behind it" and explicitly *not* what memory
  says — the tense rule is attributed to `gitlore:memory-writing`
  unconditionally. That is what the record requires, and it matches the
  code: `commit_mode` feeds `commit_directive`, `hold_decision` and
  `memory_directive`'s branch, and none of them changes the tense of
  anything.
- l.169-176 "With nothing to approve, the wrap-up completes in a single
  turn" still holds under the new second disjunct: a `T ∧ C` hold with
  clean memory is released by `handoff-approved` inside the same turn,
  since nothing waits on a user answer. Checked explicitly because the new
  disjunct creates holds the old prose did not contemplate.
- l.190-214 "Deciding makes no tool call" correctly places memory as the
  step *before* the deciding step ("nothing in them waits on a decision …
  the commit answer does not set their tense") and the commit *after* the
  checkpoint as the printed commit act, before the arming instruction.
  Both match the shipped skill bodies and `compose_directives`' order.

## /Users/david/code/handoff/docs/design/rejected-alternatives.md

1. **Minor** — `docs/design/rejected-alternatives.md:108`. The line is 107
   characters, against the repo's 80-column hard-wrap convention for docs
   (CLAUDE.md, "a count is only honest once a hard-wrapping formatter has
   run … `rumdl` with MD013 reflow at 80 columns"). It is the only
   over-long line this plan introduced. Proposed fix: reflow the paragraph
   at 80 columns. Evidence:
   `awk 'length>80 {print FILENAME":"FNR": "length}'
   docs/design/rejected-alternatives.md` reports 108 at 107, and
   `git diff 411f2c7~1..6866a4e -- docs/design.md | grep -n 'protecting no'`
   shows the line entered with this plan's `docs/design.md` hunk (later
   moved verbatim by the design-doc split). The other over-long lines in
   the file (14, 71, 154) are bare-link lines that predate the plan.

Otherwise correct: the "One hold predicate" entry (l.104-115) states the
rejected predicate, the single differing cell (untyped handoff +
`with-commit` + clean memory), why the first disjunct's reason does not
transfer there, and why a forgotten `handoff-approved` call is silent —
all of which match `hold_decision`'s docstring, `report-watcher-failure.sh`'s
`held` exemption as described in CLAUDE.md, and the outline's rejected
alternative. The hub's index of rejected alternatives (`docs/design.md:266`)
lists "One hold predicate", so the two halves agree.

## Clean

Checked and found correct:

- Both SKILL.md bodies reduce to exactly three steps, with the headings
  the design record names.
- No residual cross-product prose in either skill (commit × held ×
  driven): `git diff` confirms the old handoff Step 2/Step 3 and precompact
  steps 4/5 were deleted, not relocated.
- No tense clause in either skill ("present-tense truth" appears nowhere
  under `skills/`).
- No stale closing lines: "Ready to commit, then /clear" and its
  `/compact` twin appear nowhere under `skills/`.
- The "A driven transition whose directive needs an answer is written but
  not armed…" sentence is gone from both skills.
- `.claude/gitlore-commit-memory` is not reachable from either skill body
  (`grep -rn "gitlore-commit-memory" skills/` → no match), so the
  standalone-commit path stays unreachable under `with-commit`.
- Anti-patterns survive in both skills, including the ones the outline
  called non-deferrable: no direct `.claude/autodrive` write, no asking
  whether to clear/compact under a driven transition, no reprinting the
  continuation prompt or the pasteable transition line, no `rename` under
  precompact.
- Both skills state the tool-call prohibition in a form that covers the
  whole span: "These writes are the only tool calls allowed before
  `handoff-checkpoint`" (handoff:21-22, precompact:18-19), so the narrower
  Step 2 bold ("Make no tool call between deciding and
  `handoff-checkpoint`") does not open a gap for a Read taken *while*
  deciding.
- Word counts: handoff 1791, precompact 1128 — both under the 2000-word
  cap.
- `handoff-todo.md` open-items-only rule is intact in the handoff
  templates section (l.150-154) and echoed in the precompact body
  (l.61-62).
- The changelog entry, the design nodes and CLAUDE.md agree with each
  other and with the code on the hold rule, the part order and the
  one-producer-per-path rule for the closing line.
- The 2026-09-17 supersede blockquote is correctly scoped to three things
  and its two standing claims are true.
- `docs/changelog.md`'s index line is in the required format and
  newest-first; its link resolves.
- Every test-suite claim CLAUDE.md makes about this plan's new rows names
  a test that exists.

## Unverified suspicions

- `docs/design/the-checkpoint-directive.md:96-98` says `held` "is the one
  state that outlives the turn that wrote it". Under the new second
  disjunct (`T ∧ C`, clean memory) the hold is released by
  `handoff-approved` inside the same turn, so the sentence is now true of
  the state's *purpose* rather than of every instance. Whether that
  generalization is worth narrowing is an editorial call I cannot settle
  from the code; the paragraph's actual subject — why `held` names an
  owner — is unaffected either way.
- `skills/handoff/SKILL.md` has no counterpart to precompact's "Padding
  the closing line into a summary of the session." anti-pattern. I could
  not establish from the record whether that asymmetry is deliberate (the
  compaction is about to produce a summary, which is the stated reason for
  precompact's version) or an omission.

## Severity counts

Critical 0 · Major 0 · Minor 7
