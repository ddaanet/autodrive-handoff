# Item 3.2 slice 1 — test review

Scope: the three rows `handoff-approved: status fact then closing content —
{rename,clear,compact}` in `tests/checkpoint.bats`. SUT (`bin/handoff-approved`)
untouched.

## Checks

1. **Mechanical.** Before fixes: rows 13–15 failed on assertions (content
   checks at lines 218/228/239), rows 1–12 and 16–27 green. Confirmed.
2. **Held for this session / exit 0.** Each fixture's line 1 is
   `held $CLAUDE_CODE_SESSION_ID` (the suite's exported id, same as the
   existing held→armed row), and each kind's shape parses under
   `handoff_drive_read` (`rename` 3 lines, `clear` 4, `compact` 3). Each row
   asserts `[ "$status" -eq 0 ]` before any content check, and the red run
   shows the status and line-1 assertions passing — so the rows reach the
   success path, not a refusal.
3. **Blank-line separator — was missing; fixed.** The interface specifies
   status fact, one blank line, then the closing line; no row asserted the
   blank line. Bats' `lines` array drops empty lines, so `${lines[1]}` cannot
   express it. Added to all three rows:
   `[[ "$output" == "${lines[0]}"$'\n\n'* ]]`, with a comment on the first.
4. **Wrong kind's closing line — was open; fixed lightly.** `clear` and
   `compact` both asserted only `End on one line` present / `Ready to` absent,
   so a script printing the clear line for compact (or vice versa) passed.
   Added `*"Clear armed"*` to the `clear` row and `*"Compaction armed"*` to the
   `compact` row — the kind-distinguishing word from `closing_directive`
   (`_checkpoint_lib.py:204-208`). Case-sensitive, so neither matches the
   lowercase status fact (`clear armed` / `compact armed`). The `rename` row's
   `Ready to /clear` already excludes the `/compact` variant. Exact text stays
   slice 2's job.
5. **Bats idioms.** Bare mid-body `[[ … ]]` is the file's existing idiom, and
   per `shell-gotchas` `references/bats.md` (verified on Bats 1.11.1, the
   installed version) a failing mid-body `[[` aborts the test under errexit.
   No change needed.

## Re-run after fixes

`bats tests/checkpoint.bats`: rows 13–15 `not ok`, each now failing on the
separator assertion (`[[ "$output" == "${lines[0]}"$'\n\n'* ]]`) — a genuine
assertion red, since today's output is the status fact alone with no blank
line after it. All other rows green. `shellcheck -x tests/checkpoint.bats`
clean.

Sanity: the strengthened assertions were evaluated against the expected
GREEN output (status fact, `\n\n`, `closing_directive("handoff", typed=True)`)
and pass, so they do not over-constrain the implementation.

Nothing committed.
