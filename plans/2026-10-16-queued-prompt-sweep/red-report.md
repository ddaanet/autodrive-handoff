# Queued-prompt sweep: red-phase report

Tests only. Changed: `tests/hook-test.bats`, `tests/checkpoint.bats`,
`tests/mod/handoff.test.ts`. Nothing under `scripts/`, `hooks/` or
`tests/mod/rig.ts`. Nothing committed. Revised to the plan's revised contract:
the marker is written by `inject-checkpoint-root.sh` and only read by
`report-drive-failure.sh`.

## Exact strings the implementer must use

Marker: `$HANDOFF_POINTER_DIR/handoff-prompt-<session_id>`, bytes
`<prompt_id>\0`. Written by `inject-checkpoint-root.sh`; the sweep rows write it
themselves and never expect the sweep to.

Queued `clear` or `compact` (swept, recorded `state=armed`, no lines offered),
both asserted by whole equality, built from one template in
`assert_cancel_report <output> <command> <skill>`:

- systemMessage: `<ESC>[0mhandoff: transition cancelled — a prompt arrived before it ran.`
  (leading `\033[0m`, em dash U+2014, closing period, no `Type in order`).
- additionalContext, with `/clear` and `handoff` for a clear, `/compact` and
  `precompact` for a compact, nothing before or after:
  `The driven <command> did not run. Answer this prompt, then run the <skill> skill again with the same transition, unless this prompt changes that.`

Unchanged-case companions assert today's whole systemMessage:
`<ESC>[0mhandoff: stale autodrive discarded — the drive mod did not run it.\nType in order:\n<lines>`.
The unloaded-mod note keeps `safe-mode`, `2.1.287`, `managed settings` and the
`Present these lines …:\n<lines>` ending, and does not contain the phrase below
when the input has a `prompt_id`.

No `prompt_id` in the input (message unchanged, the note gains this exact
lowercase substring, so it must not open a sentence):
`a prompt typed while that turn was still running`

The marker is compared whole and byte-exact against the input's `prompt_id`:
NUL-terminated on disk, so an id with leading or trailing spaces, an embedded
or final newline compares as itself (`read -r`, `$(...)`, first-line and
trimmed compares fail rows).

## Fixture helpers

`hook-test.bats`: `run_report_failure` takes `PROMPT_ID` from the environment
(unset or empty: the input has no `prompt_id` key). `make_pointer_dir`,
`seed_prompt_marker`, `marker_holds`, `seed_armed_kind`, `seed_queued`,
`assert_cancel_report`, `assert_unloaded_report`,
`seed_marker_in_untrusted_dir`.
`checkpoint.bats`: `run_inject_root_ids <repo> <cmd> <session_id> <prompt_id>`
(`-` leaves a key out, `''` sends it empty); `setup` now exports
`HANDOFF_POINTER_DIR` under `$BATS_TEST_TMPDIR`; the hook is expected to create
the directory (`mkdir -m 700 -p`), so the rows do not.

## Results against the unchanged code

`bats tests/hook-test.bats tests/checkpoint.bats` from the repo root: 305 tests,
292 ok, 13 not ok, all new rows below marked RED; no pre-existing row and no
positive companion broke. `shellcheck -x tests/*.bats` clean.
`claude plugin test`: 11 pass, 5 fail, all `expect(...).toEqual` with
`prompt.read` in `Received` (`compact with focus…`, `clear: rename…`,
`rename kind…`, `first rejected line…`, `a rejected continuation prompt…`).

### tests/hook-test.bats

