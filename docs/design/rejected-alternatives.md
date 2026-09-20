# Rejected alternatives

Part of [handoff — Design](../design.md).

**A bare magic-string sentinel for the payload's actions** — `"@empty"` or
`"clear"` as the value of `task`, instead of `{"action": "clear"}`. It
reinstates the defect class it was meant to retire, one spelling along: a
typo in a bare token is indistinguishable from content, so `"claer"` is
written to the file as the task frame's body, silently, exactly as `null`
silently meant "no-op". `{"action": "emty"}` is a schema error naming the
field, because the object shape is what makes the value's role explicit
enough to check. This is the first shape considered at the proof pass, and
the one a future session will re-propose.
[The payload names its actions](../changelog/2026-09-07-the-payload-names-its-actions.md)

**Loading via an `@.claude/handoff.md` reference** — the reference is
resident in every turn and cannot be conditional. `SessionStart` +
`additionalContext` injects once, only when there is something to inject.
[Original design](../changelog/2026-05-19-original-activation-and-loading.md)

**A generated `handoff.md` artifact** — a non-versioned twin shadowing a
versionable source, which also inlined raw transcript into anything that
committed it. The frame is assembled in memory at read time instead.
[Read-time assembly](../changelog/2026-06-05-read-time-assembly.md)

**A `PreCompact` hook for the memory flush** — hooks are mechanical and the
flush is judgment; `PreCompact(manual)` can annotate or block a compaction
but cannot run an agent turn.
[Session compaction](../changelog/2026-07-12-session-compaction.md)

**Merging handoff into gitlore**, **moving the checkpoint into gitlore**
behind a `command -v` lookup, and **gitlore superseding handoff** — distinct
timescales and machinery for the first; the detection round-trip the
packaging exists to avoid for the second; for the third, supersession means
gitlore carries all of handoff's machinery, vendored and kept in sync.
[Session compaction](../changelog/2026-07-12-session-compaction.md)

**Live `git status` in `load-handoff.sh`**, and **reorder + amend** (commit,
regenerate the handoff, amend) — the first adds a git shell-out to a pure
assembler for a content problem; the second reopens a closed artifact and
breaks the paired in-history record. Machinery to make a wrong fact accurate.
[Commit status excluded from the task
frame](../changelog/2026-06-24-commit-status-excluded.md)

**Trusting the raw `.cwd` field**, or **recording the root via
`WorktreeCreate`/`CwdChanged`** — the first drifts with `cd` and `/add-dir`;
the second is observational, with no clean per-worktree storage, and fragile
against the stateless `.git` walk.
[Per-worktree handoff
root](../changelog/2026-06-09-per-worktree-handoff-root.md)

**A session-id sidecar or a recency timeout for a stale sentinel** —
the most likely trigger is an Esc in the *same* session, so the id matches
and the next `Stop` arms it anyway; a timeout is a guess about how long a
turn may run, and a wrong guess silently drops a wanted compaction.
[A stale autocompact is one a later turn can
see](../changelog/2026-07-22-stale-autocompact.md)

**Detecting commit awareness in the checkpoint, and defaulting the answer**
— a transcript scrape is the maintenance trap this design already refuses,
and a slash-command name is not the question; a default is the answer given
by an agent that has not thought about it, and thinking about it is the
entire contribution. A third mode value would branch identically and only
rename a shade of prose.
[Commit awareness](../changelog/2026-07-25-commit-awareness.md)

**Injecting the remainder at the first `UserPromptSubmit`** to place a new
user task ahead of it — position is a weak lever (recency argues the other
way), explicit conditional wording is the strong one, and it needs a
once-per-session latch on a per-turn hook.
[A place for the todo list](../changelog/2026-07-22-a-place-for-the-todo-list.md)

**Accepting SDD's pre-6.2.0 flat ledger path for back-compatibility** — it
honours the bug, since the current skill guarantees such a file is somebody
else's leftover. Gating on the named plan file still existing was rejected
too: it false-negatives on a plan that landed and was tidied away.
[An orphaned ledger hijacks the
handoff](../changelog/2026-07-26-orphaned-ledger.md)

