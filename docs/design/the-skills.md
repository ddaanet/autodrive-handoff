# The skills

Part of [handoff — Design](../design.md).

One skill per boundary, plus the rename and the restart:

| boundary | skill | transition field |
|---|---|---|
| compaction | `/handoff:precompact` | `compact`: `false` \| `true` \| `"<directive>"` |
| clear | `/handoff:handoff` | `clear`: `false` \| `true` |

`/handoff:restart` is a fourth, separate skill rather than a third row in
this table — it shares the driven-transition machinery (a `kind` in
the same sentinel, the same walker) but not the boundary shape: no commit
awareness, no task/todo drafting, no prepare-only reading, because nothing
inside a live session can adopt an upgraded plugin, hook, MCP server, or
`settings.json` — those resolve once, at process startup, so exit-and-relaunch
is the only remedy and it is always typed, never merely prepared. See
[Driving the TUI](driving-the-tui.md) for the kind itself.

`/handoff:pending` is a fifth skill with no design surface at all: it reports
the `## Current task`, `## Open decisions` and `## Remaining` sections of the
frame already injected into context, making no tool call and writing no file.
It appears nowhere else in the design because there is nothing else to say
about it.

The judgment is per-boundary, not per-drive-mode: commit awareness, memory
capture, the task/todo drafting rules and the file-vs-prompt seam are
identical whether or not the agent types the command afterwards. So whether
the transition is typed is a **field of the payload**, decided the way
`commit` already is — one fact the agent supplies, everything downstream
deterministic — rather than a skill of its own.

A separate driven skill per boundary was the earlier shape, and it cost
routing (six trigger phrases each, every one naming the sibling it was not,
so "compact and continue" reaching `precompact` produced a prepared
compaction nobody ran), duplication (the arming discipline and the sentinel's
line shapes stated twice in prose), and expressiveness: driving a transition
*without* a continuation prompt was unreachable, because the driven skills
treated the prompt as intrinsic. The fields cover the cross product:

```
handoff     clear:false          continue:null   prepare only
handoff     clear:true           continue:null   clear, then stop
handoff     clear:true           continue:"…"    clear and continue
precompact  compact:false        continue:null   prepare only
precompact  compact:true|"…"     continue:null   compact, then stop
precompact  compact:true|"…"     continue:"…"    compact and continue
```

The transition field is named after the command it types, and its value is
that command's argument: `/clear` takes none, so it is a bool; `/compact`
takes an optional focus directive, so it is a bool or the directive itself.
`false` does not mean "no sentinel" — it means the command is not typed.

What the separate skills bought, and what this gives up, is that the
transition was settled by *which name the description matched* rather than
by reading the request: a misread now drives a transition where only
preparation was asked for. The fields are required and have no default, so
the question is at least always asked; and the prepare-only wording is the
larger half of both descriptions, since that is the reading a bare
"handoff" or "precompact" should get.

- **`/handoff:autoname`** — rename only, neither boundary. Decides a title
  and calls the checkpoint with `{"skill": "autoname", "rename": …}`, the
  whole payload. Every other field is a schema error under it, and no
  directive is composed — its description promises no memory write, and a
  memory directive is an instruction to make one. For `/btw` side
  conversations and any session worth a name while the main thread stays
  live.
- **`/handoff:restart`** — exit and relaunch, neither boundary either. Its
  whole payload is `{"skill": "restart", "continue": …}`: no title (a
  restart renames nothing), no task/todo, no commit awareness, and every
  boundary field is a schema error under it by the same key-presence rule
  autoname uses. No directive is composed, for the same reason as autoname —
  nothing here implies a memory write. Unlike autoname it does carry
  `continue`, since a restart can still be handed a continuation prompt for
  the far side.
