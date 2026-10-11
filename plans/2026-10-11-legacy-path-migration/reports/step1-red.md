# Step 1 (Loader) — RED report

> **Corrected at review, 2026-10-11.** The report said "130 ok, 20 not ok". The run gives 22 not ok: two rows were left out of the list below, `load-handoff (age): a half loaded from a legacy path is aged by that file` and `load-handoff (age): a legacy file shadowed by a root file does not make the frame younger`. Both are red at `[ "$framed" != "$CTX" ]` (the note suffix is absent), and both extend the "age is taken from the files that count" rule to legacy files, which is the plan's intent. They stay. After the review fixes (`step1-red-fixes.md`) the file holds 155 rows: 130 ok, 25 not ok. The three added rows are red; the 22 earlier reds are unchanged and no previously passing row changed. What else changed is in `step1-red-fixes.md`; the interface and wording below stand, except that the headings-only legacy case in the "Shadowed means" line is now pinned (existence, F4).

Only `tests/hook-test.bats` changed. Not committed. The checked-out branch is `dev`, not `main`; I left it as is.
Baseline: `bats tests/hook-test.bats` is 130 ok, 20 not ok. All 20 are the new rows below.
`shellcheck -x tests/hook-test.bats` is clean. Run the new rows alone with `bats --filter 'legacy|shadow' tests/hook-test.bats`.

## Interface the tests fix (for GREEN)

`handoff_frame <task> <todo> [<legacy-task> <legacy-todo>]`
- The two legacy paths are optional. Absent is the same as a path that does not exist, so the existing two-argument rows stay valid.
- Per half: the root file when it has a body, else the legacy file when it has a body.
- `FRAME` keeps its shape (header, then task, then todo). It never contains a notice.
- New variables, each 1 or 0 and reset on every call:
  - `FRAME_TASK_LEGACY` and `FRAME_TODO_LEGACY`: the half came from the legacy path.
  - `FRAME_TASK_SHADOWED` and `FRAME_TODO_SHADOWED`: the half came from the root file and a legacy file exists beside it.
- Shadowed means the root file has a body and the legacy file exists. The rows do not test a legacy file that exists with no body behind a root file with a body.
- The loaders append the notices after `FRAME`. The size in the message is `${#FRAME}`, as today.
- Loader paths: `.claude/handoff-task.md` and `.claude/handoff-todo.md`, as `$cwd/...` constants in `_lib.sh`.

## Notice wording (constants at `loaded_re`, `tests/hook-test.bats`)

Agent channel (`additionalContext`), one paragraph per note:

| case | text |
|---|---|
| task from legacy | `Task loaded from legacy .claude/handoff-task.md; the next checkpoint moves it to TASK.md.` |
| todo from legacy | `Todo loaded from legacy .claude/handoff-todo.md; the next checkpoint moves it to TODO.md.` |
| task shadowed | `Legacy .claude/handoff-task.md is ignored: TASK.md has a body. Delete it once nothing in it is still needed.` |
| todo shadowed | `Legacy .claude/handoff-todo.md is ignored: TODO.md has a body. Delete it once nothing in it is still needed.` |

User channel (`systemMessage`) fragments:
- `task from .claude/handoff-task.md, next checkpoint moves it`
- `todo from .claude/handoff-todo.md, next checkpoint moves it`
- `.claude/handoff-task.md ignored, TASK.md wins`
- `.claude/handoff-todo.md ignored, TODO.md wins`

Order, identical on both channels: from-legacy task, from-legacy todo, ignored task, ignored todo, then the gap note.

`load-handoff.sh`:
- Message: `handoff: loaded — N B, saved AGE; <fragments "; "-joined>[; No todo|; No task frame]`.
- Context: `FRAME`, then each note as `\n\n<note>`, then the gap line `\n\nNo todo.` or `\n\nNo task frame.` when it applies, then `\n`.
- Both halves legacy gives no gap line.

