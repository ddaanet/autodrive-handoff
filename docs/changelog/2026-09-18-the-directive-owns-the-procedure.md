# The directive owns the procedure (2026-09-18)

After the checkpoint call, `skills/handoff/SKILL.md` steps 2–3 and
`skills/precompact/SKILL.md` steps 4–5 described a cross product in prose:
commit or not × held or armed × driven or prepared. The agent had to work out
which cell it was in. `checkpoint.py` already held every input to that product,
and it already printed the memory half of it. Splitting the procedure between
prose and output caused three defects.

- **The prepared `with-commit` closing line was stale.** "Ready to commit,
  then /clear" and its `/compact` twin were written before the agent made the
  commit itself, in the same turn, after the checkpoint. In that cell the line
  was never true by the time the agent printed it. The `without-commit` and
  driven lines were accurate, but they sat in the same prose matrix and had to
  move with it.
- **Commit-before-arm was only prose.** A driven `with-commit` boundary with
  clean memory was written `armed`. If the commit failed and the agent stopped
  to report it, `Stop` fired anyway and the transition ran over uncommitted
  work.
- **The tense clause was a drifted copy.** "Under `with-commit`, memory bodies
  state present-tense truth" put a condition on a rule that
  `gitlore:memory-writing` §2 states unconditionally.
  [Commit awareness](2026-07-25-commit-awareness.md) had already recorded that
  the tense half needs no mode. The memory directive interpolates gitlore's
  approval clause, which opens by invoking that skill, so how memory is written
  is owned downstream. The skill bodies need not say anything about it.

## The change

Both skills now have three steps:

1. If durable learnings surfaced, write them to memory.
2. Decide the payload and run `handoff-checkpoint`, with no other tool call
   between the two.
3. Follow what it prints, in order.

Everything after the call is printed by the checkpoint for the one cell the
call is in: memory approval, the commit, the `handoff-approved` call and the
closing line. For the two boundary skills the parts print in this order, each
only under its own condition. `autoname` and `restart` still print nothing.

1. the memory directive, when one is owed;
2. the todo boundary (`handoff`) or the SDD nudge (`precompact`), as before;
3. the commit act, under `with-commit`: "Once everything above is done, make
   the commit the request called for." It names no git verb, because the
   request may be an amend or a fresh commit and the checkpoint cannot tell
   which;
4. the arming instruction, when held. It is reworded to "Once everything
   above is done, run `handoff-approved`", because the memory directive that
   "Once that is done" used to point at no longer sits directly above it.
   Under a typed `with-commit` boundary with clean memory, that directive is
   not printed at all;
5. the closing line, when not held.

Writing the steps down removes the stale line and the tense clause. Holding
the transition is what closes the commit-before-arm gap.

## The hold rule

Let `M` mean a memory directive was emitted, `C` the mode is `with-commit`, `K`
the sentinel types anything, and `T` the transition is typed. The sentinel is
written `held` iff `(K ∧ M) ∨ (T ∧ C)`. `hold_decision` computes it once, and
the same value selects between the arming instruction and the closing line, so
the sentinel and the printed ending cannot disagree.

The first disjunct is the old rule. The second is new. It is scoped to *typed*
transitions rather than to `K`, because what it protects under `C` is a
transition that would run over a failed commit. An untyped handoff types only
`/rename`, and a `/rename` that fires over a failed commit costs nothing.

*Rejected: one predicate, `K ∧ (M ∨ C)`.* `T` implies `K`, and an untyped
precompact types nothing, so the two rules differ in exactly one cell: an
untyped handoff, `with-commit`, clean memory. There the uniform predicate would
hold the sentinel and protect no state. The first disjunct's reason does not
carry over, since that reason is a `/rename` typed into a pane that shows the
approval question, and with clean memory nothing is asked. The cost falls on
"handoff and commit", the most common invocation, which would gain a
`handoff-approved` call. Forgetting that call would lose the title silently:
a same-session `held` file is exempt from the sweep, and
`report-watcher-failure.sh` reports nothing about `held`.

Two rows over one fixture pin the difference, and each was mutation-checked.
Typed + `C` + clean memory must be `held`, so dropping the second disjunct reds
it. Untyped handoff + `C` + clean memory must be `armed`, so widening to
`K ∧ C` reds it, along with an older rename-only row that pins the same cell's
sentinel bytes.

## One producer for the closing line

Each path has one producer. When the sentinel is not held, the checkpoint
prints the closing line last. When it is held, `bin/handoff-approved` prints
it, because that command runs a turn or more after the checkpoint's output. It
prints its status fact first (what is armed, and that it runs at the end of the
turn), then a blank line, then the closing line as literal text for each kind.
It chooses the text from `DRIVE_KIND` alone, which is enough: `autoname` never
holds, so a held `rename` is always an untyped handoff, and a held `clear` or
`compact` is always driven. The text is literal rather than composed in Python,
so the command stays a single file rewrite (NFR1). A bats row compares it with
`closing_directive()`, so the two producers cannot drift apart.

Both producers open the line with "Once everything above is done, end on one
line: `…`". The anchor was added after the Phase 3 checkpoint review, with my
human partner's approval. The case that needs it is an untyped precompact with
dirty memory. That boundary is armed, not held, because it types nothing, so
its closing line comes straight after a memory directive that asks for
approval. Without the anchor, the closing line could end the same reply that
asks the question. The commit act and the arming instruction already waited
for everything above them. The closing line now reads the same way.

## The refusal prints alone

`memory_directive` returns a `MemoryPart(text, refusal)`. The clause-file
refusal (`gitlore.memoryApprovalClauseFile` unset, or its file missing) says to
restart and retry. A commit act, an arming instruction or a closing line after
it would tell the agent to finish a boundary it has just been told cannot
proceed. So when the memory part is the refusal, the checkpoint prints it alone.
The sentinel state is unchanged, because the retry composes the sentinel again.

The `with-commit` memory text lost its last sentence, "Nothing further is
needed from you", because the commit act printed two parts later contradicts
it. It keeps the clause saying that this turn's commit carries the memory. The
load-bearing negative is untouched: `with-commit` output never mentions the
trigger file.

The skill bodies also dropped "A driven transition whose directive needs an
answer is written but not armed…". That sentence described mechanism, and it
would now be false: under `T ∧ C` with clean memory, the transition is held
although no directive needs an answer.

## Memory leaves the deciding step

[Memory moves inside the deciding
step](2026-09-17-memory-moves-inside-the-deciding-step.md) put memory writes
inside the deciding step, after the commit answer, because that answer set the
tense the memory bodies were written in. That dependency was the only reason
for the placement, and the tense clause was the only thing that created it.
Once the clause goes, nothing about memory depends on the commit answer, and
memory becomes its own first step, ahead of every decision.

This reverses the placement one commit after it was made. The reversal is
narrow. Memory is still written before the checkpoint, which its directive
keys on. The commit still lands after the checkpoint and before arming. That
rule is unchanged, but the checkpoint's printed commit act now carries it
instead of skill prose, and the hold rule backs it.
