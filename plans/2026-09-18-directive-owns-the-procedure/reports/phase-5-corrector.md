# Phase 5 corrector — Records

Scope: `git diff 7ede79e..HEAD -- docs CLAUDE.md`. Fixes are applied in the
working tree and nothing is committed. `just precommit` is green: jq lint,
shellcheck, ruff check, ruff format, docformatter, mypy, ty, bats (169 ok),
and pytest (261 passed, 11 deselected).

## 1. Accuracy against the code

I checked these claims against the code, and they hold:

- **Hold rule.** The records state `(K ∧ M) ∨ (T ∧ C)`, computed once. This
  matches `hold_decision` in `scripts/checkpoint.py`. The same value feeds
  `compose_sentinel` and `Ending`.
- **Part order.** Memory, then the todo boundary or SDD nudge, then the commit
  act, then arming or closing. This matches `compose_directives`, and the
  arming and closing parts are mutually exclusive.
- **Closing-line texts.** The texts match `closing_directive` in both the
  prepared form and the driven form. The "Once everything above is done"
  opening appears in `commit_directive`, `arming_directive` and
  `closing_directive`.
- **Two producers.** When the sentinel is not held, the checkpoint prints the
  closing line. When it is held, `bin/handoff-approved` prints the status
  fact, a blank line, and then the per-kind literal. `DRIVE_KIND` is enough to
  choose the line, because `autoname` and `restart` never hold.
- **Refusal alone.** `memory.refusal` returns early with `[memory.text]`. The
  refusal still counts as `M` in `hold_decision`, so "sentinel composed as
  usual" is accurate.
- **`MemoryPart(text, refusal)`.** The return type is stated correctly. The
  "Nothing further is needed from you" sentence has been dropped from the code.
- **Coupling.** The `gitlore.memoryApprovalClauseFile` coupling is read by
  `_resolve_approval_clause`.
- **Test counts.** I re-collected them with bare `pytest --collect-only -q`:
  - `test_checkpoint.py`: 171
  - `test_watcher_lib.py`: 49
  - `test_drive_when_idle.py`: 30
  - `test_tui_conformance.py`: 11 (deselected by default)
  - total: 261 of 272

  All of these match `CLAUDE.md`.
- **Mutation evidence, checked against the slice reports:**
  - "drop the disjunct ⟹ that row alone reds": confirmed by
    `item-2-1-s1-code-review.md` (2 failures, both parametrizations of the
    one row).
  - "widen to `K ∧ C` ⟹ that row reds together with the rename-only row":
    confirmed by `item-2-1-s2-test-review.md`, mutation A.
  - "each producer's three arms mutated separately, each reds its own row":
    confirmed by `item-3-2-s2-test-review.md`, M1–M6.
  - The trailing-newline residual: confirmed by the same report's M7.
  - Precompact closing-line-last "mutation-checked by printing it first":
    confirmed by `phase-3-corrector.md` fix 1.
  - The armed refusal row alone catches a closing line appended by the hold:
    confirmed by `item-3-1-s2-test-review.md`, M6.
- **Named test rows.** `test_*_parts_print_in_order`,
  `test_clause_refusal_is_followed_by_no_commit_or_arming`,
  `test_refusal_prints_alone_when_not_held`, the commit-act pair and the
  `*_closing_only` rows all exist.

Fix applied:

- **Minor, in the changelog entry.** "A bats row compares it with
  `closing_directive()`" is wrong: there are three rows, one per kind
  (`tests/checkpoint.bats:221,232,243`). It now reads "One bats row per
  kind". This entry is the phase's own new entry and has not been released
  yet, so correcting it in place is in scope.

## 2. Supersession discipline

- **2026-09-17 blockquote.** It is scoped to exactly the three items that
  Item 5.1 names:
  - the ordering reason, "after the commit answer because that answer sets
    the tense";
  - the tense clause restored to precompact;
  - "It now sits in Step 2".

  It names what still stands: memory before the checkpoint, and the commit
  after the checkpoint and before arming, with the same rule on a new carrier.
  It points at its sibling, and it heads the whole file because the entry has
  no sections, which is the same precedent as
  `2026-07-27-content-null-is-a-no-op.md`. No change needed.
- **Index line.** It has the shape `- [2026-09-18 — Title](changelog/<file>.md)
  — hook`, sits at the top, and carries no version. That matches the
  neighbouring lines. No change needed.
- **`docs/design.md`.** It has no dated headings, and no dated text was added
  outside changelog link targets. I fixed one stretch of past-relative
  wording, listed under §3.

## 3. Staleness sweep

I grepped all five IN files for these terms: held, composed onto, arming
instruction, Ready to commit, nothing further, prints nothing, silent, tense,
Step 1 decides, report readiness, readiness, 140, "very hook", "waits on",
step N, "driven skill", "arms the sentinel", "memory directive says".

Fixes applied:

- **Major, `CLAUDE.md`, `report-watcher-failure.sh` bullet.** It said a held
  transition "waits on an approval whose answer arrives at this very hook".
  That was stale under `T ∧ C`: a held file can instead wait on a commit that
  failed and is retried in a later turn. It now says the transition waits on a
  release that can come in a later turn, either the memory approval (answered
  at this hook) or a failed commit being retried. "The session that would
  approve it" became "release it".
- **Minor, `CLAUDE.md`, `handoff_drive_read` bullet.** "The approval it waits
  on arrives in that session" became "the release it waits on comes from that
  session", for the same reason.
- **Major, `docs/design.md`, §Held, owner paragraph.** This is the equivalent
  passage in design.md. It said "the session whose approval it waits on", "That
  approval arrives in that session", and "past the approval there is no
  outstanding one". All three are now phrased in terms of the release, and the
  paragraph now says why the state outlives a turn: the approval is answered in
  a later turn, and a failed commit is retried in one.
