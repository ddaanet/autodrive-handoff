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

**A `PreCompact` hook for the memory flush** — `PreCompact(manual)` can
annotate or block a compaction but cannot run an agent turn, and the flush
needs one: summarize, get approval, write the message file. It stays a skill
the user runs before compacting, where that turn exists. Compaction threatens
conversation state only, so the commit can wait for any later commit.
[Session compaction](../changelog/2026-07-12-session-compaction.md),
[The mechanical principle is narrowed; a reviewer waits for a
measurement](../changelog/2026-10-15-the-mechanical-principle-is-narrowed.md)

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
turn may run, and a wrong guess silently drops a wanted compaction. Both stay
rejected for the owner's own sentinel, which its next prompt sweeps
unconditionally. Across sessions the owner rides on line 1 rather than in a
sidecar, and what is timed is the owner's transcript, never the sentinel.
[A stale autocompact is one a later turn can
see](../changelog/2026-07-22-stale-autocompact.md),
[The armed sentinel has an
owner](../changelog/2026-10-13-the-armed-sentinel-has-an-owner.md)

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
mirrored into `TODO.md` — two records of one thing drift, and the
stale one gets believed. Excluding the overlap costs nothing, which is why
the boundary is drawn there rather than around the file.
[The ledger and the todo file are different
scopes](../changelog/2026-08-08-ledger-and-todo-are-different-scopes.md)

**A cap fitted to how often task files exceed it** — the first draft took
1500 characters because it rejected about one version in seven. That figure
was 14% or 43% depending on which versions were counted, and either way it
measured the symptom: a task file is long because it carries a plan, a
done-log and working conventions, not because tasks are long. The cap is set
from the task in hand once the rest has left.
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

**A fallback for the old paths that retires by version, by tripwire or by
nothing** — the loader does read `.claude/handoff-task.md` and
`.claude/handoff-todo.md` ([the decision](decisions.md)), and what stays ruled
out is every way of leaving it unattended. A version gate, or a tripwire that
warns or fails from one, says nothing about which repositories still hold a
frame under the old names, and turns a release into the moment that frame stops
loading. A fallback with no stated condition outlives the migration it exists
for, which is the argument that first rejected it and still holds; it is why
the condition is written down, and the removal is an item in `TODO.md`. Also
rejected: **advising the agent to delete a legacy file that a root file
shadows**. The note states that it is ignored and nothing more, since advice
in that channel reads as authorisation to delete a file nobody asked about.
[Legacy paths are read, and the checkpoint moves them](../changelog/2026-10-11-legacy-paths-are-read-and-moved.md),
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

**Protecting a foreign `TODO.md`** from a whole-content write. The file is
tracked and was injected at session start, so the write is informed and
recoverable, and the collision is the point: it is the same list.
[TASK.md and TODO.md move to the root](../changelog/2026-10-11-task-and-todo-move-to-the-root.md)

**A bare relative path in the printed `git rm --cached` line**, and a
**top-anchored pathspec**, `:/<prefix><path>` or `:(top,literal)<prefix><path>`,
in place of `git -C <root>`. The bare form is relative to the agent's Bash
working directory, which persists across calls and can be any directory under
the root; from a subdirectory it matched nothing, and `--ignore-unmatch -q`
kept the miss silent. A top-anchored form needs the root's path below the top
of its repository, a query (`git rev-parse --show-prefix`) whose failures are
silent: a missing git raised and exit 128 yielded an empty prefix and a wrong
pathspec. Unliteral, `:/` also reads the root's own name as a pathspec, so a
root named `a*b` unstaged a sibling's file and one named `!x` was magic, quoting
that the shell sees and git does not. `:(top,literal)` closes that hazard and
keeps the query. Also rejected: **`--literal-pathspecs`** ahead of `-C`. Probed,
it changes nothing the line can print: `-C` already keeps the root's name out of
every pathspec, and the two paths left are fixed names with no magic character,
so the rows over `!x`, `^x`, `a*b`, `a?b` and `a[1]` roots pass without it. `git -C <root>` was first rejected for putting the root on the
line, where a newline in it splits the line; the prefix form had the same
residual, so the objection never separated them. It is now the form in use.
[Legacy paths are read, and the checkpoint moves them](../changelog/2026-10-11-legacy-paths-are-read-and-moved.md)
[The git line names paths from the top](../changelog/2026-10-12-the-git-line-names-paths-from-the-top.md)
[The unstage line runs from the root](../changelog/2026-10-13-the-unstage-line-runs-from-the-root.md)

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
auto-compaction gap for free — but `TODO.md` is durable and tracked and
sits on disk across days of unrelated work, so this injects a stale frame
into every threshold compaction in every session in the repo,
unrequested and mid-session. The asymmetry is principled: compaction is the
one boundary the harness enters on its own, so it is the one that needs a
signal of intent. Also rejected: **prepare-only with a driven continuation**
— a sentinel whose before-lines are empty but whose after-line is not. Cheap
and appealing, but a skill that types one of the two lines has no sentence
that describes it.
[Driven transitions](../changelog/2026-07-29-driven-transitions.md)

