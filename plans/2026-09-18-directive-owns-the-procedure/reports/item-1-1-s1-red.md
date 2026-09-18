# Item 1.1, slice 1/1 — RED report

Mode: RED. k=1: `commit_directive()` stubbed importable but inert (returns
`""`), no restructuring of `checkpoint.py`.

## Stub

`scripts/_checkpoint_lib.py`, added ahead of `arming_directive()`:

```python
def commit_directive() -> str:
    """Return the commit act, printed under "with-commit".

    Stub for RED (Item 1.1 slice 1): inert, returns "". The real body names
    no git verb.
    """
    return ""
```

## Tests added

`tests/test_checkpoint.py`, new `# Commit act` section between the memory
directive tests and `# Composition`. Also added `import _checkpoint_lib as
lib` (module-level, `pyproject.toml`'s `pythonpath = ["scripts"]` resolves
it) and `Callable` to the `collections.abc` import.

- `test_with_commit_prints_the_commit_act` — parametrized on `handoff_payload`
  / `precompact_payload`, over a clean `make_gitlore_repo` (clean memory, no
  ledger).
- `test_without_commit_prints_no_commit_act` — same fixture and
  parametrization.
- `test_commit_act_names_no_git_verb` — no fixture, calls `lib.commit_directive()`
  directly.

## Run: `pytest tests/test_checkpoint.py -k commit_act -v`

All 5 fail on `assert commit_act` (`AssertionError: assert ''`) — none pass,
none error (no ImportError, no collection failure):

```
tests/test_checkpoint.py::test_with_commit_prints_the_commit_act[handoff_payload] FAILED
    commit_act = lib.commit_directive()
>   assert commit_act
E   AssertionError: assert ''
tests/test_checkpoint.py:2213: AssertionError

tests/test_checkpoint.py::test_with_commit_prints_the_commit_act[precompact_payload] FAILED
    commit_act = lib.commit_directive()
>   assert commit_act
E   AssertionError: assert ''
tests/test_checkpoint.py:2213: AssertionError

tests/test_checkpoint.py::test_without_commit_prints_no_commit_act[handoff_payload] FAILED
    commit_act = lib.commit_directive()
>   assert commit_act
E   AssertionError: assert ''
tests/test_checkpoint.py:2226: AssertionError

tests/test_checkpoint.py::test_without_commit_prints_no_commit_act[precompact_payload] FAILED
    commit_act = lib.commit_directive()
>   assert commit_act
E   AssertionError: assert ''
tests/test_checkpoint.py:2226: AssertionError

tests/test_checkpoint.py::test_commit_act_names_no_git_verb FAILED
    commit_act = lib.commit_directive()
>   assert commit_act
E   AssertionError: assert ''
tests/test_checkpoint.py:2234: AssertionError

5 failed, 149 deselected in 0.97s
```

## Full-file run: `pytest tests/test_checkpoint.py -q`

`5 failed, 149 passed in 20.42s` — the same 5 new tests, every pre-existing
row (including `test_not_gitlore_managed_silent`,
`test_gitlore_clean_memory_silent` and the memory-directive rows the new
`import _checkpoint_lib as lib` sits beside) unaffected.

## Scope confirmation

No changes to `checkpoint.py`, `bin/handoff-approved`, `tests/checkpoint.bats`,
or any skill body. Tests are uncommitted; nothing committed this run.
