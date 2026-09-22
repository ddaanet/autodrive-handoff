# The hooks' walker exports get a seam

2026-09-22. Closes the last item of the 2026-09-21 frame: the four spawning
hooks' `HANDOFF_LOG_FILE` (and sibling) exports had no row, for want of a
synchronous seam on a detached spawn.

## The seam

`stub_walker` in `tests/hook-test.bats`: a `python3` stub placed first on the
suite's `PATH` for the row. When its argv names `drive_when_idle.py` it writes
the walker's `HANDOFF_LOG_FILE`, `HANDOFF_FAIL_FILE`, `HANDOFF_PENDING_FILE`,
`HANDOFF_EXIT_FILE`, `HANDOFF_TRANSCRIPT` and the argv after the script path
to `$BATS_TEST_TMPDIR/walker-spawn` and exits; any other `python3` call
(`worktree_root.py`, `_checkpoint_lib.py`) execs the real interpreter,
captured before the stub dir is prepended. Installed per row, not in
`setup()`: most rows never spawn the walker. `wait_for_walker_spawn` polls for
the dump, 0.05s × 60.

## Rows

One per hook — `stop-drive.sh` (armed `rename`, before-line `/rename …`),
`load-handoff.sh` (`source: clear`, pending `clear` with after-line),
`load-compact.sh` (pending `compact` with continuation), `load-restart.sh`
(pending `restart` with continuation). Each pins the five paths exactly —
only `stop-drive.sh` exports the pending and exited ones — plus the pane and
the lines handed as argv.

## Mutation check

`export HANDOFF_LOG_FILE=…` commented out in `scripts/load-compact.sh`, then
`bats tests/hook-test.bats`:

```
1..146
not ok 110 load-compact.sh: the walker is handed the log, fail and transcript paths for the after-line
```

That row alone. Restored.

## Gate

`just precommit`: every lint clean, bats ok, `285 passed, 14 deselected`.

The dispatched sonnet agent wrote the rows and the `CLAUDE.md` update and went
idle on its background gate; the mutation check, the gate and this report
were run by the orchestrating session.
