# Step 1 (Loader) — RED review

Reviewed: `git diff tests/hook-test.bats` (uncommitted), against `plan.md`
(Decisions, Contracts "Loader", Steps 1) and `reports/step1-red.md`.

## Verdict: APPROVE WITH CHANGES

The red is genuine and the suite has teeth for nearly every mutant named in the
brief. Before GREEN starts: add one `load-compact` row (F1) and settle the
plan inconsistency (F2). The rest are low-cost hardening and record fixes. None
of them changes an existing row's expectations, except F7 if the directive
sentence is dropped.

## How this was checked

- `bats tests/hook-test.bats` on the working tree: **152 rows, 130 ok, 22 not
  ok**. The 128 rows at `HEAD` plus the 2 new guards pass. All 22 failures are
  new rows. The author's report says 20 because it leaves out the two `age`
  rows (F6).
- **Satisfiability.** In a scratch copy (`$TMPDIR/ref`, outside the repo), I
  wrote a reference implementation of `handoff_frame` with the four flags, a
  shared note builder and the two loaders, following the author's interface.
  All **152/152 pass**. So no red row fails because of a typo, a fixture slip or
  a helper bug: the assertions, fixtures and helpers can all be met together.
- **Red reasons**, read from the bats output. Each failure is an assertion about
  the missing behaviour:
  - `[ "$rc" -eq 0 ]`: legacy is ignored today (rows 24–26, 29).
  - `${FRAME_*_LEGACY:-unset} = 0|1`: the flags do not exist yet (27, 30, 31).
  - `assert_framed`: the legacy todo is not loaded (28).
  - `[ "$framed" != "$CTX" ]`: the note suffix is absent (load-handoff 85–93).
  - The `$MSG` equality (load-compact 111–115).

  Rows that stop at their first assertion have later assertions nobody has seen
  run. The reference run covers those too.
- **Mutation run.** 19 mutants of the reference implementation, each applied
  in place and proved to have landed. Results:

| mutant | killed by |
|---|---|
| task/todo legacy flags swapped | 24, 26, 29, 85, 87, 90, 112, 113 |
| root-wins dropped, todo half (legacy preferred) | 27, 88, 93, 114 |
| root-wins dropped, task half | 27, 28, 31, 88, 89 |
| shadowed flag set when root is headings-only | 29, 90 |
| headings-only root file wins (existence shadows) | 29, 91, 115 |
| load-handoff: notes on context only / message only | 85–93 (each) |
| load-compact: notes on context only / message only | 111–115 (each) |
| load-handoff: gap line before the notes | 85–93 |
| note order per half instead of per kind | 89 only |
| age includes a shadowed legacy file | 93 |
| size counts more than `FRAME` | 85–93 and two pre-existing load-handoff rows |
| load-compact drops the task-legacy note | 112, 113 |
| legacy file counted by existence, not body (guards) | 94, 116 |
| **load-compact drops the task-shadowed note** | **survives** (F1) |
| **two of the four flags reset lazily (`:=0`)** | **survives** (F3) |
| **shadowed requires a legacy *body*, not existence** | **survives** (F4) |
| **legacy read from `$CLAUDE_PROJECT_DIR`, not the root** | **survives** (F5) |

- `assert_notes` (`tests/hook-test.bats:1050`) is not vacuous. The regex is
  anchored at `^` and covers the whole lead through the size, which is pinned
  to `${#framed}`, the age and the `; `. The remainder is then compared to `$2`
  for equality. The message is therefore asserted whole. The context is
  asserted whole by the pattern used in every row: strip a fixed suffix, check
  `framed != CTX`, then `assert_framed` on the rest. The two mutants that drop a
  channel confirm it.
- `shellcheck -x tests/hook-test.bats` is clean. `git diff --name-only` lists
  `TASK.md`, `TODO.md` and `tests/hook-test.bats`. The `TASK.md`/`TODO.md`
  edits were already in the session-start snapshot and are the orchestrator's
  frame, not this slice's. Production code is unchanged.

## Findings, ranked

### F1 (medium): load-compact never sees a shadowed task or two kinds of note together

`tests/hook-test.bats:1432–1515`. The compact rows cover legacy todo, legacy
task, both legacy, shadowed todo and headings-only todo. No row has a root
`TASK.md` with a body beside a legacy task, and none mixes a from-legacy note
with an ignored note. **Verified mutant:** load-compact drops the
task-shadowed note, and all compact rows pass. A load-compact whose note order
differs from load-handoff's would also pass. That mutant is plausible if GREEN
builds the notes in each loader rather than in `_lib.sh`. The loader's own
comment says a hand-written `TASK.md` with a body is injected at this boundary,
so this case is real.

