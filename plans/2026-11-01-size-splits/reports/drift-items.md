# Drift items report

Commit 1461ea6 (dev). `just precommit`: passed (520 pytest, check-plugin, check-code, check-refs, check-size).

## 1. Doc drift
- `skills/handoff/references/design.md:26`: "last user prompts" -> "current task" (Next step row uses "current task + open decisions"; no transcript is read, decisions.md:92).
- `.gitignore`: `git grep` shows no hit in scripts/, hooks/, bin/, skills/. Only other hit: tests/test_checkpoint_directives.py:86-87, which asserts the names are absent from the output. Removed both entries and the comment.

## 2. autodrive.failed limit (holds)
`scripts/report-drive-failure.sh:196-231` reads and consumes `$failed` with no session or owner check (owner logic at 189, 241, 293 covers only the sentinel). It also clears a stranded `pending` (222-226). Added a bullet to the Limits list of `docs/design/sessions-sharing-a-root.md`.

## 3. Precompact claim (was wrong)
`scripts/checkpoint.py:370-372` composes `lib.sdd_directive` into the stdout of the same call that writes `TODO.md`; `_checkpoint_lib.py:221-241` holds the "Keep them out of TODO.md" text. `skills/precompact/SKILL.md` never mentions SDD or the ledger. Rewrote the sentence in `docs/design/the-checkpoint-directive.md` (~line 80): precompact is no different; the nudge guides the next edit, not that write.

## Notes
- TODO.md: the three items dropped; TASK.md left unstaged. `memory` submodule shows modified (untouched).