**Driving the TUI through tmux** — the design before the mod: a detached
walker typed each line into the composer with `send-keys` once the pane read
idle, behind a `Stop` hook that armed it, with a `SessionStart` loader spawning
a second walker for the continuation. It worked, and it cost an undocumented
surface at every step: the idle and busy chrome, the composer's layout, the
foreground command of the pane, and a tmux that the agent's sandbox cannot
reach and a user outside tmux does not have, which is why the lines were
printed for pasting there. Every defect in its record was the platform moving
under a guess about that surface. The mods API runs a command "as if the
person typed it" and resolves when it has taken effect, so the surface the
walker guessed at is not needed. Ruled out for good, with the whole family of
fixes it grew: tuning its constants against a shutdown nothing bounds
(`HANDOFF_WATCHER_SHELL_SETTLE`), a second tmux query to tell a shell's `❯`
from the TUI's (`#{alternate_on}`), a landing window sized to a measured boot,
and a gate that tells the composer's row apart by the U+00A0 its glyph is
padded with.
[Predicates match the real pane](../changelog/2026-08-13-predicates-match-the-real-pane.md),
[The composer row carries its own gap](../changelog/2026-09-22-the-composer-row-carries-its-own-gap.md),
[The plugin becomes a mod](../changelog/2026-10-08-the-plugin-becomes-a-mod.md)