| Row | Now | Why |
| --- | --- | --- |
| session-pointer: sweeps a long-stale prompt marker | RED | `handoff-prompt-ancient` still exists; the `find` filter lacks the name |
| session-pointer: keeps another live session's prompt marker | green | companion; reds a filter that sweeps too much |
| queued: owner's armed rename spared, nothing said or recorded | RED | `[ "$output" = "" ]`: swept with the unloaded-mod note |
| fresh id: armed rename swept with the unloaded-mod note | green | companion over the same fixture |
| queued: armed clear swept, recorded, cancelled, no lines | RED | `assert_cancel_report`: message and note are the unloaded-mod ones; also pins the sweep record (1 line, `kind=clear`) and the marker left as it was |
| fresh id: armed clear swept with the unloaded-mod note | green | companion |
| queued: armed compact swept, recorded, cancelled, no lines | RED | `assert_cancel_report`, same reason, `kind=compact` |
| fresh id: armed compact swept with the unloaded-mod note | green | companion |
| no `prompt_id`: swept as today, note names a typed-ahead prompt | RED | `CTX` lacks the phrase; sweep, whole message and unloaded-mod note already hold |
| no `prompt_id`, directory present, marker absent or holding an empty id: swept, not queued | RED | `CTX` lacks the phrase. Pins the non-empty-id test (absent and empty are equal) |
| no marker yet, first prompt with an id: swept | green | companion; reds a compare against the current id |
| queued: id with leading/trailing spaces and newlines matching exactly is spared | RED | `[ "$output" = "" ]`: swept |
| an id differing from the marker's by trailing space, final newline, leading space, extra line (and the marker the longer) is swept | green | companion over the same fixture; reds a trimming or first-line compare |
| a prompt with an id writes no marker, whatever the sentinel does | green | negative; only an impl that writes in the sweep fails it (no file, none created, an older marker neither changed nor re-touched) |
| no drift, a `prompt_id` and its marker, no sentinel: no `find` forked | green | negative; `find_witness_stub`, beside the existing no-`find` row; fails an impl that checks the directory before it knows it needs the marker |
| another live session's armed file, queued id: untouched, nothing said | green | liveness rule decides, not the marker |
| another session's armed file, stale transcript, queued id: swept as today | green | reds a dropped owner test (it would be cancelled) |
| queued id, held or pending: untouched | green | the id is consulted only for `armed` |
| queued id, malformed file: swept as malformed | green | same |
| symlinked marker holding the current id: not read, file swept | green | companion; reds a read through the link |
| symlinked marker directory holding the current id: not read, file swept | green | companion; reds a skipped `marker_dir_ok` |
| group/world-writable marker directory holding the current id: not read, file swept | green | companion, same |

Dropped from the earlier draft: every row that had the sweep write the marker
(a prompt with an id writes the marker, the lifecycle row, not-rewritten, the
no-session-id write row, the replaced-symlink row, and the write halves of the
two directory rows).

### tests/checkpoint.bats (beside the `inject-checkpoint-root` rows)

| Row | Now | Why |
| --- | --- | --- |
| a `handoff-checkpoint` call leaves the `prompt_id`, NUL-terminated, in a 0700 directory with no stray temporary | RED | `marker_holds` (cmp, file absent); also asserts the rewrite as before |
| a `handoff-approved` call leaves it too | RED | `marker_holds`, same |
| a later call replaces it; another session's marker is its own | RED | `marker_holds` |
| a command that is neither call: no marker, no output, no directory | green | negative; reds an impl that writes before matching |
| no marker without a `session_id` or without a `prompt_id` (each absent or empty, both), rewrite unchanged | green | negative; reds `or` for `and` |
| a resolver that crashes leaves no marker either | green | negative; reds a write ahead of the resolution |
| a symlinked marker replaced, target never created | RED | `[ ! -L … ]`: no marker written at all; reds a write through the link once it exists |
| a marker that cannot be written leaves the output byte-identical (parent a file, 777 directory, symlinked directory) | RED | the baseline run's `marker_holds`; the three comparisons then pin the output and that nothing lands in an untrusted directory |
| a `prompt_id` with a space, a final newline, an inner newline, edge spaces, `-n\n` round-trips | RED | `marker_holds` on the first id |

## Mutation checks

Run against a throwaway implementation in a copy of the repo under `$TMPDIR`
(nothing under the repo touched); each reds at least the rows named.

- owner test dropped: `queued id, armed by another session whose transcript is stale`.
- non-empty `prompt_id` test dropped: `no prompt_id and no marker` (both cases).
- kind test dropped (cancel every queued kind): the rename row and the whitespace-spared row.
- marker write dropped in `inject-checkpoint-root.sh`: the five RED writer rows above.
- sweep writes the marker on every prompt: the three fresh-id companions, the first-prompt row, the whitespace-mismatch row and the sweep-writes-none row.
- compare against the first line only: the whitespace-spared row. Trailing-space trim: the whitespace-mismatch row.
- `find` forked on every prompt carrying an id: the `no find forked` row alone.
- directory check skipped: the symlinked-directory and writable-directory rows.
- injector: writes before matching reds the neither-call and crashed-resolver rows; `or` for `and` reds the missing-id row; `$(...)` on the id reds the round-trip row; a direct `>` over the name reds the symlink row; a marker failure that aborts the hook reds the unwritable-marker row.

## Mod test edits

Unchanged from the earlier draft: `prompt.read` removed from the five expected
logs; the two bail rows deleted. `tests/mod/rig.ts` untouched; its
`prompt.read` stub and `promptTexts` go in the green step.

## Open points for the implementer

1. The injector must create the pointer directory itself (`mkdir -m 700 -p`);
   the writer rows start without one. The sweep rows pre-create it, as
   `session-pointer.sh` does.
2. The no-`prompt_id` phrase is only tested on an armed owner's file.
3. `claude plugin test` and bats were run unsandboxed only where needed
   (`claude`).
