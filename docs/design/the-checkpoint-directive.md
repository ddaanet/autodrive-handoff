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

1. what the call did to a half's legacy file, one line each: moved to the root
   name, removed, or ignored because the root file has a body. They are facts
   about a change already made, so they come first and carry no act;
2. the memory directive, when the `gitlore-memory` submodule is registered
   and dirty: the dirty listing and one sentence sending the agent to the
   `gitlore:commit` skill, the same text under both commit modes;
3. the todo boundary (`handoff`) or the SDD ledger nudge (`precompact`),
   when a live ledger exists;
4. the commit act, under `with-commit` — make the commit the request called
   for, including any change to `TASK.md` and `TODO.md`. It names no git verb
   for the commit: the request may be an amend or a fresh commit, and the
   checkpoint cannot tell which. It names the two files because nothing has
   staged them, and, when the memory directive was emitted, the memory gitlink
   `gitlore:commit` staged, so the commit carries the pointer too. When the
   call moved or removed a legacy file it leads with the
   one git line the checkpoint does name, `git -C <root> rm --cached
   --ignore-unmatch -q -- <path> …`, over those paths alone and
   never an ignored one, so git records a rename once the files are added.
   Each path is relative to the root, which `-C` names, so the line runs from
   any directory. A root holding a backtick or a control character (newline,
   carriage return, escape, DEL) would end the code span or split the line, so
   the line gives way to one plain sentence that echoes none of the path and
   asks for the unstaging by hand with `git rm --cached` from the project
   root; every other root prints byte for byte as before;
5. the arming instruction, when the sentinel is held — run
   `handoff-approved`;
6. the closing line, when it is not — an instruction to end the reply on one
   quoted line: `Ready to /clear` or `Ready to /compact` when prepared, the
   transition armed and running when the turn ends when driven.

The commit sentence, the arming instruction and the closing line each open
"Once everything above is done", so none of them lands in a reply that is
still asking for the memory approval. The git line that may lead the commit act
opens "Before committing" instead, since it is an act owed whenever the commit
comes. The closing line is the one where this is not already implied by the
hold: an untyped precompact with dirty memory runs nothing, so it is armed
rather than held, and its closing line follows the approval question
directly. Ordering the commit before the
arming instruction is what places a commit the ask implies after the
checkpoint — it has to carry `TASK.md` and `TODO.md` as the checkpoint left
them, which is why it names them: nothing has staged either — and before the
transition is released.

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

`autoname` prints nothing: it is not a boundary, owes no memory write, and
has no procedure after the call.
[The directive owns the
procedure](../changelog/2026-09-18-the-directive-owns-the-procedure.md)

### Where in the turn a directive lands

