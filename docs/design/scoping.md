# Scoping

Part of [handoff — Design](../design.md).

Every cwd-scoped hook anchors on `handoff_root_read()` — the enclosing linked
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
`HANDOFF_ROOT` and `HANDOFF_ROOT_BRANCH` (the `handoff_drive_read` idiom),
and nothing prints the root: a `$(...)` capture strips trailing newlines, so a
root ending in one came back naming a sibling directory. For the same reason
every hook reads the hook input's `.cwd` NUL-terminated rather than through
`jq -r` in a capture, the resolver answers NUL-terminated, the drift marker
holds its cwd NUL-terminated, and `worktree_root.py` reads a worktree's
`.git` file as git does — everything after `gitdir: ` with trailing CR and LF
stripped — rather than line by line. Containment beats
the branch the walk took: a submodule or vendored checkout inside the
project is `inside`, not `foreign`.

A fifth label, `unresolved`, is the resolver failing: `worktree_root.py`
crashed or answered something that is not one of the four, which bash 3.2
cannot see as an exit status through a process substitution, so the answer is
judged. The root is then empty and every caller says so on its own channel
rather than exiting 1 in silence: the write guard denies a write whose path
names `autodrive`, since it can no longer tell the sentinel from another
project's, the loaders and the prompt-time hook report on both channels,
`inject-checkpoint-root.sh` leaves the command alone so the checkpoint refuses
the unset `HANDOFF_ROOT`, and `drive-take.sh` hands the mod a plan carrying
only the message to toast.

The last two labels are **drift** — the session cwd has left the launch repo
while the root, and every handoff file under it, has not. Nothing else
announces that: the environment block, `gitStatus` and the project
`CLAUDE.md` all follow cwd. `report-drive-failure.sh` reports it at
`UserPromptSubmit`, where the root is resolved every turn anyway, because
drift can be transient and a later gate would see nothing while the split
was live for the whole blip. The cwd is the hook input's, any string, and the
note is harness text the agent reads, so both paths are shown `%q`-quoted: a
newline, an escape sequence or a backtick in a directory name arrives as data
rather than as a line, a terminal restyle or the end of a code span. One report
per episode: a marker holds the destination last announced, whole, and
returning clears it. The marker's directory is shared by every local user, so
any name in it may be a link someone else planted: the marker is used only in
a directory that is no link and is this user's, read only through an
`O_NOFOLLOW` open of a regular file this user owns (`handoff_read_regular`),
and written as a `mktemp` file renamed over the name, which replaces a link
rather than following it. Where the directory fails that test there is no
marker, and drift is reported every turn rather than never.

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

`write-guard.sh` is the one path-scoped hook: one jq parse and a substring
test on the Write/Edit hot path, then root resolution and a comparison of
resolved paths, done in the script itself. It tells "another file" from "the sentinel's name, in another
project" and denies the second as well as this project's own. That comparison
is the cross-project security boundary; what it is made on, and what it does
not catch, is in [The write path](the-write-path.md#what-is-guarded).
