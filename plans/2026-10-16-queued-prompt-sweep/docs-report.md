# Queued-prompt sweep: docs report

Docs only; nothing under scripts/, hooks/, tests/, memory/ or the other plans
files was touched, and nothing is committed.

## Files changed

- `docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md` (new) —
  the write-time record: the defect, the live evidence, the cancel-vs-spare
  decision and why, the marker at the checkpoint call and not per prompt, the
  no-`prompt_id` fallback, the mod's composer check removed, residual bounds
  (including the unpinned `own` on the marker read).
- `docs/changelog.md` — index line, newest first, no version.
- `docs/changelog/2026-10-08-the-plugin-becomes-a-mod.md` — Superseded
  blockquote scoped to the mod reading the prompt box.
- `docs/changelog/2026-10-13-the-armed-sentinel-has-an-owner.md` — Superseded
  blockquote scoped to "the owner's own prompt is the exact discriminator".
- `docs/changelog/2026-07-22-stale-autocompact.md` — Superseded blockquote
  scoped to "the owner's own prompt sweeps unconditionally".
- `docs/design/queued-prompts.md` (new) — the design node: the queued prompt,
  the `prompt_id` discriminator, the marker, the rename/clear/compact
  outcomes, why cancel, the no-id fallback, residual bounds. A new node
  because the section pushed `driving-the-transition.md` to 404 lines.
- `docs/design/driving-the-transition.md` — "Running the plan" no longer
  reads the composer (and says why); the stale-sentinel paragraphs now say
  "when a prompt arrives has not run" and point to the new node; a short
  pointer section; the third cause named; the Verification bullet drops the
  prompt bail.
- `docs/design/scoping.md` — the prompt marker beside the drift marker
  (writer, guards in `_lib.sh`, NFR2 negative path) and the pointer-dir sweep
  covering both.
- `docs/design/decisions.md` — the owner-judges-stale entry gains the queued
  exception; new standing call on cancel vs spare and the checkpoint-time marker.
- `docs/design/rejected-alternatives.md` — sparing every kind, recording every
  prompt's id in the sweep, the mod reading the prompt box; sidecar entry
  qualified.
- `docs/design.md` — FR-H no longer claims a prompt check; hub routing line
  for the new node; decision and rejected-alternative index lines.
- `CLAUDE.md` — mod bullet; `report-drive-failure.sh`, `_lib.sh`,
  `session-pointer.sh` and `inject-checkpoint-root.sh` bullets; the
  `claude plugin test` paragraph (bail row and mutation removed); routing table;
  `tests/hook-test.bats` and `tests/checkpoint.bats` coverage prose with the new
  rows, the mutation list and the `own` residual bound.
- `README.md` — hook table, "a prompt sent while the wrap-up turn still runs",
  the mod no longer checking the prompt box, the `PreToolUse(Bash)` marker, the
  new `/tmp/claude/handoff-prompt-<session id>` file row.
- `skills/handoff/references/design.md` — not touched; it states neither the
  old premise nor the bail.

## Final grep

`grep -rn "prompt.read\|prompt bail\|stops entirely on user text\|cannot fire between" CLAUDE.md README.md docs/ skills/`

```
docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md:97:**The mod no longer reads the composer.** The `$.prompt.read()` check before
docs/changelog/2026-10-16-a-prompt-queued-into-the-arming-turn.md:103:in `tests/mod/handoff.test.ts` now omits `prompt.read`, and an unstubbed call
docs/changelog/2026-10-08-the-plugin-becomes-a-mod.md:6:> longer does. The `$.prompt.read()` check before each line is gone, because
docs/changelog/2026-10-08-the-plugin-becomes-a-mod.md:42:(`$.prompt.submit`), read the prompt box (`$.prompt.read`) and show a toast.
```

The two today's-entry matches are the record of the removal itself. The 10-08
matches are the permitted superseding blockquote (line 6) and the entry's
untouched original text (line 42). No match in CLAUDE.md, README.md,
docs/design/ or skills/.

## Line counts of touched design files

```
 315 docs/design/decisions.md
 360 docs/design/driving-the-transition.md
  57 docs/design/queued-prompts.md
 330 docs/design/rejected-alternatives.md
 114 docs/design/scoping.md
 378 docs/design.md
```

All under 400.

## Notes

- I did not run a hard-wrapping formatter (`rumdl`) over the touched files;
  a few reflowed paragraphs may be ragged.
- The changelog entry's "queued compact / queued rename as its own turn" bound
  rests on the live-fix report's "not settled" list; the live run covered
  queued rename (spared), queued clear (cancelled) and Esc-then-prompt (swept).
- `skills/autoname/SKILL.md` line 36 ("the next prompt prints the line for the
  user to run") is still true for the unloaded-mod case; left as is.
