# handoff — Design

Living document. States what this plugin is, how it works today, and why
each standing decision was made. Present tense throughout: when a decision
is reversed, this document is rewritten rather than annotated.

The write-time record of every design change lives in `changelog/`, one
file per change, dated, indexed by [`changelog.md`](changelog.md). Those files are never
edited after the fact — they say what was true and what was believed when
they were written, which is what makes them worth keeping.

This document is a **hub**. `docs/design/` holds one node per mechanism or
argument; read the node before making a claim about, or changing, what it
argues. The routing table under Architecture, and the two indexes under
Design decisions and Rejected alternatives, are the entry points.

Last updated: 2026-09-21.

## Problem

When a Claude Code session grows long or a user wants to `/clear` mid-task,
some state is worth preserving for the successor agent. Existing solutions
either over-capture (full-transcript summaries that drift) or under-capture
(nothing at all, relying on the user to re-explain).

The goal here is to identify the *irreducible residual* — what state
actually needs crossing the `/clear` boundary given everything else the
Claude Code ecosystem already handles — and build the minimum machinery
for it.

## Research — SOTA for session handoff (April 2026)

Four dominant families observed in the wild:

### 1. In-session auto-compaction

Claude Code `/compact`, Codex CLI, OpenCode. LLM summarises the full
trajectory at a threshold (80–95%), fresh context resumes with the
summary. Differ only in what's kept alongside the summary.

- Claude Code: summary only
- Codex CLI: summary + recent ~20k tokens
- OpenCode: summary + pruned tool outputs, last ~40k tokens protected

All acknowledge cumulative accuracy loss across multiple compactions.

### 2. Manual structured handoff

Amp handoff, jdhodges' CLAUDE.md + HANDOVER.md pattern. User-directed,
explicit. Typical envelope:

```
Goal / Status / Context / Decisions made / What to avoid /
Open questions / Next step
```

Often paired with a durable `HANDOVER.md` that survives across sessions.
This is SOTA for *cross-session* continuity. The existing `/ddaa:handoff`
skill in the `ddaa` plugin targets this pattern (claude.ai-oriented).

### 3. Structured note-taking / memory tools

Anthropic memory tool beta, Cursor/ChatGPT memory, Cline/Copilot "memory
bank". Agent writes to files outside the context, reads them at session
start. Claude Code auto-memory is this family.

### 4. Sub-agent isolation

Parent delegates to sub-agents with a clean minimal-viable-context
envelope; sub-agents return 1–2k-token summaries. LangGraph supervisor
patterns, OpenAI Agents SDK handoffs.

LangChain's framing — **write / select / compress / isolate** — is the
cleanest mental model for judging a given design.

## Analysis — what is the residual after auto-memory + harness?

Memory + harness + training already supply:

| SOTA field | Handled by |
|---|---|
| Context (durable) | auto-memory |
| Decisions (durable) | auto-memory |
| What to avoid | auto-memory (feedback files) |
| Goal (meta-level) | auto-memory (project files) |
| Status | code + `git status` |
| Conversation arc | session JSONL (orthogonal, used via `claude -c`) |

What's reconstructible from state:

| Field | Reconstruction |
|---|---|
| Agent responses | re-derive from intent + code state |
| Tool results | re-run |
| Files touched | the harness's own `gitStatus` block at load time |

What's irreducible:

- **current_task** — a pointer to what was in progress
- **open_decisions** — unmade choices still blocking progress

Plus one that is reconstructible only by *model inference*, which is a
different thing:

- **the undone half of a task list** — a decomposition is judgment, and
  after a compaction it is re-derived from a paraphrase with real error
  probability, failing silently by redoing finished work. See
  [Reconstructable is two categories, not
  one](changelog/2026-07-22-a-place-for-the-todo-list.md).

The original analysis carried a fourth category — the last N verbatim user
prompts, as "the only unreconstructable conversational signal" ([the
argument, in full](changelog/2026-05-19-original-activation-and-loading.md)).
It was implemented, shipped, and withdrawn: a faithful transcript does not
read as a report about a past session, it reads as *memory*, and the successor
narrates a prior session's work as its own. See [Task frame drops the
transcript and file list](changelog/2026-07-17-task-frame-drops-transcript.md).

Those categories constitute the artifact this plugin produces. Everything
else on the SOTA list is already handled, or reconstructible from code /
git / memory.

## Requirements

These labels are cited throughout `CLAUDE.md`, the skill bodies and the
scripts' own comments, so they are fixed points: the numbering is never
compacted, and a requirement that dies leaves its number retired rather than
reused. They arrived from two plans with independent numbering, which is why
the driven-transition pair is lettered — `FR-G` and `FR-H` would have
collided as numbers.

**[The write path](design/the-write-path.md).**

- **FR1** — One entry point, `handoff-checkpoint`, serves every skill that
  writes. Which boundary is in play is a payload field, not a separate
  binary.
