# Item 1.1 / slice 5 — RED report

Test added: `tests/test_checkpoint.py::test_clause_refusal_is_followed_by_no_commit_or_arming`
(inserted after `test_arming_text_refers_to_everything_above`, before the
`# Composition` section).

## What it asserts

Fixture: `make_gitlore_repo` + `dirty_memory`, `gitlore.memoryApprovalClauseFile`
unset via `git config --unset`, `handoff_payload("with-commit")` with
`clear = True` (typed transition).

- `lib.commit_directive()` and `lib.arming_directive()` are asserted non-empty
  before the absence checks (per the runbook's standing rule).
- `result.returncode == 0`.
- stdout (lowercased) contains `gitlore.memoryapprovalclausefile` — the
  clause-file refusal fired.
- stdout contains neither `commit_directive()` nor `arming_directive()` —
  the refusal suppresses everything after it.
- Sentinel line 1 is still `held sess-checkpoint` — the refusal suppresses
  the printed parts, not the hold.

## RED run

```
$ pytest tests/test_checkpoint.py -k test_clause_refusal_is_followed_by_no_commit_or_arming -vv
```

Failed on the intended assertion (`assert commit_act not in out`), not an
error/collection failure:

```
E       AssertionError: assert 'Now make the commit the request called for.\n' not in '...\n\n\nNow make the commit the request called for.\n\n\nOnce everything above is done, run `handoff-approved` (Bash, no arguments).\n\n'
```

Today's `main`/`compose_directives` still prints the commit act and the
arming instruction after the clause-file refusal text — exactly the defect
this slice's test is meant to catch (R5).

## Full-file run

```
$ pytest tests/test_checkpoint.py -q
1 failed, 159 passed in 52.77s
```

Only the new test fails; the rest of the file (all prior slices'
tests, including `test_arming_instruction_follows_every_other_part` and
`test_with_commit_memory_text_drops_nothing_further`) stays green.

## Mutation check

Not run here — per the dispatch, the mutation check named in the slice
(print parts 3–4 regardless of `refusal` ⟹ this row alone reds) is done
after GREEN, by code review.

## Notes

- No SUT files touched.
- Committed nothing.
