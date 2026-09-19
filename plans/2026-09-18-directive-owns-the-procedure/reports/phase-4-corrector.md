# Phase 4 checkpoint review — skill bodies

Scope: `git diff 7389e56..HEAD -- skills` (Items 4.1, 4.2), checked against the
runbook's Phase 4 section, the outline, and the printed text in
`scripts/_checkpoint_lib.py`, `scripts/checkpoint.py:compose_directives` and
`bin/handoff-approved`.

Verdict: sound. No critical or major findings. Two minor fixes applied.
`just precommit` exits 0: manifest/settings lint, shellcheck, ruff/mypy/ty
("All checks passed!" x2), bats 169/169 ok, pytest 261 passed / 11 deselected.

## 1. Remove and Keep

### Item 4.1 — `skills/handoff/SKILL.md`

| Spec | Status |
|---|---|
| Remove: tense clause in **Capture memory** | Gone. The rest became Step 1. |
| Remove: step 2 commit-placement paragraph | Gone. |
| Remove: step 3 "Say what the boundary is ready for" + matrix | Gone. |
| Rewrite: "prints nothing when there is nothing further to do" | Now "prints what is left to do at this boundary". Accurate: a boundary always prints at least the closing line or the arming instruction, and the refusal prints alone. |
| Keep: three decisions (typed, continuation, commit awareness) | Verbatim in Step 2, including "The ask stops at the transition". |
| Keep: "owns the decision — do not re-derive or verify it" | In Step 3. |
| Keep: non-zero-exit instruction | In Step 3. |
| Keep: templates, seam section, every anti-pattern | Unchanged. The `## The seam: files vs. continuation prompt` heading is intact. The anti-pattern's "Step 1" ref was correctly updated to "Step 2". |

### Item 4.2 — `skills/precompact/SKILL.md`

| Spec | Status |
|---|---|
| Remove: step 1 tense paragraph | Gone. |
| Remove: step 2 "in the tense the commit answer sets" | Gone. |
| Remove: step 3's closing commit-placement paragraph | Gone. |
| Remove: step 5 + matrix | Gone. |
| Rewrite: "Nothing printed → nothing further to do" | Replaced by the shared Step 3 paragraph. |
| Rewrite: "one silent checkpoint call and one line of reply" | Now "nothing durable, clean memory, no commit — is one checkpoint call, and its output is the one line you end on." Accurate. It omits a live SDD ledger, which adds the nudge, but that is not the normal case and Step 3 covers extra parts. |
| Keep: do-not-re-derive, non-zero exit | In Step 3. |
| Keep: deferral to `../handoff/SKILL.md` | In Step 2. It resolves: the path exists and names "the full templates, the rules behind them, and the seam". |
| Keep: every anti-pattern, incl. padding the closing line | All seven are unchanged. |

### The unlisted cut

Both artisans cut "A driven transition/compaction whose directive needs an
answer is written but not armed, and the directive says how to release it."
Precompact's version also said "That is what keeps the compaction from running
at the end of the turn that asked the question."

**Judgement: nothing lost. The cut stands.** The sentence's only actionable
content is "the directive says how to release it". The printed arming
instruction ("Once everything above is done, run `handoff-approved` …") carries
that act, and `handoff-approved`'s own status line ("… armed; it runs at the
end of this turn") carries the one fact the agent needs afterwards. The rest is
mechanism, meaning why the hold exists. An agent cannot act on it, and
`craft:directive-writing` says to omit it. It was also stale in one direction:
since Phase 2, a transition is also held under `T and C` with clean memory,
where no directive "needs an answer". Kept as written, it would have misstated
the new hold rule. The rationale belongs in `docs/design.md` (see the Phase 5
notes).

## 2. Execution trace

Each cell was walked using only the new body plus the printed output.

- **Untyped handoff + with-commit + clean memory.** Hold rule
  `(K∧M)∨(T∧C)`: K true, M false, T false, so the sentinel is `armed`. Printed:
  commit act, then `Once everything above is done, end on one line: \`Ready to
  /clear\`.` Step 3 takes the parts in order: make the commit, then end on
  "Ready to /clear". `Stop` types `/rename` after the commit. Correct.
- **Typed handoff + with-commit + clean memory.** `T∧C`, so the sentinel is
  `held`. Printed: commit act, then the arming instruction. The agent commits
  and runs `handoff-approved`, which prints `handoff: clear armed; it runs at
  the end of this turn.` and then the closing instruction
  (`Clear armed — it runs when this turn ends.`). Step 3's "whatever you run
  may print the next part" covers that second producer. Correct. The commit
  lands before the arming.
- **Untyped precompact + dirty memory.** K is false (the bare marker types
  nothing), so the sentinel is `armed`. Printed: memory directive, then the
  SDD nudge if a ledger is live, the commit act under `C`, and finally
  `… end on one line: \`Ready to /compact\`.` The memory directive asks for
  approval, so the turn ends on the blockquote. "Each one waits for everything
  above it" and the closing line's own "Once everything above is done" keep
  the agent from appending the closing line to the approval question. After
  approval, the agent writes the message file(s), commits under `C`, and ends
  on "Ready to /compact". Correct.
