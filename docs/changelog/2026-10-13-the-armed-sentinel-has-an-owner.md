# The armed sentinel has an owner

2026-10-13.

## What happened

A driven clear armed by a `with-commit` handoff never ran. The sweep record
added earlier the same day ([The sweep leaves a
record](2026-10-13-the-sweep-leaves-a-record.md)) named the remover:

```
2026-10-13T17:38:01Z	sweeper=2254740a-…	state=armed	owner=-	kind=clear	age=2s	cwd=/Users/david/code/handoff
```

A different session, two seconds after the write, while the owning turn was
still running. The harness starts a background session in the same root after a
`git commit` (the commit review). That session runs `report-drive-failure.sh` on
its own `UserPromptSubmit`, sees an `armed` file, and sweeps it as one that
outlived its turn.

## The premise that was wrong

The sweep rested on one claim, stated in
[A stale autocompact is one a later turn can
see](2026-07-22-stale-autocompact.md): a `UserPromptSubmit` that can see an
`armed` file is by construction a turn later than the one that wrote it. That
holds within one session. It does not hold across sessions sharing a root, and
the hook runs in every one of them. The `held` rule from [Held names its
owner](2026-08-10-held-names-its-owner.md) made the same mistake on the other
state: it took "another session is taking prompts in this repo" to mean that the
owner was gone, and swept the file as abandoned. A background review session
taking a prompt says nothing about the owner.

## The change

**`armed` names its owner**, exactly as `held` does: line 1 is
`armed <session-id>`, one id, required. `pending` stays ownerless, because
past the take the transition belongs to the confirming `SessionStart` in
whichever session it opened. `handoff_drive_read` requires the owner on `held`
and `armed` and rejects one on `pending`. `handoff_drive_arm` writes the line it
is given. `handoff-approved` passes `armed <owner>` on, because the session that
approved is the one whose turn end takes the transition. `drive-take.sh` writes
a bare `pending`. `checkpoint.py` now needs `CLAUDE_CODE_SESSION_ID` for every
sentinel it composes, armed or held, `autoname`'s `rename` included, and refuses
before writing anything when it is unset.

**Only the owner's turn end takes it.** Leaving a live owner's file at another
session's prompt is not enough on its own, because that session's turn ends a
few seconds later. Its `turn.complete` would run `drive-take.sh`, which took any
`armed` file, and the owner's `/rename` and `/clear` would run in the review
session. So the mod now records the `Stop` event's `session_id` beside its cwd
and passes it to `drive-take.sh <cwd> <session-id>`. The script takes an `armed`
file only when its owner is that session. With no session id it takes nothing.
The plan it prints is unchanged, so the fixtures are too. `just mod-smoke` now
hands `claude -p` a `--session-id` and writes the sentinel owned by it. A row
whose sentinel names a different id fails, which shows the id really arrives
from the host's `Stop` event.

> **Superseded 2026-10-14** (see [Cross-session limits,
> documented](2026-10-14-cross-session-limits-documented.md)) on the `held`
> column alone: another session's `held` file is never swept on liveness, live
> owner or not, since it waits on a human approval of unbounded length; a dead
> owner's is left for the next checkpoint to replace, and `abandoned` is gone.
> The `armed` column stands.

**The sweep asks whether the owner is live.** For `armed` and `held`:

| owner | `armed` | `held` |
|---|---|---|
| this session | swept as an aborted turn | kept |
| another session, live | left untouched, nothing said | left untouched, nothing said |
| another session, not live | swept as stale | swept as abandoned |

A malformed file is still swept, and a stranded `pending` is still cleared
only by the failure report. The sweep record now shows the owner of an `armed`
file too.

## Liveness is a heuristic

`handoff_owner_live` takes the hook input's `transcript_path`, which the hook
now reads NUL-terminated like its other fields. The owner's transcript is
`<owner>.jsonl` in the same directory, and it counts as live when that file's
mtime is within `HANDOFF_OWNER_LIVE_SECS` of now, 600 seconds by default. The
variable can be overridden, which the tests use. With no `transcript_path` in the
input, an owner id that is not a plain file name, or no transcript for the
owner, the owner is not live and the file is swept as before.

The 2026-08-10 entry rejected an age-based sweep of a `held` file. This rule is
not that one. It never looks at the sentinel's age. It looks at whether the
session named on line 1 is still writing its transcript. The own-session case is
untouched: the owner's own next prompt still sweeps its aborted `armed` file
however fresh its transcript is, and that stays the exact discriminator it was.

The heuristic has known ways to fail:

> **Superseded 2026-10-14** (see [Cross-session limits,
> documented](2026-10-14-cross-session-limits-documented.md)) on the bullet
> below: a `held` file is no longer swept on liveness, so an owner idle past
> the window keeps it.

- **An owner idle past the window.** A `held` file waits on an approval. If the
  owner sits idle for more than 600 seconds before answering, another session's
  prompt sweeps the file as abandoned. That is the same outcome every
  cross-session sweep had before this change, so this case is no worse than it
  was.
- **An owner whose transcript goes quiet while it works.** Any stretch of
  more than 600 seconds in which the owner's turn writes nothing to its own
  transcript would read as gone. A long subagent dispatch is the likely
  candidate, since the subagent's messages go to a transcript of their own.
  This is not observed: [Nudge the boundary at a context-size
  threshold](2026-08-01-context-threshold-trigger.md) records only that the
  parent's newest usage sample is stale during a dispatch. A sentinel is composed
  by the turn's last call, so a live `armed` file and a long dispatch rarely
  overlap.
- **A transcript in another directory.** Transcripts are grouped by project
  directory. An owner whose transcript sits somewhere else reads as not live,
  and its file is swept. That is again the earlier behaviour.

Each of these failures makes the sweep remove a file it should have kept. That
is what the code did before this change, so no case is made worse. The reverse
error, keeping a file whose owner is gone, needs a transcript written less than
600 seconds ago by a session that has quit. No other session's turn end takes
such a file, because `drive-take.sh` checks the owner. The first prompt after
the window closes then sweeps it.

`.claude/autodrive.failed` still has no owner. A live session's prompt therefore
consumes and reports a drive failure recorded by another session. That is
unchanged by this entry.
