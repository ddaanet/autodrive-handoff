# Design decisions

Part of [handoff — Design](../design.md).

The dated records named here are in the `changelog-archive` tag's
`docs/changelog/`.

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
content, a wrong one is writable, and it selects what the mod runs when the turn ends.
The todo file stays a ledger the agent maintains all session, never
regenerated from a paraphrase.
2026-07-27 One channel, one writer,
2026-10-11 TASK.md and TODO.md move to the root

**Both files are tracked, and for the same reason.** `## Current task` and
`## Remaining` are two sections of one snapshot, and tracking one while
discarding the other puts half a frame in history — the half naming work not
yet done, which is what a reader of the trail is looking for. They are tracked
the ordinary way, in the project root: a pending-work list is a `TODO.md`
like any other, and a project that already has one shares it. Nothing stages
them, so the commit that follows a checkpoint carries them because the commit
act names them, and a release refuses while either is dirty.
2026-07-23 Overflow deserves the same persistence,
2026-10-11 TASK.md and TODO.md move to the root

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
2026-10-11 TASK.md and TODO.md move to the root

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
and not before 2026-11-16, a month past the day that first held (2026-10-16),
with no version in code, docs or tests, and `grep -rni legacy scripts/ tests/`
starts the one deletion pass. **Reopen if** the condition is not what ends it:
a repository that keeps a shadowed legacy file is told so at every start, by
design.
2026-10-11 Legacy paths are read, and the checkpoint moves them

**The compact boundary carries no task.** A compaction produces its own
account of the task, the summary, and a snapshot written just before it is a
second one: on disk beside the first, liable to disagree with it, and
re-injected at the next session start after the work has moved on. So
`precompact` takes no `task` and removes the file. What has to cross verbatim
— a commit range, a checklist — goes in the todo file or in the `compact`
focus directive, which is what the task file was standing in for when the
todo file did not exist.
2026-07-20 One task file, two transitions,
2026-10-11 TASK.md and TODO.md move to the root

**Commit/push status never appears in either file.** The routine wrap-up is
`/handoff` then `/commit`, so any bookkeeping written at handoff time is
falsified by the very next action, lands in history, and is re-injected
stale. This is a content problem, fixed at the template level — the template
has no slot for it — not a remembered prohibition. The legitimate case
("changed X but not committed because tests are red") is an open decision,
stated as the *why*.
2026-06-24 Commit status excluded from the task frame

**The frame carries no transcript.** Verbatim prior exchanges arrive in
conversational grammar and are read as memory, not as a report; the hazard
scales with volume, and trimming changes length, not register.
2026-07-17 Task frame drops the transcript and file list

