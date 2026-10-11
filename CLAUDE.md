# Agent Instructions — handoff plugin

Plugin development conventions. Applies when working inside this repo
to edit the plugin's skill, hook, mod, or script.

## Layout

High-level flow: the skill decides the task/todo/rename content, then issues
one `handoff-checkpoint` Bash call carrying the whole wrap-up as a
schema-validated JSON payload on stdin → `checkpoint.py` writes `TASK.md` and
`TODO.md` in the project root (FR5 write semantics — content written as given,
or a named action) and `.claude/autodrive`, and does no git work (NFR1):
both files are plain tracked files and nothing stages them → the turn ends:
`classic.Stop` records the cwd and `turn.complete` runs the drive in
`hooks/handoff.ts`, which has `scripts/drive-take.sh` take the sentinel and
print the plan, then runs each line through `$.command.run` or
`$.prompt.submit` → the transition's own `SessionStart(clear|compact)` loader
consumes the `pending` sentinel and injects the frame (header + whichever of
the two files has a body, each half falling back to its old path under
`.claude/` while that bridge lasts) → `SessionStart(startup)` injects it into
a fresh session. `README.md` has the user-facing version.

The checkpoint also emits, on stdout, the procedure for the one cell the call
is in: when a gitlore-memory submodule is dirty, a memory directive tells the
agent to summarize → get approval → write gitlore's message file, plus the
trigger file only under `without-commit`, which gitlore's own `PostToolBatch`
hook consumes (under `with-commit` the message file alone leaves the memory
commit to the parent commit's pre-commit hook, so both paths end with one
parent commit carrying the source change and the gitlink bump). After the
memory part it prints the commit act under `with-commit`, then either the
instruction to run `handoff-approved` (held) or the closing line the reply
ends on — so the skills state none of it. See
`docs/changelog/2026-07-25-commit-awareness.md`,
`docs/changelog/2026-07-27-one-channel-one-writer.md` and
`docs/changelog/2026-09-18-the-directive-owns-the-procedure.md`.

**Two boundaries, two skills, one flow.** `handoff` for `/clear`, `precompact`
for `/compact`; the `skill` field names it, which also keys the directive
composition (memory gate + todo boundary for clear, memory gate + SDD ledger
nudge for compact). Only `handoff` carries `task`, bounded by FR13 (at most
1000 characters of prose, no list item); `precompact` forbids the key and
removes `TASK.md`, because the summary carries the task. Both carry `todo`,
the durable side of the seam: content that must survive verbatim, while the
continuation prompt is only a handle to it. Whether the transition is carried
out is a **field of the payload**:
`clear` (bool) at one boundary, `compact` (bool or focus directive) at the
other, plus `continue` (null or one line of prose) at both, all required with
no default — the code calls a carried-out transition `typed`, a name from when
it was keystrokes. `checkpoint.py` composes `.claude/autodrive` from those
fields and reads it back through `handoff_drive_read`, so the composer and the
parser cannot drift; `compact: false` still writes the two-line expectation
marker (FR-G), which runs nothing but is what `SessionStart(compact)` gates the
todo's re-injection on. The sentinel is written **only** by the checkpoint
(FR3), and a direct agent Write/Edit to it is denied by `write-guard.sh`;
`autoname` is a third `skill` value on the same call rather than a template in
its skill body. There is no restart skill or kind: `/restart` is a Claude Code
built-in. See `docs/changelog/2026-08-05-transitions-become-modes.md`,
`docs/changelog/2026-08-09-one-writer-for-the-sentinel.md`,
`docs/changelog/2026-10-08-the-plugin-becomes-a-mod.md` and
`docs/changelog/2026-10-11-task-and-todo-move-to-the-root.md`.

`TODO.md` is a scratch list the agent edits freely all session (FR4); the
checkpoint's wrap-up call is where the final remainder gets folded in, not the
only writer. It is the ledger; whatever todo tracker the harness exposes is a
cache, and nothing in the plugin names one. A project that already has a
`TODO.md` shares it. Neither file is guarded, gitignored or staged by a hook,
and only `{"action": "clear"}` and the compact boundary remove one; what
counts as empty is the loader's question, not the writer's. See
`docs/changelog/2026-07-22-a-place-for-the-todo-list.md` and
`docs/changelog/2026-10-11-task-and-todo-move-to-the-root.md`.

