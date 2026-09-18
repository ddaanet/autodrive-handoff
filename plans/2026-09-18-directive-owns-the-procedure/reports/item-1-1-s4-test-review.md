# Item 1.1 — slice 4 test review

Tests reviewed: `test_arming_instruction_follows_every_other_part` and
`test_arming_text_refers_to_everything_above` (`tests/test_checkpoint.py`,
`# Arming` section). SUT untouched.

## Mechanical check

`pytest tests/test_checkpoint.py -k "arming_instruction_follows or arming_text_refers"`
gives 2 failed, 0 passed, 0 errors. Both fail on an assertion:

- `test_arming_instruction_follows_every_other_part`: `assert 1131 < 1065`
  (the ordering check; the arming text is appended to the memory part, ahead
  of the todo boundary).
- `test_arming_text_refers_to_everything_above`: `'everything above' in 'Once
  that is done, run `handoff-approved` (Bash, no arguments).\n'`.

The RED report's full-file run showed 157 passed and 2 failed, so no other
row regressed.

## Wrong-reason hunt

**(a) A GREEN that moves the arming text but keeps its wording.** Both tests
catch it independently. The first reds on `"Once that is done" not in out`:
a grep of `scripts/` finds that phrase only in `arming_directive()`, so if
the old text is printed, the phrase is in stdout. The second reds on
`everything above`. A reword that adds "everything above" but keeps "Once
that is done" still reds the first test. Sound.

**(b) Is the arming text unique in stdout?** The test did not check this.
`out.index(arming)` finds the first occurrence, so a GREEN that printed the
arming text twice (once still attached to the memory part, once at the end)
would pass both the ordering check and `endswith`. **Fixed:** added
`assert out.count(arming) == 1` ahead of the index checks. Against the
current SUT it passes (the text appears once), and the test still reds on the
ordering assertion. The test counts the whole arming string rather than
`handoff-approved`, so the memory directive or the gitlore clause mentioning
`handoff-approved` elsewhere cannot trip it.

**(c) Does the sentinel assertion read the real file?** Yes. It reads
`repo / ".claude" / "autodrive"`. `run_checkpoint` sets `HANDOFF_ROOT=repo`,
and the autouse fixture at `test_checkpoint.py:41` pins
`CLAUDE_CODE_SESSION_ID=sess-checkpoint`, which overrides the live session's
id. Existing rows 1758 and 1816 use the same literal. The assertion passes
today, before the ordering check fails, so the fixture reaches the held cell
(typed clear + dirty memory) as intended.

**(d) Should the test also check that arming comes after the memory part?**
It is covered without a separate index check. With `count(arming) == 1`, the
stripped `endswith` puts the only copy of the arming text after every other
byte of stdout. That includes the memory directive, and in any later phase
the commit act, which is absent here anyway because the cell is
`without-commit`. The `todo_boundary < arming` index check is now implied by
those two, but it stays as the slice spec wrote it, and its failure message
is the one that names the defect today.

## Other observations

- The non-empty guards on `todo_boundary(root)` and `arming_directive()` are
  in place, as the standing rule requires. `add_sdd_ledger` is what makes
  `todo_boundary` non-empty.
- `test_arming_text_refers_to_everything_above` is a pure check on the
  function's return value. That fits its contract: where the text is printed
  is the first test's job.

## Changes made

- `tests/test_checkpoint.py`: added `assert out.count(arming) == 1` in
  `test_arming_instruction_follows_every_other_part`. I re-ran both tests
  afterwards and both are still red on the same assertions as above.

Verdict: ready for GREEN.
