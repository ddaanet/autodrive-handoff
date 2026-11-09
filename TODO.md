## Open decisions

- Whether to commit the `TASK.md` rename staged in `/Users/david/code/Archive/2026/raspberrypi` (its legacy `.claude/handoff-task.md`, migrated with `git mv`). It is another repo, so it waits on my human partner's say. Default: commit it there as `docs: move the task file to the root`.
- Whether to release `dev` now: it carries the legacy-fallback removal since 0.21.2 and has had per-commit review only, not the release review.

## Remaining

- gitlore 0.11.0 shipped D70 on 2026-10-31, so the `gitlore:commit` skill the memory directive names exists. At the next wrap-up over dirty memory, check that the agent reaches the skill and commits through it, and that the memory commit carries no zero-byte sandbox mask (`git -C memory show --stat HEAD`, unsandboxed).
- Decide whether to rework the prompt-after-`Stop` cancel, from the `/simplify` altitude review: `scripts/drive-cancel.sh` repeats decisions the take already makes, and `hooks/handoff.ts` tells a cancel from a rename plan by whether `note` is present. The proposal, not prototyped: the mod runs `drive-take.sh` at the first of `turn.complete` or an in-window prompt, keeps the plan on the window, and cancel shrinks to removing the `pending` file it just made. One more case, found by the release review: a cancel answered in a later window removes an earlier drive's `pending` file while that drive runs on (the `pending)` arm of `scripts/drive-cancel.sh`, whose outcome `tests/mod/window.test.ts` pins), so the toast and note claim a cancel, a sweep is recorded for a transition that ran, and the prompt is answered in a context that is then cleared; the trigger is inferred, not probed.