The one exception is the **legacy files**, `.claude/handoff-task.md` and
`.claude/handoff-todo.md`, where 0.15 kept the two halves. The loaders read a
half from its legacy file when the root file has no body, and the checkpoint
moves or removes a legacy file inside plan resolution so it cannot come back as
the frame; a root file with a body wins and its legacy file is reported ignored,
never touched. Both ends decide by body and shadowing by the legacy file's
existence. It is a bridge that goes once no sibling repository still has
`.claude/handoff-*.md`: `grep -rni legacy scripts/ tests/` starts the one
deletion pass, with one name per language (`HANDOFF_LEGACY_REL_*` in `_lib.sh`
and again in `checkpoint.py`). The retirement names no version, in code, docs or
tests. See `docs/changelog/2026-10-11-legacy-paths-are-read-and-moved.md`.

The mod needs Claude Code >= 2.1.287. `plugin.json` has no minimum-version
field, so that is stated in `README.md` and surfaced at runtime by the sweep
note in `report-drive-failure.sh`.

### Skills, manifest, hooks, mod

- `.claude-plugin/plugin.json` — manifest.
- `skills/handoff/SKILL.md` — the clear boundary's protocol
  (`/handoff:handoff`), driven or not, and the single source of truth for the
  markdown templates of `TASK.md`/`TODO.md` and for the seam
  between what belongs in a file and what in a continuation prompt. Three
  steps: durable learnings to memory (the only tool calls allowed ahead of the
  checkpoint); decide the three fields the payload cannot derive — driven or
  not, continuation or not, **does the ask this call serves imply a commit** —
  plus title/task/remainder, then one `handoff-checkpoint` call as a JSON
  heredoc; follow what the checkpoint prints, in order, without re-deriving it.
  Stays <= 2000 words.
- `skills/precompact/SKILL.md` — the compact boundary's protocol, in the same
  three steps (`compact` carries the focus directive; no `rename` and no
  `task`, both schema-forbidden there). Defers templates and seam rules to
  `handoff`.
- `skills/autoname/SKILL.md` — decides a session title (no tool calls), then
  one `handoff-checkpoint` call whose whole payload is
  `{"skill": "autoname", "rename": "<title>"}`. Every other field is
  schema-forbidden, which also keeps the memory directive from composing. It
  stays a skill because a mod command cannot rename from inside its own
  handler; the checkpoint composes a `rename` sentinel the drive runs.
- `skills/pending/SKILL.md` — lists the task frame's `## Open decisions` and
  `## Remaining` as already in context: no tool calls, nothing written.
- `skills/handoff/references/design.md` — condensed design notes; the full
  rationale is in `docs/design.md`.
- `hooks/hooks.json` — declares `"modules": ["./handoff.ts"]` plus six
  command hooks, every `${CLAUDE_PLUGIN_ROOT}` path double-quoted (the
  validator warns otherwise): `UserPromptSubmit` (`report-drive-failure.sh`);
  `PreToolUse(Write|Edit)` (`write-guard.sh`); `PreToolUse(Bash)`
  (`inject-checkpoint-root.sh`); `SessionStart` on every source
  (`session-pointer.sh`), on `startup|clear` (`load-handoff.sh`) and on
  `compact` (`load-compact.sh`).
- `hooks/handoff.ts` — the mod. `classic.Stop` records the turn's cwd and
  nothing else (an interrupt fires no `Stop`, so an aborted turn arms nothing);
  `turn.complete` consumes it and drives **inline** — the host refuses
  `$.command.run` from a `Stop` hook's call context, `$.clock.after` from it
  included, and timers die under `-p`. Fast path: a cwd equal to the session
  root with no `.claude/autodrive` returns without a spawn. Otherwise it runs
  `scripts/drive-take.sh`; empty stdout is nothing armed. It reads the prompt
  before each line and stops entirely on user text; a `/`-line is
  `$.command.run({command, args})`, other prose
  `$.prompt.submit({text, asUser: true})`; the first rejection writes
  `failFile` and toasts, and ends the sequence. It never reads the sentinel. A
  hooks module may pass `$` only to top-level functions (a static check at
  load). See `docs/design/driving-the-transition.md`.
- `scripts/drive-take.sh <cwd>` — takes the armed transition. Parses through
  `handoff_drive_read`, acts only on `armed`, moves it to `pending`
  (`handoff_drive_arm`, atomic) or removes it for `rename` (no confirming
  source), then prints one JSON line `{kind, before[], after[], failFile,
  message}`; empty stdout for no file, `pending` or `held`. FR-G (empty
  `before`) leaves `pending` and prints only the message; a malformed file is
  removed and reported with `kind: null`. Its stdout is pinned by
  `tests/mod/fixtures/*.json`.