- **FR2** — The payload is JSON on stdin, validated against a schema. A
  violation exits non-zero and names the offending field and what was wrong.
- **FR3** — `handoff-task.md` is written only by the checkpoint. An agent
  `Write`/`Edit` to that path is denied. `.claude/autodrive` is held to the
  same rule.
- **FR4** — `handoff-todo.md` is a scratch list by design. The agent edits it
  freely all session; the checkpoint is only the wrap-up path.
- **FR5** — The todo payload supports incremental update:
  `{"action": "edit", "old_string": …, "new_string": …}` as well as content
  written whole. The task file is authored whole, so it has no edit action
  and the schema refuses one.
- **FR6** — A file whose body is empty is removed, and the removal staged.
  File present ⟹ content pending. Empty is what is left once blank lines and
  ATX headings are taken out, a heading being markdown's own — so a shebang,
  a `#tag`, or a `# comment` inside an indented code block are all content,
  and a line of spaces is not.
  [A heading is not a leading `#`](changelog/2026-09-14-a-heading-is-not-a-leading-hash.md)
- **FR7** — Everything the checkpoint writes is staged with `git add -f`,
  deletions included. The checkpoint cannot do it itself (NFR1), so it
  records the paths in `.claude/checkpoint-manifest` and `PostToolUse(Bash)`
  stages them.
- **FR8** — The checkpoint composes `.claude/autodrive` from the transition
  fields — every line that gets typed, including the `/rename` that sets the
  session title.
- **FR9** — Everything the agent does after the checkpoint call is printed
  by the checkpoint, in a fixed order, each part present only under its own
  condition: the memory directive, the todo boundary (`handoff`) or the SDD
  ledger nudge (`precompact`), the commit act, then either the arming
  instruction or the closing line. The skill's last step is to follow it in
  order. See [The checkpoint directive](design/the-checkpoint-directive.md).

**The driven transition** — argued in
[Driving the TUI](design/driving-the-tui.md).

- **FR-G** — The prepare-only compact path re-injects the frame. Nothing is
  typed, but the transition is *expected*, and that expectation is what
  `SessionStart(compact)` gates re-injection on — otherwise a hand-typed
  `/compact` would re-inject nothing.
- **FR-H** — A multi-line sequence re-gates on idle between lines.
  Confirming one can take `CONSUME_TIMEOUT` (300s) and the pane is live
  throughout, so nothing is typed without a fresh idle wait and a fresh
  composer check.

**Constraints** — argued in [The write path](design/the-write-path.md) and
[Scoping](design/scoping.md).

- **NFR1** — No git or tmux work runs in the agent's sandboxed Bash. A
  sandboxed `git add` can stage successfully while stranding
  `.git/index.lock`, which fails the *next* command — in the routine wrap-up,
  the user's `/commit` — naming a git process that does not exist; and tmux
  is unreachable there at all. This is a constraint, not a preference.
- **NFR2** — The `PostToolUse(Bash)` and `PreToolUse(Bash)` hooks fire on
  every Bash call in every session with the plugin installed. Their negative
  case is one jq parse plus, respectively, one `stat` and one substring test.
  Neither resolves the root unless it has already matched.
- **NFR3** — Skill bodies get shorter, not longer. The checkpoint exists to
  move mechanism out of prose.

**FR12 is gitlore's, not this plugin's** — the registration of the
`gitlore-memory` submodule in `.gitmodules` as the activation gate. It is
cited here because the memory directive keys on it (see
[The checkpoint directive](design/the-checkpoint-directive.md)); the rest of
gitlore's numbering has no meaning in this repo.

## Architecture

Five skills, one write path, eleven hooks, and two files that cross a
boundary.

Where the argument lives:

- [The write path](design/the-write-path.md) — What crosses the boundary, who
  is allowed to write it, and what one checkpoint call does?
- [The skills](design/the-skills.md) — Which skills exist, and why is the
  transition a payload field rather than a skill of its own?
- [Driving the TUI](design/driving-the-tui.md) — How does a transition get
  typed into the composer, and what confirms each line landed?
- [The checkpoint directive](design/the-checkpoint-directive.md) — What does
  the checkpoint print for the agent to do next, when is the transition held,
  and where does gitlore meet this plugin?
- [Scoping](design/scoping.md) — Which root does a hook anchor on, and how is
  a session that drifts out of it reported?
- [Release infrastructure](design/release-infrastructure.md) — Why is the
  release machinery vendored from claude-plugin-dev rather than inlined?
- [Design decisions](design/decisions.md) — Why is each standing call the way
  it is?
- [Rejected alternatives](design/rejected-alternatives.md) — What was ruled
  out, and on what grounds?

## Design decisions

The standing calls, each argued in
[`design/decisions.md`](design/decisions.md):