`load-compact.sh`:
- Message: `handoff: compacted — todo re-injected; <fragments>.` or `handoff: compacted — No todo; <fragments>.`
- Context: `FRAME`, then each note as `\n\n<note>`, then `\n`. There is no gap line on this channel.
- With no notes, both are unchanged.

## Rows added (all in `tests/hook-test.bats`)

The `handoff_frame` rows come after "handoff_frame (output)" and are called directly, never through `run`.
- `handoff_frame (legacy task alone)`: red at the line `[ "$rc" -eq 0 ]`. Legacy is ignored today, so rc is 1.
- `handoff_frame (legacy todo alone)`: red at `[ "$rc" -eq 0 ]`, same reason.
- `handoff_frame (both halves legacy)`: red at `[ "$rc" -eq 0 ]`, same reason.
- `handoff_frame (root with a body beside a legacy file)`: the rc and frame assertions pass, then it fails at `[ "${FRAME_TASK_LEGACY:-unset}" = "0" ]` because the variable is unset.
- `handoff_frame (root task shadows a legacy task, todo only legacy)`: red at `assert_framed`. The todo is not loaded from legacy today.
- `handoff_frame (headings-only root beside a legacy body)`: red at `[ "$rc" -eq 0 ]`.
- `handoff_frame (neither root nor legacy has a body)`: rc, FRAME and the old flags pass, then it fails at `[ "${FRAME_TASK_LEGACY:-unset}" = "0" ]`.
- `handoff_frame (a second call)`: the first call's rc passes, then it fails at `[ "${FRAME_TODO_LEGACY:-unset}" = "1" ]`.

The `load-handoff` rows follow the "neither state" row, after a new `assert_notes <frame-size> <tail>` helper.
- `load-handoff (legacy task alone)`: red at `[ "$framed" != "$CTX" ]`. The context is `No task frame or todo.\n`, so the suffix strip changes nothing.
- `load-handoff (legacy todo alone)`: red at `[ "$framed" != "$CTX" ]`.
- `load-handoff (both halves legacy)`, run under source `startup`: red at `[ "$framed" != "$CTX" ]`.
- `load-handoff (root files with a body shadow legacy files)`: red at `[ "$framed" != "$CTX" ]`. The root frame loads today but the notes are missing.
- `load-handoff (root task shadows a legacy task, todo only legacy)`: red at `[ "$framed" != "$CTX" ]`.
- `load-handoff (headings-only root task beside a legacy task body)`: red at `[ "$framed" != "$CTX" ]`.
- `load-handoff (headings-only root todo beside a legacy todo body)`: red at `[ "$framed" != "$CTX" ]`.
- `load-handoff (legacy files with no body, no root file)`: GUARD. It passes today and must keep passing: no frame, no legacy note, the neither state on both channels.

The `load-compact` rows come before "pending of kind clear".
- `load-compact (legacy todo alone, no task)`: red at the `$MSG` equality. The message today is `compacted — No todo.`.
- `load-compact (legacy task alone)`: red at the `$MSG` equality.
- `load-compact (both halves legacy)`: red at the `$MSG` equality.
- `load-compact (root todo with a body shadows a legacy todo)`: red at the `$MSG` equality.
- `load-compact (headings-only root todo beside a legacy todo body)`: red at the `$MSG` equality.
- `load-compact (legacy files with no body, no root file)`: GUARD. It passes today (consumed, `compacted — No todo.`, nothing injected).

## Plan inconsistency to settle before GREEN (flag, not decided)

For a headings-only root file beside a legacy file with a body, the loader contract loads the legacy file. The checkpoint contract defines the effective current content as the root file if it exists, else the legacy file. A headings-only root file exists, so the checkpoint would treat that half as "both present: root wins", and the legacy file would not be moved.

My from-legacy notice says "the next checkpoint moves it". In this case that claim would be false unless Step 2 treats a body-less root file as absent. Resolve this in Step 2, or reword the headings-only rows' note.
