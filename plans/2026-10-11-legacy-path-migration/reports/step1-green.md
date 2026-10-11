# Step 1 (Loader) — GREEN report

Changed: `scripts/_lib.sh`, `scripts/load-handoff.sh`, `scripts/load-compact.sh`. Nothing else (`tests/hook-test.bats` untouched by this slice, `_checkpoint_lib.py` untouched). Nothing staged or committed.

## Interface (`scripts/_lib.sh`)

- Constants beside `HANDOFF_REL_*`: `HANDOFF_LEGACY_REL_TASK=".claude/handoff-task.md"`, `HANDOFF_LEGACY_REL_TODO=".claude/handoff-todo.md"`. The comment names them as the one marker for the fallback and gives the retirement condition (no sibling repository still has `.claude/handoff-*.md`, check `ls /Users/david/code/*/.claude/handoff-*.md`); no version number.
- `handoff_frame <task> <todo> [<legacy-task> <legacy-todo>]`: per half, root file when it has a body, else the legacy file when it has a body. Sets on every call by plain assignment: `FRAME`, `FRAME_TASK`, `FRAME_TODO`, `FRAME_TASK_LEGACY`, `FRAME_TODO_LEGACY`, `FRAME_TASK_SHADOWED`, `FRAME_TODO_SHADOWED`. Shadowed = root half counts and the legacy file exists (`-f`, body or not). rc 1 when `FRAME` is empty. `FRAME` never holds a note. Spawn count: the body check (python) runs on a legacy file only when the root half has no body, and not at all when the legacy path does not exist, so repositories without legacy files spawn exactly what they did.
- `_handoff_has_body <lib> <path>`: private helper (file with a body).
- `handoff_frame_notes`: reads the flags and sets parallel arrays `FRAME_NOTES_CTX` (agent sentences) and `FRAME_NOTES_MSG` (user fragments), reset per call, order: task legacy, todo legacy, task ignored, todo ignored. Text built from the path constants, so both loaders produce identical notes and step 2 can mirror them. Expand as `${A[@]+"${A[@]}"}` (bash 3.2, `set -u`).

## Loaders

- Both anchor on `handoff_root` (`$cwd`) for the root and legacy paths; the worktree row covers it.
- `load-handoff.sh`: passes the legacy paths, calls `handoff_frame_notes`; age is taken from the legacy file when it supplied the half, the root file when it did, and a shadowed legacy file is not counted; context gets each note as `\n\n<note>` then the gap line; message gets the fragments after `loaded — …` and before the gap note. Size stays `${#FRAME}` (notes are appended to `context` after `FRAME` is measured).
- `load-compact.sh`: same frame call and notes; message is `handoff: compacted — todo re-injected|No todo` then `; <fragment>` per note and a final `.`; context is `FRAME` plus notes; still silent with nothing pending and still consumes only a `pending` `compact`.
- Header comments updated where they turned false (`handoff_frame` header, `load-handoff.sh` header). No docs, README, CLAUDE.md or plan touched.

## Evidence

| suite | before | after |
|---|---|---|
| `bats tests/hook-test.bats` | 155 rows, 130 ok, 25 not ok | 155 rows, 155 ok, 0 not ok (counts from `$TMPDIR/bats.out`) |
| `bats tests/checkpoint.bats tests/drive-take.bats` | not run before the change (files untouched by the slice) | 28 ok, 0 not ok |
| `pytest -q` | not run before the change | 224 passed, 3 deselected |
| `shellcheck -x scripts/*.sh bin/* tests/*.bats` | | clean |

`just precommit` and `just mod-smoke` not run (step 4).

## Mutation checks

Each applied as a temporary edit to `scripts/_lib.sh`, run with `bats --filter 'legacy|shadow|handoff_frame'`, then restored from a copy; `diff` against the copy and `git status` confirm the restore.

| mutant | red rows |
|---|---|
| root-wins dropped (task half checks the legacy file first) | 6: `handoff_frame` root-with-body, root-task-shadows, second call; `load-handoff` root files shadow, root task shadows; `load-compact` root task shadows |
| shadowed set by legacy body instead of existence (todo half) | 1: `handoff_frame (root with a body beside a legacy file with no body)` |
| flags not reset between calls, as `: "${X:=0}"` | 1: `handoff_frame (a second call)` |
| flags not reset, reset lines deleted outright | 27 (unset variables under `set -u` and the `:-unset` guards), more than the targeted mutant |

## Inconsistencies found

- None in the tests. The plan's Amended blockquote and the tests agree with the code (body decides on both sides in the loader; existence decides "shadowed").
- Note for step 2: the shadowed note's wording (`… is ignored: TASK.md has a body.`) and the from-legacy promise ("the next checkpoint moves it") now exist only in `handoff_frame_notes`; the checkpoint's stdout is a separate Python producer, so mirroring is by hand and needs its own rows.
