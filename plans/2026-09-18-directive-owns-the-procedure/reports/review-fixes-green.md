# GREEN — review-fixes (findings 2, 3, 4)

No commit, no staging — per dispatch override, the parent session owns the
commit. Only the three named files were touched:
`scripts/checkpoint.py`, `scripts/_checkpoint_lib.py`, `bin/handoff-approved`.
No test file was edited.

## Step 1 — session id validated before any write (finding 2)

Red rows:
`test_held_via_commit_session_id_unset_errors_before_any_write`,
`test_held_via_memory_session_id_unset_errors_before_any_write`.

**Ordering, and why it can't disagree with the sentinel's state.** `main()`
already computed `held = hold_decision(transition, memory=…, commit=…)`
once, after the write phase, and fed that single value to both
`compose_sentinel` (the state line) and `Ending` (the printed part). I moved
the `memory = lib.memory_directive(...)` call and the `hold_decision(...)`
call up, ahead of the task/todo write phase and `write_manifest` — nothing
about `hold_decision`'s inputs (`transition`, `memory.text`, `commit_mode`)
depends on anything the write phase produces, so moving it earlier changes
no computed value, only when it runs. Immediately after computing `held`,
`if held: require_session_id(...)` — a single new call site, no second read
of the hold predicate, so the value that gates the check is the exact same
`bool` that later gates the sentinel's `held <session>` / `armed` line and
the `Ending.held` used to pick the arming instruction vs. the closing line.
There is now exactly one `hold_decision` call in `main()`, same as before —
I did not duplicate it to check early and again late.

**The check itself.** Extracted the existing inline check from
`_build_restart_transition` into a shared `require_session_id(field, reason)`
helper (same wording pattern — `"CLAUDE_CODE_SESSION_ID is unset — {reason}"`
— just parameterized by field and reason), and `_build_restart_transition`
now calls it too (`require_session_id("restart", "cannot compose the resume
command")`). The held-path call site is `require_session_id("transition",
"cannot compose a held sentinel naming the session holding it")`, `err()`'d
the same way as every other schema-time refusal, before `plan_task` /
`plan_todo` / `apply_plan` / `write_manifest` / `compose_sentinel` ever run —
so on this path nothing is written: no task file, no todo file, no manifest,
no sentinel.

The armed path is untouched by the new check — `held` is `False` there, so
`require_session_id` is never called, keeping
`test_armed_cell_succeeds_with_session_id_unset` green with the variable
unset.

Targeted run after this step:
```
$ pytest tests/test_checkpoint.py -q -k "held_via_commit_session_id_unset or held_via_memory_session_id_unset or held_session_id_set_still_succeeds_via_commit or armed_cell_succeeds_with_session_id_unset or restart"
19 passed
```
All four rows from this section pass; the `restart`-selected rows (which
share the refactored helper) stay green too.

## Step 2 — `closing_directive` raises on an unknown skill (finding 4)

Red row: `test_closing_directive_raises_on_unknown_skill`.

Added, ahead of the existing body:
```python
if skill not in ("handoff", "precompact"):
    raise ValueError(skill)
```
in `scripts/_checkpoint_lib.py`. `raise ValueError(f"unknown skill {skill!r}")`
was tried first but tripped ruff's `TRY003` (long message outside the
exception class, and `scripts/*.py` carries no per-file ignore for it, unlike
`tests/**`); `raise ValueError(skill)` satisfies both ruff and the test
(`pytest.raises(ValueError, match="bogus")` matches on `str(exc)`, which for
`ValueError("bogus")` is `"bogus"`).

```
$ pytest tests/test_checkpoint.py -q -k closing_directive
1 passed
```

## Step 3 — `bin/handoff-approved` refuses an unexpected kind (finding 3)

Red row: `tests/checkpoint.bats` — "handoff-approved: a held sentinel of an
unexpected kind -> exit 2, left held, naming the kind".

Added a `case "$DRIVE_KIND" in rename | clear | compact) ;; *) err "the held
transition is kind \`$DRIVE_KIND\`, which this command does not know how to
arm" ;; esac` guard immediately after the owner check and **before**
`handoff_drive_arm`, so a held sentinel of an unexpected kind is left held
(`handoff_drive_arm` never runs) rather than being consumed into `armed`
with no closing line to print. The existing closing-line `case` is untouched
in shape — no `*)` arm added there, since it is unreachable once the new
guard runs first — only its comment was rewrapped (same words, ~76-column
wrap instead of the ~117-column line) as asked; the "Restart never holds…"
sentence stays in place there, and a distinct short comment was written for
the new guard case rather than moving that sentence.