- `scripts/load-handoff.sh` — `SessionStart(startup|clear)`: assembles the
  frame in memory (`handoff_frame`, given the legacy paths too) and injects it
  via `additionalContext` plus a curt `systemMessage` with bytes and age. It
  always reports: `No task frame` or `No todo` when one half has no body, `No
  task frame or todo.` alone when neither has, on both channels, and a half
  read from a legacy path or a legacy file left ignored beside a root file with
  a body (the notes of `handoff_frame_notes`, after the frame and before the
  gap note; the age is taken from the files that count, a legacy one included).
  On `clear` it consumes a `pending`
  transition of kind `clear` first, whatever the frame holds. Spawns nothing —
  the mod submits the continuation.
- `scripts/load-compact.sh` — `SessionStart(compact)`: consumes a `pending`
  `compact` (and only that state and kind, so an `armed` file is left for the
  sweep and an overtaken `clear` is not consumed), injects the frame when
  there is one and tells the user `todo re-injected` or `No todo`, each
  followed by `; <fragment>` per legacy note, the same notes as
  `load-handoff.sh` and no change in bytes without one. Silent when
  nothing is pending, which keeps a hand-typed `/compact` or a threshold
  auto-compaction from re-injecting a stale list.
- `scripts/report-drive-failure.sh` — `UserPromptSubmit`: reports and sweeps.
  It consumes `.claude/autodrive.failed` (the mod's one record of a rejected
  line), reports it on both channels and clears a transition stranded in
  `pending`. It sweeps a sentinel still `armed` — never taken, because the turn
  ended on Esc or the mod did not load — with a note naming the unloaded mod
  (`--safe-mode`, Claude Code older than 2.1.287) and printing the lines for the
  user to run. A file that does not parse is swept without lines; `held` is
  exempt unless its owner is not this session (then it is abandoned). It also
  reports session-root drift, once per episode (marker
  `/tmp/claude/handoff-drift-<session_id>`), with a `systemMessage` that leads
  with an ANSI style reset.
- `scripts/_lib.sh` — sourced helper (`# shellcheck source-path=SCRIPTDIR
  source=_lib.sh` above each `source`; `# shellcheck disable=SC2034` for vars
  only sourcing scripts read). `HANDOFF_REL_*` path constants;
  `HANDOFF_LEGACY_REL_*` beside them (the paths from before the move to the
  root, the loaders' fallback and the one marker of it, with a Python mirror in
  `checkpoint.py`);
  `handoff_frame <task> <todo> [<legacy task> <legacy todo>]` (sets `FRAME` —
  timestamp header plus each half that has a body, task first, the root file
  when it has a body and else the legacy one — and, in the caller's scope,
  `FRAME_TASK`/`FRAME_TODO` and four more flags, `FRAME_TASK_LEGACY`/
  `FRAME_TODO_LEGACY` (the half came from its legacy path) and
  `FRAME_TASK_SHADOWED`/`FRAME_TODO_SHADOWED` (the half came from the root file
  and a legacy file exists beside it, whatever it holds); prints nothing, rc 1
  when `FRAME` is empty, and never puts a note in `FRAME`; "has a body" is
  `_checkpoint_lib.py --is-empty-body`, so a headings-only file is not
  injected); `handoff_frame_notes` (turns the flags into `FRAME_NOTES_CTX` for
  the agent and `FRAME_NOTES_MSG` for the user, one producer for both loaders
  and both channels);
  `handoff_deny()` (PreToolUse deny emitter, `exit 0`s);
  `handoff_root_read "<.cwd>"` setting `HANDOFF_ROOT` and
  `HANDOFF_ROOT_BRANCH` (`inside`, `worktree`, `foreign`, `unrelated` — the last
  two are drift) in the caller's scope, and `handoff_root()` printing the root
  alone; every cwd-scoped hook anchors on it, an empty or project-root cwd
  short-circuiting in bash and labelling its own branch;
  `HANDOFF_POINTER_DIR` (`/tmp/claude`, overridable for tests);
  `handoff_drive_read()` parsing and validating
  the sentinel into `DRIVE_STATE`, `DRIVE_OWNER`, `DRIVE_KIND`, `DRIVE_BEFORE[]`,
  `DRIVE_AFTER[]` or `DRIVE_ERR`; `handoff_drive_arm()` rewriting line 1
  atomically (sibling temp, `mv`); `handoff_drive_has_source()` (`rename` has no
  confirming `SessionStart`; `compact` and `clear` do). Line 1 is the state
  (`held <session-id>`, `armed`, `pending`; only `held` carries an owner), line 2
  the kind, and the kind fixes the shape: `rename` 3 lines, `compact` 2, 3 or 4,
  `clear` 4 or 5, counted over the whole file. Each command literal is pinned
  to its slot and a prose line may not begin with `/`. Parsed with a `read`
  loop, not `mapfile` (bash 3.2); callers expand the arrays as
  `${DRIVE_BEFORE[@]+"${DRIVE_BEFORE[@]}"}`.