**Fix.** Add one row:
- Files: `$tmp/TASK.md` with a body (the seeded one will do), a legacy task, a
  legacy todo, no `TODO.md`, pending `compact`.
- `MSG`: `handoff: compacted — todo re-injected; $legacy_todo_msg; $shadowed_task_msg.`
- `CTX`: header, the root task, the legacy todo, then `$legacy_todo_ctx`, then
  `$shadowed_task_ctx`, then `\n`.

That one row kills both mutants.

### F2 (medium, a decision): the from-legacy note's promise against the Checkpoint contract

This is the author's flagged inconsistency. It affects rows 29, 90, 91 and 115
(`:408`, `:1133`, `:1146`, `:1492`).

**Analysis.** The loader decides by body: "the root file when it has a body;
else the legacy file". The Checkpoint contract decides by existence:
"Effective current content … is the root file, else the legacy file"; "Both
present: root wins, legacy untouched". With a headings-only root file beside a
legacy body, the agent is shown the legacy content and told "the next
checkpoint moves it". The checkpoint then treats the half as "both present".
Consequences under the plan as written:

- `todo: keep` keeps the headings-only root file and leaves the legacy file
  where it is. Every later load shows the legacy file again with the same false
  promise. The state never resolves on its own.
- `todo: edit` with an `old_string` copied from the frame fails with
  `old_string` absent, because it runs against the root file
  (`plan_todo`, `scripts/checkpoint.py:529`). The agent sees text in its frame
  that the checkpoint says is not there.
- A content string writes the root file and leaves the legacy file untouched.
  If the written content has a body, the next load reports the legacy file as
  ignored, which is acceptable. If it is headings-only (the agent finished
  every item), **the stale legacy todo comes back as the frame** at the next
  load, and finished items get redone.
- The checkpoint's "reported as ignored" notice is false for this half: the
  loader read the legacy file, it did not ignore it.

**Option A: Step 2 treats a body-less root file as absent** (effective content
is the root file when it has a body, else the legacy file).
- The loader and the checkpoint share one predicate, `is_empty_body`, which the
  checkpoint already imports.
- The note becomes true. `keep` and `edit` act on what the agent was shown.
- The move overwrites a root file that has only headings. Nothing but headings
  is lost, including when the file is a project's own `TODO.md` holding only
  headings.
- It costs one amendment to the plan's Checkpoint bullets: "root absent" in
  the rename bullet becomes "root absent or without a body", and "Both
  present" becomes "root with a body". It also adds one pytest row per action
  in Step 2.
- These red rows stand as written.

**Option B: reword the note for this case.** For example: "loaded from legacy
…; TASK.md has no body, so the next checkpoint leaves both in place".
- This adds a third note type, and rows 29/90/91/115 change.
- The stuck state and the `edit` mismatch above remain by design. The agent can
  only resolve them by hand.
- The resurrection-after-headings-only hazard remains.
- The checkpoint's "ignored" report still contradicts the loader.

**Recommendation: A.** Bring it to my human partner for the call before GREEN,
since it amends the plan's Checkpoint contract. It does not touch the Loader
contract.

