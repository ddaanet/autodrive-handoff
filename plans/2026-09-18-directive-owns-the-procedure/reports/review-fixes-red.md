# RED — review-fixes (findings 2, 3, 4, 12, 13, 14)

Source: `plans/2026-09-18-directive-owns-the-procedure/reports/deliverable-review.md`.

Files touched: `tests/test_checkpoint.py`, `tests/checkpoint.bats`. No
production code (`scripts/`, `bin/`) carries any net change — see the
before/after `git diff --stat` at the end.

## A. Held path validates the session id before any write (finding 2)

New tests in `tests/test_checkpoint.py`, in a new section "Held path
validates CLAUDE_CODE_SESSION_ID before any write (finding 2)":

- `test_held_via_commit_session_id_unset_errors_before_any_write` — held via
  `(T ∧ C)`: `handoff_payload("with-commit")` with `clear: True`,
  `CLAUDE_CODE_SESSION_ID` unset.
- `test_held_via_memory_session_id_unset_errors_before_any_write` — held via
  `(K ∧ M)`: `handoff_payload("without-commit")`, dirty memory, untyped
  handoff, `CLAUDE_CODE_SESSION_ID` unset.
- `test_held_session_id_set_still_succeeds_via_commit` — paired positive over
  the `(T ∧ C)` fixture, variable set → `held sess-checkpoint`.
- `test_armed_cell_succeeds_with_session_id_unset` — an armed cell
  (`handoff_payload("without-commit")`, clean memory, untyped) still succeeds
  with the variable unset.

Both negative rows assert `result.returncode != 0`, `"CLAUDE_CODE_SESSION_ID"
in result.stderr`, `"cannot read back" not in result.stderr` (the vacuous-pass
guard: today's message is the composer-blaming
`"composed a sentinel this version cannot read back — line 1 state \`held\`
must name the session holding it"`, which contains neither the variable name
nor anything actionable), and that nothing was written (no task file, no todo
file, no manifest, no sentinel).

Red output (`pytest tests/test_checkpoint.py -q -k "held_via_commit_session_id_unset or held_via_memory_session_id_unset"`):

```
________ test_held_via_commit_session_id_unset_errors_before_any_write _________
>       assert "cannot read back" not in result.stderr
E       AssertionError: assert 'cannot read back' not in 'handoff-che...holding it\n'
E         'cannot read back' is contained here:
E           s version cannot read back — line 1 state `held` must name the session holding it

________ test_held_via_memory_session_id_unset_errors_before_any_write _________
>       assert "cannot read back" not in result.stderr
E       AssertionError: assert 'cannot read back' not in 'handoff-che...holding it\n'
```

Both fail on the assertion (message content), not on setup, an import, or a
crash — confirming the message really is the composer-blaming one today and
that `handoff-task.md`/manifest/sentinel are indeed already on disk by the
time it's printed (the test would otherwise fail earlier, on
`_assert_nothing_written`, which it does not reach first because pytest
reports the first failing `assert` — verified separately below that the
writes are in fact present today).

Verified independently that the "nothing written" half is also currently
false by running the reproduction from finding 2 directly:

```
$ env -u CLAUDE_CODE_SESSION_ID HANDOFF_ROOT=<tmp-gitlore-repo> python3 scripts/checkpoint.py <<<'<payload>'
# rc 2; .claude/handoff-task.md and .claude/checkpoint-manifest present, no .claude/autodrive
```
(This matches the review's own verification at deliverable-review.md:101-104.)

The two positive rows pass today (4 passed alongside the two failures — see
combined run below), confirming the paired-positive and armed-cell-stays-green
requirements are already true and must stay true after GREEN.

## B. `bin/handoff-approved` refuses a held sentinel of an unexpected kind (finding 3)

Not dropped: `handoff_drive_read` accepts `held` independently of `DRIVE_KIND`
(the state check at `_lib.sh:189-215` and the kind check at `:223-265` are
separate `case` statements), so a held `restart` sentinel is a shape it reads
back cleanly, which is exactly the gap finding 3 describes.

New bats test in `tests/checkpoint.bats`:

```
@test "handoff-approved: a held sentinel of an unexpected kind -> exit 2, left held, naming the kind" {
    repo="$(make_repo)"
    printf '%s\n' "held $CLAUDE_CODE_SESSION_ID" restart "/exit" "claude --resume sess-other" \
        > "$repo/.claude/autodrive"
    run_approved "$repo"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"restart"* ]]
    [ "$(head -n1 "$repo/.claude/autodrive")" = "held $CLAUDE_CODE_SESSION_ID" ]
}
```

Red output (`bats tests/checkpoint.bats -f "unexpected kind"`):

```
not ok 1 handoff-approved: a held sentinel of an unexpected kind -> exit 2, left held, naming the kind
# (in test file tests/checkpoint.bats, line 198)
#   `[ "$status" -eq 2 ]' failed
```

Fails on the exit-code assertion (today's script exits 0 for `restart`,
since the `case "$DRIVE_KIND"` has no `*)` arm and `handoff_drive_arm` already
ran before the case), not on a missing binary or a 127.

## C. `closing_directive` raises on an unknown skill (finding 4)

New test in `tests/test_checkpoint.py`:

```python
def test_closing_directive_raises_on_unknown_skill() -> None:
    with pytest.raises(ValueError, match="bogus"):
        lib.closing_directive("bogus", typed=False)