- **Major, `docs/design.md`, §Held, first-disjunct paragraph.** It said "Only
  the memory gate defers". That was false once the commit act holds a typed
  transition. It now says the ledger nudge and the todo boundary never hold,
  and that the commit act is the part that can fail, which is what the second
  disjunct covers.
- **Minor, `docs/design.md`, §"Deciding makes no tool call".** "The commit
  answer no longer sets their tense" is past-relative wording in the living
  doc. It now reads "does not set their tense".
- **Minor, `CLAUDE.md`, High-level flow paragraph.** It described the stdout
  output as only the memory directive. It now adds one sentence: after the
  memory part, the checkpoint prints the commit act and then either the
  arming instruction or the closing line, so the skills state none of it. It
  also gains a pointer to the 2026-09-18 changelog entry.
- **Minor, formatting.** Phase 5 left four lines over 80 columns: three in
  `docs/design.md` (the checkpoint paragraph at about line 287, "Any
  rebalancing of the gitlore", and the "One hold predicate" entry) and one in
  the `bin/handoff-approved` bullet in `CLAUDE.md`. I rewrapped all four.

Checked and left unchanged:

- `design.md` §"With nothing to approve, the wrap-up completes in a single
  turn". This still holds under `T ∧ C`, because the commit and
  `handoff-approved` land in the same turn.
- §Held's title, "a transition an approval has not released". It still reads
  correctly, since `handoff-approved` is the approval act in both disjuncts.
- The `design.md` line "`handoff-approved` — which verifies the state and
  nothing else". This is counterfactual ("without the name it would…"), so it
  is not a claim about current behaviour.
- The `bin/handoff-approved` error wording "not this session's approval to
  give". This is code and out of scope. It is still accurate in the sense
  above.

## 4. Proportion

Phase 5 grew `docs/design.md` from 1155 to 1246 lines, and it is 1248 after
my rewraps.

- **"What the checkpoint prints".** This section is mostly current design: the
  parts, their conditions, the anchor rationale, the two producers, and
  refusal-alone. The one piece of history in it was "rather than leaving the
  agent to locate itself in a prose matrix", which describes the old shape. I
  rewrote it as a present-tense statement: "the skill bodies state none of it".
- **Held, second-disjunct paragraph.** Its closing sentence ("Holding it would
  add a `handoff-approved` call to 'handoff and commit', the most common
  invocation, for no protected state") repeated the cost argument that the new
  "One hold predicate" rejected-alternative entry already makes. I replaced it
  with a pointer to that entry, so the argument lives in one place.
- **Rejected-alternative entry.** This is the correct home for the rejection,
  so I kept it.

The file is still about three times the 400-line soft cap. Splitting it is
out of scope, and it is noted here for a later pass.

## 5. Lifecycle audit

- **`git status`.**
  - Tracked modifications: only this pass's three uncommitted files,
    `CLAUDE.md`, `docs/design.md`, and
    `docs/changelog/2026-09-18-the-directive-owns-the-procedure.md`.
  - The `??` entries are the known phantoms. In this sandbox they stat as
    0-byte read-only regular files dated 2026-09-18 22:32. Some of them, such
    as `.bashrc`, are listed as bind-mount points in `/proc/self/mountinfo`.
- **Staged content.** None; `git diff --cached` is empty.
- **In-progress operations.**
  - No `MERGE_HEAD`, no `CHERRY_PICK_HEAD`, no `rebase-merge/`, and no
    `rebase-apply/`.
  - `.git/REBASE_HEAD` exists, dated 2026-07-22. It is a leftover pseudo-ref.
    With neither rebase directory present, no rebase is in progress, and it is
    harmless.
- **Lock files under `.git/`:**
  - `.git/config.lock`: 0 bytes, `r--r--r--`, dated 2026-09-18 22:32. It is a
    bind-mount point in this sandbox, like the phantoms. I left it in place as
    instructed, and commits work around it.
  - Four more 0-byte locks, which were not in the brief:

    | Lock | Timestamp | Matches |
    |---|---|---|
    | `.git/logs/HEAD.lock` | 2026-09-18 22:56:41 | — |
    | `.git/logs/refs/heads/main.lock` | 2026-09-19 13:10:15 | — |
    | `.git/refs/remotes/origin/HEAD.lock` | 2026-09-19 13:28:51 | Item 5.1 commit time exactly |
    | `.git/logs/refs/remotes/origin/HEAD.lock` | 2026-09-19 13:28:51 | Item 5.1 commit time exactly |

    None of them is a mount point, and no git process is running.
    Later commits (5.2 at 13:32, 5.3 at 13:37) succeeded, so none of them
    blocks a commit. They are stale leftovers from sandboxed subagent commits,
    of the same kind as the two ref locks removed earlier in this run.
    `refs/remotes/origin/HEAD.lock` would block any later update of
    `origin/HEAD`, for example `git remote set-head` or a fetch that touches
    it.

    **Not removed:** `.git/` is outside this review's scope. The team lead
    should remove all four; they are proven stale by the evidence above.
- **Handoff runtime files.**
  - Absent: `.claude/checkpoint-manifest`, `.claude/autodrive`,
    `.claude/autodrive.failed`, `.claude/autodrive.exited`,
    `.claude/gitlore-memory-message`, and `.claude/gitlore-commit-memory`.
  - Present and tracked, as expected: `.claude/handoff-task.md`,
    `.claude/handoff-todo.md`, `.claude/gitlore-hook-setup` and
    `.claude/settings.json`.

## UNFIXABLE

None within IN. The oversized `docs/design.md` and the four stale `.git/`
locks are outside scope and are reported above.
