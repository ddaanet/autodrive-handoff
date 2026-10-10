# TASK.md and TODO.md move to the project root

## Context

The task frame lives in two gitignored, force-added files under `.claude/`,
kept honest by five mechanisms: a write guard on the task file, a
`PostToolUse(Write|Edit)` stager for the todo file, a manifest plus
`PostToolUse(Bash)` stager for the checkpoint's writes, and an empty-body rule
two writers enforce. My human partner's call ("simplification shock") is that
this machinery guards a distinction that does not exist: the todo file is a
pending-work list like any `TODO.md`, and the task file needs no protection
the checkpoint authoring it whole does not already give.

Decided in conversation on 2026-10-10/11:

- The files become plain tracked `TASK.md` and `TODO.md` in the project root.
  A collision with an existing `TODO.md` is intentional.
- The hooks that deny task-file edits, auto-stage on edit and auto-remove on
  empty go.
- `SessionStart` reports an empty frame instead of staying silent: "No task
  frame", "No todo", "No task frame or todo." Empty means missing or
  headings-only.
- `precompact` always removes `TASK.md`; the summary carries the task.
- The task content is capped at 1500 characters of body and takes no list
  items, so step lists are forced into `TODO.md`. Evidence:
  `reports/task-length-survey.md` (the 282 current-contract versions: median
  716, p90 1754; the cap rejects 14.5% and the list rule catches the
  short list-bearing ones the cap misses).

  > **Corrected at review, 2026-10-11.** The draft said "441 versions since
  > the todo file existed" for these figures. They are the survey's
  > 282-version sample (era 3, no `## Open decisions`); the report's section 7
  > recomputes over all 441 (median 872, p90 2529, cap alone rejects 26.5%,
  > cap or list item 42.9%). Era 2, before the todo file took the step lists,
  > accounts for the gap (93.3% fail there). What still stands: the cap and
  > the list rule target era 3's behaviour, where they reject 13-14%.

  > **Corrected at review, 2026-10-11.** This bullet said the cap "is capped
  > at 1500 characters" as decided, and the note above said "What still
  > stands: the cap and the list rule target era 3's behaviour". My human
  > partner reopened the number: a threshold fitted to how often raw files
  > exceed it measures the symptom. It is set instead from what is left of a
  > task file once its overflow is sent where it belongs — the plan to execute
  > and open decisions to `TODO.md`, standing rules and conventions to memory
  > through the approval gate, what was just completed cut to one sentence —
  > leaving the task in hand and its immediate continuity.
  > `reports/overflow-analysis.md` measures that residual; the cap is written
  > **N** below until my human partner confirms a value. What still stands:
  > a character cap on the body and the no-list rule.
- The toolkit's `.claude/` release exemption is asked to go
  (`claude-plugin-dev/inbox/brief-remove-claude-exemption.md`, already
  dropped). A dirty `TASK.md`/`TODO.md` refusing a release is accepted.

Defaults I am taking where no answer was given — each is a line to strike
if wrong:

1. **The `autodrive` guard stays.** `write-guard.sh` shrinks to that one file.
2. **Checkpoint staging goes too** (manifest, `bash-post.sh`,
   `PostToolUse(Bash)`): nothing is gitignored, so nothing needs `git add -f`.
3. **The checkpoint stops deleting on an empty body.** Only an explicit
   `{"action": "clear"}` and the precompact removal delete. The emptiness rule
   has one reader left, the loader.
4. **No protection for a foreign `TODO.md`.** A whole-content `todo` write
   overwrites it; the file is tracked and was injected at session start, so
   the write is informed and recoverable. The skill gains one line: an
   existing list in another shape keeps its shape.
5. **No migration code.** Consumers move their files by hand; the README and
   the changelog entry carry the two `git mv` lines. Nothing reads the old
   paths.
6. **The empty-frame report goes on both channels** from `load-handoff.sh`
   only. `load-compact.sh` stays silent when no compaction was prepared.

## What changes

### Paths and the checkpoint

- `scripts/_lib.sh`, `scripts/checkpoint.py`: `HANDOFF_REL_TASK = "TASK.md"`,
  `HANDOFF_REL_TODO = "TODO.md"`. `.gitignore` loses the two file entries and
  `.claude/checkpoint-manifest`. This repo's own files: `git mv` to the root.