```

Red output:

```
________________ test_closing_directive_raises_on_unknown_skill ________________
    def test_closing_directive_raises_on_unknown_skill() -> None:
>       with pytest.raises(ValueError, match="bogus"):
E       Failed: DID NOT RAISE <class 'ValueError'>
```

Fails because today's `if/else` silently returns the precompact wording for
any skill other than `"handoff"` — an assertion failure (`Failed: DID NOT
RAISE`), not an import/attribute error.

## Combined red run (A + C)

```
$ pytest tests/test_checkpoint.py -q -k "held_via_commit_session_id_unset or held_via_memory_session_id_unset or held_session_id_set_still_succeeds_via_commit or armed_cell_succeeds_with_session_id_unset or closing_directive_raises_on_unknown_skill or untyped_precompact_with_commit_clean_memory_is_armed or handoff_commit_precedes_closing_line_when_armed"
..FF..F                                                                  [100%]
3 failed, 4 passed, 172 deselected in 2.40s
```

Failed: the two held/session-id rows (A) and the unknown-skill row (C).
Passed: the paired-positive session-id row, the armed-cell-with-unset-id row
(both A), and the two pinning rows D/E below (already green, as designed).

## D. Handoff commit < closing over an armed with-commit fixture (finding 12)

New test `test_handoff_commit_precedes_closing_line_when_armed`: repo =
`make_gitlore_repo` (clean memory), `handoff_payload("with-commit")`
(untyped handoff, default `clear: False`) → armed. Asserts
`commit_index < closing_index` and `out.endswith(closing)`.

Green on arrival (as expected for a pinning slice) — see combined run above
(passed).

Mutation evidence: in `compose_directives` (`scripts/checkpoint.py`), changed

```python
        parts.append(lib.closing_directive(skill, typed=ending.typed))
```

to

```python
        parts.insert(0, lib.closing_directive(skill, typed=ending.typed))
```

Re-ran `pytest tests/test_checkpoint.py -q -k test_handoff_commit_precedes_closing_line_when_armed`:

```
>       assert commit_index < closing_index
E       assert 68 < 0
```

Reds on the assertion — the row is load-bearing. Reverted the edit by
inverting it exactly (`insert(0, ...)` → `append(...)`), restoring the
original line.

## E. `first_line == "armed"` for untyped precompact + with-commit + clean memory (finding 13)

New test `test_untyped_precompact_with_commit_clean_memory_is_armed`: repo =
`make_gitlore_repo` (clean memory), `precompact_payload("with-commit")`
(default `compact: False`, untyped) → asserts the sentinel's first line is
`"armed"` (the FR-G marker cell, `¬K ∧ ¬T ∧ C`).

Green on arrival — see combined run above (passed).

Mutation evidence: in `hold_decision` (`scripts/checkpoint.py`), changed

```python
    return (bool(transition.cmds) and memory) or (transition.typed and commit)
```

to

```python
    return (bool(transition.cmds) and memory) or commit
