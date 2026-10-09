## Remaining

- Step 7, the dogfood: a real `/handoff:handoff` with `clear: true` and a continuation, and `/handoff:autoname`, in this repo, then a forced failure (an unknown command line in a hand-made armed sentinel) reported at the next prompt. Run `just mod-smoke` first against the installed Claude Code.
- A version bump through `just release` stays my human partner's call; the change is breaking (two `skill` values and one kind removed, Claude Code >= 2.1.287 required).
- Delegation notes for the next dispatches: launch delegates unnamed; a Write in this repo can return `gave no verdict`, so tell delegates to write through a Python script under `$TMPDIR`; keep every shell command on absolute paths with an explicit `cd`.