**A directive is correct only where in the turn it lands.** handoff runs its
checkpoint in the same turn as the writes — deliberately, so the snapshot
costs one round trip — so a directive about *how to write them* arrives
after they exist. precompact is no different: the SDD nudge's "Keep them out
of TODO.md" prints in the call that writes `TODO.md`, and `skills/precompact/SKILL.md`
says nothing of it beforehand, so it guides the next edit, not that write. Shared
prompt text is shared only where the flows agree; naming the safe route is
the load-bearing half of any prohibition.

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
`SessionStart(compact)` gates the todo's re-injection on to a gate it has
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
(see [One hold predicate, rejected](#one-hold-predicate-rejected)).

`held` is the one state that outlives the turn that wrote it on purpose: the
approval is answered in a later turn, and a failed commit is retried in one.
It names its owner, the session whose release it waits on, carried on line 1
as `held <session-id>` — and `armed` names its owner the same way, because
other sessions sharing the root take prompts and end turns while it waits for
its own (see [Sessions sharing a root](sessions-sharing-a-root.md#the-owner)). That
release comes from that session or not at all. Another session's prompt never
sweeps it, live owner or not: it waits on a human approval of unbounded
length, and an idle transcript is what that wait looks like. A dead owner's
file stays until the next checkpoint in the root replaces it, and arms nothing
meanwhile: without the name it would stay armable indefinitely, and
`handoff-approved` — which otherwise verifies only the state and the kind —
would run a dead session's `/rename` and `/clear` in a live conversation; with
it, `handoff-approved` refuses a held file another session owns.
`handoff_drive_arm` writes the line 1 it is given: `handoff-approved` passes
`armed <owner>`, since the session that approved is the one whose turn end
takes the transition, and `drive-take.sh` passes a bare `pending`, since past
the take nothing is any one session's.

### One hold predicate, rejected

**One hold predicate** — hold whenever the sentinel types anything and
either memory is owed or the turn carries a commit. A typed transition
always types something and an untyped precompact types nothing, so this
differs from the rule in exactly one cell: an untyped handoff under
`with-commit` with clean memory. There it would hold a sentinel whose only
line is `/rename`, protecting no state — the first disjunct's reason, a
`/rename` typed into a pane showing
the approval question, does not transfer, since clean memory asks nothing —
and it would add a `handoff-approved` call to the most common invocation. A
forgotten call there is silent: a same-session `held` is exempt from the
sweep, and nothing reports one, so the title is lost unnoticed.

## The gitlore seam

The checkpoint's directive is the plugin's one seam with
[gitlore](https://github.com/ddaanet/gitlore). When the `gitlore-memory`
submodule is registered and dirty, it prints the dirty listing and one
sentence: commit it through the `gitlore:commit` skill, invoked before a
summary is drafted. The skill owns the summary format, the review against
`gitlore:memory-writing` and the approval protocol (show the summary, end the
turn, commit on the approving reply), so the directive carries a pointer and no
copy, and a change to any of them lands in one place. It names neither the
command nor the format. The coupling is the `.gitmodules` registration that
gates it and the skill's name; no file, no git config key and no gitlore
internal.

A memory commit is the agent's own act, and no hook commits memory, so
nothing the plugin writes could approve or trigger one. The mode therefore
does not change the memory part: the same text serves `with-commit` and
`without-commit`. What the mode changes is the commit act. `gitlore-commit`
stages the moved memory gitlink in the parent index, and under `with-commit`
the commit act names it, so the parent commit the request calls for records the
pointer along with `TASK.md` and `TODO.md`. The approval takes a turn before
that commit, which is why a sentinel that names a command still holds while the
approval is owed (see "Held" above). The plugin needs a gitlore that ships
`gitlore:commit`; it keeps no fallback for the file handshake that skill
replaced.
[Memory commits go through the skill](../changelog/2026-10-30-memory-commits-go-through-the-skill.md)

`ledger_path` is the one-row registry of foreign workflow-owned
progress ledgers (currently superpowers SDD). It detects **liveness**, not
presence: the current layout glob plus an identity first line, most-recent
mtime among several, fail open. Both the nudge and the todo-file boundary
interpolate what it prints, so they cannot disagree about what exists.

### Decisions

**The agent supplies one fact; the code owns the branch.** Commit awareness
— *does the ask this call serves imply a commit?* — is a fact about the
conversation that no script can see, and everything downstream of the answer
is deterministic. It does not change how memory is committed or what memory
*says*: the memory directive is the same text in both modes, and how memory bodies are written, present-tense
truth included, is `gitlore:memory-writing`'s rule, which holds in every mode
and which `gitlore:commit` has the agent apply before it drafts the summary.
The transition fields are the same shape, which is why they are fields and not
skills.

**Ask the question the request can answer.** The rule this replaced counted
a commit landing in a later session, because it framed the question as where
the memory belongs rather than whether anything present decides it — and
that is unanswerable in the prepare-only modes, where the agent has no
evidence in front of it and guesses. The ask stops at the transition,
uniformly: one sentence that holds for every mode is worth more than a
carve-out for the compaction, which keeps the session alive and could
legitimately look past it. Nothing about the memory commit rides on the answer
any more, so a wrong guess costs a parent commit that is made or skipped, not
an approved summary that goes unread.

**The directive points at the skill and holds no copy of the protocol.** The reader is a
fresh agent, so what it needs is the skill's name; the command, the file
formats and the hooks gitlore once consumed are mechanism it cannot act on, and
text that carries them is verified and narrated back. Nothing is named that
would need forbidding.

**With nothing to approve, the wrap-up completes in a single turn.** No
detection round-trip exists between deciding and writing: the checkpoint is
unconditional, and it decides for itself whether memory or a ledger is in
play. When memory *is* pending, the directive asks for approval — a user
response, which ends the turn — and a driven transition is therefore held
and released only in the turn after the answer, or it would compact or
clear away the conversation the answer applies to. Any rebalancing of the
gitlore seam must preserve both halves.

### Rejected alternatives

**Detecting commit awareness in the checkpoint, and defaulting the answer**
— a transcript scrape is the maintenance trap this design already refuses,
and a slash-command name is not the question; a default is the answer given
by an agent that has not thought about it, and thinking about it is the
entire contribution. A third mode value would branch identically and only
rename a shade of prose.

**A `PreCompact` hook for the memory flush** — `PreCompact(manual)` can
annotate or block a compaction but cannot run an agent turn, and the flush
needs one: summarize, get approval, commit. It stays a skill
the user runs before compacting, where that turn exists. `precompact` commits
memory before the compaction, because the summary the compaction leaves is a
paraphrase of the conversation.

**Merging handoff into gitlore**, **moving the checkpoint into gitlore**
behind a `command -v` lookup, and **gitlore superseding handoff** — distinct
timescales and machinery for the first; the detection round-trip the
packaging exists to avoid for the second; for the third, supersession means
gitlore carries all of handoff's machinery, vendored and kept in sync.
