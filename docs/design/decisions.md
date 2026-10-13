# Design decisions

Part of [handoff — Design](../design.md).

**Extraction is deterministic; judgment is the agent's.** The plugin
captures the two fields `/compact`, Session Memory, and training cannot
supply. It does not add a third summarisation layer.

**Both files are plain files; only the sentinel is guarded.** The task file
needs no protection from the agent that authors it. The checkpoint replaces it
whole at every clear boundary, so nothing a direct edit leaves behind survives
the next one, and until then it is a note the next session reads, which is
what the todo file is too. So neither file is guarded, gitignored or staged by
a hook, and a guard, two stagers and a manifest are machinery the design does
without. The sentinel is the different case and keeps its guard: its state is
content, a wrong one is writable, and its lines are run as commands.
The todo file stays a ledger the agent maintains all session, never
regenerated from a paraphrase.
[One channel, one writer](../changelog/2026-07-27-one-channel-one-writer.md),
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

**Both files are tracked, and for the same reason.** `## Current task` and
`## Remaining` are two sections of one snapshot, and tracking one while
discarding the other puts half a frame in history — the half naming work not
yet done, which is what a reader of the trail is looking for. They are tracked
the ordinary way, in the project root: a pending-work list is a `TODO.md`
like any other, and a project that already has one shares it. Nothing stages
them, so the commit that follows a checkpoint carries them because the commit
act names them, and a release refuses while either is dirty.
[Overflow deserves the same
persistence](../changelog/2026-07-23-overflow-deserves-persistence.md),
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

**The task is bounded, and the bound is set from the residual.** The template
asked for a task of "usually one sentence" and measured task files had a
median body of 872 characters and a 90th percentile of 2529: advice does not
hold under work pressure, so the checkpoint enforces a cap and refuses a list.
The number comes from what a task file holds once everything with another
home has gone there — the plan and open decisions to the todo, standing rules
and conventions to memory through its approval gate, finished work down to
one sentence. That residual has a 95th percentile of 867 characters, and 1000
is the first round number above it. A cap fitted to how often raw files
exceed it would have measured the symptom, and the figure moved by a factor
of three with the choice of sample. **Reopen if** the residual moves: the
method and its scripts are in the plan's `reports/overflow/`.
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

**The old paths are read and moved, and the bridge retires by a condition.**
A repository that crossed the move to the root keeps its frame under
`.claude/handoff-task.md` and `.claude/handoff-todo.md`, and a loader that
ignores those names reports an empty frame for one that is stranded. So per
half the loader reads the root file when it has a body and the legacy file
otherwise, and the checkpoint moves a legacy todo onto `TODO.md` or removes a
legacy file its write would leave to be loaded again, inside plan resolution
so nothing moves unless both halves resolve. The root file wins when it has a
body: the legacy file is left as it is and the agent is told it is ignored,
with no advice to delete it. Both ends decide by body (`is_empty_body`) and
shadowing by the legacy file's existence. The checkpoint does no git work, so
under `with-commit` it prints the `git rm --cached` line that makes git record
a rename, as `git -C <root> rm …` over paths relative to
the root, which runs from any directory. The fallback is a
bridge: it goes once no sibling repository still has `.claude/handoff-*.md`,
with no version in code, docs or tests, and `grep -rni legacy scripts/ tests/`
starts the one deletion pass. **Reopen if** the condition is not what ends it:
a repository that keeps a shadowed legacy file is told so at every start, by
design.
[Legacy paths are read, and the checkpoint moves them](../changelog/2026-10-11-legacy-paths-are-read-and-moved.md)

**The compact boundary carries no task.** A compaction produces its own
account of the task, the summary, and a snapshot written just before it is a
second one: on disk beside the first, liable to disagree with it, and
re-injected at the next session start after the work has moved on. So
`precompact` takes no `task` and removes the file. What has to cross verbatim
— a commit range, a checklist — goes in the todo file or in the `compact`
focus directive, which is what the task file was standing in for when the
todo file did not exist.
[One task file, two
transitions](../changelog/2026-07-20-one-task-file-two-transitions.md),
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

**Commit/push status never appears in either file.** The routine wrap-up is
`/handoff` then `/commit`, so any bookkeeping written at handoff time is
falsified by the very next action, lands in history, and is re-injected
stale. This is a content problem, fixed at the template level — the template
has no slot for it — not a remembered prohibition. The legitimate case
("changed X but not committed because tests are red") is an open decision,
stated as the *why*.
[Commit status excluded from the task
frame](../changelog/2026-06-24-commit-status-excluded.md)

**The frame carries no transcript.** Verbatim prior exchanges arrive in
conversational grammar and are read as memory, not as a report; the hazard
scales with volume, and trimming changes length, not register.
[Task frame drops the transcript and file
list](../changelog/2026-07-17-task-frame-drops-transcript.md)

