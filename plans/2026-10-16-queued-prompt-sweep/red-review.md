# Queued-prompt sweep: red-phase review

Reviewed: `git diff -- tests/` (`tests/hook-test.bats`, `tests/mod/handoff.test.ts`)
against `plan.md` (queued `rename` spared; queued `clear`/`compact` swept and
cancelled; note text per `craft:directive-writing`) and `red-report.md`.

## Verdict: needs changes (small)

The rows are sound, discriminating and red for the right reason. Two things must
change before green: the cancel-row assertions have to be rewritten to the new
note text (finding 1, already planned), and one conflict with a pre-existing
row that the plan does not mention (finding 2) needs a decision. The rest are
additions the implementer could otherwise slip through (findings 3-5).

## Re-run (unchanged code, this session)

- `bats tests/hook-test.bats`: 276 tests, 267 ok, 9 not ok, exactly the 9 the
  report lists as RED (187, 215, 217, 219, 221, 222, 224, 225, 234). Every
  pre-existing row passes; every positive companion passes.
- Each RED row fails on an assertion about the hook's output or the filesystem,
  not on setup (the fixtures exist and the hook runs to completion; the
  `[ "$output" = "" ]`, `assert_cancel_report`, `marker_holds` and `! -L` lines
  are what fail). `shellcheck -x tests/hook-test.bats` is clean.
- `claude plugin test`: 11 pass, 5 fail, all `expect(...).toEqual` on the call
  log with `prompt.read` still in `Received`; the 11 passing include FR-G,
  malformed plan, the Stop-with-no-session-id and link-at-failFile rows. No
  setup or import failure.

## Prototype check (stronger than argument)

I wrote a throwaway implementation of the contract in a copy of the repo under
`$TMPDIR/proto/r` (nothing in `/Users/david/code/handoff` touched) and ran the
whole bats file against it, with one switch per mutation.

- Faithful implementation: every new row green; the only red is the
  pre-existing `no drift, no marker: no find forked` (finding 2).
- Compare against the current id (marker written before it is read): 9 new rows
  red: the three fresh-id companions, the first-prompt row, the lifecycle row,
  both symlinked-marker rows, both marker-directory rows.
- Owner test dropped: exactly one row reds, `queued id, armed by another session
  whose transcript is stale` (line 3096). The "another live session" row does
  not discriminate it, because that file is reclassified `foreign` before the
  queued test is reached; it guards a different thing. One row is thin but real.
- `prompt_id`-non-empty test dropped (empty id equals absent marker): the new
  `no prompt_id and no marker` row reds, and so do about a dozen pre-existing
  sweep rows (they send no `prompt_id` and have no marker).
- Kind test dropped, read as "cancel every queued kind": the `rename` row and
  the lifecycle row red. Read as "spare every queued kind": the `clear` and
  `compact` rows red (they require the sentinel gone, a sweep record and the
  cancel report). Both readings are caught.

## Plan "Tests" bullets against rows

| Bullet | Row(s) | Reds when |
| --- | --- | --- |
| queued rename spared | 2917 | impl sweeps it; compare uses current id inverted; kind test dropped (cancel-all) |
| fresh id swept (rename) | fresh-id rename | compare against current id; marker never read |
| clear / compact swept, recorded, cancel message + note, no lines, no unloaded-mod note | 2940, 2960 + fresh-id pairs | impl spares them, or offers lines, or keeps the unloaded-mod text, or names the wrong skill |
| no `prompt_id`: swept, note names typed-ahead prompt | "swept as today" | phrase missing; sweep skipped |
| no marker yet | "first prompt" | impl treats absence as queued, or compares against the current id |
| marker NUL-terminated; not written without ids; symlink | 3020, 3052, no-session-id row, not-rewritten row, symlink rows, dir rows | write skipped, written with newline, written with empty ids, rewritten, written through a link or an untrusted directory |
| other session's armed file | live row, stale row | owner test dropped (stale row only) |
| session-pointer sweep | 187 + companion | `find` filter lacks the name; filter widened too far |

All bullets have a row and each row tests what its name says.

## Findings