A related hole, for Step 2 and not this slice: A does not close it alone. When
a root file has a body and a legacy file sits beside it ("both present: legacy
untouched"), a later checkpoint that writes the root file body-less brings the
legacy file back at the next load. Step 2 should judge this by the root file
*after* the write. When the planned root content has no body and a legacy file
exists, either remove the legacy file as `clear` does, or say so on stdout.
Add this to the Step 2 rows or to `TODO.md`.

### F3 (low): the reset row sets only two of the four flags before resetting

`tests/hook-test.bats:439`. The first call sets `FRAME_TODO_LEGACY` and
`FRAME_TASK_SHADOWED`. `FRAME_TASK_LEGACY` and `FRAME_TODO_SHADOWED` are 0
before and after, so the row proves nothing about their reset. **Verified
mutant:** those two initialised with `: "${X:=0}"` instead of `X=0` pass every
row. `TASK_LEGACY` and `TASK_SHADOWED` cannot both be 1 in one call.

**Fix.** Three calls in the row:
1. Root task body, legacy task, legacy todo: assert `TODO_LEGACY=1` and
   `TASK_SHADOWED=1`.
2. Legacy task, root todo body, legacy todo, in a second directory: assert
   `TASK_LEGACY=1`, `TODO_SHADOWED=1`, and the first pair now 0.
3. The `gone-*` paths: assert all four are 0.

### F4 (low): "shadowed" with a body-less legacy file is unpinned

No row puts an empty or headings-only legacy file behind a root file with a
body. The author's report states this. **Verified mutant:** requiring a legacy
body for `*_SHADOWED` passes every row. The plan says "the legacy file exists
and is ignored". Step 2's "both present … reported as ignored" will go by
existence. Leaving the loader free to differ invites the loader and the
checkpoint to disagree about the same file.

**Fix.** Add one `handoff_frame` row: root todo with a body, zero-byte legacy
todo, so `FRAME_TODO_SHADOWED=1`. Or, if my human partner prefers silence for
a body-less legacy file, pin that with a row and say so in the plan.

### F5 (low): the legacy paths are only exercised where root equals `$CLAUDE_PROJECT_DIR`

Every loader row runs with `cwd = $tmp = $CLAUDE_PROJECT_DIR`. **Verified
mutant:** reading the legacy files from `$CLAUDE_PROJECT_DIR/.claude/` passes.
That breaks the repo convention that hooks anchor on `handoff_root`, never on
`CLAUDE_PROJECT_DIR`.

**Fix.** Add one row modelled on "load-handoff (worktree cwd: reads worktree
task, not main)" (`:1230`):
- `make_worktree`, with a legacy task body in `$wt/.claude/`.
- A different legacy task body in `$tmp/.claude/`, and no `$tmp/TASK.md`.
- Assert the worktree body and `$legacy_task_ctx` are in the context, and the
  main tree's body is not.

### F6 (record): the author's report miscounts and leaves out two rows

`reports/step1-red.md:4` says "130 ok, 20 not ok". The run gives 22 not ok.
Two rows are not listed: "load-handoff (age): a half loaded from a legacy path
is aged by that file" (`:1163`) and "… a legacy file shadowed by a root file
does not make the frame younger" (`:1176`). Both are sound. They extend
CLAUDE.md's "age taken from the files that count" to legacy files, which is
the plan's intent even though the Loader contract never mentions age. They
kill the "age includes a shadowed legacy" and "age from root paths" mutants.
Keep them, and amend the report to list them with their red lines (both fail
at `framed != CTX`).

### F7 (low, wording beyond the plan): the shadowed note issues a directive

`tests/hook-test.bats:929–930`: "… is ignored: TASK.md has a body. **Delete it
once nothing in it is still needed.**" The plan's Decision is that the agent
is told the file "is there" and "is ignored". The added sentence tells the
agent to delete a file that is usually tracked, on its own judgement. It is a
nudge toward an unrequested destructive edit, and it runs against the plan's
"never … removed by the migration" posture.

Recommend dropping the sentence, so the note ends at "TASK.md has a body.",
unless my human partner wants the nudge. Mechanically it is harmless either
way, but it is outward-facing wording, so it is my human partner's call.

The other wording and order choices are invented but forced by "asserted
whole", and harmless to implement as written:
- the four `_ctx` and `_msg` strings;
- from-legacy notes before ignored notes, task before todo;
- notes before the gap line;
- `; `-joined fragments before load-compact's closing full stop.

Suggest GREEN keep the strings as constants in `_lib.sh` next to
`LEGACY_RELS`, so Step 2's stdout can mirror them.

### F8 (nit): a comment that does not match its rows

`tests/hook-test.bats:1055`: "setup() seeds $tmp/TASK.md; each legacy row
removes it first." Rows at `:1100`, `:1118`, `:1133` and `:1163` overwrite it.
`:1146` relies on the seeded body (`hook smoke test` is in its expected frame).

**Fix.** "setup() seeds $tmp/TASK.md; a row that wants no root task removes
it, and a row that keeps it says so in its expected frame."

## Contract fit (summary)

The rows match the Loader contract and Decisions:
- Root wins (27, 88, 114).
- A headings-only root file does not shadow (29, 90, 91, 115).
- Both channels are asserted whole on both loaders.
- `FRAME_TASK`/`FRAME_TODO` keep their meaning, and `FRAME` never holds a note
  (every `handoff_frame` row checks `FRAME` whole).
- The old two-argument call still passes.
- The Step 1 list is covered: legacy only per half, both legacy, root shadows,
  headings-only root, neither (30, plus the guards 94 and 116).

The guards are non-vacuous in the same way as row 30: a loader that tested
existence instead of body fails both (mutation-checked, table above).

Style matches the neighbouring rows: helpers above their users, direct calls
for `handoff_frame`, `split_output`, the strip-suffix pattern and `:-unset`
guards. Paths are quoted throughout. The fixtures sit under
`$BATS_TEST_TMPDIR`, which has no spaces, the same as the existing rows.
