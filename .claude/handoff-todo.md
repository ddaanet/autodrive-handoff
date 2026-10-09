## Remaining

- Confirm the clear dogfood: this session's first prompt was the continuation, the frame was injected, and `.claude/autodrive` and `.claude/autodrive.failed` are absent.
- Forced failure: arm a sentinel whose command line is unknown (check the exact shape against `handoff_drive_read` first), end a turn, and confirm the next prompt reports the rejected line and `.claude/autodrive.failed` is consumed.
- Not-loaded path: launch with `claude --safe-mode`, arm a sentinel, submit any prompt, and confirm the sweep note names the unloaded mod and prints the lines to type.
- Delete the leftover `.claude/autodrive.log` (written only by the retired walker) if it is untracked.
- Write the dogfood result into the plan's reports directory as `step7-dogfood.md`.
- Release: the version bump through `just release` is my human partner's call; the change is breaking (the `restart` kind and skill are gone).