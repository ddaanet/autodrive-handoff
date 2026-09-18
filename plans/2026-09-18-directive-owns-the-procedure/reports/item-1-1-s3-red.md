# Item 1.1 / Slice 3 — RED report

Test added: `tests/test_checkpoint.py::test_with_commit_memory_text_drops_nothing_further`,
placed after `test_without_commit_keeps_standalone_two_file_instruction` (same
memory-text grouping as the existing `carries the memory` rows), before the
`# Commit act` section header.

```python
def test_with_commit_memory_text_drops_nothing_further(tmp_path: Path) -> None:
    repo = make_gitlore_repo(tmp_path)
    dirty_memory(repo)
    result = run_checkpoint(repo, handoff_payload("with-commit"))
    assert result.returncode == 0
    assert "gitlore memory has uncommitted changes" in result.stdout
    assert "nothing further" not in result.stdout.lower()
```

No SUT changes (`scripts/*` untouched).

## Per-test output

### `test_with_commit_memory_text_drops_nothing_further` — target test

```
$ pytest tests/test_checkpoint.py::test_with_commit_memory_text_drops_nothing_further -v
FAILED tests/test_checkpoint.py::test_with_commit_memory_text_drops_nothing_further

    assert result.returncode == 0
    assert "gitlore memory has uncommitted changes" in result.stdout
>   assert "nothing further" not in result.stdout.lower()
E   AssertionError: assert 'nothing further' not in 'gitlore mem...led for.\n\n'
E     'nothing further' is contained here:
E       gitlore memory has uncommitted changes:
E       ...

1 failed in 0.64s
```

Fails on the intended absence assertion (the third `assert`), not on the
earlier non-empty/anchor check — `assert result.returncode == 0` and
`assert "gitlore memory has uncommitted changes" in result.stdout` both pass
first, proving the test reaches production code and the fixture (dirty
memory, `with-commit`) is live before the discriminating assertion runs.
Today's `_checkpoint_lib.py:144-145` text — `"The commit that lands these
changes carries the memory. Nothing further is needed from you."` — is what
trips it.

### Full file — `pytest tests/test_checkpoint.py -q`

```
........................................................................ [ 45%]
..................................................................F..... [ 91%]
.............                                                            [100%]
1 failed, 156 passed in 19.44s
```

The one failure is the new test. All 156 pre-existing rows stay green,
including:
- `test_with_commit_states_commit_carries_the_memory` (asserts `"carries the
  memory"` present) — untouched, still green.
- `test_with_commit_summary_write_only_no_trigger_mention` (the load-bearing
  trigger-file negative) — still green.