1. **Cancel-row assertions need rewriting to the new note text; use whole
   equality.** `tests/hook-test.bats:2838` (`cancel_phrase`) and `:2891`
   (`assert_cancel_report`) assert the fragment `arrived after the checkpoint`,
   which no longer exists. The new text is short and is the contract, so assert
   it whole, built once from a template in the helper:
   `note="The driven $cmd did not run. Answer this prompt, then run the $skill skill again with the same transition, unless this prompt changes that."`
   with `$cmd`=`/clear`,`$skill`=`handoff` and `$cmd`=`/compact`,`$skill`=`precompact`.
   Then `[ "$CTX" = "$note" ]` and `[ "$MSG" = $'\033[0m'"handoff: $cancel_msg." ]`
   (today the message check is a prefix glob; the unchanged-case rows already
   compare the message whole, and the hook strips the joining space, so equality
   holds when the cancel note is the only note). Equality subsumes every
   negative the helper makes today (`Present these lines`, `safe-mode`,
   `2.1.287`, `managed settings`, `Type in order`, `did not run it`, the other
   skill's name), so delete them rather than keep a redundant list. Fragments
   would let the implementer append a mechanism clause back in, which is what the
   directive rule forbids.
   Also keep the `wc -l` = 1 and `kind=` assertions on the sweep record
   (2940, 2960); they stay valid.
2. **"No `handoff` in the compact note" negative: drop it, equality replaces
   it.** With the compact text containing no `handoff` the check
   (`${CTX//precompact/}` has no `handoff`) is a tautology of the equality in
   finding 1. Under the old fragment design the strict ban was too strong in one
   way (it would have rejected the plugin-qualified name `autodrive-handoff:precompact`,
   whose namespace contains `handoff`, and the clear row's `*handoff*` match was
   satisfied by the same namespace without naming the skill); under whole
   equality both problems vanish. Do not keep a loosened fragment such as
   `run the handoff skill`.
3. **A pre-existing row is invalidated by the plan and nothing says so.**
   `tests/hook-test.bats:3608` (`no drift, no marker: no find forked`) passes
   only because its input carries no `prompt_id`. A real Claude Code always
   sends one, so the hook will now fork `find` (inside `marker_dir_ok`), a
   `mktemp` and `handoff_replace` on every prompt, and the row stays green over
   it. My prototype failed this row only because it ran `marker_dir_ok` before
   testing the id. Decision for the coordinator: either (a) accept the cost and
   narrow the row's name and the header comment (`report-drive-failure.sh:42-44`,
   "no-file path must be silent and cheap") to say it holds without a
   `prompt_id`, or (b) require the marker path to avoid the forks when it can
   (read the marker with `handoff_read_regular` only when the file is armed and
   owned, which needs no `find`; write only when the id differs) and add a row
   with `PROMPT_ID` set, no sentinel and the marker already holding it, using
   `find_witness_stub`. The red phase should carry whichever is chosen; today it
   carries neither. Recommend (b) for the read side and note that the write on a
   changed id cannot avoid `mktemp`.
4. **Whitespace and NUL safety of the marker is untested.** All ids in the rows
   (`arming-prompt`, `prompt-one`) are plain tokens, so an implementation that
   reads with `read -r` (trims), `$(cat)` (strips trailing newlines) or compares
   by first line passes everything. Add two rows beside `:3020`: (a) marker
   holds `$'id with space \n'`-shaped value (leading space, trailing space and an
   embedded newline, seeded with `printf '%s\0'`), input `PROMPT_ID` equal to it:
   a queued `rename` is spared, and the written marker after a different id
   with the same shape is byte-exact through `marker_holds`; (b) marker holds
   `p1`, input is `p1 ` (trailing space): swept, not spared. The input side is
   already built correctly: `jq --arg pid` in `run_report_failure` (`:2494-2507`)
   matches the neighbouring rows, and the seeded and compared marker uses
   `printf '%s\0'` with `cmp` against `printf '%s\0'`, so NUL termination is
   checked in both directions.
5. **"No lines offered" is asserted only through the header phrase.** The
   cancel helper checks `Present these lines` and `Type in order` are absent; an
   implementation that prints `/clear` and `pick up the queued task` bare in the
   note passes. With finding 1's equality this is closed for the note; for the
   message, equality on `$MSG` closes it as well. If equality is not adopted,
   add `[[ "$CTX$MSG" != *"pick up the queued task"* && != *"/rename Queued Title"* ]]`
   (compact: `keep the parser work`).
6. **Mod tests: the edits are meaning-preserving; one plan line is stale.**
   `tests/mod/handoff.test.ts` loses `prompt.read` from the five expected logs
   (`compact with focus`, `clear: rename…`, `rename kind`, `first rejected line`,
   `a rejected continuation prompt`) and nothing else changes: same commands,
   same order, same `fs.write` and toast expectations. The two bail rows (`text
   in the prompt box before the first line…`, `text typed mid-sequence…`) are
   deleted. Their `writes == []` assertions went with them. `plan.md` section 2
   still says they "become one row: text in the input box does not stop the
   sequence", but the same section deletes `promptTexts` from the rig, so such a
   row could not exist after green. Edit the plan line to say the rows are
   deleted and `prompt.read` absence from every log is the pin (as the report
   already says). `rig.ts` and `hooks/handoff.ts:50` are rightly untouched in
   red.
7. **Minor, no change required.** (a) Queued `clear`/`compact` rows do not
   assert the marker afterwards (`marker_holds arming-prompt`); one line each
   would catch an impl that rewrites it on the cancel path. (b) Pointer
   directory absent when the report hook runs is untested (report ambiguity 1);
   the common session creates it at SessionStart, so leave it, but say so in
   the plan. (c) `link` and `unread` with a queued id are not covered; the plan
   lists them as untouched and the `held`/`malformed` rows already pin that the
   id is consulted only for `armed`.

## Answers to the coordinator's questions

- Assertions against the exact text: whole-note equality on `$CTX`, whole
  equality on `$MSG` (cancel fragment plus the closing period, no lines), for
  both kinds, from one template that differs in `/clear`/`handoff` versus
  `/compact`/`precompact`.
- The "no `handoff` in the compact note" negative no longer makes sense; equality
  covers it. Do not loosen it to a fragment.
- Earlier question (strict ban vs `run the handoff skill`): moot under equality;
  the strict ban was unsafe only because the plugin namespace
  `autodrive-handoff` contains the word.
