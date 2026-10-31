---
paths:
  - "scripts/_checkpoint_lib.py"
  - "scripts/_checkpoint_plan.py"
  - "scripts/checkpoint.py"
  - "scripts/_lib.sh"
  - "scripts/_lib_drive.sh"
  - "scripts/_lib_frame.sh"
  - "scripts/load-*.sh"
  - "tests/*legacy*"
  - "tests/hook-helpers.bash"
  - "tests/lib-frame.bats"
  - "tests/load-compact.bats"
  - "tests/test_checkpoint_directives.py"
  - "tests/test_checkpoint_root_files.py"
---

# The legacy bridge

`.claude/handoff-task.md` and `.claude/handoff-todo.md` are the legacy files,
where the two halves lived before `TASK.md` and `TODO.md` moved to the root.
Behaviour lives in `docs/design/the-write-path.md` and
`docs/design/decisions.md`.

- Both ends decide by body, and shadowing by the legacy file's existence. The
  loaders read a half from its legacy file when the root file has no body; a
  root file with a body wins, and its legacy file is reported ignored, never
  touched. A symlink at any of the four paths counts as absent.
  `handoff_frame_notes` is the one producer of those notes, for both loaders
  and both channels.
- The checkpoint moves or removes a legacy file inside plan resolution, so it
  cannot come back as the frame: `keep` moves a legacy todo; a content write,
  an `edit` result or `clear` removes it unless the root file has a body before
  and after. A symlink to a file at the legacy path is refused, and the legacy
  file is unlinked only after the root file is written.
- Under `with-commit`, the commit act leads with
  `git -C <root> rm --cached --ignore-unmatch -q -- <path> …`
  (`legacy_unstage_directive`), naming only the paths this call moved or
  removed.
- One name per language marks the paths: `HANDOFF_LEGACY_REL_*` in `_lib.sh`
  and again in `_checkpoint_plan.py`. `tests/test_checkpoint_legacy.py` holds
  the whole checkpoint migration, one file whatever its length.
- The retirement names no version, in code, docs or tests.

## Removal

The bridge is removed not before 2026-11-16 (the legacy item in `TODO.md`).
The deletion pass starts from `grep -rni legacy scripts/ tests/`, not from
this file's `paths:`: the grep also finds legacy rows inside files not named
for it. It adds what the `TODO.md` item lists beyond that grep, the pieces
that lack the word among them, and ends by deleting this file,
`.claude/rules/legacy.md`.