- `checkpoint.py`:
  - `write_manifest`, `FilePlan.manifest_lines` and every `W`/`D` line go.
  - `_plan_file` loses its `lib.is_empty_body` branch: a content string is a
    write, `clear` is a removal (`none` when the file is absent).
  - `task` under `precompact` is forbidden by key presence, like `rename`
    (`validate_task` takes `skill`); the precompact plan for the task file is
    always a removal.
  - New `validate_task_shape(content)`, run from `validate_task` so it fails
    before any write (the existing plan-then-apply order already guarantees
    this): body is the content minus ATX heading lines (reuse
    `lib._ATX_HEADING`, made public), stripped; `len(body) > N` or any line
    matching `^\s*([-*+]|\d+[.)])\s` is an `err("task", …)`. Each message
    names the measured fact (the count; the line number and its first words)
    and where the overflow goes: remaining steps and open decisions to
    `todo`, finished work cut to one sentence, standing rules and conventions
    to memory through its approval gate.
  - `compose_sentinel` creates `.claude/` if absent — with the frame in the
    root, the sentinel is the only thing left that needs the directory.
- `_checkpoint_lib.py`: `sdd_directive` and `todo_boundary` name `TODO.md`;
  `commit_directive` says the commit carries `TASK.md` and `TODO.md`, since
  nothing pre-stages them any more. `is_empty_body` and its CLI stay, now
  serving the loader.

### Hooks

- Delete `scripts/write-stage.sh` and `scripts/bash-post.sh` and their two
  `PostToolUse` entries in `hooks/hooks.json`; rewrite its `description`.
  Six command hooks remain.
- `scripts/write-guard.sh`: `autodrive` only. `handoff_match_target` drops to
  one (basename, rel) pair and loses `MATCHED_NAME`, its variadic form having
  one caller and one file left.
- `handoff_frame` (`_lib.sh`): a file counts when
  `python3 _checkpoint_lib.py --is-empty-body < file` says it has a body,
  replacing `-s`. It also sets `FRAME_TASK` / `FRAME_TODO` (0/1) in the
  caller's scope so the loaders can say which half is missing without testing
  twice.
- `scripts/load-handoff.sh`: the transition consume is unchanged and still
  precedes everything. Then the note is `loaded — <size>, saved <age>` plus
  `No task frame` or `No todo` when one half is empty, or `No task frame or
  todo.` alone when both are. The empty-frame note goes in `systemMessage`
  and `additionalContext`; the script no longer has a silent exit.
- `scripts/load-compact.sh`: unchanged gates. After a prepared compaction it
  injects what `handoff_frame` assembles (the todo; `TASK.md` is gone by
  construction) and reports `compacted — todo re-injected` or `compacted — No
  todo`.

### Skills

- `skills/handoff/SKILL.md`: paths; drop "denying a direct Write there" and
  the empty-content-removes paragraph; the task template states the cap and
  the no-list rule in one line each and loses "Usually one sentence"; the
  seam example moves the commit range from "the task file" to `TODO.md`,
  where the cap now sends it; one line on a pre-existing `TODO.md` keeping
  its shape. Stays under 2000 words.
- `skills/precompact/SKILL.md`: no `task` key; one sentence saying the
  summary carries the task and that anything that must survive verbatim goes
  in `TODO.md` or the `compact` focus directive; "the frame's re-injection"
  becomes the todo's.
- `skills/pending/SKILL.md`, `skills/autoname/SKILL.md`,
  `skills/handoff/references/design.md`: paths and the guard wording.

### Records (same pass as the code they describe)

- `docs/changelog/2026-10-11-task-and-todo-move-to-the-root.md` plus its index
  line: the argument above, the survey numbers, the 2026-07-20 reversal and
  why the todo file answers what motivated it, the six defaults.
- `> **Superseded 2026-10-11**` blockquotes, scoped to the section that
  changed, on `2026-07-20-one-task-file-two-transitions`,
  `2026-07-21-precompact-resets-the-task-file`,
  `2026-07-23-overflow-deserves-persistence` (force-add),
  `2026-07-27-one-channel-one-writer` (guard, manifest, content-decides-absence)
  and `2026-09-13-the-named-path-is-the-report` (bash-post).
- `docs/design.md`: FR3 narrows to the sentinel; FR4 covers both files; FR6
  and FR7 retire, numbers kept; new **FR13** (the task content is bounded);
  NFR2 names `PreToolUse(Bash)` alone; "eight hooks" becomes six; decision
  and rejected-alternative index lines follow their nodes.
- `docs/design/the-write-path.md` (rewritten around: two root files, one
  checkpoint, no staging), `decisions.md` ("The task file is checkpoint-only"
  and "Both files are tracked" rewritten; a new entry for the cap),
  `rejected-alternatives.md` (the `PostToolUse(Write|Edit)` merge entry goes
  with its subject), `the-skills.md`, `driving-the-transition.md` (FR-G now
  gates the todo), `the-checkpoint-directive.md`, `scoping.md`.
