# Seam B review: cd0d5b5

Scope: `/code-review medium cd0d5b5`, plus the five targeted checks (a) to (e) in the brief. The skill's own findings are merged below and triaged by the rule that a finding is high or medium only when a reader following the text would do the wrong thing.

Counts: 0 high, 1 medium, 7 low, 1 pre-existing (outside the diff, not counted).

## Verified clean

- **Verbatim.** A word-level diff of the removed lines against the node's added lines shows only reordering, the new headings, the `#one-hold-predicate-rejected` relink, the dropped changelog links, the dropped sentences the report names (entry 1's sentence 2, entry 3's first two sentences), and the one fold. No other moved word changed.
- **(a) Fold accuracy.** The new sentence (`the-checkpoint-directive.md:234-236`) is true. `scripts/checkpoint.py:72-73` emits `lib.memory_directive` for `precompact` as well as `handoff`. `held` (`checkpoint.py:176`) holds a driven compact whenever memory is owed, so the commit comes before `/compact` runs. Under `compact: false` the marker names no command, so the approval question comes before `Ready to /compact`. The stated reason matches the record's own supersession note (`docs/changelog/2026-07-12-session-compaction.md`: "commits before the summariser runs, because the summary is written from the conversation and after compaction that conversation is a paraphrase") and the skill's opening ("Compaction paraphrases the conversation", `skills/precompact/SKILL.md`). The problem is the sentence the fold sits beside; see M1.
- **(b) Partial moves.** Nothing was lost. Entry 1's dropped sentence 2 (the answer changes the commit act, the driven hold and the gitlink naming) is in the node at `:23-28` (the commit act names the gitlink), `:107-115` (second disjunct) and `:167-170` ("What the mode changes is the commit act"). Entry 3's dropped first two sentences are the seam's first paragraph, `:152-162` (the dirty listing plus one sentence naming `gitlore:commit`; the skill owns the format, review and approval; "a change to any of them lands in one place"). The duplicates that remain agree with each other: `:189` "the same text in both modes" and `:166` "the same text serves `with-commit` and `without-commit`". Neither contradicts the other.
- **(c) Referents.** "the first disjunct's reason" (`:143`) now resolves better than before, because the Held section names the disjuncts directly above. "the detection round-trip the packaging exists to avoid" (`:240`) has its antecedent in "With nothing to approve" (`:212-213`), now in the same section. "The rule this replaced" (`:195`) and "the writes" (`:78`) never had an antecedent in either location, so the move did not break them (L5).
- **(d) Links and index.** `just check-refs` resolves 261 references and `just check-size` passes. Each anchor exists once in the node: `#decisions` (`:183`), `#rejected-alternatives` (`:221`), `#where-in-the-turn-a-directive-lands` (`:75`) and `#one-hold-predicate-rejected` (`:136`; the comma drops out of the slug). The nine `docs/design.md` index lines (252-255, 270, 282-284, 292, 303) all name bold leads that still exist in `decisions.md` and `rejected-alternatives.md`.
- **(e) Pointer conclusions.** Each shortened pointer in `rejected-alternatives.md` (26, 28-30, 65, 149) states a true conclusion. Where it gives a reason, the reason is the standing ground: the turn a hook cannot run, and a held sentinel that protects no state.

## Medium

### M1. `docs/design/the-checkpoint-directive.md:233-236`: the fold leaves the superseded sentence standing in the present tense

