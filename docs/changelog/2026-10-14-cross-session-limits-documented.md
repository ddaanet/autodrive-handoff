# Cross-session limits, documented; the held exemption widened

2026-10-14.

## The question

A review of the sentinel's cross-session handling, after [The armed sentinel
has an owner](2026-10-13-the-armed-sentinel-has-an-owner.md), listed the ways
two sessions sharing one root still lose work:

- **Checkpoint against checkpoint.** `checkpoint.py` renames its sentinel over
  whatever is at `.claude/autodrive`. When two sessions checkpoint in one root,
  the later one replaces the earlier one's sentinel, and the earlier session's
  turn end finds a file another session owns and takes nothing, silently.
- **`TASK.md` and `TODO.md` are last-writer-wins.** Each checkpoint writes the
  content it is given; a second session's wrap-up replaces the first's.
- **The take is not atomic.** `drive-take.sh` reads the sentinel, checks state
  and owner, then rewrites line 1 (`handoff_drive_arm` reads the lines below
  line 1 again at that moment). A checkpoint landing between the two is turned
  `pending`, or removed for `rename`, under the earlier plan.
- **A `held` file swept on an idle transcript.** Another session's `held` file
  was swept as abandoned once its owner's transcript was quiet for
  `HANDOFF_OWNER_LIVE_SECS` (600 s). A held file waits on a human approval, and
  an idle transcript is exactly what a session waiting on its user looks like,
  so a long approval wait in one session lost its transition the moment
  another session in the root took a prompt; `handoff-approved` then exited 2
  on the absent file.
- **A `.claude/` shared between roots** (a symlink from one worktree to
  another's, or any other sharing). The owner on `armed` and `held` tells
  sessions apart, but `pending` is ownerless by necessity: the session after a
  `/clear` has a new id, so the file cannot name it. A `pending` file one root
  wrote can be consumed by the other root's loader.

## The decision

My human partner's call: the design is inherently unsafe across sessions
sharing one root, and making it safe needs locks, per-session sentinels or
content checksums, machinery out of proportion to the setup it serves. The
first three items and the shared `.claude/` are documented as known limits,
not fixed. The mitigation is one session per root at a time, or a worktree per
session: the root is already worktree-scoped (`worktree_root.py`), so each
worktree has its own `.claude/`, `TASK.md` and `TODO.md`.

The `held` sweep is the exception, and is fixed: sweeping a transition that is
blocked on user feedback is not acceptable. **The held exemption changed**:
`report-drive-failure.sh` never sweeps a `held` file on transcript idleness,
whoever owns it. The liveness test applies to `armed` alone, which lives only
until its owner's turn ends. The owner's own `held` file stays exempt as
before. A dead owner's `held` file is left on disk: it is a few short lines,
arms nothing by itself — `handoff-approved` refuses a held file another
session owns — and the next checkpoint in the root replaces it.

| owner | `armed` | `held` |
|---|---|---|
| this session | swept as an aborted turn | kept |
| another session, live | left untouched, nothing said | left untouched, nothing said |
| another session, not live | swept as stale | left untouched, nothing said |

`abandoned` is gone as a sweep state, with its report.

## No refusal of a symlinked `.claude/`

The readers and writers bound their no-follow guarantee at the last
component: a symlinked `.claude/` is read and written where it points, as the
root and legacy files are. Refusing one was weighed and not done. A project
directory the user has accepted as trusted can already ship hooks and
settings, so a link planted there adds no capability an attacker lacked.
Claude Code itself documents symlinks only for `.claude/rules/` and skills
(code.claude.com/docs/en/memory.md, code.claude.com/docs/en/skills.md), not
for `.claude/` as a whole, which has a history of bugs
(anthropics/claude-code#764, anthropics/claude-code#10522). A shared
`.claude/` is unsupported rather than guarded.

## Rejected

- **Per-session sentinels, locks or checksums.** Each fixes one of the races
  above at the cost of a second file per session, a lock with its own stale
  case to sweep, or a compare-and-swap the bash readers would each have to
  implement. None of them touches `TASK.md`/`TODO.md`, which are shared state
  by design: two sessions writing one task frame conflict whatever the
  sentinel does.
- **Recording the root path in the sentinel and checking it on take**, to
  catch a `.claude/` shared between roots. More machinery, and a line in the
  grammar every reader parses, for a setup that is unsupported.

## Also in this pass

Code fixes from the same review, each with its rows: `session-pointer.sh`
creates `/tmp/claude` 0700, as the drift report does, so a group-writable umask
no longer makes the drift note repeat every prompt; a sentinel reader whose
`python3 -I` helper fails is its own outcome (`handoff_drive_read` returns 2),
so no caller removes a sentinel that may be valid; `checkpoint.py` refuses a
sentinel path that cannot take a file (`.claude` a file, `.claude/autodrive` a
directory) before writing `TASK.md` or `TODO.md`, naming the field; a
non-drifted prompt with no drift marker no longer forks `find`; and a `Stop`
with no session id is reported, `drive-take.sh` printing a `kind: null` plan
for an armed file and the mod writing it to `autodrive.failed`; and the mod no
longer writes `autodrive.failed` through a link at the name. The mods API has
no write that replaces rather than follows, so the mod stats the name first
(`isLink`, one call) and skips the record with a toast when it is a link; a
link put there between the stat and the write is still followed, a bound
accepted in a project directory the user trusts. The review's
claim that the sweep record's age `stat` follows a link did not reproduce:
GNU `stat -c` and BSD `stat -f` both report the link itself unless given `-L`.