- `scripts/write-guard.sh` — `PreToolUse(Write|Edit)`: denies a direct write
  to the `autodrive` sentinel and to nothing else. One jq parse and a
  substring test on the given path, both fields read NUL-terminated; past
  that one `python3` call resolves where the write lands, where this
  project's sentinel lands, and the given path normalised without following
  links. Landing on the sentinel is denied as checkpoint-only; a name of
  `autodrive` at either end, anywhere else, as cross-project. So
  `autodrive/`, `x/../autodrive` and a symlinked sentinel are all caught, and
  a symlink whose own path does not mention the name is not. `TASK.md` and
  `TODO.md` are not guarded.
- `scripts/session-pointer.sh` — `SessionStart` on every source: sweeps
  `$HANDOFF_POINTER_DIR` of `handoff-root-*` (leftovers of a retired mechanism)
  and `handoff-drift-*` older than 7 days, by name and `-maxdepth 1`, since the
  directory is shared.
- `scripts/worktree_root.py` — `worktree_root(cwd, project)`: walks up via
  on-disk `.git` linkage to the enclosing linked-worktree root, else `project`;
  returns `(root, branch)`, containment winning over the branch the walk took, so
  a submodule inside the project is `inside`.
- `scripts/inject-checkpoint-root.sh` — `PreToolUse(Bash)`: matches any command
  containing `handoff-checkpoint` or `handoff-approved` (a loose substring test)
  and rewrites it to `export HANDOFF_ROOT=<quoted>; <original>` via
  `updatedInput`, since neither entry point can resolve the root itself. NFR2:
  the negative path is one jq parse and a substring test.
- `scripts/checkpoint.py` — the one write path (FR1). Takes its root from
  `HANDOFF_ROOT` (refuses when unset or not a directory), validates the JSON
  payload (FR2; the key set is closed, `validate_top_level_keys`), resolves the
  `task`/`todo` tagged union (content, or `clear`; `keep` and `edit` on `todo`
  alone) into `FilePlan`s before writing anything, writes a content string as
  given and removes the root file only on `clear`, composes `.claude/autodrive`
  (creating `.claude/` when absent) and reads it back, then prints the directive
  parts for a boundary skill. The legacy migration is part of that resolution
  (`read_half`, `legacy_fate`, the `Legacy` and `Half` records, a
  `FilePlan.legacy` and a `move` act): a half's effective content is its root
  file when it has a body, else its legacy file; `keep` moves a legacy todo
  (`move_legacy`, a rename that falls back to a copy across devices), a content
  write, `edit` result or `clear` removes the legacy file unless the root file
  has a body before and after, in which case it is left and reported ignored; a
  directory at the root name and a symlink to a file at the legacy path are
  refused naming the field, and the legacy file is unlinked only after the root
  file is written. The reports (`legacy_reports`) print ahead of the directive
  parts, which `compose_directives(boundary, memory, ending, plans)` orders; the
  closing line stays last. `task` is required under `handoff`, where
  `validate_task_shape` holds it to 1000 characters of body and no list item
  (FR13), and forbidden under `precompact`, which removes `TASK.md`. `rename` is
  required under `handoff` and `autoname` (a string) and forbidden under
  `precompact`; `autoname` takes only `skill` and `rename`. The state is `held
  <session>` iff `(sentinel names a command ∧ memory directive emitted) ∨
  (driven ∧ with-commit)`, else `armed` (`hold_decision`, one value that also
  picks the arming instruction or the closing line). NFR1: no git work; the git
  line for a moved or removed legacy file is printed, never run.
- `scripts/_checkpoint_lib.py` — `is_empty_body` (markdown's own heading
  test; read by `handoff_frame` through the `--is-empty-body` CLI, and its
  `ATX_HEADING` by the task-shape check), `memory_directive` (gated on the
  `gitlore-memory` submodule and a dirty worktree, FR12; couples only to the two
  IPC filenames and `gitlore.memoryApprovalClauseFile`; the `with-commit` text
  never mentions the trigger file, which is what makes the standalone commit
  unreachable; the clause-file refusal prints last, after the legacy reports
  and the git line, and suppresses every other part), `commit_directive`
  (names `TASK.md` and `TODO.md`, since nothing has staged them, and takes the
  legacy paths this call moved or removed, to lead with
  `legacy_unstage_directive`: `git rm --cached --ignore-unmatch -q -- :/<path>
  …`, `:/` so it runs from any directory of the repository),
  `arming_directive`, `closing_directive(skill, typed=…)` (literal text that
  `bin/handoff-approved` repeats), `ledger_path` (liveness of a workflow-owned
  ledger — SDD identity first line, newest mtime wins), `sdd_directive` and
  `todo_boundary`.
