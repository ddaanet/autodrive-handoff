# 2026-10-17 — The checkpoint's lock covers the plan

The checkpoint took the sentinel's lock after it had resolved the `TASK.md` and
`TODO.md` plans, so an `edit` resolved against a body read before a wait was
applied afterwards over whatever the actor holding the lock had written in the
meantime, with the holder's change lost.

## Decision

Only the scope moves: `checkpoint.py` takes the lock before the first read of
either frame file, so planning (`plan_task`, `plan_todo`,
`require_something_to_continue`), applying the plans and writing the sentinel
are one locked scope. No new logic.

Left outside the lock, each for a reason:

- payload validation, `validate_root` and `require_session_id` read only the
  payload and the environment, and a bad call should not wait for a lock;
- the memory directive reads the gitlore submodule's state, which no actor of
  the sentinel writes, and `hold_decision` needs it;
- `check_sentinel_target` refuses a `.claude` that is a file, which the lock's
  own `mkdir` would otherwise meet first.

The lock still does not guard `TODO.md` against direct edits: the agent's Edit
tool takes none, and concurrent sessions in one root are a non-goal.

`tests/test_checkpoint_hold.py` has the row: a holder changes `TODO.md` (the
edit's `old_string` kept, another line altered) while the checkpoint waits, and
the result holds both changes.