```
$ bats tests/checkpoint.bats -f "unexpected kind"
ok 1 handoff-approved: a held sentinel of an unexpected kind -> exit 2, left held, naming the kind
```

## Full suites and linters

```
$ pytest tests/test_checkpoint.py -q
179 passed in 48.33s

$ bats tests/checkpoint.bats
1..28
ok 1..28   (all 28 pass, including the three targeted rows above)

$ bats tests/hook-test.bats -f "approved"
1..0   (no rows match that filter in this file — nothing to report)

$ ruff check scripts/ tests/
All checks passed!

$ ruff format --check scripts/ tests/
11 files already formatted

$ docformatter --check scripts/*.py tests/*.py
tests/test_checkpoint.py   # pre-existing (untouched by this dispatch — see
                            # `git diff --stat tests/test_checkpoint.py`,
                            # 138 insertions from the RED phase); not a file
                            # this dispatch may edit

$ mypy scripts/checkpoint.py scripts/_checkpoint_lib.py
(no output — clean)

$ ty check scripts/checkpoint.py scripts/_checkpoint_lib.py
All checks passed!

$ shellcheck -x bin/handoff-approved
(no output — clean)
```

## Stale documentation (not edited — for the parent)

`CLAUDE.md:533-534` (the `bin/handoff-approved` bullet):

> `handoff_drive_arm`; exits 2 naming the state it found when the file is
> absent or not `held`, and naming the owner when the held file is another
> session's — the approval it speaks for is the one *this* session was asked
> for, and the state alone does not say that.

Now incomplete: it also exits 2 naming the *kind* when the held file's kind
is not `rename`/`clear`/`compact`, checked before `handoff_drive_arm` runs
(so the file is left `held`, not moved to `armed`). Proposed addition, right
after the owner clause:

> — and naming the kind when the held file's kind is none of `rename`,
> `clear` or `compact`, checked ahead of `handoff_drive_arm` so the file is
> left `held` rather than consumed into a state with no closing line to
> print.

`docs/design/the-checkpoint-directive.md:103`:

> `handoff-approved` — which verifies the state and nothing else — would
> drive a dead session's `/rename` and `/clear` into a live conversation.

"and nothing else" is now false: it also verifies the kind (`rename`/
`clear`/`compact`) before arming. The sentence's own point (why the owner
name matters) is unaffected, so the narrowest fix is dropping the "and
nothing else" clause or widening it to "and the owner" — e.g. "which
verifies the state, the owner and the kind —". This file is outside my
touched set (the concurrent markdown-editing agent's scope), so left as-is.

No other passage found describing `CLAUDE_CODE_SESSION_ID` validation as
absent on the held path, or `closing_directive` as silently defaulting for
an unrecognized skill — grepped `CLAUDE.md` and `docs/design/*.md` for
`CLAUDE_CODE_SESSION_ID`, `closing_directive`, `handoff-approved` and read
every hit.

## Tree state

```
$ git status --short | grep -v '^??'
M  .claude/handoff-todo.md
 M CLAUDE.md
 M README.md
 M bin/handoff-approved
 M docs/changelog.md
 M docs/design.md
 m memory
 M scripts/_checkpoint_lib.py
 M scripts/_lib.sh
 M scripts/checkpoint.py
 M skills/handoff/SKILL.md
 M skills/precompact/SKILL.md
 M tests/checkpoint.bats
 M tests/test_checkpoint.py
 M tests/test_tui_conformance.py
```

Nothing staged, nothing committed. `bin/handoff-approved`,
`scripts/checkpoint.py` and `scripts/_checkpoint_lib.py` carry this
dispatch's changes; every other modified path was already dirty before this
dispatch started (the concurrent markdown-editing agent's work, and the
pre-existing `_lib.sh`/`test_checkpoint.py`/`checkpoint.bats` changes from
earlier phases of this plan) and was not touched here.

## Order tests were made to pass

1. `test_held_via_commit_session_id_unset_errors_before_any_write` and
   `test_held_via_memory_session_id_unset_errors_before_any_write` together
   (one code change covers both — the early `hold_decision` + guard in
   `main()`), verified alongside the paired positives.
2. `test_closing_directive_raises_on_unknown_skill`.
3. `tests/checkpoint.bats` — "handoff-approved: a held sentinel of an
   unexpected kind -> exit 2, left held, naming the kind".
