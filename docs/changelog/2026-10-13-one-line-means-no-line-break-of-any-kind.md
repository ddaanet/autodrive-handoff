# One line means no line break of any kind

2026-10-13.

## The defect

`require_one_line` in `_checkpoint_payload.py` held `continue` and the
`compact` focus directive to one line by rejecting `\n` and nothing else. Each
lands on a line of `.claude/autodrive` that the mod submits with one Enter, and
`handoff_drive_read` reads the file line by line. A CR, a vertical tab, a form
feed, NEL or a Unicode line or paragraph separator is a break to a terminal, to
a TUI composer or to some other line-wise reader, so a payload carrying one
passed validation and could be submitted early or split where the parser saw a
single line.

Beside it, the loaders' note for a task read from the legacy
`.claude/handoff-task.md` said the next checkpoint *moves it* to `TASK.md`.
Only the todo half is ever moved (`keep` carries a legacy todo's bytes); `task`
is required content or `clear` under `handoff` and removed under
`precompact`, so a legacy task file is removed, never moved, and the note told
the agent its task would be carried when it would not.

## The change

- A one-line value is one `str.splitlines` leaves whole: `value.splitlines()`
  must be `[value]`. That rejects LF, CR, VT, FF, FS, GS, RS, NEL, LS and PS,
  and a trailing break too, and the error names them. Python's own list was
  taken rather than a hand-picked set, so the check and its documentation
  cannot drift. The `rename` title needed nothing: it is flattened on `\s`,
  which in Python matches every one of these.
- The legacy-task note says the next checkpoint removes the legacy file and
  that the task a handoff checkpoint is given goes to `TASK.md`, on both
  channels (`task from .claude/handoff-task.md, next checkpoint removes it`).
  The todo note is unchanged.

## Rows

`tests/test_checkpoint_transition.py`: `continue` and `compact` each with every
break, exit 2 naming the field and no sentinel written; red before the change
for every break but LF (18 of 20). Mutation: putting back the `"\n" in value`
test reds the same 18. The note's pinned wording in `tests/hook-test.bats`
(`legacy_task_ctx`, `legacy_task_msg`) was changed first, reding six loader
rows until the producer matched.
