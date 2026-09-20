# The write path

Part of [handoff — Design](../design.md).

## The seam

`.claude/handoff-task.md` and `.claude/handoff-todo.md` are the durable
side. Both are git-tracked (force-added by a hook; both are listed in
`.gitignore` so *only* a hook can add them). Both are injected verbatim at
`SessionStart`, task first, under one timestamp header — the *frame*,
assembled in memory by `handoff_frame()` in `scripts/_lib.sh` and shared by
the two loaders so the two transitions cannot drift.

- **`handoff-task.md`** — `## Current task` alone. Written **only** by the
  checkpoint; a direct agent Write or Edit is denied by `write-guard.sh`. A
  snapshot of a moment.
- **`handoff-todo.md`** — `## Open decisions` when any remain, plus
  `## Remaining`, open items only. A scratch list the agent edits directly
  all session; the wrap-up only folds in the final remainder. A ledger, not
  a snapshot — open decisions live here rather than in the task file
  because they get revisited and resolved mid-session, same as any other
  open item.

The frame carries no session id, no transcript, no file list, and no
commit/push status. The working set comes from the harness's own
`gitStatus` block at load time.

## One channel, one writer

Both wrap-up skills decide their content and then make exactly one Bash
call: `handoff-checkpoint`, a PATH-resident shim (`bin/`) over
`scripts/checkpoint.py`, taking the whole wrap-up as a schema-validated
JSON payload on stdin — `skill`, `commit`, the boundary's transition field,
`continue`, `rename` at the clear boundary, and `task` / `todo` as a tagged
union: the file's content directly as a string, or an object naming an
action. `task` takes `{"action": "clear"}`; `todo` also takes
`{"action": "keep"}` and `{"action": "edit", "old_string": …,
"new_string": …}`. The task file is authored whole at every boundary, so it
has no edit action, and no keep — a boundary with nothing to carry says so
with `clear`, which is the case an agent used to reach for `null` and get
silence. Both keys are required by key presence: `null` and an absent key
are each a named error, because a spelling that quietly does the wrong
thing is the defect this shape exists to prevent — a wrong one has to fail
loudly rather than acquire a meaning. The action object holds to the same
rule inside itself: its own `action` is read by key presence, so an explicit
`null` is reported as the value it is rather than as an omission, and any key
the named action does not take is a named error rather than a silent
discard. Ignoring one reopens the defect one level down — an agent told
`must be "clear", got "write"` that corrects only the action leaves its
`content` in place, and the frame is removed with nothing said. The payload's
own key set is closed the same way, a level up: a key outside the union any
skill takes is named rather than discarded, since a *misspelled required* key
already fails by key presence while a *superfluous* one — `tasks` beside a
well-formed `task` and `todo` — did not. That check is flat rather than
per-skill, because every known key under a skill that forbids it is already
rejected upstream by a message naming the skill or the transition, and a
per-skill check has no point to run but ahead of those, where it would
replace their wording with a generic one. What is left for it is a key
belonging to no skill's vocabulary, which has nothing skill-specific to say
about it. The two
`required` messages name the whole vocabulary for the same reason: that
branch is what an out-of-date producer sending the retired
`{"file_path": …, "content": …}` shape lands on, so it has to say what to
write instead. There is no `file_path` —
`plan_task`/`plan_todo` compose the real path from `HANDOFF_ROOT`, so a
payload-supplied one would ask the agent to derive a path from a root it
cannot read, only to be checked against the one the write uses anyway. A
violation exits non-zero naming the offending field. The wrap-up is applied
whole or not at all: both halves resolve to a plan — the path, the act, the
body and the manifest lines that record it — before either file is touched,
so every failure the two halves raise leaves the disk as it was.
[The payload names its actions](../changelog/2026-09-07-the-payload-names-its-actions.md),
[Nothing is written until both halves resolve](../changelog/2026-09-13-nothing-is-written-until-both-halves-resolve.md),
[The vocabulary is closed at both levels](../changelog/2026-09-14-the-vocabulary-is-closed-at-both-levels.md)

It gets its root from `HANDOFF_ROOT`, injected into the command's
environment by a `PreToolUse(Bash)` hook (`inject-checkpoint-root.sh`) that
matches any command containing `handoff-checkpoint` or `handoff-approved`,
resolves the root fresh from the payload `cwd`, and rewrites the command to
`export HANDOFF_ROOT=<quoted>; <original>` via `updatedInput` — `export …;`
rather than a bare `VAR=…` prefix, so the value survives a batched command.
The checkpoint refuses when it is unset or not a directory, naming the
unrecognised-invocation cause. Resolving on every call, at the moment the
value is used, replaces an earlier session-keyed pointer file sampled once at
`SessionStart`: `SessionStart(resume)` fires with the *resuming* process's
cwd, before the harness moves the session into its own project dir, so a
sample taken there could stamp the wrong repo onto a pointer read later in
the same session. See
[`docs/changelog/2026-08-10-checkpoint-root-via-updatedinput.md`](../changelog/2026-08-10-checkpoint-root-via-updatedinput.md).

The checkpoint applies the writes, removes any file whose resulting body is
empty, composes `.claude/autodrive` from the transition fields, leaves
`.claude/checkpoint-manifest` behind, and prints on stdout what the agent
does next (see [What the checkpoint
prints](the-checkpoint-directive.md#what-the-checkpoint-prints)). It **changes no git
state** and touches tmux not at all — it queries git read-only and stops
there: it runs in the agent's
sandboxed Bash, where `git add` can leave `.git/index.lock` behind and fail
the *next* command (which in the routine wrap-up is the user's `/commit`),
and where tmux is unreachable. `PostToolUse(Bash)` (`bash-post.sh`) consumes
the manifest instead — `git add -f` for every listed path, deletions
included, and a path it could not stage named on both channels rather than
dropped from the counts — that name carries the whole report, a hook's stderr
on `exit 0` reaching neither audience. A root that is not a git repository at
all is separated ahead of the loop and reported once rather than once per
path: nothing there can be staged, and nothing is wrong. A `D` line for a
path `git ls-files` does not list is skipped rather than attempted: both
files are gitignored, so nothing but a hook ever stages them, and a `git
reset` since the last checkpoint — or a file the user wrote by hand — leaves
the path untracked, so this call's removal emits a `D` for something the
index never held. `git add -f` exits 128 there with `did not match any
files`, and that is the one benign failure in this loop. The guard's own exit
status is read rather than inferred from its empty output, a failing `ls-files`
being a repository `add` could not have staged into either. Staging is all it does: a sentinel the checkpoint
wrote is armed at `Stop` like any other, so spawning the walker here would
type into a live turn, which is the one thing the `Stop` gate exists to
prevent.

`file present ⟹ content pending` is an invariant two writers enforce
(`checkpoint.py` and `write-stage.sh`, the latter through a
`_checkpoint_lib.py --is-empty-body` subprocess spawn so the two cannot
disagree about what counts as empty), not an instruction the agent has to
remember. `checkpoint.py` and `_checkpoint_lib.py` (with `drive_when_idle.py`
and `_watcher_lib.py`, in [Driving the TUI](driving-the-tui.md)) are a
2026-08-10 Python port of what was
`checkpoint.sh` + `_checkpoint-lib.sh`: both did bash's worst work —
structured data, not text streams — and both run once per boundary, never on
a hot path, so the interpreter-startup tax lands where it is cheapest to pay.
The six event hooks that fire on every tool call stay bash. See
[`docs/changelog/2026-08-10-python-split.md`](../changelog/2026-08-10-python-split.md).
