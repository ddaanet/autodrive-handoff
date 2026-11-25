# The Vibe port

The native Vibe port of the plugin, and what could not cross. The port is
mechanism-shaped by the portability findings (`memory/vibe-plugin-portability.md`,
verified against mistral-vibe 3.0.1): Vibe's hook surface is
`post_agent`/`pre_tool`/`post_tool` only — no SessionStart, no Stop, no
PreCompact — and its Claude-format adapter refuses executable scripts, so the
mod cannot run in any form. The port is `vibe-plugin/`, a separate tree: four
skills, one write path, one AGENTS.md line, one optional compaction prompt.

## What ports and what drops

The write path ports; everything that ordered a transition around it drops.
The consequences, kept together so the shape reads in one place:

- **The write path is `vibe-plugin/scripts/checkpoint.py`** and its three
  `_checkpoint_*` siblings. The payload schema loses `continue`, which only a
  driven continuation could serve, and `compact` becomes a boolean only —
  Vibe's `/compact` takes no argument, so the Claude focus string has no
  carrier; the error says to put the focus in the todo. `precompact` drives
  no compaction: it is the memory flush and the `TASK.md`/`TODO.md`
  update, then the closing line naming `/compact` for the user.
- **The transition is user-run.** Nothing under Vibe can type `/clear`
  (`/compact`, `/rename`), so the closing directive names the command for the
  user instead of announcing an armed transition, and the skills' anti-pattern
  "never print the command for the user to run" inverts into its instruction.
  The skill bodies carry the inversion; the checkpoint never mentions Vibe's
  surface beyond the closing line.
- **The frame is read, not injected.** One AGENTS.md line replaces the
  SessionStart loaders and arrives whole (verbatim splice, no cut, no
  `persisted-output` wrapper); the `pending` skill assumes that read. The
  line ships in `vibe-plugin/README.md` for consumer projects; this repo's own
  `AGENTS.md` is the ddaanet-flavoured instance of it (the frame files plus
  the memory entry-points, directed 2026-11-23).
- **No sentinel, no lock, no hold, no `handoff-approved`, no write guard.**
  Each dropped piece lacked its Vibe carrier for a structural reason, not
  because hooks are out of scope: Vibe's `pre_tool`/`post_tool` hooks are real
  surface, in scope where a particular need is — [the decisions
  ledger](decisions.md) documents why a version guard is not one.
  There is no competing take to lock against and nothing to arm; a call's
  root is the cwd, guarded by a run-from-the-project-root check inside the
  checkpoint. A direct edit to `TASK.md`/`TODO.md` is a plain file write, as
  under Claude those files always were (NFR1).
- **Memory rides gitlore alone.** Vibe has no `gitlore:commit` skill; the seam needs gitlore discoverable under Vibe.
  Vibe discovers plugins only from `~/.vibe/plugins/` and `.vibe/plugins/`,
  so gitlore (a Claude-format plugin, user-scope for Claude Code) sits
  outside that surface, and the port makes no move to pull it in: bridging
  through a symlink into Claude Code's plugin cache was ruled out (see
  `rejected-alternatives.md`), and gitlore shipping natively is its own
  repo's work. The memory directive therefore does not send the agent to
  `gitlore:commit`: it prints the dirty status, tells the agent to report
  the memory as uncommitted to the user, left for a session that has gitlore.
  The with-commit act leaves the memory pointer out of the commit and says so
  in the reply. The adapter would expose gitlore's skill as
  `{plugin namespace}:{frontmatter name}` (`_native.py`, verified in the
  3.0.1 source); the port does not rely on it.

## Where the copies live

The canonical Python is `vibe-plugin/scripts/`; `just sync-vibe` copies the
four modules into the three caller skills (`handoff`, `precompact`,
`autoname`; `autoname` runs from any directory, with no project root required), and each skill invokes the copy through the base directory the
skill tool prints — the frame's decided invocation. The copies are not a
build artifact Vibe assembles: the installed plugin ships them as-is, so
byte equality is what keeps the copies one program, and it is asserted by
`tests/test_vibe_checkpoint.py`. The fork is not type-checked: mypy and ty read only
`scripts/` and `tests/` (`[tool.mypy] files`, `[tool.ty]` in
`pyproject.toml`), and three directories of flat modules reusing the same
names would collide under them. What covers it is ruff, docformatter and
`tests/test_vibe_checkpoint.py`, whose byte-equality assertion ties the
copies to the canonical modules. The check-size caps apply to every file as usual; the
checkpoint fork's directory is sized like the Claude one.

## The compact seam

There is no way to drive a compaction under Vibe, so `precompact` does what
`handoff` does to the two files and leaves `/compact` to the user: both
files survive it on disk. The optional custom compaction prompt is the one
piece of the seam left: `compaction_prompt_id` names a bare filename
resolved from the project's `.vibe/prompts/` first, then the user's, then
builtins (Vibe 3.0.1, `core/prompts/__init__.py`), and the prompt text
replaces the builtin summary request entirely. The shipped
`prompts/compaction.md` has the summary state the current task and the next
action from the conversation, and instead of copying `TASK.md` and
`TODO.md` it tells the next turn to re-read both from disk, where they
survive. The checkpoint does not check whether the prompt is installed: with
the task on disk, a missing prompt costs a paraphrase, not the task.

## Install and verification status

Install is copy-plus-two-config-steps, in `vibe-plugin/README.md`. Verified
2026-11-23 under 3.0.1 source and the test suite: the end-to-end checkpoint
(payload on stdin from a skill-directory path), the schema fork, and
gitlore's alias naming. Not yet verified live: a
Vibe session invoking a ported skill end to end (`/autodrive-handoff:handoff`
in a consumer) — it needs the installed state, which is the user's
environment, and a headless probe. A symlink of the Claude cache into
`~/.vibe/plugins/` was probed live on 2026-11-23 (all six `gitlore:*`
skills surfaced under exact names) and then removed as ruled out.
