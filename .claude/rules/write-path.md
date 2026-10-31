---
paths:
  - "scripts/*checkpoint*.py"
  - "bin/handoff-*"
  - "tests/test_checkpoint_*.py"
---

# Write-path conventions

Behaviour lives in `docs/design/the-write-path.md` and
`docs/design/the-checkpoint-directive.md`; read the one you touch first.

- `checkpoint.py` is the one write path for `TASK.md` and `TODO.md` (FR1)
  and the one composer of `.claude/autodrive` (FR3). Past it, the plugin's
  scripts only rewrite the sentinel's state line (`handoff_drive_arm`) or
  remove it, and `write-guard.sh` denies an agent `Write`/`Edit` to it. Add no
  other composer.
- No git work (NFR1). A git line the agent needs, such as the legacy unstage,
  is printed, never run.
- Every schema or write-time error exits through `lib.err` in
  `_checkpoint_lib.py`: it names the field and exits 2.
- `_checkpoint_payload.py` reads the payload only. What reads the environment
  (`validate_root`, `require_session_id`) lives in `checkpoint.py`.
- `bin/handoff-approved` repeats `closing_directive()`'s text byte for byte,
  one literal per `case` arm: change both together. `tests/bin-commands.bats`
  pins its output against `closing_directive()` itself, so the two producers
  cannot drift.
- The memory directive is the same text under both commit modes.
- `tests/test_checkpoint_*.py` drive `scripts/checkpoint.py` end to end
  through a subprocess (`run_checkpoint`). They import `CONTINUATION` from
  `checkpoint.py` rather than restating it, and read the sentinel back
  through `handoff_drive_read`.
