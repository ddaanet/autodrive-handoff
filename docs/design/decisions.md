# Design decisions

Part of [handoff — Design](../design.md).

**Extraction is deterministic; judgment is the agent's.** The plugin
captures the two fields `/compact`, Session Memory, and training cannot
supply. It does not add a third summarisation layer.

**The task file is checkpoint-only; the todo file is not.** They look alike
and are not. The task file is authored fresh from the conversation at every
boundary, so a prior copy on disk is only something to be read, extended, or
partially edited instead of replaced — hence one writer and a hard guard.
The todo file is a ledger the agent maintains all session; wiping it
destroys the half of the frame a `/clear` discards outright, and after a
compaction the context it would be re-authored from is a paraphrase. One
protocol for both was an artifact of their sharing one activation hook.
[One channel, one writer](../changelog/2026-07-27-one-channel-one-writer.md)

**Both files are tracked, and for the same reason.** `handoff-task.md` pairs
with a gitlore memory commit as an in-history record; `## Current task` and
`## Remaining` are two sections of one snapshot, and tracking one while
discarding the other puts half a frame in history — the half naming work not
yet done, which is what a reader of the trail is looking for.
[Overflow deserves the same
persistence](../changelog/2026-07-23-overflow-deserves-persistence.md)

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

**Nothing that asks whether an action took effect reads the pane.** Every
pane-derived predicate is a guess about undocumented chrome, and three
independent ones failed: a stale scrollback timer reading as busy, a queued
submit showing no spinner, a 103-second compaction showing none either.
Confirmation comes from harness-authoritative signals — a file the
transition's own `SessionStart` consumes, or the session transcript. The
rule holds without exception: the rename was the last holdout, confirming by
grepping the pane for the title's first 20 characters, which matches
whenever the title is on screen for any other reason. It now counts
`custom-title` entries in the transcript, and the harness's own auto-titling
writes a distinct `type`, so an exact match cannot false-positive on it.
[The submit signal, a third
time](../changelog/2026-07-22-confirm-the-compaction.md)

**The armed transition is one file whose body names the transition.** One
composer, one session, at most one transition in flight — so the invariant
needs somewhere to live, and the filename is not it. While identity sat in
the name (`autorename`, `autocompact`), each instance cost a full parallel
pipeline: a constant pair, a validator, a `Stop` arm, a watcher, a failure
channel, a stale sweep. Two `Stop` hooks would then race for one composer
whenever both files existed, and nothing anywhere represented the fact that
they could not both be armed. Moving the kind into the body makes the
invariant structural, and collapses three watchers into one walker.
[Driven transitions](../changelog/2026-07-29-driven-transitions.md)

**The transition carries its own state.** There is exactly one transition in
flight at a time, and two filenames were one object at two points in its
life — so every gate read the point it cared about by choosing a name, and
the machine between them existed only as `mv` calls scattered across four
hooks. Line 1 of `.claude/autodrive` is the state and the gates are state
checks, which is the same guarantee stated directly: `Stop` will not re-arm
something already in flight, and the sweep will not take something
legitimately mid-window. Adding a state is now a value, not a filename and
four new gates. The state being content rather than a name also makes a
wrong one writable, which is why the file has a single writer: the
checkpoint composes it, and a direct agent Write or Edit is denied outright.
[One transition, one file, explicit
state](../changelog/2026-08-03-one-transition-one-file.md)

**Observability is not gated on the happy path.** A clean run says nothing
about whether a dirty one would be noticed, and the failing run is exactly
the one nobody is watching. Every non-delivery path a watcher can observe
itself writes a reason to a file. Nothing is inferred from state that is
legitimately present (a file in state `pending` during the whole Stop →
compaction window): a false-positive-free signal is worth the tail of
watchers killed outright.
[A detached watcher's failure has to become a
file](../changelog/2026-07-20-watcher-failure-becomes-a-file.md)

**A foreign tool's state file is detected by liveness, not presence.**
Layouts move and the old path becomes a declared stray; abandoned files are
never cleaned up. Presence alone false-positives, and the harm is a directive
naming another plan's file as this session's ledger. Detection is read-only
and fails open.
[An orphaned ledger hijacks the
handoff](../changelog/2026-07-26-orphaned-ledger.md)

**A foreign ledger scopes the todo file; it does not replace it.** An SDD
ledger holds the tasks of one plan and is deleted with it. `handoff-todo.md`
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
act the checkpoint prints: after it so it carries the handoff files the
checkpoint staged, and before the arming instruction so the transition is
released only once it has landed.
[Deciding makes zero tool calls, stated
once](../changelog/2026-08-11-decide-with-zero-tool-calls.md),
[Memory moves inside the deciding
step](../changelog/2026-09-17-memory-moves-inside-the-deciding-step.md),
[The directive owns the
procedure](../changelog/2026-09-18-the-directive-owns-the-procedure.md)

**The composer row is identified by its U+00A0 gap.** The TUI pads its composer
glyph with a no-break space; a shell prompt pads the same glyph with an ordinary
one. That single character is what separates a live composer from a `❯` sitting
in a prompt or in scrollback, and without it the boot gate opens at the shell
and a driven restart's continuation is typed into a terminal reading nothing.
The gap's *width* stays derived from the captured line, so what is pinned is the
one value that is not layout — and the evidence it can carry that weight is that
it has already been what separates a real pane from a composed one, in
2026-08-13's inverted `is_typing`. The direction of failure is the other half: a
Claude Code that stops emitting it leaves no row reading as a composer, so
nothing is typed and the walker reports, with `just tui-conformance` seeing it
before production does. [The mechanism](driving-the-tui.md), [The composer row
carries its own
gap](../changelog/2026-09-22-the-composer-row-carries-its-own-gap.md)

**Nothing about the exiting process is read.** A driven restart once
identified it by a bounded parent-chain walk, to replay its argv — `$PPID`
inside a hook is the `/bin/sh -c` wrapper Claude Code spawns, whose argv is
the hook command line, so the naive reading relaunched the hook itself. The
walk fixed that and the replay then compounded the launcher's flags one copy
per restart, so both are gone: the line is composed from the session id alone,
and the one thing still needed from that process — the moment it lets go of
the terminal — is read from the pane, not from the process table.
[The relaunch stops replaying argv](../changelog/2026-08-14-the-relaunch-stops-replaying-argv.md)
