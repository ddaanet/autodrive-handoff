Verdict: pass

Reviewed `git diff -- tests/hook-test.bats tests/checkpoint.bats tests/mod/handoff.test.ts` against `plan.md`, `red-review.md` and `red-report.md`. No file under `scripts/`, `hooks/` or `tests/` was edited. The prototypes below ran in a copy under `$TMPDIR/p`.

## Re-run against unchanged code

- `bats tests/hook-test.bats tests/checkpoint.bats`: 305 tests, 13 not ok, matching the report.
  - Rows 187, 215, 217, 219, 221, 222, 224 are in `hook-test.bats`.
  - Rows 283, 284, 285, 289, 290, 291 are in `checkpoint.bats`.
  - Each fails on an assertion about the hook's output or the filesystem. Examples: `[ "$output" = "" ]`, `assert_cancel_report`, the `$noprompt_phrase` match, `[ ! -L … ]`, `marker_holds` (cmp, status 2 because the file is absent).
  - Nothing fails on setup or a missing helper.
  - Every companion and negative row is green. `shellcheck -x tests/hook-test.bats tests/checkpoint.bats` is clean.
- `claude plugin test`: 11 pass, 5 fail, each an `expect(...).toEqual` with `prompt.read` still in `Received`. The five are `compact with focus`, `clear: rename…`, `rename kind…`, `first rejected line…` and `a rejected continuation prompt…`. This matches the report.

## Prototype check

- **Injector.** I wrote a throwaway marker writer into `inject-checkpoint-root.sh`: ids read in the same NUL-terminated jq parse, `mkdir -m 700 -p`, the `marker_dir_ok` checks, a `mktemp` sibling and `handoff_replace`.
  - All 31 rows of `checkpoint.bats` go green.
  - Mutations that red at least one row:
    - `printf '%s\n'` for the NUL, 6 rows.
    - A write straight to the name with no `mktemp` sibling, row 289 (the symlink row).
    - `mkdir` without `-m 700`, row 283.
    - `or` for `and` on the id test, row 287.
    - Dropping the world/group-writable `find` check, row 290.
- **Sweep.** I patched `report-drive-failure.sh` to read `prompt_id` as a fourth NUL-terminated field. It reads the marker only for an armed file the session owns, behind `marker_dir_ok` and `handoff_read_regular … own`. It spares a queued rename, cancels a queued clear or compact with the exact plan text, and adds the typed-ahead phrase when the input has no `prompt_id`.
  - All 274 rows of `hook-test.bats` go green. That includes the whitespace rows, `no find forked` with a `prompt_id`, and the cancel rows with whole equality on `$CTX` and `$MSG`.
  - Mutations (the `session-pointer` row is red throughout because the prototype lacks the filter):
    - Owner test dropped: row 228 reds (the stale-transcript, other-session row).
    - Non-empty `prompt_id` test dropped: the `no prompt_id and no marker` row reds.
    - Kind test dropped: the clear and compact cancel rows red.
    - Compare to the first word only: the exact-whitespace spared row and the whitespace-mismatch row red.
    - Marker read without the NUL (`read -r`): the exact-whitespace spared row reds.
    - `marker_dir_ok` skipped: the symlinked-directory and writable-directory rows red.

## Earlier findings

1. Cancel rows assert whole equality from one template: resolved.
   - `assert_cancel_report` (`hook-test.bats:2892-2897`) builds the note from `The driven $2 did not run. Answer this prompt, then run the $3 skill again with the same transition, unless this prompt changes that.` and asserts `$CTX` equal to it.
   - The strings equal the plan's text: `/clear` with `handoff`, `/compact` with `precompact`.
   - `$MSG` equals `ESC[0m` + `handoff: transition cancelled — a prompt arrived before it ran.`, which is the plan's fragment with the existing prefix and closing period.
   - The `wc -l` = 1 and `kind=` assertions on the sweep record stay.
2. The `handoff` negative in the compact note: resolved. It is dropped and equality replaces it.
3. The `no find forked` row: resolved, option (b).
   - A new row (`hook-test.bats:3598`) sends `PROMPT_ID` with a matching marker and no sentinel, uses `find_witness_stub`, and asserts the marker is unchanged.
   - It stays green on my prototype, which reads the marker only for an armed, owned file.
   - It would red an implementation that runs `marker_dir_ok` before it knows it needs the marker.
   - The older `no drift, no marker` row stays as it was, which is correct.