- **Clause-file refusal.** Printed alone. The agent follows it: run
  `/handoff:restart`, then retry. Nothing in the body tells the agent to
  compose a closing line or to commit, so the absence of both is correct
  behaviour and not a gap. Correct.

Neither body still tells the agent to compose a closing line or to place a
commit. The remaining "commit" mentions are the commit-awareness decision and
the "Commit/push status" anti-pattern about file content. Both are legitimate.

## 3. Consistency and length

- After the fixes below, Step 1 and Step 3 are byte-identical across the two
  bodies (`diff` checked). Step 2 differs only where the boundary does: `clear`
  vs `compact` + focus directive, `rename`, and the templates inline vs
  deferred.
- Word counts: handoff 1791, precompact 1128. Both are under 2000.
- Stale step cross-references: none. The only one is handoff's anti-pattern
  "Step 2", which is correct.

## 4. Directive quality

The new text states acts ("Carry out each part in the order printed"), with no
mechanism, and it names no identifier the reader should not reach for. The
anti-patterns stay.

Noted and not changed: handoff's anti-pattern "Both are settled by the request
and the armed file" reads "armed" loosely on the held path. That text predates
Phase 4, and the reader's act does not change.

## Fixes applied (all minor)

1. `skills/handoff/SKILL.md` Step 3: one line was 81 columns. Reflowed it to
   ≤80, matching precompact's wrap byte for byte.
2. `skills/precompact/SKILL.md` Step 1: "capture them in auto-memory" became
   "write them to auto-memory". This matches the step heading and handoff's
   Step 1.

UNFIXABLE-in-scope: none.

Side note: `reports/item-4-2.md` says its commit was blocked by a stale
`main.lock`. `git log` shows `f30b184` (Item 4.2) landed afterwards, so that
line is stale. It is a write-time report and is left as written.

## Phase 5 notes (stale statements in OUT docs)

`CLAUDE.md`, Layout section:

- The `skills/handoff/SKILL.md` bullet has the old shape: "Step 1 decides all
  three fields …", "Still in step 1, and before the checkpoint, it captures
  memory", "which makes it write memory as if the change has landed" (the tense
  clause), "Step 2 … places a commit the ask implies: after the checkpoint …
  and before the transition is armed", and "Step 3 reports what the boundary is
  ready for, in one line." New shape: Step 1 is memory, Step 2 decides and runs
  the checkpoint, and Step 3 follows the printed parts in order. The checkpoint
  prints the commit act and the closing line.
- The `skills/precompact/SKILL.md` bullet says "Decide the same three fields
  as handoff's step 1 …, capture durable learnings …, follow whatever directive
  it prints (memory commit, ledger flush, and/or the arming instruction), and
  report readiness in one line". The order is now memory first, and the
  readiness line is printed by the checkpoint, not composed by the agent.
- The `scripts/checkpoint.py` bullet says the state is `held <session>` "iff the
  sentinel types anything at all and a memory directive was emitted". The rule
  is now `(K∧M)∨(T∧C)`. The same bullet says "with the arming instruction
  composed onto the memory directive when the sentinel is held". The arming
  instruction is now its own part after the commit act, and the closing line
  is printed when the sentinel is not held.
- The `_checkpoint_lib.py` bullet says "Couples only to the two IPC filenames —
  never gitlore internals". This is stale: the directive reads
  `gitlore.memoryApprovalClauseFile` (already named in the outline). It also
  says "both skills finish memory before running the checkpoint". That is still
  true.
- The `tests/test_checkpoint.py (140 tests)` count is stale.
- The bullet should mention `commit_directive`, `arming_directive` and
  `closing_directive`, plus `bin/handoff-approved`'s per-kind closing line.

`docs/design.md`:

- § "Held: a transition an approval has not released" (≈ lines 593–612) gives
  the old hold condition ("types anything at all and a memory directive was
  emitted") and says the release instruction is "composed onto the end of that
  directive". It needs the `T∧C` disjunct and its reason: a commit that fails
  must not have a transition run over it. It should also say why the untyped
  `/rename` is exempt under `C`.
- ≈ lines 780–786, "The agent supplies one fact": "It changes what memory
  *says* (under `with-commit`, bodies state present-tense truth …)". The
  tense rule no longer depends on the mode. It is owned by
  `gitlore:memory-writing`.
- ≈ lines 933–947: the memory writes "sit inside that step … after the commit
  answer that sets their tense", and "A commit the ask implies … comes after
  the checkpoint" is stated as skill-prose discipline. Memory is now its own
  Step 1 ahead of deciding. The commit placement still stands, but the
  checkpoint's printed commit act now carries it. This paragraph and the
  2026-09-17 changelog link need the supersession the outline describes.
- ≈ line 1063: "arming discipline would stay a rule the agent is asked to
  follow". This is still true as a rejected alternative. Check it reads
  consistently once commit-before-arm moves into the hold rule.

`skills/handoff/references/design.md`: no stale statement about steps, the
commit, the closing line or the hold was found (grep for
commit/step/closing/ready/held).

`docs/changelog/2026-09-17-memory-moves-inside-the-deciding-step.md`: needs
the scoped `> **Superseded 2026-09-18**` blockquote that the outline
specifies.
