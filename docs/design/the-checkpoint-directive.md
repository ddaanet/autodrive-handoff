# The checkpoint directive

Part of [handoff — Design](../design.md).

## What the checkpoint prints

Both boundary skills end the same way: follow what the checkpoint printed,
in order. Everything the procedure turns on after that call — whether memory
is owed, the commit mode, whether the sentinel names any command, whether the
transition is driven — is already an input to the checkpoint, so it prints
the procedure for the one cell of that cross product the call is in, and the
skill bodies state none of it. The parts, each present only under its own
condition:

1. the memory directive, when the `gitlore-memory` submodule is registered
   and dirty;
2. the todo boundary (`handoff`) or the SDD ledger nudge (`precompact`),
   when a live ledger exists;
3. the commit act, under `with-commit` — make the commit the request called
   for. It names no git verb: the request may be an amend or a fresh commit,
   and the checkpoint cannot tell which;
4. the arming instruction, when the sentinel is held — run
   `handoff-approved`;
5. the closing line, when it is not — an instruction to end the reply on one
   quoted line: `Ready to /clear` or `Ready to /compact` when prepared, the
   transition armed and running when the turn ends when driven.

The commit act, the arming instruction and the closing line each open "Once
everything above is done", so none of them lands in a reply that is still
asking for the memory approval. The closing line is the one where this is
not already implied by the hold: an untyped precompact with dirty memory
runs nothing, so it is armed rather than held, and its closing line
follows the approval question directly. Ordering the commit before the
arming instruction is what places a commit the ask implies after the
checkpoint — it has to carry the handoff files the checkpoint staged — and
before the transition is released.

The closing line has one producer per path. Not held, the checkpoint prints
it last. Held, `bin/handoff-approved` prints it after its own status fact
(what is armed, and that it runs at the end of the turn), because the
release comes a turn or more after the checkpoint's output. It picks the
text from the sentinel's kind alone, which is enough: `autoname` never
holds, so a held `rename` is an untyped handoff, and a held `clear` or
`compact` is driven. The text is literal there rather than composed, so the
command stays one file rewrite (NFR1), and a test compares it with
`closing_directive()` so the two producers cannot drift. One hold decision
writes the sentinel's state and selects between the arming instruction and
the closing line, so the file and the printed ending cannot disagree.

The clause-file refusal prints alone. When memory is dirty but gitlore's
approval clause cannot be read — `gitlore.memoryApprovalClauseFile` unset,
or its file missing — the memory part tells the agent to restart and retry,
and a commit act, arming instruction or closing line after it would tell the
agent to finish a boundary it has just been told cannot proceed. The
sentinel is composed as usual; the retry composes it again.

`autoname` prints nothing: it is not a boundary, owes no memory write, and
has no procedure after the call.
[The directive owns the
procedure](../changelog/2026-09-18-the-directive-owns-the-procedure.md)

## Held: a transition an approval has not released

The checkpoint writes the sentinel `held` when it **names any command at all**
and a memory directive was emitted, or when the transition is **driven** and
the mode is `with-commit`, and prints the instruction to release it as its
own part, after the commit act. `bin/handoff-approved` is the one command
that leaves the state, through the same `handoff_drive_arm` `drive-take.sh`
uses.

The first disjunct guards a memory approval: commands run at the end of a
turn that is about to end on a question. A transition armed alongside that
question clears or compacts away the very conversation the answer applies
to. The condition names the hazard rather than its trigger, and the hazard
is the commands running, not which transition they carry. An untyped handoff
runs no transition but still runs `/rename`, racing the same
answer — so it holds too. What is exempt is the sentinel that names nothing
at all: the bare compact marker, which would otherwise lose the expectation
`SessionStart(compact)` gates the frame's re-injection on to a gate it has
no reason to wait on. Of the other parts, the ledger nudge and the todo
boundary never hold: they are acts, not questions, and the turn's end comes after
them either way. The commit act is the one that can fail, which is the
second disjunct.

The second disjunct guards the commit. Armed, a driven transition runs at
the end of the turn whatever happened in between, and a commit that fails ends
the turn too — the agent stops to report it — so the transition would clear
or compact over uncommitted work. Held, it runs only once `handoff-approved`
is called, which the printed order puts after the commit. The disjunct is
scoped to a driven transition rather than to any command: an untyped
handoff's only line is `/rename`, which costs nothing when it fires over a
failed commit, and with clean memory there is no question for it to race
(see "One hold predicate" under [Rejected
alternatives](rejected-alternatives.md)).

`held` is the one state that outlives the turn that wrote it: the approval
is answered in a later turn, and a failed commit is retried in one. So it is
the one that names its owner, the session whose release it waits on, carried
on line 1 as `held <session-id>`. That release comes from that session or
not at all: once another session is taking prompts in the repo, the file is
abandoned, and `report-drive-failure.sh` sweeps it exactly as it sweeps a
stale `armed` one. Without the name it would stay armable indefinitely, and
`handoff-approved` — which otherwise verifies only the state and the kind —
would run a dead session's `/rename` and `/clear` in a live conversation.
`handoff_drive_arm` replaces line 1 whole, so leaving `held` drops the owner
with it, which is right: past the release nothing is outstanding, and no
state below `held` accepts an owner.

## The gitlore seam

The checkpoint's directive is the plugin's one seam with
[gitlore](https://github.com/ddaanet/gitlore). When the `gitlore-memory`
submodule is registered and dirty, it instructs the agent to summarize → get
approval → write `.claude/gitlore-memory-message`, and — only under
`without-commit` — `.claude/gitlore-commit-memory`. That trigger file is the
entire difference between the two paths: written, gitlore's `PostToolBatch`
commits memory standalone; withheld, the parent commit's pre-commit hook
folds it into the source commit. Both are file writes, which sidesteps the
sandbox and the auto-mode classifier. The coupling is two IPC filenames plus
one advertised `git config` key — `gitlore.memoryApprovalClauseFile`, whose
value is the file holding the approval wording the directive quotes, so the
wording has one owner instead of a copy per consumer. Never gitlore
internals.

`ledger_path` is the one-row registry of foreign workflow-owned
progress ledgers (currently superpowers SDD). It detects **liveness**, not
presence: the current layout glob plus an identity first line, most-recent
mtime among several, fail open. Both the nudge and the todo-file boundary
interpolate what it prints, so they cannot disagree about what exists.