**Reading the pane to confirm an action** — three independent pane-derived
predicates failed on undocumented chrome: a stale scrollback timer reading as
busy, a queued submit showing no spinner, and a 103-second compaction showing
none either. Confirmation by a file the transition's own `SessionStart`
consumes, or by the session transcript, replaced them one at a time, and the
last pane-reading confirmation (a grep for the title's first 20 characters)
went with the walker. With the mod the host's own resolution is the
confirmation, so no signal is read back at all.
[The submit signal, a third
time](../changelog/2026-07-22-confirm-the-compaction.md)

**A `restart` kind, and identifying the exiting process** — an exit and
relaunch line typed into a bare shell after `/exit`, which needed the walker to
find a shell prompt it could not observe. Its argv replay compounded the
launcher's flags one copy per restart, and the composed line
`claude --resume <sid>` resolved through PATH was the fix that outlived it.
Claude Code now ships `/restart` as a built-in, and `--resume` already carries
the conversation whole, so the kind, its skill and its relaunch machinery are
gone rather than ported.
[The relaunch stops replaying argv](../changelog/2026-08-14-the-relaunch-stops-replaying-argv.md),
[Restart drive repair](../changelog/2026-08-13-restart-drive-repair.md)

**A `/autoname` mod command** — a registered command that forks a title and
runs `/rename`. The host refuses `$.command.run` from inside a command
handler, so the rename could land only after the next ordinary turn, and never
under `-p`. `autoname` stays a skill whose checkpoint call composes a `rename`
sentinel, which the drive runs at the end of the turn that wrote it.

**A second parser of the sentinel in the mod** — reading
`.claude/autodrive` from TypeScript to skip the process spawn. Four other
readers already share `handoff_drive_read`; a fifth copy of the grammar drifts,
and the mods API has no rename or delete for the atomic `armed` → `pending`.
The cost it would save is paid only on the rare path: the every-turn check is a
single `exists` on the project root.

**Per-session sentinels, locks or checksums for sessions sharing a root** —
one sentinel per session, a lock around the checkpoint and the take, or a
checksum the take compares before rewriting. Each closes one race (a later
checkpoint replacing an earlier session's sentinel, the take's read and
rewrite in two steps) at the cost of a second file per session, a lock with
its own stale case to sweep, or a compare-and-swap every bash reader would
implement, and none touches `TASK.md` and `TODO.md`, which are shared state by
design: two sessions writing one task frame conflict whatever the sentinel
does. The complexity is out of proportion to a setup a worktree per session
already avoids. **Recording the root in the sentinel**, checked on take, to
catch a `.claude/` shared between roots, is more machinery and another line
every reader parses for a setup that is unsupported. **Refusing a symlinked
`.claude/`** adds nothing either: a project directory the user has accepted as
trusted can already ship hooks and settings, so a planted link gives an
attacker no capability, and Claude Code documents symlinks only for
`.claude/rules/` and skills (code.claude.com/docs/en/memory.md,
code.claude.com/docs/en/skills.md), not for `.claude/` as a whole, which has a
history of bugs (anthropics/claude-code#764, anthropics/claude-code#10522).
[Cross-session limits, documented](../changelog/2026-10-14-cross-session-limits-documented.md)

**A reviewer agent for the handoff task, or for memory destinations, for now**
— rejected on measurements, so each reading reopens on a number. For the
handoff frame, the rates measured over 612 task versions are the rates before
FR13, not its residual. The best estimate of what FR13 leaves is 26 to 28% per
class among frames that already fit, and it assumes agents relocate a refused
frame's content rather than compress it. The reviewer's own error is large: a
Haiku reader disagreed with the hand reading on 20 to 28% of versions per
class and with itself on 12% of sentences between runs, so a blocking check
that wrong refuses about one compliant frame in four, and no Sonnet reading
exists. After FR13 a miss is at most 1000 characters of redundant text per
session start, plus a convention that reaches no approval gate; the history
shows no session acting on a bad frame. It reopens at 100 task versions written
under 0.16.1 or later across at least five repositories, re-measured with the
report's scripts. If that residual warrants a gate, the shape the data support
is narrow: a prompt-type `PreToolUse` hook on the `handoff-checkpoint` call
with `continueOnBlock` (the default deny ends the turn, against the
single-turn wrap-up), judging `task` alone, on a Sonnet-class model, scored
offline against the labelled versions first so its false-refusal rate is a
number before it can refuse anything. Not verified: timeout behaviour, whether
the `if` filter parses a heredoc command, any limit on the input size.

For memory destinations, a blind reviewer's yield was concentrated in one
transient wave and one kind of move. Of the 26 redirected rounds in the 87
rounds it would have run in (from 2026-08-28), 24 fall in one fortnight of
September, after two sibling skill plugins arrived. Across all redirected
facts, fact to skill matched 17 of 26 and fact to the tool, hook or template
that owns the behaviour 0 of 10. It reproduced almost none of the rejections
("nowhere" for 1 of 24 rejected facts, none of the 14 rejected rounds) and
raised a spurious objection on about 1 approved round in 9.
The levers belong to gitlore and were sent there as a brief: an inventory of
the owners a fact can go to, and a per-fact existence answer in the approval
summary. The reading changes with a second wave of redirections after the next
growth of the skill library, measured the same way, or a rerun of the blind
test with repository access that lifts recall on tool-bound facts above zero.
[The mechanical principle is narrowed; a reviewer waits for a
measurement](../changelog/2026-10-15-the-mechanical-principle-is-narrowed.md)