**The agent supplies one fact; the code owns the branch.** Commit awareness
— *does the ask this call serves imply a commit?* — is a fact about the
conversation that no script can see, and everything downstream of the answer
is deterministic. It changes where the memory commit *lands*, and whether
the checkpoint prints a commit act and holds a typed transition behind it.
It does not change what memory *says*: how memory bodies are written,
present-tense truth included, is `gitlore:memory-writing`'s rule, which
holds in every mode and which the memory directive invokes through gitlore's
approval clause. The transition fields are the same shape, which is why they
are fields and not skills.
[Commit awareness](../changelog/2026-07-25-commit-awareness.md),
[Transitions become modes](../changelog/2026-08-05-transitions-become-modes.md)

**Ask the question the request can answer.** The rule this replaced counted
a commit landing in a later session, because it framed the question as where
the memory belongs rather than whether anything present decides it — and
that is unanswerable in the prepare-only modes, where the agent has no
evidence in front of it and guesses. It is also the hazard: withholding
gitlore's trigger defers the memory commit to a parent commit's pre-commit
hook, and a commit on the far side of a `/clear` is owed by no live session,
so the approved summary goes unread and the next session's memory write
stales it. The ask stops at the transition, uniformly — a compaction keeps
the session alive, so a commit named in *its* continuation prompt would in
fact have a live hook, but one sentence that holds for every mode is worth
more than one correctly deferred memory commit.
[Transitions become modes](../changelog/2026-08-05-transitions-become-modes.md)

**Withholding is a mechanism.** The standalone memory commit is reachable
only through one filename, and the `with-commit` directive's reader is a
fresh agent with no other source for it — so saying nothing makes that path
unreachable, while a prohibition would introduce the concept it forbids. The
same cut removes mechanism a reader cannot act on: it does not sit inert, it
gets verified and narrated back.
[Commit awareness](../changelog/2026-07-25-commit-awareness.md)

**A directive is correct only where in the turn it lands.** handoff runs its
checkpoint in the same turn as the writes — deliberately, so the snapshot
costs one round trip — so a directive about *how to write them* arrives
after they exist. precompact reads its directive before it writes. Shared
prompt text is shared only where the flows agree; naming the safe route is
the load-bearing half of any prohibition.
[A directive must fit where in the turn it
lands](../changelog/2026-07-22-directive-fits-where-it-lands.md)

**Hooks are mechanical; anything requiring judgment is in a skill.** A
`PreCompact` hook cannot run an agent turn. A probe cannot see the agent's
task list. Detection that would need a transcript scrape — activation,
commit intent, the todo list — is either asked of the agent or not asked at
all, because keying on tool names in JSONL is a maintenance trap the harness
has already sprung once.

**The armed transition is one file whose body names the transition.** One
session, at most one transition in flight — so the invariant needs somewhere
to live, and the filename is not it. While identity sat in the name
(`autorename`, `autocompact`), each instance cost a full parallel pipeline: a
constant pair, a validator, an arm step, a driver, a failure channel, a stale
sweep. Two arm steps would then race whenever both files existed, and nothing
anywhere represented the fact that they could not both be armed. Moving the
kind into the body makes the invariant structural, and collapses three drivers
into one.
[Driven transitions](../changelog/2026-07-29-driven-transitions.md)

**The transition carries its own state.** There is exactly one transition in
flight at a time, and two filenames were one object at two points in its
life — so every gate read the point it cared about by choosing a name, and
the machine between them existed only as `mv` calls scattered across
several hooks. Line 1 of `.claude/autodrive` is the state and the gates are state
checks, which is the same guarantee stated directly: `drive-take.sh` will not take
something already in flight, and the sweep will not take something
legitimately mid-window. Adding a state is now a value, not a filename and
four new gates. The state being content rather than a name also makes a
wrong one writable, which is why the file has a single writer: the
checkpoint composes it, and a direct agent Write or Edit is denied outright.
[One transition, one file, explicit
state](../changelog/2026-08-03-one-transition-one-file.md)

**A sentinel names its owner, and only the owner judges it stale.** Every
session sharing the root runs the same hooks and the same mod, the background
session the harness starts after a `git commit` among them, so seeing a
sentinel says nothing about whose it is. `held` and `armed` carry their owner on
line 1. Only the owner's turn end takes an `armed` file, and only the owner's
prompt sweeps one as an aborted turn. Another session sweeps it, or a `held`
one, only once the owner is not live by its transcript's mtime. That test is a
heuristic. Every way it can be wrong sweeps a file that should have stayed,
which is the behaviour it replaced, so no case is worse than before.
[The armed sentinel has an
owner](../changelog/2026-10-13-the-armed-sentinel-has-an-owner.md)