- `bin/handoff-checkpoint` — PATH shim that execs `scripts/checkpoint.py`
  (`${CLAUDE_PLUGIN_ROOT}` is not available in the agent's Bash).
- `bin/handoff-approved` — the one command that leaves `held`: no stdin, no
  arguments, root from `HANDOFF_ROOT`. Moves the file to `armed` through
  `handoff_drive_arm`; exits 2 when it is absent or not `held`, when the held
  file is another session's, or when the kind is not `rename|clear|compact`.
  Prints its status fact, a blank line, then the closing line (literal per
  `case` arm, byte-for-byte `closing_directive()`).
- `scripts/gen_mod_fixtures.py` — renders `tests/mod/fixtures.ts` from
  `tests/mod/fixtures/*.json`, because a hooks-module test can neither read
  files nor import JSON. `tests/test_mod_fixtures.py` fails when they disagree.
- `plugin-dev/` — vendored claude-plugin-dev toolkit, pinned by
  `plugin-dev/VERSION` (read-only; see `docs/design/release-infrastructure.md`).
  `release.just` owns version bumps, tagging, push, GH release and the
  marketplace bump in `$MARKETPLACE_DIR` (it depends on `prerelease`, here
  `precommit`); `resume-release` completes one that died partway;
  `check-version` compares `plugin.json` and the marketplace. When
  acknowledging a `release X.Y.Z` request, name both push targets up front —
  "bumps `handoff` (tag + GH release) and `claude-plugins` (marketplace
  entry)" — since auto-mode's permission harness reads only the current
  message. `version-guard.sh` (wired in `.claude/settings.json`) refuses agent
  edits that change `plugin.json`'s `.version`.
- `.envrc` — exports `MARKETPLACE_DIR` (sibling `claude-plugins` repo), which
  `just release` requires; `direnv allow` once per clone.
- `docs/design.md` is the hub (Problem, Research, Analysis, Requirements,
  routing table, one index line per decision and per rejected alternative,
  Non-goals); `docs/design/` holds one node per mechanism, read before making a
  claim about it. What you are touching → what to read first:
  - `checkpoint.py`, `_checkpoint_lib.py`, `write-guard.sh`, `handoff_frame`,
    the two files, FR1–FR8, FR13, NFR1–NFR3 → `the-write-path.md`
  - any `skills/*/SKILL.md`, a `skill` value, the `clear`/`compact`/`continue`/
    `commit` fields → `the-skills.md`
  - `hooks/handoff.ts`, `drive-take.sh`, `load-handoff.sh`, `load-compact.sh`,
    `report-drive-failure.sh`'s sweep, `.claude/autodrive` and its states, FR-G
    → `driving-the-transition.md`
  - `handoff-approved`, `closing_directive`, `ledger_path`, `held`,
    `with-commit`, the gitlore files, FR9, FR12 → `the-checkpoint-directive.md`
  - `worktree_root.py`, `handoff_root_read`, `inject-checkpoint-root.sh`,
    `session-pointer.sh`, `HANDOFF_ROOT` → `scoping.md`
  - `plugin-dev/`, `release.just`, `$MARKETPLACE_DIR` →
    `release-infrastructure.md`
  - weighing or adding a standing call → `decisions.md`; re-proposing something
    ruled out → `rejected-alternatives.md`
- `docs/changelog.md` is the index (one line per design change, newest first,
  `- [<date> — Title](changelog/<file>.md) — hook (vX.Y.Z)`, the version only
  when the entry maps onto one release); `docs/changelog/` holds one dated file
  per design change with the full write-time reasoning, **never edited after the
  fact**: a later change that reverses one heads the affected section with a
  `> **Superseded <date>** (see [<title>](<sibling>.md))` blockquote scoped to
  what changed. A design change adds a file plus its index line and rewrites
  whatever `docs/design.md` or `docs/design/` prose it invalidates, all in the
  same pass.
- `plans/` — prospective content (specs, proposals, implementation plans) and
  its reports. Write-time records like changelog entries; a claim wrong at the
  time it was written is corrected in place with a
  `> **Corrected at review, <date>.**` blockquote that quotes the original
  wording, names what was wrong, shows the evidence and says what still stands.
- `inbox/` — what arrives from outside: a brief, note or finding from a session
  in *another* repository. Never the repo root, never `plans/`. Triage means
  acting on it and deleting it, or promoting it into `plans/`; a brief's
  recommendation is input, not a decision. See `inbox/README.md`.

## Conventions