**The agent supplies one fact; the code owns the branch.** The argument is in [The checkpoint directive](the-checkpoint-directive.md#decisions).

**Ask the question the request can answer.** The argument is in [The checkpoint directive](the-checkpoint-directive.md#decisions).

**The directive points at the skill and holds no copy of the protocol.** The argument is in [The checkpoint directive](the-checkpoint-directive.md#decisions).

**A directive is correct only where in the turn it lands.** The argument is in [The checkpoint directive](the-checkpoint-directive.md#where-in-the-turn-a-directive-lands).

**Mechanical logic lives in a script or hook, not in a skill's prose; the
skill body holds judgement only.** Detection, branching and decisions that can
be computed are computed by a script or hook, which emits a structured result
or the agent's instructions. The typical consequence is a skill conditional
removed: a script probes the environment and prints the procedure for the one
cell the call is in, where the skill would state the condition in prose for the
agent to evaluate. The principle moves mechanics out of skills. It is not a bar
on judgement in a hook, and whether a hook may judge is weighed on the facts of
the event: per Claude Code's hook documentation as read on 2026-10-12 (not
run), `PreToolUse` accepts `type: "prompt"` and `type: "agent"` handlers and
`SessionStart` accepts neither. A probe cannot see the agent's task list.
Detection that would need a transcript scrape — activation, commit intent, the
todo list — is either asked of the agent or not asked at all, because keying
on tool names in JSONL is a maintenance trap the harness has already sprung
once.
2026-10-15 The mechanical principle is narrowed; a reviewer waits for a measurement

**The armed transition is one file whose body names the transition.** One
session, at most one transition in flight — so the invariant needs somewhere
to live, and the filename is not it. While identity sat in the name
(`autorename`, `autocompact`), each instance cost a full parallel pipeline: a
constant pair, a validator, an arm step, a driver, a failure channel, a stale
sweep. Two arm steps would then race whenever both files existed, and nothing
anywhere represented the fact that they could not both be armed. Moving the
kind into the body makes the invariant structural, and collapses three drivers
into one.
2026-07-29 Driven transitions

**The transition carries its own state.** There is exactly one transition in
flight at a time, and two filenames were one object at two points in its
life — so every gate read the point it cared about by choosing a name, and
the machine between them existed only as `mv` calls scattered across
several hooks. Line 1 of `.claude/autodrive` is the state and the gates are state
checks, which is the same guarantee stated directly: `drive-take.sh` will not take
something already in flight, and the sweep will not take something
legitimately mid-window. Adding a state is now a value, not a filename and
four new gates. The state being content rather than a name also makes a
wrong one writable, which is why the file's writers are a closed set: the
checkpoint composes it, `handoff_drive_arm` rewrites only its state line, and
a direct agent Write or Edit is denied outright.
2026-08-03 One transition, one file, explicit state

**The continuation is a constant; the agent authors no prompt.** What follows
a driven transition is a yes-or-no field, and `true` makes the composer write
the fixed line `Continue where the previous context stopped.`. Nothing the
agent writes is submitted as the continuation prompt, so that channel cannot
leak the task. At a clear the files are the only carrier: anything the next
session needs is in `TASK.md` or `TODO.md`, or it is gone, and `true` is
refused when neither would have a body. At a compact the summary and the
agent-written focus directive carry too. The skills no longer argue what a
prompt may carry, because the schema leaves nothing to argue.
2026-10-15 The continuation is a constant

**The sentinel carries data, and the mod holds the commands and the prompt.**
The file holds a kind, a `continue` flag and one free-text argument;
`hooks/handoff.ts` maps the kind to `/rename`, `/clear` and `/compact` and holds
the one prompt as a literal. The file once held the slash commands and a prompt
line, and the mod ran whatever the plan listed, so what the mod could run was
whatever the reader's validation let through: any continuation text not
beginning with `/` reached `prompt.submit` as the user, and a reader of the mod
alone could see no limit. Now what the mod can run is checkable from the mod
alone, and no text on disk reaches `prompt.submit`. Whatever writes the file,
the guard on `Write` and `Edit` notwithstanding, reaches only those three
commands with a free-text argument, plus the fixed prompt. The mod still reads
neither the sentinel nor the prompt box, so the rejected second parser stands.
[The sentinel](the-sentinel.md)

**A sentinel names its owner, and only the owner judges it stale.** The
owner rides on line 1 of `armed` and `held`; the argument is in [Sessions
sharing a root](sessions-sharing-a-root.md#decision).

**A prompt queued into the arming turn cancels a `clear` or `compact`, and
spares a `rename`.** A spared `clear` or `compact` would run cleanly, but the
prompt would be lost as handoff state: the files were written before it, its
answer lives only in the context `/clear` discards, and `TODO.md` does not
carry it across a `/compact`. The cancel tells the agent to answer and run the
skill again, so the files catch up first. The turn's `prompt_id` is recorded
at the checkpoint call rather than at every prompt, which would fork on each
one. [A prompt queued into the arming turn](queued-prompts.md),
2026-10-16 A prompt queued into the arming turn

**The sentinel's actors hold a lock across each read-decide-write.** The host
does not order a prompt's sweep against the mod's take, and a sweep that read
`armed` could delete the `pending` file the take had armed meanwhile, then tell
the user the mod never ran a transition that runs. An advisory `flock` makes
each actor's decision and write one step, with a bounded wait that fails open,
since a hook that waits for ever is worse than the race. The lock orders the
actors and not the arrival of a prompt: a prompt after the arming turn's
`Stop` is ordered by the mod's window
([queued-prompts.md](queued-prompts.md#a-prompt-after-stop)). [The sentinel's lock](sentinel-lock.md),
2026-10-16 The sentinel takes a lock

**Observability is not gated on the happy path.** A clean run says nothing
about whether a dirty one would be noticed, and the failing run is exactly
the one nobody is watching. The drive runs after the turn that armed it, so a
rejected command has no one to tell; every non-delivery the mod observes itself
writes a reason to a file, and the next prompt reports it. Nothing is inferred
from state that is legitimately present (a file in state `pending` during the
whole window between the take and the transition): a false-positive-free
signal is worth the tail of failures that never reach it.
2026-07-20 A detached watcher's failure has to become a file

**The drive runs inline at `turn.complete`, never from `Stop`.** The host
refuses `$.command.run` from a call context the turn is waiting on, and a
timer started there inherits the context, so deferring from `Stop` does not
help; under `-p` a timer fires after the session is gone. `Stop` only records the
cwd, which keeps the guarantee that an interrupt arms nothing, and the drive
awaits each command in the first handler the host allows. The sentinel is read
by `drive-take.sh` and by nothing in the mod: one parser, and the atomic state
change is a file operation the mods API does not offer.
2026-10-08 The plugin becomes a mod,
[the mechanism](driving-the-transition.md)

**A foreign tool's state file is detected by liveness, not presence.**
Layouts move and the old path becomes a declared stray; abandoned files are
never cleaned up. Presence alone false-positives, and the harm is a directive
naming another plan's file as this session's ledger. Detection is read-only
and fails open.
2026-07-26 An orphaned ledger hijacks the handoff

**A foreign ledger scopes the todo file; it does not replace it.** An SDD
ledger holds the tasks of one plan and is deleted with it. `TODO.md`
holds work outstanding across sessions, most of it belonging to no plan and
often to another repository. Only their overlap — the plan's own tasks,
copied across — can drift, so only the overlap is excluded. Standing the
whole file down discards every item no ledger will ever carry, in the one
direction a `/clear` cannot recover.
2026-08-08 The ledger and the todo file are different scopes

**The design names no todo tool.** The harness's task-list family is behind
a server-side killswitch and has already changed generations once; an
affordance that can vanish between two sessions on the same binary cannot be
a dependency. The file is the ledger, whatever tracker is live is a cache,
and the cache may legitimately hold more (identity, ordering, per-item
history) because that surplus is boundary-local.
2026-07-22 A place for the todo list

**With nothing to approve, the wrap-up completes in a single turn.** The argument is in [The checkpoint directive](the-checkpoint-directive.md#decisions).

**A context-size nudge was tried and dropped.** `PostToolBatch` fired once a
session's prompt crossed a fixed threshold, injecting a directive naming
`/handoff:precompact`. Dropped rather than fixed: it fired too early on a
prompt that was already large for legitimate reasons, and once right after a
driven compaction against a context the boundary had just shrunk. Sometimes
followed, sometimes ignored — the net was more trouble than the nudge earned.
2026-08-01 Nudge the boundary at a context-size threshold,
2026-08-09 A compaction invalidates every sample above it, and
2026-08-10 Drop the context-size nudge.

**Between deciding and the checkpoint, no tool call.** `handoff` decides
from the conversation already in context — the agent already holds
everything it needs, and a Read/Bash/Grep call on project state there
duplicates work `handoff-checkpoint` does internally while risking action on
state gone stale by write time. A live session read the rule seconds
beforehand and still `cat`-ed both task files "to check": a general
verify-before-acting habit overrode an instruction that read as descriptive
rather than binding. The rule is one prohibition at the head of the one step
that decides and checkpoints, phrased as an imperative on the next action,
with the reason stated in the matching `## Anti-patterns` entry. Wording is
the fix; a hook blocking Read/Bash/Grep between the skill's invocation and
the checkpoint was not built, and is the next escalation if wording proves
insufficient, not further wording tweaks.

Memory writes are the one call that precedes the checkpoint. They are the
step before the deciding one, the skill's first, and nothing in them waits on
a decision — how memory is written is gitlore's rule in every mode, so the
commit answer does not set their tense. They still precede the checkpoint
call, whose memory directive keys on a dirty submodule. Nothing else is
read, not even the plugin's own files: a reference file both skills read on
every call is rejected (see
[rejected alternatives](rejected-alternatives.md)). The todo template and
rules are inlined in both boundary skills, so neither makes a read to draft,
and the window between deciding and the checkpoint holds no call.
A commit the ask implies is not an exception either, because it comes after
the checkpoint, as the commit act the checkpoint prints: after it so it
carries the two files the checkpoint wrote, and before the arming
instruction so the transition is released only once it has landed.
