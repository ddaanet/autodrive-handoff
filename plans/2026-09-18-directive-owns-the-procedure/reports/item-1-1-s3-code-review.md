# Code review — Item 1.1 slice 3

Commit reviewed: "Item 1.1/3 — with-commit memory text drops "nothing further"".
Scope: `scripts/_checkpoint_lib.py` `memory_directive`'s with-commit text,
plus the new test row `test_with_commit_memory_text_drops_nothing_further`.

## Findings

- **Sentence removed, no reworded equivalent.** The with-commit branch now
  ends at "The commit that lands these changes carries the memory." A grep
  for `further`, `needed from you` and `nothing else` across `scripts/*.py`
  and `bin/*` returns nothing. The only `nothing further` left in scripts/
  and tests/ is the new test's own negative assertion.
- **Reads well next to the commit act.** Under with-commit the parts now go:
  memory directive, which ends with the one reassurance clause
  (`craft:directive-writing` keeps exactly one); todo boundary; "Now make the
  commit the request called for."; then the arming instruction if the
  transition is held. Nothing in the memory text now contradicts the commit
  act that follows it, and the reassurance is still true of every flow,
  because it says "the commit that lands these changes", not "this turn's
  commit". No mechanism was added.
- **Trigger file still unmentioned.** The with-commit branch builds no string
  that uses `trigger`. The load-bearing negative
  `test_with_commit_summary_write_only_no_trigger_mention` (whole-word
  `trigger` absent) still passes, and so does the `carries the memory`
  positive.
- **Docstrings/comments.** The `memory_directive` docstring does not quote or
  describe the removed sentence. Nothing in scripts/ or tests/ refers to it.
  docs/ and CLAUDE.md were out of scope (Phase 5).
- **Test quality.** The negative is lowercased and pairs with a positive over
  the same fixture ("gitlore memory has uncommitted changes"), so it cannot
  pass vacuously on empty stdout.

## Mutation check

I restored the sentence in place ("… carries the memory. Nothing further is
needed from you."), then ran
`pytest tests/test_checkpoint.py -k "nothing_further or carries or trigger"`.
Result: 1 failed, 4 passed. The failure was
`test_with_commit_memory_text_drops_nothing_further` at its
`nothing further` assertion, and that row was the only one to go red. I then
restored the file, and `git status` shows scripts/ and tests/ clean.

## Fixes applied

None. I still ran `just precommit` on the restored tree, and it exited 0
(pytest: 247 passed, 11 deselected).

Refactor flagged: none