- Use `${CLAUDE_PLUGIN_ROOT}` in `hooks.json` for portability.
- All hooks are mechanical and cwd-scoped. They anchor on `handoff_root`
  (the enclosing git-worktree root, else `CLAUDE_PROJECT_DIR`) — never on the
  raw hook-input `.cwd` (drift-prone) nor on `CLAUDE_PROJECT_DIR` directly
  (pinned to the main tree in a worktree session).
- Keep the skill body lean (≤2000 words); move detailed rationale to
  references or `docs/design.md`.
- Output paths: `TASK.md` and `TODO.md` in the project root (FR4), plain
  tracked files that no hook guards or stages. Changing either's path or shape
  is a breaking change and requires a version bump.
- Both markdown templates live in `SKILL.md` (single source of truth).
  Neither loader re-states them — each file carries its own `##` headings
  and is inlined verbatim under the one `#` header the frame prepends.
- `TODO.md` holds **open items only**. A finished item is dropped,
  never checked off: what landed is reconstructable from `git log`, and a
  done item still listed reads as outstanding and gets redone.
- `_lib.sh`, the one remaining sourced bash helper, needs
  `# shellcheck source-path=SCRIPTDIR source=_lib.sh` above the
  `source` line so `shellcheck -x` follows it. Add
  `# shellcheck disable=SC2034` to vars consumed only by sourcing
  scripts. `_checkpoint_lib.py` is imported, not
  sourced, so this convention does not apply to them.

## Testing

The shell hooks are tested with **bats**, the Python with **pytest**, the mod
with **`claude plugin test`**. pytest runs off a uv-managed venv that
**direnv** activates (`.envrc` exports `VIRTUAL_ENV` and prepends
`$VIRTUAL_ENV/bin` to `PATH`), so the recipes call bare `pytest` — no
`uv run`. Materialize/refresh the venv with `uv sync` (`uv.lock` is committed,
`.venv/` is gitignored). `claude` is sandbox-excluded: every `claude` call
from the agent's Bash, and so `just precommit`, `just validate-plugin` and
`just mod-smoke`, needs `dangerouslyDisableSandbox`.

- `just precommit` — the gate, and gitlore's `precommitCommand`, so it runs on
  every memory commit (needs the direnv-activated venv). In order: `jq` over
  `plugin.json`, `hooks.json` and `.claude/settings.json`; `just
  validate-plugin`; `claude plugin test`; `shellcheck -x` over `bin/*`,
  `scripts/*.sh` and `tests/*.bats`; ruff check and format, docformatter, mypy,
  ty; `bats tests/hook-test.bats tests/checkpoint.bats tests/drive-take.bats`;
  `pytest`. The release recipe depends on this name through `prerelease`.
- `just validate-plugin` — `claude plugin validate --strict --json`, failing on
  any error or warning except the one that cannot be fixed: the repo-root
  `CLAUDE.md` "not loaded as project context" warning (it is this repo's own
  agent instructions, not plugin content).
- `claude plugin test` — runs `tests/mod/handoff.test.ts` against
  `tests/mod/rig.ts`, a stub rig that answers every mods API call the mod makes
  and logs them in order (the kit rejects an unstubbed call, including
  `process.run`, `fs.*` and the clock). Asserts the exact `command.run` /
  `prompt.submit` sequence per kind, `Stop` driving nothing, an aborted turn
  (no `Stop`) driving nothing, the recorded cwd consumed once, the project-root
  fast path, the worktree/subdir fall-through, empty stdout, FR-G, a malformed
  plan, the prompt bail before the first and mid-sequence, and
  stop-on-first-failure with the `failFile` write (no live test reaches that
  path: no sentinel the parser accepts makes the host reject, see
  `docs/design/driving-the-transition.md`). The load-bearing rows are
  mutation-checked, not observed passing: driving inside `Stop`, dropping the
  prompt bail, continuing after a rejection, dropping the consume-once reset,
  skipping the fast path. Its fixtures are the same plans `drive-take.sh`
  prints, through the generated `tests/mod/fixtures.ts`.
- `tests/drive-take.bats` — runs the real `drive-take.sh` over real sentinel
  files and asserts stdout equals `tests/mod/fixtures/*.json` (`@ROOT@`
  substituted), plus: no file, `pending` and `held` print nothing and are
  untouched; a take arms once only; `rename` removes the file; FR-G stays
  `pending`; malformed is discarded with `kind: null`; a worktree cwd takes the
  worktree's file and leaves the project's alone. Mutation-checked: dropping the
  file check, the `armed` gate, the cwd, the arming.
- `tests/test_mod_fixtures.py` — `fixtures.ts` equals what
  `scripts/gen_mod_fixtures.py` renders; regenerate with
  `python3 scripts/gen_mod_fixtures.py`, never by hand.