**Observability is not gated on the happy path.** A clean run says nothing
about whether a dirty one would be noticed, and the failing run is exactly
the one nobody is watching. The drive runs after the turn that armed it, so a
rejected line has no one to tell; every non-delivery the mod observes itself
writes a reason to a file, and the next prompt reports it. Nothing is inferred
from state that is legitimately present (a file in state `pending` during the
whole window between the take and the transition): a false-positive-free
signal is worth the tail of failures that never reach it.
[A detached watcher's failure has to become a
file](../changelog/2026-07-20-watcher-failure-becomes-a-file.md)

**The drive runs inline at `turn.complete`, never from `Stop`.** The host
refuses `$.command.run` from a call context the turn is waiting on, and a
timer started there inherits the context, so deferring from `Stop` does not
help; under `-p` a timer fires after the session is gone. `Stop` only records the
cwd, which keeps the guarantee that an interrupt arms nothing, and the drive
awaits each command in the first handler the host allows. The sentinel is read
by `drive-take.sh` and by nothing in the mod: one parser, and the atomic state
change is a file operation the mods API does not offer.
[The plugin becomes a mod](../changelog/2026-10-08-the-plugin-becomes-a-mod.md),
[the mechanism](driving-the-transition.md)

**A foreign tool's state file is detected by liveness, not presence.**
Layouts move and the old path becomes a declared stray; abandoned files are
never cleaned up. Presence alone false-positives, and the harm is a directive
naming another plan's file as this session's ledger. Detection is read-only
and fails open.
[An orphaned ledger hijacks the
handoff](../changelog/2026-07-26-orphaned-ledger.md)

**A foreign ledger scopes the todo file; it does not replace it.** An SDD
ledger holds the tasks of one plan and is deleted with it. `TODO.md`
holds work outstanding across sessions, most of it belonging to no plan and
often to another repository. Only their overlap — the plan's own tasks,
copied across — can drift, so only the overlap is excluded. Standing the
whole file down discards every item no ledger will ever carry, in the one
direction a `/clear` cannot recover.
[The ledger and the todo file are different
scopes](../changelog/2026-08-08-ledger-and-todo-are-different-scopes.md)

**The design names no todo tool.** The harness's task-list family is behind
a server-side killswitch and has already changed generations once; an
affordance that can vanish between two sessions on the same binary cannot be
a dependency. The file is the ledger, whatever tracker is live is a cache,
and the cache may legitimately hold more (identity, ordering, per-item
history) because that surplus is boundary-local.
[A place for the todo list](../changelog/2026-07-22-a-place-for-the-todo-list.md)

**With nothing to approve, the wrap-up completes in a single turn.** No
detection round-trip exists between deciding and writing: the checkpoint is
unconditional, and it decides for itself whether memory or a ledger is in
play. When memory *is* pending, the directive asks for approval — a user
response, which ends the turn — and a driven transition is therefore held
and released only in the turn after the answer, or it would compact or
clear away the conversation the answer applies to. Any rebalancing of the
gitlore seam must preserve both halves.

**A context-size nudge was tried and dropped.** `PostToolBatch` fired once a
session's prompt crossed a fixed threshold, injecting a directive naming
`/handoff:precompact`. Dropped rather than fixed: it fired too early on a
prompt that was already large for legitimate reasons, and once right after a
driven compaction against a context the boundary had just shrunk. Sometimes
followed, sometimes ignored — the net was more trouble than the nudge earned.
[Nudge the boundary at a context-size
threshold](../changelog/2026-08-01-context-threshold-trigger.md),
[A compaction invalidates every sample above
it](../changelog/2026-08-09-samples-are-scoped-to-the-compaction.md), and
[the removal](../changelog/2026-08-10-drop-context-threshold-nudge.md).

**Deciding makes no tool call.** `handoff` decides
from the conversation already in context — the agent already holds
everything it needs, and a Read/Bash/Grep call there duplicates work
`handoff-checkpoint` does internally while risking action on state gone
stale by write time. A live session read the rule seconds beforehand and
still `cat`-ed both task files "to check": a general verify-before-acting
habit overrode an instruction that read as descriptive rather than binding.
The rule is one prohibition at the head of the one step that decides and
checkpoints, phrased as an imperative on the next action, with the reason
stated in the matching `## Anti-patterns` entry. Memory writes are not an
exception to it, because they are not part of that step: they are the step
before it, the skill's first, and nothing in them waits on a decision — how
memory is written is gitlore's rule in every mode, so the commit answer
does not set their tense. They still precede the checkpoint call, whose
memory directive keys on a dirty submodule. A commit the ask implies is not
an exception either, because it comes after the checkpoint, as the commit
act the checkpoint prints: after it so it carries the two files the
checkpoint wrote, and before the arming instruction so the transition is
released only once it has landed.
[Deciding makes zero tool calls, stated
once](../changelog/2026-08-11-decide-with-zero-tool-calls.md),
[Memory moves inside the deciding
step](../changelog/2026-09-17-memory-moves-inside-the-deciding-step.md),
[The directive owns the
procedure](../changelog/2026-09-18-the-directive-owns-the-procedure.md)