4. Whitespace rows: resolved.
   - The exact-match row uses the id `$' lead  and trail \nsecond line \n'`, and a queued rename is spared.
   - The mismatch row covers a trailing space, a final newline, a leading space and an extra line, plus the marker being the longer. All are swept.
   - `checkpoint.bats` round-trips `two words`, a final newline, an inner newline, edge spaces and `-n\n`.
5. No lines offered: resolved by the equality on `$CTX` and `$MSG`. The seeded lines `pick up the queued task` and `/rename Queued Title` cannot appear.
6. Mod edits: resolved.
   - `prompt.read` leaves all five logs and the two bail rows are deleted.
   - The plan's section 2 now says the same, with absence from every log as the pin.
   - `rig.ts` and `hooks/handoff.ts` are rightly untouched in red.
7. Minor items:
   - (a) resolved: both cancel rows end with `marker_holds arming-prompt`.
   - (b) still open, see finding 1 below.
   - (c) still open, see finding 2 below.

## Plan "Tests (red first)" bullets against rows

Every bullet has a row, and every gate row has its positive over the same fixture.

- Marker writer:
  - NUL-terminated, on `handoff-checkpoint` and on `handoff-approved`: rows 283 and 284.
  - Session scoping and replacement: row 285.
  - Non-matching command: row 286.
  - No ids, or empty ones: row 287.
  - Resolver crash: row 288.
  - Symlinked marker: row 289.
  - Unwritable marker with byte-identical output: row 290. It covers a file as the parent, a 777 directory and a symlinked directory.
  - Whitespace round-trip: row 291.
- Sweep:
  - Queued rename spared (215) with the fresh-id companion (216).
  - Clear and compact cancelled (217, 219) with companions (218, 220).
  - No `prompt_id` (221); no marker or an empty one (222); first prompt (223).
  - Whitespace pair (224, 225).
  - The sweep writes no marker (226).
  - Another session's file, live (227) and stale (228).
  - `held`, `pending` and malformed with a queued id.
  - Symlinked marker and symlinked or writable directory (231, 232, 233).
  - `no find forked` with a `prompt_id`.
  - `session-pointer` sweeping a stale marker, with its keep companion (187, 188).

## Findings (none blocking)

1. `plans/2026-10-16-queued-prompt-sweep/plan.md:43-45` and `tests/hook-test.bats:255-256`. The typed-ahead phrase is pinned in the tests as an exact lowercase substring, `a prompt typed while that turn was still running`. The plan only says the note "names a prompt typed while that turn was still running", so the string lives only in `red-report.md`.
   - Fix: copy the phrase into the plan as the pinned substring, with the note that it must not open a sentence.
   - Leave the tests as they are.
2. Review items 7b and 7c are not covered in the tests or the plan.
   - An absent pointer directory when the report hook runs is unspecified. The sweep rows pre-create the directory, and row 287 only constrains the injector.
   - A queued id with `link` or `unread` is not covered.
   - Fix: add one sentence to the plan saying an absent or untrusted directory reads as no marker, so the file is swept as today. Optionally add a one-line row with the directory removed and a `prompt_id` set.
   - The `held` and `malformed` rows already pin that the id is consulted only for `armed`, so no more rows are needed for `link` and `unread`.
3. `tests/checkpoint.bats:340-341` and `hook-test.bats:563-571`, the symlinked-directory rows.
   - On Linux, a symlink's mode is 777, so the writable-directory `find` check also rejects the link. Dropping `! -L` and `-O` from a prototype left every row green.
   - The two guards are not isolable on Linux. This is the same property as the existing drift-marker rows.
   - No change needed. The macOS run is what discriminates `! -L`, and the plan's "drift marker's guards" wording carries it.
4. `tests/checkpoint.bats:291` (row 290).
   - Its three comparisons against the baseline are not exercised against current code, because the row reds at the baseline `marker_holds`.
   - I checked them with the prototype: they hold, and dropping the `find` permission check reds the row. No change is needed.
   - Do not weaken the baseline assertion.

## Overspecification and whitespace safety

- No helper names in `_lib.sh` are pinned. The tests touch only the marker path and bytes, the cancel strings, the sweep record and the phrase in finding 1.
- Row 287 requires that the injector creates no pointer directory when either id is missing. That follows from the plan's "when both are non-empty" and is not extra.
- Row 290 compares `$output`, which under bats `run` includes stderr. This means a marker failure must also be silent on stderr, which matches the plan's "never changes the hook's output".
- Ids with spaces, a final newline and an inner newline go through `jq --arg` on the input side and `printf '%s\0'` on the marker side. The comparison is `cmp` against `printf '%s\0'`, so NUL termination is checked in both directions.