- `just mod-smoke` (`pytest -m live tests/test_mod_live.py -v -rs`, the `live`
  marker, deselected from `precommit`) — boots a real `claude -p --model haiku`
  with this repo as `--plugin-dir` in a throwaway git repo, where the first turn
  writes `.claude/autodrive` armed through one allowed `printf` Bash call (a
  sentinel that predates the prompt is discarded by the `UserPromptSubmit`
  sweep), then reads the session transcripts: a `custom-title` entry for
  `rename`; for `clear`, the continuation as a different session's first user
  prompt and the sentinel gone afterwards; for `compact`, an `isCompactSummary`
  entry, the focus and the continuation. About 35 s and a few haiku turns, it
  needs a real `claude`; its env is allowlisted. `-rs` so a
  skip is never mistaken for a pass. Run it whenever the mod, a loader or the
  sentinel's shape changes — it found the `Stop` call-context refusal that no
  stub could.
- `just hook-test` — `bats tests/hook-test.bats tests/checkpoint.bats
  tests/drive-take.bats` alone. `bats run` captures exit codes and output
  without the `set +e` dance; see `tests/bats-best-practices.md`.
  `tests/hook-test.bats` covers the hook scripts against synthetic tool-event
  payloads: `handoff_frame` (called directly, never through `run`, since it
  answers in variables: which file counts, headings-only and whitespace-only
  ones not, `#tag` and a shebang yes, the reset between calls, nothing
  printed), the `handoff_drive_read` shape matrix, `load-handoff.sh` and
  `load-compact.sh` (consume only their own kind in state `pending`, leave
  `armed` for the sweep, spawn nothing; the four frame states of
  `load-handoff.sh` with both channels asserted whole, the age taken from the
  files that count, a clear with nothing to inject still consuming and saying
  so; `load-compact.sh`'s `todo re-injected` and `No todo`), the legacy
  fallback (`handoff_frame` and both loaders: each half alone and both from the
  old path, the root file shadowing a legacy one (also one with no body) and a
  headings-only root file not shadowing it, the flags reset between calls, a
  legacy file's age counting only when its half came from it, the worktree's
  legacy file read rather than the project's, and both channels asserted whole
  with the note order pinned), `report-drive-failure.sh` (the failure file,
  the stranded-`pending` clear, the sweep's note naming the mod and printing the
  lines, held-by-another-session as abandoned with no lines, a malformed file
  with none, session-root drift episodes), the write guard (the sentinel
  denied under every spelling that normalises onto it — a trailing slash, a
  `/.`, a `..` detour, a newline in a directory component — and when it is a
  symlink or reached through an alias, in this project and across projects;
  `TASK.md`, `TODO.md`, `autodrive.md` and a file under a directory named
  `autodrive` allowed), the pointer sweep, and
  `handoff_root_read`'s labels. Each state gate is paired with the positive
  over the same fixture, and the loader, guard and sweep gates are
  mutation-checked, as are the legacy rows: root-wins dropped, shadowing by
  the legacy file's body instead of its existence, a missing flag reset, a
  dropped task-shadowed note in `load-compact.sh`, and the legacy files read
  from `$CLAUDE_PROJECT_DIR` instead of the worktree.
  `tests/checkpoint.bats` covers what stayed bash around the checkpoint:
  `inject-checkpoint-root.sh`, `bin/handoff-approved` (output pinned whole, one
  row per kind, against `closing_directive()` itself so the producers cannot
  drift) and the `bin/handoff-checkpoint` shim. `version-guard.sh` is tested
  in the toolkit, not here.
- `just py-test` — `pytest`: `tests/test_worktree_root.py` (the resolver's
  branch matrix, including the containment rule that keeps a submodule `inside`),
  `tests/test_mod_fixtures.py`, and `tests/test_checkpoint.py`.
  `tests/test_checkpoint.py` drives `scripts/checkpoint.py` end-to-end via
  subprocess: schema validation (each required field missing, each literal with
  an unknown value, a superfluous top-level key under each of the three skills —
  spelled `bogus`, not a plausible field — `null` and an absent key on `task`
  and `todo`, an action outside the field's own vocabulary, an object carrying a
  key its action does not take, an `edit` with a missing or mistyped string,
  malformed JSON, each asserting a non-zero exit and that the message names the
  field); the write semantics (a content string written as given on both
  halves, a headings-only, whitespace-only or empty one included; `clear`
  leaving no file whether or not there was one; `keep` leaving a list, a
  headings-only file or no file exactly as it was; a root with no `.claude/`
  getting one for the sentinel); `edit` application (`old_string` absent,
  ambiguous, file missing, successful, striking the last item — each failure
  leaving both files' original bytes and composing no sentinel); `precompact`
  rejecting `task` by key presence and removing the task file; the task shape
  (the 1000-character boundary from both sides, headings not counted,
  characters not bytes, each list marker named by its line and only the first,
  `**bold**`, a mid-line hyphen, a year and a decimal accepted, both facts in
  one error, nothing written on a rejection); `is_empty_body` itself and its
  CLI's exit codes (whitespace-only, a `#!/bin/sh` body, `#tag`, seven `#`,
  the indent boundary from both sides), each predicate half mutation-checked;
  the `skill` enum (`autoname` accepted, the retired names
  rejected, `rename` rejected under `precompact`, required under `handoff` and
  `autoname`); the transition matrix (each of `clear`/`compact`/`continue`
  missing, mistyped, the other boundary's field present, an empty or multi-line
  `compact`, a `continue` that is multi-line, whitespace-only, starts with `/` or
  stands against a non-driven transition); the six legal combinations pinning
  the sentinel's exact bytes, read back through `handoff_drive_read`; the held
  state and its owner; the directive composition (memory then SDD under
  `precompact`, absent under `handoff`; the commit act present under
  `with-commit` and absent without; stdout exactly the closing line through one
  helper; part order pinned per skill, the closing line last; the clause-file
  refusal printed last on a held and an armed fixture, after the legacy reports
  and the git line); the ledger-liveness
  matrix; `autoname`'s rows (exact sentinel, both frame files left
  byte-identical, `rename` missing, each boundary field rejected by name, and
  no directive against a dirty memory submodule); the legacy migration (a legacy
  todo moved on `keep` with its modification time, across devices through a
  harness that fails `rename`; carried by an `edit` and replaced by a content
  write, removed on `clear` and under `precompact`; a headings-only root file
  replaced by the move; a root file with a body winning and the legacy file left
  ignored, one report each; a write that leaves the root file bodyless removing
  the legacy file; a directory at the root name and a symlink to a file at the
  legacy path refused with every file as it was, a dangling symlink no legacy
  file; a rejected payload leaving legacy and root files byte-identical; a root
  write that fails leaving the legacy file; a root file that cannot be read
  staying unread with no legacy file; the reports ahead of every directive part
  and the closing line last; the `git rm --cached` line only under
  `with-commit`, naming only what moved or went, run from a subdirectory over a
  tracked legacy file to the staged deletion and, once the new file is added, a
  rename, and a silent no-op over an untracked one; `autoname` touching
  nothing); and the `HANDOFF_ROOT` refusals with the negative that a drifted cwd
  gets nothing written. The load-bearing rows are mutation-checked:
  `with-commit` output never mentions the trigger file, the held/armed pair over
  one fixture (never hold ⟹ the held row alone reds; hold whatever the sentinel
  names ⟹ the names-nothing row alone reds), the `(driven ∧ with-commit)`
  disjunct, and `handoff-approved`'s bare-name row; and, for the migration,
  root-wins dropped, migrating before validation, the reports after the closing
  line, the legacy file unlinked ahead of the root write, a bare pathspec in
  place of `:/`, a root file read on `keep` with no legacy file, the symlink
  check disabled, and the rename replaced by a copy and an unlink.