**Letting the plan's tasks live in both files**, tracked in the ledger and
mirrored into `handoff-todo.md` — two records of one thing drift, and the
stale one gets believed. Excluding the overlap costs nothing, which is why
the boundary is drawn there rather than around the file.
[The ledger and the todo file are different
scopes](../changelog/2026-08-08-ledger-and-todo-are-different-scopes.md)

**Merging the `PostToolUse(Write|Edit)` scripts** into one — they share a
preamble, now factored into `handoff_match_target()`, but not a job.
[Consolidation pass](../changelog/2026-07-20-consolidation-pass.md)

**A parallel pipeline per transition** — the driven clear's first draft:
`.claude/autoclear` beside `autocompact`, its own validator, `Stop` arm,
watcher, failure channel and stale sweep. Sibling-over-parameterisation is
house style and the per-kind validation rules genuinely do differ, which is
why the kind line survives into the unified format. What does not differ is
the pipeline around them. Also rejected: **omitting `/clear` from the
sentinel body** as ceremony (true only while the filename named the
transition), **naming the skills `compact` and `clear`** (namespaced anyway,
so the short name is never available and the collision is paid for in every
doc sentence), and **`autocompact`/`autoclear` as skill names** (collides
with the harness's own threshold auto-compaction, a real named feature).
[Driven transitions](../changelog/2026-07-29-driven-transitions.md)

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
[The directive owns the
procedure](../changelog/2026-09-18-the-directive-owns-the-procedure.md)

**Keeping the sentinel a skill-body write** once the transition became a
payload field — a minimal diff, but the fields would then be advisory: the
checkpoint could validate the combination and nothing more, the line shapes
would stay as prose in two skill bodies, and arming discipline would stay a
rule the agent is asked to follow rather than one the code enforces. Also
rejected: **printing the sentinel for the agent to write when deferring**
(transcription through the model on the one path where correctness matters
most), **a second full checkpoint call carrying the resolved gate** (it
deadlocks — under `with-commit` the memory worktree is still dirty when the
gate resolves, so the second call re-emits the same directive and refuses to
arm), and **`--arm` as a flag on `handoff-checkpoint`** (overloads a command
whose contract is "read a payload on stdin" with one that reads nothing).
[Transitions become modes](../changelog/2026-08-05-transitions-become-modes.md)

**Injecting the frame on any compaction where one exists**, closing the
auto-compaction gap for free — but `handoff-task.md` is durable and
git-tracked and sits on disk across days of unrelated work, so this injects
a stale frame into every threshold compaction in every session in the repo,
unrequested and mid-session. The asymmetry is principled: compaction is the
one boundary the harness enters on its own, so it is the one that needs a
signal of intent. Also rejected: **prepare-only with a driven continuation**
— a sentinel whose before-lines are empty but whose after-line is not. Cheap
and appealing, but a skill that types one of the two lines has no sentence
that describes it.
[Driven transitions](../changelog/2026-07-29-driven-transitions.md)

**Every way of identifying the exiting `claude` process** — its argv was once
replayed as the relaunch line, and three candidates were weighed for finding
it: the hook script's grandparent (the `/bin/sh -c` wrapper survives or is
exec-optimised away at the shell's discretion, so a fixed depth is the same
brittleness under a different constant), a parent-chain walk by argv[0]
basename (shipped, then withdrawn), and tmux's `#{pane_pid}` (exact and
indifferent to the process's name, but the composer ran before the tmux check
and had to serve the not-in-tmux paste path too, where there is no pane to
ask). The whole question is closed rather than settled: the line is composed
from the session id alone, so nothing identifies that process at all.
[Restart drive repair](../changelog/2026-08-13-restart-drive-repair.md),
[The relaunch stops replaying argv](../changelog/2026-08-14-the-relaunch-stops-replaying-argv.md)

**Lengthening `HANDOFF_WATCHER_SHELL_SETTLE`** — tuning a constant against
an unbounded shutdown. The failure returns under load, and it is silent: the
pane looks untouched.
[Restart drive repair](../changelog/2026-08-13-restart-drive-repair.md)
