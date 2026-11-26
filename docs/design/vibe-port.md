# The Vibe port

The native Vibe port of the plugin, and what could not cross. The port is
mechanism-shaped by the portability findings (`memory/vibe-plugin-portability.md`,
verified against mistral-vibe 3.0.1): Vibe's hook surface is
`post_agent`/`pre_tool`/`post_tool` only — no SessionStart, no Stop, no
PreCompact — and its Claude-format adapter refuses executable scripts, so the
mod cannot run in any form. The port is `vibe-plugin/`, a separate tree: four
skills, one write path, one AGENTS.md line. Vibe plugins cannot execute a
prompt or drive a transition: `/clear`, `/compact` and a continuation are not
supported by the platform, so the mechanics are the simple ones.

## What ports and what drops

The write path ports; everything that ordered a transition around it drops.
The consequences, kept together so the shape reads in one place:

- **The write path is `vibe-plugin/scripts/checkpoint.py`** and its three
  `_checkpoint_*` siblings. The payload schema loses `continue`, `clear` and
  `compact`: it carries no transition flag, because nothing drives a
  transition and the closing line is the same either way; each key is refused
  as unknown. `precompact` drives no compaction: it is the memory flush and
  the `TASK.md`/`TODO.md` update, then the closing line handing the user a
  `/compact` line to paste.
- **The transition is user-run.** Nothing under Vibe can type `/clear`
  (`/compact`, `/rename`), so the closing directive names the command for the
  user instead of announcing an armed transition, and the skills' anti-pattern
  "never print the command for the user to run" inverts into its instruction.
  The skill bodies carry the inversion; the checkpoint never mentions Vibe's
  surface beyond the closing line and the rename part, which says under
  `handoff` to type `/rename` after the `/clear` (the print order puts it
  first, but it titles the current session).
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
  Step 1 of the two boundary skills therefore writes a durable fact as a plain
  file in the mounted store (the `gitlore-memory` submodule, at its
  `.gitmodules` path), by the store's own `MEMORY.md` conventions, with no
  gitlore skill in the path; the directive then reports it. Reading that
  `MEMORY.md` and writing the facts are the only tool calls before the
  checkpoint. The with-commit act leaves the memory pointer out of the commit and says so
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
`handoff` does to the two files and ends on a `/compact <direction>` line
for the user to paste: both files survive the compaction on disk. Vibe's
TUI `/compact` takes optional text to guide the summary (3.0.1,
`/compact [instructions]`), appended to the builtin summary request. The
direction (`COMPACT_DIRECTION` in `_checkpoint_lib.py`) says the two files
are the task frame and must not be reproduced, asks the summary for the
current task and next action as the conversation stands, and says the next
turn first reads both files from disk. No focus field exists: a user who
wants one adds it to the pasted line.

This replaced an installed `compaction_prompt_id` prompt. Plugins cannot
execute a prompt, and that prompt replaced the whole builtin summary request,
had to be installed and refreshed by hand, and broke config validation when
its file was missing. A direction on the user's own `/compact` has none of
those costs.

## Install and verification status

Install is copy-plus-one-config-step, in `vibe-plugin/README.md`. Verified
2026-11-23 under 3.0.1 source and the test suite: the end-to-end checkpoint
(payload on stdin from a skill-directory path), the schema fork, and
gitlore's alias naming. Not yet verified live: a
Vibe session invoking a ported skill end to end (`/autodrive_handoff:handoff`
in a consumer; that slash-menu spelling, the manifest name with `-` turned to `_`
by `_typescript_identifier` in `_native.py`, was read from the 3.0.1 source and
not exercised live) — it needs the installed state, which is the user's
environment, and a headless probe. A symlink of the Claude cache into
`~/.vibe/plugins/` was probed live on 2026-11-23 (all six `gitlore:*`
skills surfaced under exact names) and then removed as ruled out.