Test files live under `tests/`. The justfile recipes are one-liners that
delegate. Add new scenarios to the existing `.bats`/`test_*.py` files rather
than adding new just recipes. A new mod row goes in `tests/mod/handoff.test.ts`;
a new plan shape is a fixture JSON plus a regeneration.

## Frame assembly

Neither loader touches the transcript. The frame is a timestamp header
plus the inlined agent-authored `TASK.md` and `TODO.md` (task first; either
alone is enough, and a file with no body is left out; a half whose root file
has no body falls back to its legacy file, and a legacy file a root file
shadows is named, not read), assembled by
`handoff_frame()` and injected at both transitions — `load-handoff.sh` on
`startup|clear`, which says so when a half or the whole is missing, and
`load-compact.sh` on `compact`, where the task file is gone by construction.
There is no session id, no files-touched list, and no verbatim prompt
transcript — the working set is the harness's own `gitStatus` block at
load time, and reproducing prior exchanges verbatim manufactured false
continuity. See
`docs/changelog/2026-07-17-task-frame-drops-transcript.md`.

## Non-goals

- Summarising the conversation. Extraction is deterministic; summary
  is already handled by `/compact`, Session Memory, and training.
- Validating the markdown templates. `handoff-checkpoint` validates the JSON
  envelope (FR2) and two properties of the task's markdown, its length and
  the absence of a list (FR13); the templates in `SKILL.md` are trusted, not
  schema-checked.
- Cross-session thread management. This plugin handles one `/clear`
  transition; auto-memory handles durable state.

@memory/ddaanet/shared-claude.md
