# Sessions sharing a root

Part of [handoff — Design](../design.md). The sentinel's states, the take and
the sweep are in [Driving the transition](driving-the-transition.md); this node
holds what matters only when a second session runs in the same root: whose
sentinel it is, when another session's prompt may sweep it, what the sweep
leaves on record, and what stays unsafe.

## The owner

Every session sharing the root runs the same hooks and the same mod — the
background session the harness starts after a `git commit` among them — so the
owner is what tells one session's sentinel from another's.

## Liveness

The prompt-time sweep of an `armed` sentinel ([Reporting a failure, sweeping a
stale sentinel](driving-the-transition.md#reporting-a-failure-sweeping-a-stale-sentinel))
runs on the owner's own next prompt after an aborted turn. Another session's prompt can arrive while the
owning turn is still running too. For a file owned by another session the hook
asks whether that session
is **live** — its transcript, `<owner>.jsonl` beside the one in the hook input's
`transcript_path`, written within `HANDOFF_OWNER_LIVE_SECS` (600 s by default).
That question is asked of `armed` alone, which lives only until its owner's
turn ends. A live owner's `armed` file is left untouched and nothing is said (the sweep
classifies it as the state `foreign`, which it never removes);
one whose owner is not live (stale or missing transcript, or no
`transcript_path` in the input) is swept as in [Reporting a failure, sweeping
a stale sentinel](driving-the-transition.md#reporting-a-failure-sweeping-a-stale-sentinel).
Liveness is a heuristic,
and each way it can be wrong sweeps an `armed` file that should have stayed —
an owner turn that writes nothing to its transcript for the whole window.
The likely cause of such a stretch is a long subagent dispatch, whose messages
go to a transcript of their own (not observed). A transcript in another
project directory also reads as not live, and its file is swept. The reverse
error, keeping a file whose
owner has quit, needs a transcript written inside the window by a session that
is gone, and no other session's turn end takes such a file, since
`drive-take.sh` checks the owner; the first prompt after the window sweeps it.

Before the owner, the sweep rested on the premise that a `UserPromptSubmit`
which sees an `armed` file is a turn later than the one that wrote it. That
holds within one session only, and there only for a prompt not queued into the
arming turn ([A prompt queued into the arming turn](queued-prompts.md)); the
hook runs in every session sharing the root, and a background review session's
prompt, two seconds after the write, swept a live owner's file as one that
outlived its turn.

## The `held` exemption

A `held` file is never swept on liveness, whoever owns it. It waits on a human
approval, which takes as long as it takes, and an idle transcript is exactly
what a session waiting on its user looks like. A dead owner's `held` file stays
on disk: it is a few short lines, arms nothing by itself (`handoff-approved`
refuses a held file another session owns), and the next checkpoint in the root
replaces it.

## The sweep's record

Each removal the sweep makes (and each cancel by `drive-cancel.sh`) also appends a line to `.claude/autodrive.swept`:
time, the removing session, the file's state, owner, kind and age, and the
cwd. The sweep's report lands on the removing session's own channels, which
the session that composed the file never sees, and background sessions
sharing the root (the commit review) run this hook too; without the record a
vanished sentinel names no remover. It is newest first, trimmed to 50 lines,
never consumed, and a failed write never blocks the sweep. `.claude/` is the
agent's to write, so the record is never followed through a symlink: one that
is a link, or not a regular file, is left alone and nothing is recorded, the
old record is read through one `O_NOFOLLOW` open rather than a test and a
read, and the rewrite goes through a `mktemp` file beside it rather than a
fixed name a planted link could redirect, renamed over the record by
`os.replace`, which replaces a link put there meanwhile where `mv` would move
the file into a directory it names. It says who took the file and how old it was; it
does not decide whether the sweep was right.

## Limits

The owner keeps one session from running or sweeping another live session's
transition. It does not make a root safe for two sessions at once, and the
rest is a known limit rather than a defect: making it safe needs per-session
sentinels or checksums, out of proportion to a setup a worktree per session
avoids (see [Rejected alternatives](#rejected-alternatives)).

- **Checkpoint against checkpoint.** The checkpoint renames its sentinel over
  whatever is there. A later checkpoint in the root replaces an earlier
  session's sentinel, and that session's turn end finds a file another session
  owns and takes nothing, silently.
- **`TASK.md` and `TODO.md` are last-writer-wins.** Each checkpoint writes what
  it is given.
- **A `.claude/` shared between roots**, by symlink or otherwise, is
  unsupported. `pending` is ownerless by necessity — the session after a
  `/clear` has a new id, so the file cannot name it — and the other root's
  loader can consume it. The owner on `armed` and `held` does not cover it.
- **`.claude/autodrive.failed` has no owner.** The mod's record of a rejected
  line names no session, so a live session's next prompt consumes and reports
  a failure another session recorded, and clears that session's stranded
  `pending`.

The mitigation is one session per root at a time, or a worktree per session:
the root is the enclosing worktree ([Scoping](scoping.md)), so each has its own
`.claude/`, `TASK.md` and `TODO.md`.

## Decision

**A sentinel names its owner, and only the owner judges it stale.** Every
session sharing the root runs the same hooks and the same mod, the background
session the harness starts after a `git commit` among them, so seeing a
sentinel says nothing about whose it is. `held` and `armed` carry their owner on
line 1. Only the owner's turn end takes an `armed` file, and only the owner's
prompt sweeps one as an aborted turn, unless the prompt was queued into the
arming turn. Another session sweeps an `armed` file
only once the owner is not live by its transcript's mtime. That test is a
heuristic, and every way it can be wrong sweeps a file that should have
stayed, so it is not applied to `held`, which waits on a human for as long as
that takes: no session ever sweeps a `held` file, its owner included, and a
dead owner's is replaced by the next checkpoint.

## Rejected alternatives

**A session-id sidecar or a recency timeout for a stale sentinel** —
the most likely trigger is an Esc in the *same* session, so the id matches
and the next `Stop` arms it anyway; a timeout is a guess about how long a
turn may run, and a wrong guess silently drops a wanted compaction. Both stay
rejected for the owner's own sentinel, which its next prompt sweeps as an aborted turn
unless that prompt was queued into the arming turn. Across sessions the owner
rides on line 1 rather than in a sidecar, and what is timed is the owner's transcript, never the sentinel.

**Per-session sentinels or checksums for sessions sharing a root** — one
sentinel per session, or a checksum the take compares before rewriting. Each
closes one race (a later checkpoint replacing an earlier session's sentinel)
at the cost of a second file per session or a compare-and-swap every bash
reader would implement, and none touches `TASK.md` and `TODO.md`, which are shared state by
design: two sessions writing one task frame conflict whatever the sentinel
does. The complexity is out of proportion to a setup a worktree per session
already avoids. A lock was first ruled out here with them and has since been
adopted for a narrower race, between the actors of one session's sentinel, the
sweep and the take ([The sentinel's lock](driving-the-transition.md#the-sentinels-lock));
it does not make a root safe for two sessions.
