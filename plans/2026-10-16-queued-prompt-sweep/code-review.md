Verdict: changes needed

Comment fixes only (findings 1-3). The code conforms to the contract, and every
planned mutation reds. Baseline in the copy: `bats tests/hook-test.bats
tests/checkpoint.bats` has 0 `not ok` (305 rows).

## Mutations

Each applied alone in a copy of the tree, run with `bats tests/hook-test.bats
tests/checkpoint.bats`, then discarded. The repo was not edited.

| Mutation | Red rows | Which |
|---|---|---|
| (a) drop `drive_owner == session_id` from the queued condition | 1 | 228 "queued id, armed by another session whose transcript is stale: swept as today" |
| (b) drop `-n "$prompt_id"` from the queued condition | 1 | 222 "no prompt_id and no marker: swept, not mistaken for a queued prompt" |
| (c1) drop the kind test, queued rename treated like clear/compact (swept) | 2 | 215 "owner's armed rename is spared"; 224 "id with leading and trailing spaces and a newline, matching exactly, is spared" |
| (c2) drop the kind test, queued clear/compact treated like rename (left) | 2 | 217 clear swept and recorded; 219 compact swept and recorded |
| (d) drop the marker write in `inject-checkpoint-root.sh` | 6 | 283, 284, 285, 289, 290, 291 (all the writer rows) |
| (e) write the marker in the sweep (after the read) on every prompt | 2 | 226 "a prompt with an id writes no marker, whatever the sentinel does"; 265 "no drift, a prompt_id and its marker, no sentinel: no find forked" |
| (f) restore the `$.prompt.read()` bail in `hooks/handoff.ts` (`claude plugin test`, unsandboxed) | 6 of 16 | the host reports `no implementation for prompt.read` and skips the hook; the rows that expect a drive go red (including first rejected line, rejected continuation, link at failFile; 10 pass, 6 fail) |

Extra mutations beyond the plan:

| Mutation | Red rows | Which |
|---|---|---|
| (g) drop the `armed` state test from the queued read | 1 | 229 "queued id, a held or pending file: left untouched, nothing said" |
| (h) drop `marker_dir_ok` from the queued read | 2 | 232, 233 (symlinked / group- or world-writable directory) |
| (i) drop `own` from `handoff_read_regular "$prompt_marker"` | **0, survives** | no row has a marker owned by another user |
| (j) drop `handoff-prompt-*` from the `session-pointer.sh` sweep | 1 | 187 "sweeps a long-stale prompt marker" |

Note on (f): with the bail restored and the `prompt.read` stub gone, the red comes
from the kit rejecting an unstubbed call, not from a log mismatch. That is the
plan's intent ("its absence from every log pins the change"). The rows would
also go red on a restored bail if the stub were back, because every expected log
now omits `prompt.read`.

## Findings

1. `scripts/report-drive-failure.sh:15-16` (header point 2) and `:296-297` (body
   comment above the `armed_lines` block): "one still in state `armed` when a
   later turn begins never ran". A queued prompt arrives inside the arming turn,
   so this premise is the one the plan told the rewrite to correct, and it still
   sits beside the new queued logic. Same line 11-12: "Two causes" now has a
   third case (queued) described a few lines on. Fix: say "when a prompt
   arrives" in both places, and "Two causes of a stale file" so the queued
   paragraph reads as the exception it is.

2. `scripts/report-drive-failure.sh:27` (header): "the checkpoint call records
   that id". A held checkpoint is armed by `handoff-approved` in a later turn,
   and the hook writes the marker for both entry points (plan item 1,
   `inject-checkpoint-root.sh` matches either). Fix: "the checkpoint or
   `handoff-approved` call".

3. `tests/mod/handoff.test.ts:127`: the section header `// --- bail and failure ---`
   is stale now that both bail rows are gone. Fix: `// --- failure ---`.

4. `scripts/inject-checkpoint-root.sh:1-22` (file header): describes only the
   root rewrite. The hook now has a second effect, the prompt marker, and the
   only comment on it is at line 50. Fix: one sentence in the header, e.g. "On
   the matching path it also records the turn's prompt_id for
   report-drive-failure.sh (the prompt marker); the negative path is unchanged."
   Optional. Also line 50-52's "and the rewrite below is the same" is cryptic;
   "stdout is the same rewrite as without a marker" says it.

5. Mutation (i) survives: nothing pins the `own` argument for the prompt marker.
   A non-root test cannot create a file owned by another user, and the drift
   marker's `own` appears to be equally unpinned, so this matches the existing
   standard. Report only; no fix needed unless a row for the drift marker exists
   that this one should mirror.

6. Minor, not required: `marker_dir_ok` in `scripts/_lib.sh:519` is the only
   helper there without the `handoff_` prefix. It was moved verbatim, which is
   defensible; renaming means touching `report-drive-failure.sh` (3 uses),
   `inject-checkpoint-root.sh` and the `session-pointer.sh:24` comment.
   `session_id` is concatenated into the marker's path unvalidated, as the drift
   marker already does; a `/` or `..` in it makes the write fail silently
   (`mktemp` finds no directory), so it is not exploitable. No change.

## Checked, no defect

- Contract: `prompt_id` is the 4th NUL-terminated field. Queued is armed,
  owner equals session, session and prompt id non-empty, marker equals id. A
  queued rename is left with no output and no sweep record. Queued clear/compact
  are swept with `record_sweep`, the cancel fragment, the per-kind directive
  note, and no lines. A missing `prompt_id` adds the mid-sentence typed-ahead
  cause. The sweep never writes the marker (mutation e).
- Fork cost: the marker read (one `find`, one `python3`) is behind the armed,
  owner and non-empty-id test, which is evaluated in that order, so an ordinary
  prompt forks nothing new; row 265 and mutation (g) pin it.
- Whitespace/NUL: both ids are read `IFS= read -r -d ''` and written with
  `printf '%s\0'`; the sweep reads the status line, then the value to NUL. Rows
  224 and 291 cover a space and a trailing newline on each side.
- `inject-checkpoint-root.sh`: negative path still one `jq` parse (now four
  fields) and a `case` substring test; the marker block sits after the
  `unresolved` and empty-root exits, so it never runs on the negative path or an
  unresolved root. Every command in it is `|| true` or inside an `if`, with
  stderr silenced, so `set -e` cannot change stdout (mutation d and rows 290,
  289 pin it).
- `handoff_write_marker` names its sibling `<path>.XXXXXX`, which matches
  `handoff-prompt-*`, and the `find` in `session-pointer.sh` is `-mtime +7
  -delete` over that glob, so an orphan is swept. Failure removes the sibling.
- `hooks/handoff.ts` and `tests/mod/rig.ts`: no dead code left (`reads`,
  `promptTexts`, the `prompt.read` stub and its type comment are all gone; no
  other reference to `prompt.read` or a composer check in `hooks/` or
  `tests/mod/`).
- The header rewrite is accurate to the repro reports (fresh `prompt_id` after
  Esc; the turn's own `prompt_id` for a queued prompt) and does not narrate plan
  history.

## Not reviewed

Docs, changelog, `CLAUDE.md` and `README.md` (plan item 3) are unchanged, as the
green report says; they still state the old composer bail and the sweep's
premise. They remain to be done.
