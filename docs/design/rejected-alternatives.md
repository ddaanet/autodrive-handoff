# Rejected alternatives

Part of [handoff — Design](../design.md).

The dated records named here are in the `changelog-archive` tag's
`docs/changelog/`.

**A bare magic-string sentinel for the payload's actions** — `"@empty"` or
`"clear"` as the value of `task`, instead of `{"action": "clear"}`. It
reinstates the defect class it was meant to retire, one spelling along: a
typo in a bare token is indistinguishable from content, so `"claer"` is
written to the file as the task frame's body, silently, exactly as `null`
silently meant "no-op". `{"action": "emty"}` is a schema error naming the
field, because the object shape is what makes the value's role explicit
enough to check. This is the first shape considered at the proof pass, and
the one a future session will re-propose.
2026-09-07 The payload names its actions

**Loading via an `@.claude/handoff.md` reference** — the reference is
resident in every turn and cannot be conditional. `SessionStart` +
`additionalContext` injects once, only when there is something to inject.
2026-05-19 Original design: activation, loading, extraction

**A generated `handoff.md` artifact** — a non-versioned twin shadowing a
versionable source, which also inlined raw transcript into anything that
committed it. The frame is assembled in memory at read time instead.
2026-06-05 Read-time assembly: pointer + bounded scrape