- **Extraction is deterministic; judgment is the agent's.**
- **The task file is checkpoint-only; the todo file is not.**
- **Both files are tracked, and for the same reason.**
- **Commit/push status never appears in either file.**
- **The frame carries no transcript.**
- **The agent supplies one fact; the code owns the branch.**
- **Ask the question the request can answer.**
- **Withholding is a mechanism.**
- **A directive is correct only where in the turn it lands.**
- **Hooks are mechanical; anything requiring judgment is in a skill.**
- **Nothing that asks whether an action took effect reads the pane.**
- **The armed transition is one file whose body names the transition.**
- **The transition carries its own state.**
- **Observability is not gated on the happy path.**
- **A foreign tool's state file is detected by liveness, not presence.**
- **A foreign ledger scopes the todo file; it does not replace it.**
- **The design names no todo tool.**
- **With nothing to approve, the wrap-up completes in a single turn.**
- **A context-size nudge was tried and dropped.**
- **Deciding makes no tool call.**
- **Nothing about the exiting process is read.**

## Rejected alternatives

Ruled out, each argued in
[`design/rejected-alternatives.md`](design/rejected-alternatives.md):

- **A bare magic-string sentinel for the payload's actions**
- **Loading via an `@.claude/handoff.md` reference**
- **A generated `handoff.md` artifact**
- **A `PreCompact` hook for the memory flush**
- **Merging handoff into gitlore**, **moving the checkpoint into gitlore**,
  **gitlore superseding handoff**
- **Live `git status` in `load-handoff.sh`**, **reorder + amend**
- **Trusting the raw `.cwd` field**, **recording the root via
  `WorktreeCreate`/`CwdChanged`**
- **A session-id sidecar or a recency timeout for a stale sentinel**
- **Detecting commit awareness in the checkpoint, and defaulting the answer**
- **Injecting the remainder at the first `UserPromptSubmit`**
- **Accepting SDD's pre-6.2.0 flat ledger path for back-compatibility**
- **Letting the plan's tasks live in both files**
- **Merging the `PostToolUse(Write|Edit)` scripts**
- **A parallel pipeline per transition**, **omitting `/clear` from the
  sentinel body**, **naming the skills `compact` and `clear`**,
  **`autocompact`/`autoclear` as skill names**
- **One hold predicate**
- **Keeping the sentinel a skill-body write**, **printing the sentinel for the
  agent to write when deferring**, **a second full checkpoint call carrying
  the resolved gate**, **`--arm` as a flag on `handoff-checkpoint`**
- **Injecting the frame on any compaction where one exists**, **prepare-only
  with a driven continuation**
- **Every way of identifying the exiting `claude` process**
- **Lengthening `HANDOFF_WATCHER_SHELL_SETTLE`**

## Non-goals

- **Summarising the conversation.** Claude Code already has
  `/compact` (manual and automatic-at-threshold) and Session Memory
  (background summaries surfaced in the transcript). The model is
  trained to handle compacted context. This plugin does not add a
  third summarisation layer — it captures only the two fields those
  mechanisms cannot supply (current task, open decisions).
- **Cross-session thread management.** Auto-memory persists durable
  state across sessions; `claude -c` continues a specific session.
  This plugin addresses the single `/clear` transition, not multi-day
  thread juggling.
- **Validating markdown structure at write time.** `handoff-checkpoint`
  validates the JSON envelope, not the markdown content inside it; the
  templates in `SKILL.md` are trusted, not schema-checked.
- **Replacing `/ddaa:handoff`.** Different target (claude.ai vs
  Claude Code), different scope (full-session summary vs residual task
  frame). Non-overlapping.
- **Claude.ai portability.** The plugin depends on session JSONL,
  Claude Code hooks, and filesystem — all Claude Code-specific. A
  claude.ai variant would need an entirely different mechanism.

## Relationship to `/ddaa:handoff`

`/ddaa:handoff` in the `ddaa` plugin is a claude.ai-oriented full-session
summariser (75–150 line markdown document intended for pasting into a new
web conversation). It is SOTA family #2, manual structured handoff.

This plugin is narrower: Claude Code-only, `/clear`-focused, mechanical
extraction + minimal judgment. Non-overlapping. Both can coexist.

## Changelog

[`changelog.md`](changelog.md) — one line per design change, newest first,
each linking the full write-time record under `changelog/`.

## References

- LangChain's context engineering framing:
  `https://www.langchain.com/blog/context-engineering-for-agents`
- Anthropic on long-horizon agents:
  `https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents`
- Context compaction comparison (Claude Code / Codex / OpenCode / Amp):
  `https://gist.github.com/badlogic/cd2ef65b0697c4dbe2d13fbecb0a0a5f`
- jdhodges handoff pattern:
  `https://www.jdhodges.com/blog/ai-session-handoffs-keep-context-across-conversations/`
- Session JSONL format, community-maintained reference:
  `https://claude-dev.tools/docs/jsonl-format`
- Maintained session-transcript parser (code as format reference):
  `https://github.com/simonw/claude-code-transcripts`
- Hooks reference (PreCompact matchers/output, SessionStart `compact`):
  `https://code.claude.com/docs/en/hooks`
