# The skills

Part of [handoff — Design](../design.md).

One skill per boundary, plus the rename:

| boundary | skill | transition field |
|---|---|---|
| compaction | `/handoff:precompact` | `compact`: `false` \| `true` \| `"<directive>"` |
| clear | `/handoff:handoff` | `clear`: `false` \| `true` |

The two differ in one content field. `handoff` carries a `task`, because a
`/clear` leaves nothing else to say what was in hand. `precompact` takes none
and removes the task file, because the compaction's summary says it
([The compact boundary carries no task](decisions.md)). Both carry `todo`.

There is no restart skill: Claude Code's own `/restart` relaunches with
`--resume`, which carries the conversation over whole, so there is no
boundary for this plugin to cross and no frame to carry.

`/handoff:pending` is a fourth skill with no design surface at all: it reports
the `## Current task`, `## Open decisions` and `## Remaining` sections of the
frame already injected into context, making no tool call and writing no file.
It appears nowhere else in the design because there is nothing else to say
about it.

The judgment is per-boundary, not per-drive-mode: commit awareness, memory
capture, the drafting rules and the file-vs-prompt seam are
identical whether or not the plugin runs the command afterwards. So whether
the transition is driven (the code's `typed`) is a **field of the payload**, decided the way
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

The transition field is named after the command it runs, and its value is
that command's argument: `/clear` takes none, so it is a bool; `/compact`
takes an optional focus directive, so it is a bool or the directive itself.
`false` does not mean "no sentinel" — it means the command is not run.

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
  live. It is a skill rather than a mod command because the host refuses a
  command run from inside a command handler: the rename would land one
  ordinary turn late, and never under `-p`. The checkpoint call composes a
  `rename` sentinel and the mod runs it when the turn ends, like any other
  kind ([Driving the transition](driving-the-transition.md)).