- **What is wrong.** "Compaction threatens conversation state only, so the flush can wait for any later turn." is kept verbatim. The next sentence then says "`precompact` has since committed memory before the compaction instead of letting it wait". In a living design doc, two adjacent sentences now prescribe opposite timings for the memory commit.
- **Evidence.** The record superseded this claim on 2026-07-20 (the second supersession blockquote under "Manual compact as a wrap-up moment" and the one closing "Durable progress files"). The code commits before the compaction (see (a)).
- **The reading that goes wrong.** A reader who lifts the rejection's argument, or skims it, takes "can wait for any later turn" as current design. That is grounds for deferring the precompact memory commit past `/compact`, or for dropping the hold on a driven compact with dirty memory. `.claude/rules/docs.md` says a design change rewrites the prose it invalidates; it does not say to append a correction to it.
- **Suggested fix.** Replace the stale sentence with the fold, rather than keeping both. For example: "Compaction leaves disk untouched but paraphrases the conversation, so `precompact` commits memory before it." This is a departure from verbatim, but the contract already allows it because this is the fold.
- **The skill reviewer raised this independently.**

## Low (declined)

- **L1.** `docs/design.md:240-241, 276-277`: the hub still says each call is "argued in" `decisions.md` / `rejected-alternatives.md`. For nine entries the reader finds a pointer there and makes one more hop. Nothing goes wrong.
- **L2.** `docs/design/rejected-alternatives.md:28-30, 65`: "all three rejected" and "both rejected" give no reason, unlike the other two pointers. They are true and they link to the argument.
- **L3.** `docs/design/rejected-alternatives.md`: 19963 bytes, 37 under the cap, with its `size.exempt` line deleted. The next growth fails `check-size` loudly, which is the gate's design. The 55 unsettled links are the known headroom.
- **L4.** Placement. The commit-awareness arguments sit under "The gitlore seam", while `CLAUDE.md` routes the `commit` field to `the-skills.md`, which restates "one fact the agent supplies, everything downstream deterministic" (`the-skills.md:27-31`). `with-commit` also routes to this node, and the two texts agree. The node now has three differently shaped decision/rejection homes (`:75`, `:136`, `:183`/`:221`). "With nothing to approve" constrains the Held section but sits under the seam's Decisions.
- **L5.** `the-checkpoint-directive.md:78, :195`: "the writes" and "The rule this replaced" have no antecedent in the node. They had none in `decisions.md` either.
- **L6.** `the-checkpoint-directive.md:216`: "a driven transition is therefore held" is narrower than the Held rule, under which an untyped `/rename` also holds. It is verbatim and true as far as it goes, and it is not a contradiction. The skill reviewer rated it higher; it is declined because nothing in it says an untyped handoff arms.
- **L7.** The new pointer lines and two rejoined node lines (`decisions.md:98-104, 234`; `rejected-alternatives.md:26, 65, 149`; node `:189, :206, :234`) are not hard-wrapped like the rest of the files.

## Pre-existing, outside the diff (for `TODO.md`, not this commit's fix)

- **`the-checkpoint-directive.md:80`: "precompact reads its directive before it writes" appears stale.** It was moved verbatim from `decisions.md`, so this commit did not introduce it, but it now sits directly under the list naming both ledger directives. Under the current flow, `precompact`'s `TODO.md` is written by the same `handoff-checkpoint` call that prints `sdd_directive` (`checkpoint.py:88-115`: plans are applied, then the parts are composed). Its "Keep them out of TODO.md" therefore lands after the file exists, which is the same shape as the handoff no-op defect the record (`2026-07-22-directive-fits-where-it-lands.md`) fixed. `todo_boundary` names a removal; `sdd_directive` (`_checkpoint_lib.py:221-244`) does not. A reader who trusts the sentence would keep the plain prohibition. I did not probe this beyond reading the code; it would be medium if confirmed.

## Fixes

- M1: `docs/design/the-checkpoint-directive.md`, the `PreCompact` rejection. The superseded "Compaction threatens conversation state only, so the flush can wait for any later turn." and the fold that followed it are now one sentence: "`precompact` commits memory before the compaction, because the summary the compaction leaves is a paraphrase of the conversation."
- The seven lows are declined. The pre-existing item is queued in `TODO.md` and not touched here.
- `just precommit`: check-plugin, check-code, check-refs and check-size passed.