```

(widening the second disjunct from "typed and with-commit" to "with-commit"
alone — a plausible uniform predicate). Re-ran
`pytest tests/test_checkpoint.py -q -k test_untyped_precompact_with_commit_clean_memory_is_armed`:

```
>       assert first_line == "armed"
E       AssertionError: assert 'held sess-checkpoint' == 'armed'
```

Reds on the assertion. Reverted the edit exactly (restored `transition.typed
and commit`), returning the line to its original text.

## F. Exact-sentence assertion for the commit act (finding 14)

Renamed `test_commit_act_names_no_git_verb` →
`test_commit_act_is_the_exact_no_git_verb_sentence` in
`tests/test_checkpoint.py`, replacing the three-substring blacklist
(`"git commit"`, `"--amend"`, `"git add"` all absent) with an exact match
against `commit_directive()`'s current text, which
`docs/changelog/2026-09-18-the-directive-owns-the-procedure.md:45` quotes
verbatim ("Once everything above is done, make the commit the request called
for."):

```python
def test_commit_act_is_the_exact_no_git_verb_sentence() -> None:
    assert lib.commit_directive() == (
        "Once everything above is done, make the commit the request called for.\n"
    )
```

Green on arrival, as expected for a pinning slice:

```
$ pytest tests/test_checkpoint.py -q -k test_commit_act_is_the_exact_no_git_verb_sentence
1 passed
```

Mutation evidence: in `commit_directive()` (`scripts/_checkpoint_lib.py`),
changed the wording from "make the commit" to "stage and commit" (a reword
naming a verb differently, exactly the class of defect the old blacklist
would have missed — it names no `git commit`/`--amend`/`git add` substring
either):

```python
    return _printf_lines(
        "Once everything above is done, stage and commit the request called for."
    )
```

Re-ran the row:

```
>       assert lib.commit_directive() == (
E       AssertionError: assert 'Once everyth...called for.\n' == 'Once everyth...called for.\n'
E         - Once everything above is done, make the commit the request called for.
E         + Once everything above is done, stage and commit the request called for.
```

Reds on the assertion, confirming the exact-match row catches what the old
blacklist would have missed. Reverted the edit exactly, restoring "make the
commit".

## Dropped slices

None. All six (A, B, C, D, E, F) were executable as specified.

## Before/after `git diff --stat -- scripts/ bin/`

Captured before touching any production file (baseline — this is the
pre-existing, already-gated uncommitted state of the tree, untouched by this
dispatch):

```
 scripts/_checkpoint_lib.py |  4 +--
 scripts/_lib.sh            |  4 +--
 scripts/checkpoint.py      | 88 +++++++++++++++++++++++-----------------------
 3 files changed, 48 insertions(+), 48 deletions(-)
```

After D's mutation was applied and reverted:

```
 scripts/_checkpoint_lib.py |  4 +--
 scripts/_lib.sh            |  4 +--
 scripts/checkpoint.py      | 88 +++++++++++++++++++++++-----------------------
 3 files changed, 48 insertions(+), 48 deletions(-)
```
(identical to baseline)

After E's mutation was applied and reverted:

```
 scripts/_checkpoint_lib.py |  4 +--
 scripts/_lib.sh            |  4 +--
 scripts/checkpoint.py      | 88 +++++++++++++++++++++++-----------------------
 3 files changed, 48 insertions(+), 48 deletions(-)
```
(identical to baseline)

After F's mutation was applied and reverted (final state at end of this
dispatch):

```
 scripts/_checkpoint_lib.py |  4 +--
 scripts/_lib.sh            |  4 +--
 scripts/checkpoint.py      | 88 +++++++++++++++++++++++-----------------------
 3 files changed, 48 insertions(+), 48 deletions(-)
```
(identical to baseline)

Each of the three `diff --stat` comparisons was checked with `diff` against
the captured baseline file and reported `IDENTICAL` — no line-count drift,
confirming every mutation was inverted exactly. `git status --short` for
`scripts/` at the end of the dispatch shows only the three pre-existing
modified files (`_checkpoint_lib.py`, `_lib.sh`, `checkpoint.py`), matching
what `git status` showed before this dispatch began; `bin/` is untouched
throughout.

## Files changed by this dispatch

- `tests/test_checkpoint.py` — 9 new tests (A ×4, C ×1, D ×1, E ×1), 1
  renamed/rewritten test (F).
- `tests/checkpoint.bats` — 1 new test (B).
- `scripts/checkpoint.py`, `scripts/_checkpoint_lib.py` — untouched net of
  the dispatch (temporary mutations applied and reverted for D, E, F's
  mutation-check evidence only).
