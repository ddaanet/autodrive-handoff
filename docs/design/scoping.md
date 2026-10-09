# Scoping

Part of [handoff — Design](../design.md).

Every cwd-scoped hook anchors on `handoff_root()` — the enclosing linked
git-worktree root derived from on-disk `.git` linkage
(`scripts/worktree_root.py`), falling back to `CLAUDE_PROJECT_DIR` — never
the raw hook-input `.cwd` (drifts with `cd` and `/add-dir`) and never
`CLAUDE_PROJECT_DIR` directly (pinned to the main tree in a worktree
session). So a worktree session owns its own `.claude/`. The resolution is
short-circuited in bash for the trivial cases, so the every-turn hooks skip
the `python3` spawn.

The resolver also reports **which branch** produced that answer — `inside`,
`worktree`, `foreign`, `unrelated` — because the root alone collapses four
different situations into one. `handoff_root_read()` sets the caller's
`HANDOFF_ROOT` and `HANDOFF_ROOT_BRANCH` (the `handoff_drive_read` idiom);
`handoff_root()` is the printing form, since every other caller captures it
in a `$(...)` where a global would die with the subshell. Containment beats
the branch the walk took: a submodule or vendored checkout inside the
project is `inside`, not `foreign`.

The last two labels are **drift** — the session cwd has left the launch repo
while the root, and every handoff file under it, has not. Nothing else
announces that: the environment block, `gitStatus` and the project
`CLAUDE.md` all follow cwd. `report-drive-failure.sh` reports it at
`UserPromptSubmit`, where the root is resolved every turn anyway, because
drift can be transient and a later gate would see nothing while the split
was live for the whole blip. One report per episode: a marker holds the
destination last announced, and returning clears it.

The agent's own Bash cannot do any of this — `CLAUDE_PROJECT_DIR` is unset
there, and a `$PWD` fallback is wrong in exactly the drift case. So a
`PreToolUse(Bash)` hook (`inject-checkpoint-root.sh`) resolves the root the
same way, at the moment a `handoff-checkpoint` or `handoff-approved`
invocation is about to run, and injects it as `HANDOFF_ROOT` into that one
command via `updatedInput`. An earlier design published the root once per
session instead, at `SessionStart`, to a session-keyed pointer file the
checkpoint's Bash could address blind. That sample was taken at the one
moment the cwd does not yet belong to the session —
`SessionStart(resume)` fires with the *resuming* process's cwd, before the
harness moves the session into its own project dir — so it could stamp a
stale or wrong repo onto a pointer a live session then read for its whole
remaining lifetime. Resolving per call has no such moment. See
[`docs/changelog/2026-08-10-checkpoint-root-via-updatedinput.md`](../changelog/2026-08-10-checkpoint-root-via-updatedinput.md).

The drift marker is the plugin's remaining state outside a project, and it
has no owner that outlives the session. `session-pointer.sh` sweeps it (and
whatever stale root-pointer files the retired mechanism already left on
disk) on every `SessionStart`, deleting files older than seven days, scoped
by name to what this plugin writes and by `-maxdepth 1` to the level it
writes them at — the directory is shared and holds files this plugin never
wrote. A `SessionEnd` hook would clean up only the ends that fire one, which
is the opposite of the set that strands a file.

`handoff_match_target()` is the shared preamble of every path-scoped hook:
one jq parse, basename fast-path, root resolution, and resolved-path
comparison, variadic over (basename, rel) pairs — the jq spawn is on the
Write/Edit hot path, so N files must stay one parse. It distinguishes "other
file" from "basename matched but cross-project", which only `write-guard.sh`
denies. That comparison is the cross-project security boundary.