- `CLAUDE.md` layout, conventions and testing sections; `README.md`, with the
  upgrade note (`git mv .claude/handoff-task.md TASK.md` and the todo twin).
- The survey is promoted from `tmp/task-length-survey.md` to this plan's
  `reports/`, with the since-07-22 recomputation appended (its scratch data
  under `/tmp/claude/survey` will not survive).

## Steps

Each step is red first where it adds behaviour, ends on `just precommit`
(unsandboxed) and one commit on `main`. Load `craft:test-discipline` before
step 2, `craft:directive-writing` before wording the two `task` errors and
the loader notes, `craft:removing-cleanly` before step 4,
`craft:design-doc-writing` before step 6.

1. **Evidence into `plans/`**: the survey report beside this plan, committed
   with it. No code.
1a. **The overflow analysis** (added 2026-10-11): every task-file version
   since 2026-07-22 split into sentence units, each labelled by a Haiku
   reader as task-in-hand, plan, convention or done-log, counted by script;
   `reports/overflow-analysis.md` proposes N from the residual. No code.
   Step 2 waits on my human partner's value; steps 3 to 5 do not.
2. **The task shape rule** (`tests/test_checkpoint.py`, `checkpoint.py`).
   Rows: N passes and N+1 fails naming `task` and the count; heading
   lines do not count; a multi-byte body is counted in characters; each list
   marker fails naming its line; `**bold**` and a mid-line hyphen pass;
   nothing is written on either failure. Mutation-check the boundary and the
   heading exclusion.
3. **Precompact drops the task.** Rows: `task` rejected by name under
   `precompact`; an existing `TASK.md` is removed; an absent one is no error;
   the todo half is untouched. Skill body in the same commit.
4. **The move and the cut**, one commit because the halves do not stand
   alone: path constants, `.gitignore`, `git mv`, manifest and `FilePlan`
   slimming, implicit-empty removal, `write-stage.sh` and `bash-post.sh`
   deleted, `write-guard.sh` narrowed, `hooks.json`, directive wording, and
   every test that named the old paths or the cut mechanisms
   (`tests/hook-test.bats` write-stage and task-guard rows,
   `tests/checkpoint.bats` bash-post rows, the manifest assertions and FR6
   removal rows in `tests/test_checkpoint.py`). New negatives: a `Write` to
   `TASK.md` and to `TODO.md` is allowed; headings-only content is written as
   given.
5. **The loaders report.** `handoff_frame` rows first (headings-only counts
   as absent — red against `-s`), then `load-handoff.sh` (the three notes,
   each over the fixture its positive uses) and `load-compact.sh`.
   Mutation-check the body test and each note's condition.
6. **Records**: changelog entry, superseded notes, design hub and nodes,
   `CLAUDE.md`, `README.md`, remaining skill prose.

Steps 2, 3 and 5 are each a red dispatch then a green dispatch to a Sonnet
executor, reviewed one rung up; 1, 4 and 6 I do inline. Sequential, in the
main tree.

## Verification

- `just precommit` green at every commit; its recap lists the checks run.
- `just mod-smoke` after step 5 — a loader changed, and its `clear` and
  `compact` rows exercise both.
- `grep -rn 'handoff-task\|handoff-todo\|checkpoint-manifest\|write-stage\|bash-post'`
  over everything but `docs/changelog/`, `plans/` and `memory/` returns
  nothing.
- Dogfood the same day, from a second terminal:
  `claude --plugin-dir /Users/david/code/handoff` in a scratch repo holding a
  hand-written `TODO.md` — session start with neither file, with a
  headings-only `TASK.md`, with each alone; a `/handoff:handoff` whose task
  exceeds the cap; a `/handoff:precompact` over an existing `TASK.md`.
  Surprises patch this plan.

## Not in this plan

- **Releasing.** The shape change is breaking, so it wants 0.16.0, cut by
  `just release` when asked (it bumps `handoff` and `claude-plugins`).
- **This session's own wrap-up.** The plugin running here is the installed
  0.15.0, which still writes `.claude/handoff-*.md`. Until the release is
  installed, the session that implements this ends by editing `TASK.md` and
  `TODO.md` directly rather than through `/handoff:handoff`.
- **The toolkit exemption.** The brief is the end of this repo's part.
- **Other repos' stranded `.claude/handoff-*.md`.** Default 5: they are moved
  by hand, by whoever works in that repo next.
