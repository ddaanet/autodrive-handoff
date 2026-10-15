# The skills

Part of [handoff — Design](../design.md).

One skill per boundary, plus the rename:

| boundary | skill | transition field |
|---|---|---|
| compaction | `/autodrive-handoff:precompact` | `compact`: `false` \| `true` \| `"<directive>"` |
| clear | `/autodrive-handoff:handoff` | `clear`: `false` \| `true` |

The two differ in one content field. `handoff` carries a `task`, because a
`/clear` leaves nothing else to say what was in hand. `precompact` takes none
and removes the task file, because the compaction's summary says it
([The compact boundary carries no task](decisions.md)). Both carry `todo`.

There is no restart skill: Claude Code's own `/restart` relaunches with
`--resume`, which carries the conversation over whole, so there is no
boundary for this plugin to cross and no frame to carry.

`/autodrive-handoff:pending` is a fourth skill with no design surface at all: it reports
the `## Current task`, `## Open decisions` and `## Remaining` sections of the
frame already injected into context, making no tool call and writing no file.
It appears nowhere else in the design because there is nothing else to say
about it.

The judgment is per-boundary, not per-drive-mode: commit awareness, memory
capture, the drafting rules and the seam between the files and the
continuation are identical whether or not the plugin runs the command afterwards. So whether
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
handoff     clear:false          continue:false  prepare only
handoff     clear:true           continue:false  clear, then stop
handoff     clear:true           continue:true   clear and continue
precompact  compact:false        continue:false  prepare only
precompact  compact:true|"…"     continue:false  compact, then stop
precompact  compact:true|"…"     continue:true   compact and continue
```

`continue` is a boolean, and `true` is a schema error against a transition that
is not carried out, since nothing would submit the prompt, and at the clear
boundary also when neither file would have a body once the plans are applied
(checked before any write, the legacy fallback counted; after a compaction the
summary carries the task, so `precompact` is exempt). The prompt it asks
for is one fixed line, `CONTINUATION` in `checkpoint.py`, that points the fresh
context at the task and todo files. It was once a line of prose the agent
wrote, and the agent used it to carry the task: a description of the next step,
or the facts it hinged on, that no file held and that the next `/clear` lost.
With the line fixed, `TASK.md` and `TODO.md` are the only carrier at a clear
(at a compact the summary and the focus directive carry too), and the
skills ask one yes-or-no question of the user's request where they once asked
for a sentence.
[The continuation is a constant](../changelog/2026-10-15-the-continuation-is-a-constant.md)

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

- **`/autodrive-handoff:autoname`** — rename only, neither boundary. Decides a title
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