**A `PreCompact` hook for the memory flush** — it stays a skill, since a hook cannot run the agent turn the flush needs ([the directive](the-checkpoint-directive.md#rejected-alternatives)).

**Merging handoff into gitlore**, **moving the checkpoint into gitlore**
behind a `command -v` lookup, and **gitlore superseding handoff** — all three
rejected ([the directive](the-checkpoint-directive.md#rejected-alternatives)).

**Live `git status` in `load-handoff.sh`**, and **reorder + amend** (commit,
regenerate the handoff, amend) — the first adds a git shell-out to a pure
assembler for a content problem; the second reopens a closed artifact and
breaks the paired in-history record. Machinery to make a wrong fact accurate.
2026-06-24 Commit status excluded from the task frame

**Trusting the raw `.cwd` field**, or **recording the root via
`WorktreeCreate`/`CwdChanged`** — the first drifts with `cd` and `/add-dir`;
the second is observational, with no clean per-worktree storage, and fragile
against the stateless `.git` walk.
2026-06-09 Per-worktree handoff root

**A session-id sidecar or a recency timeout for a stale sentinel** —
neither is used: the owner's own sentinel is swept by its next prompt as an aborted turn,
unless that prompt was queued into the arming turn, and across sessions the owner rides on line 1 and its transcript is what is timed;
the argument is in [Sessions sharing a
root](sessions-sharing-a-root.md#rejected-alternatives).

**Sparing every kind of queued prompt**, **recording each prompt's id in the
sweep**, **the mod reading the prompt box** — a spared `clear` or `compact`
runs cleanly, but the prompt is lost as handoff state: the files were written
before it, its answer lives only in the context `/clear` discards, and
`TODO.md` does not carry it across a `/compact`. Recording each prompt's
`prompt_id` forks `find`, `mktemp` and a replace on every prompt of every
session, for a case that matters only while an owner's `armed` file exists; the
checkpoint call is the one place the arming turn's id is known. The prompt-box
read protected nothing, since `command.run` and `prompt.submit` leave composer
text untouched, and cost a transition when text was restored to the box before
the turn ended.
2026-10-16 A prompt queued into the arming turn

**Detecting commit awareness in the checkpoint, and defaulting the answer** — both rejected ([the directive](the-checkpoint-directive.md#rejected-alternatives)).

**Injecting the remainder at the first `UserPromptSubmit`** to place a new
user task ahead of it — position is a weak lever (recency argues the other
way), explicit conditional wording is the strong one, and it needs a
once-per-session latch on a per-turn hook.
2026-07-22 A place for the todo list

**Accepting SDD's pre-6.2.0 flat ledger path for back-compatibility** — it
honours the bug, since the current skill guarantees such a file is somebody
else's leftover. Gating on the named plan file still existing was rejected
too: it false-negatives on a plan that landed and was tidied away.
2026-07-26 An orphaned ledger hijacks the handoff

**Letting the plan's tasks live in both files**, tracked in the ledger and
mirrored into `TODO.md` — two records of one thing drift, and the
stale one gets believed. Excluding the overlap costs nothing, which is why
the boundary is drawn there rather than around the file.
2026-08-08 The ledger and the todo file are different scopes

**A cap fitted to how often task files exceed it** — the first draft took
1500 characters because it rejected about one version in seven. That figure
was 14% or 43% depending on which versions were counted, and either way it
measured the symptom: a task file is long because it carries a plan, a
done-log and working conventions, not because tasks are long. The cap is set
from the task in hand once the rest has left.
2026-10-11 TASK.md and TODO.md move to the root

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
2026-10-11 Legacy paths are read, and the checkpoint moves them,
2026-10-11 TASK.md and TODO.md move to the root

**Protecting a foreign `TODO.md`** from a whole-content write. The file is
tracked and was injected at session start, so the write is informed and
recoverable, and the collision is the point: it is the same list.
2026-10-11 TASK.md and TODO.md move to the root

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
2026-10-11 Legacy paths are read, and the checkpoint moves them
2026-10-12 The git line names paths from the top
2026-10-13 The unstage line runs from the root

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
2026-07-29 Driven transitions

**One hold predicate** — rejected: it would hold a sentinel that protects no state ([the directive](the-checkpoint-directive.md#one-hold-predicate-rejected)).

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
2026-08-05 Transitions become modes of the two boundary skills

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
2026-07-29 Driven transitions

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
2026-08-13 Composer predicates match the real pane,
2026-09-22 The composer row carries its own gap,
2026-10-08 The plugin becomes a mod

**Reading the pane to confirm an action** — three independent pane-derived
predicates failed on undocumented chrome: a stale scrollback timer reading as
busy, a queued submit showing no spinner, and a 103-second compaction showing
none either. Confirmation by a file the transition's own `SessionStart`
consumes, or by the session transcript, replaced them one at a time, and the
last pane-reading confirmation (a grep for the title's first 20 characters)
went with the walker. With the mod the host's own resolution is the
confirmation, so no signal is read back at all.
2026-07-22 The submit signal, a third time: confirm the compaction, not the keystroke

**A `restart` kind, and identifying the exiting process** — an exit and
relaunch line typed into a bare shell after `/exit`, which needed the walker to
find a shell prompt it could not observe. Its argv replay compounded the
launcher's flags one copy per restart, and the composed line
`claude --resume <sid>` resolved through PATH was the fix that outlived it.
Claude Code now ships `/restart` as a built-in, and `--resume` already carries
the conversation whole, so the kind, its skill and its relaunch machinery are
gone rather than ported.
2026-08-14 The relaunch stops replaying argv,
2026-08-13 Restart drive repair

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

**Per-session sentinels or checksums for sessions sharing a root** — out of
proportion to a setup a worktree per session already avoids; the argument,
and the lock adopted since for a narrower race, are in [Sessions sharing a
root](sessions-sharing-a-root.md#rejected-alternatives). **Recording the root in the sentinel**, checked on take, to
catch a `.claude/` shared between roots, is more machinery and another line
every reader parses for a setup that is unsupported. **Refusing a symlinked
`.claude/`** adds nothing either: a project directory the user has accepted as
trusted can already ship hooks and settings, so a planted link gives an
attacker no capability, and Claude Code documents symlinks only for
`.claude/rules/` and skills (code.claude.com/docs/en/memory.md,
code.claude.com/docs/en/skills.md), not for `.claude/` as a whole, which has a
history of bugs (anthropics/claude-code#764, anthropics/claude-code#10522).
2026-10-14 Cross-session limits, documented; the held exemption widened

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
2026-10-15 The mechanical principle is narrowed; a reviewer waits for a measurement

**An agent-authored continuation prompt** — one line of prose the agent wrote,
submitted after a driven transition as a handle to the files. Skill prose and a
good-and-bad pair of examples held it to that, and nothing in the schema did:
the prompt could carry the task or the facts a decision hinged on, which the
next `/clear` drops, while the files stayed thin. A fixed line asks nothing of
the agent and gives the task nowhere to go but the files.
2026-10-15 The continuation is a constant

**`turn.complete` without a preceding `classic.Stop` as the aborted-turn
signal** — instead of the `prompt_id` marker, let the mod tell the sweep that
the turn ended without a `Stop`, an Esc, so a prompt after one is stale and any
other is queued. Rejected: a queued prompt's `UserPromptSubmit` fires before
the arming turn's `Stop`, so the sweep decides before the mod knows anything,
and when the mod is not loaded nothing observes the turn at all, so the hook
must decide alone. Whether `turn.complete` fires at all on Esc is also
unverified.
[A prompt queued into the arming turn](queued-prompts.md)
