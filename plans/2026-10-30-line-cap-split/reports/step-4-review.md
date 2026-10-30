# Step 4 review: 47b3ab7, `♻️ split the two oversized checkpoint pytest files`

Read-only against the commit (`git show 47b3ab7:…` / `47b3ab7^:…`), with the
tree exported to `/tmp/claude/line-cap-split/review-4/` for collection and the
test runs. Nothing in the repo was written but this file.

## Verdict

No high or medium finding. The move is verbatim beyond what the checker sees,
every helper and comment survives exactly once in the file that uses it, the
imports and `pytestmark` are right, and every prose edit is true of the code at
47b3ab7. Six low findings follow, two of them pre-existing.

## How the non-test content was checked

The checker sees only `def test_` blocks, so I diffed the rest by line range
against the parent:

- `test_checkpoint_hold.py`: old 37–326 equal new 28–317 (old 327–328 were the
  two blank lines ahead of the moved banner). Old 329–548, the "The sentinel's
  lock" banner through the last read-back row, equal new
  `test_checkpoint_readback.py` 25–244 byte for byte.
- `test_checkpoint_transition.py`: old 22–253 equal new 22–253; old 502–532
  (the `LINE_BREAKS` comment, the dict with its literal U+2028/U+2029 and the
  line-break row) equal new 254–284. Old 254–499, from `# --- \`continue\`
  needs a task or a todo …` through the last legal-combination row, equal new
  `test_checkpoint_sentinel.py` 26–271. Old 500–501 were blank.
- Only the headers (docstring, imports) are new text, in all four files.

An `ast` pass over the four files: the union of top-level names on each side
equals the old file's, with no name defined twice except `pytestmark` (once per
file, as intended). Every module-level helper is used in the file that defines
it, and no file uses a helper defined in its sibling:

- hold keeps `_assert_nothing_written`;
- readback holds `_writing_payload`, `_tree`, `_stub_reader`;
- transition keeps `BOUNDARIES`, `DRIVEN`, `NOT_DRIVEN`, `boundary_payload`,
  `LINE_BREAKS`;
- sentinel holds `TODO_BODY`, `BODYLESS`, `clear_continue_payload`,
  `seed_frame`, `frame_bytes`.

So no helper is owed to `conftest.py` under the plan's helper rule.

Imports: `ruff check` is clean on all four files (nothing unused), and the full
run passing means nothing used is missing. Each new file carries
`pytestmark = pytest.mark.usefixtures("_session_id")`, as its siblings do and as
CLAUDE.md's py-test entry requires. The collected node ids of the two old files
equal those of the four new ones (128 each side, `diff` empty, file prefix
stripped).

References: `git grep -n -e checkpoint_hold -e checkpoint_transition 47b3ab7 --
. ':!plans' ':!docs/changelog' ':!TASK.md' ':!TODO.md'` finds only the two
intended CLAUDE.md coverage entries (lines 803 and 832). I checked each of these
against the code:

- the four CLAUDE.md entries (803–818, 832–841);
- `docs/design/sentinel-lock.md` 122–126, where "They" are the contention rows,
  and the checkpoint's two contention rows are in readback;
- the `tests/test_drive_lock.py` docstring, where the checkpoint's ordering row
  `test_sentinel_write_waits_on_the_lock` is in readback;
- the transition docstring's pointer to sentinel.

All are true. The mutation-check note stays on the hold entry, and both rows it
names are still in hold: the names-nothing row
`test_sentinel_typing_nothing_arms_even_with_memory_gate_pending` and the
`(driven ∧ with-commit)` row `test_typed_with_commit_clean_memory_is_held`.
`read_back_drive` (conftest.py:220) runs `handoff_drive_read`, as the sentinel
entry says.

## Findings

### F1 (low): sentinel opens on a subsection heading with no section banner

`tests/test_checkpoint_sentinel.py:26`. The file's first heading is
`# --- \`continue\` needs a task or a todo to point at (handoff only) ---`. Its
second is at line 146. Both were subsections of the
`# ===… The transition and the continuation ===…` banner, and that banner stayed
in transition. The three sibling files each open with a `# ===` banner
(hold:31, readback:25, transition:25). This is placement only: nothing a reader
acts on changes.

### F2 (low): the line-break row now sits under the `continue` subsection heading

`tests/test_checkpoint_transition.py:254`. `LINE_BREAKS` and
`test_compact_directive_with_any_line_break_errors` follow directly after the
four rows under
`# --- \`continue\` is a boolean; \`true\` needs a carried-out transition ---`
(line 180), with no heading of their own. So that heading reads as covering a
`compact` row. Before the commit they sat under
`# --- the legal combinations and the sentinel's bytes ---`, which was no better
a fit. The executor's report names this ("No section heading was added"). It is
placement, and the module docstring names the row.

### F3 (low): the transition docstring omits the continuation-constant row

`tests/test_checkpoint_transition.py:1-4` lists "the field matrix, `continue`
as a boolean and the refusal of a line break in the compact directive". It
leaves out `test_the_continuation_is_one_line_the_drive_will_not_run_as_a_command`
(line 173), which is in this file, as CLAUDE.md:811–812 says ("and the
continuation constant itself"). Its pointer sentence ("What the legal
combinations write into the sentinel is in tests/test_checkpoint_sentinel.py")
could send a reader looking for `CONTINUATION`'s own test to the other file. The same
pointer names only the legal combinations as having moved. The
`continue`-needs-a-body rows (old 254–372, e.g.
`test_continue_true_with_no_task_or_todo_to_point_at_errors`) moved to sentinel
too, and the pointer does not say so. But nothing states that any of these tests
is in the other file than the one it is in, so the docstring is incomplete, not
contradicted.

### F4 (low): the readback docstring stops short of "raises"

`tests/test_checkpoint_readback.py:3-4` says "a reader that cannot run or fails
removes the unverified file". `test_an_unexpected_read_back_failure_removes_the_sentinel`
(line 227) monkeypatches `checkpoint._read_back_drive` to raise `RuntimeError`.
That is not a reader failing, and CLAUDE.md:840–841 words the case as "cannot
run, fails or raises". It is a summary, not a wrong claim.

### F5 (low, process): `docs/design/` edited without loading `craft:design-doc-writing`

`docs/design/sentinel-lock.md:125`. The plan's Invariants and the dispatch's
phase-A step 2 both require loading the skill before touching `docs/design/`.
The executor's report says it did not, and argues that the edit is a filename in
one sentence. The edited sentence is true at 47b3ab7 (see above) and stays under
80 columns, so the outcome is unaffected.

### F6 (low, pre-existing, not introduced here)

- `tests/test_checkpoint_hold.py:1-4`: the docstring says "the held path's
  validation of CLAUDE_CODE_SESSION_ID". The file also tests the armed cell's
  (`test_armed_cell_session_id_unset_errors_before_any_write`, line 186). The
  text is unchanged from the parent, so this is not the split's doing.
- `tests/test_drive_lock.py:6-7`: docformatter's wrap breaks the path as
  `tests/` + newline + `test_checkpoint_readback.py`. A grep for the full path
  misses it, though the plan's basename grep finds it. The parent had the same
  break at the same place, with `test_checkpoint_hold.py`.

## Re-run checks

Verbatim checker (run from `/Users/david/code/handoff`; exit 0 for both):

```text
hold:       blocks: old 25, new 25
            verbatim: OK
transition: blocks: old 26, new 26
            verbatim: OK
```

`def test_` counts (`grep -c '^def test_'`):

| File | Parent | Commit |
| --- | --- | --- |
| `tests/test_checkpoint_hold.py` | 25 | 17 |
| `tests/test_checkpoint_readback.py` | — | 8 |
| `tests/test_checkpoint_transition.py` | 26 | 15 |
| `tests/test_checkpoint_sentinel.py` | — | 11 |

So hold + readback = 25, and transition + sentinel = 26.

Collection in the export:

- Whole suite: `520/523 tests collected (3 deselected)`, the same at 47b3ab7^.
- Per file: hold 19, readback 8 (sum 27); transition 75, sentinel 26 (sum 101).
- Node ids: old and new sets equal, 128 each.

Test runs in the export:

- The four files plus `tests/test_drive_lock.py`: `146 passed`.
- The full `pytest`: `520 passed, 3 deselected`.

Lint in the export:

- `ruff check` on the five touched Python files: `All checks passed!`.
- `ruff format --check`: `5 files already formatted`.
- `docformatter --check`: clean.
- `mypy`: rc 0.
- `ty check`: `All checks passed!`.

Line counts (`git show 47b3ab7:<path> | wc -l`):

| Path | Lines |
| --- | --- |
| `CLAUDE.md` | 911 (exempt; own TODO item) |
| `docs/design/sentinel-lock.md` | 128 |
| `tests/test_checkpoint_hold.py` | 317 |
| `tests/test_checkpoint_readback.py` | 244 |
| `tests/test_checkpoint_sentinel.py` | 271 |
| `tests/test_checkpoint_transition.py` | 284 |
| `tests/test_drive_lock.py` | 280 |

Line-cap scan of the 47b3ab7 tree (plan's Verification, outside `plans/` and
`docs/changelog/`), files over 400 lines:

| File | Lines |
| --- | --- |
| `tests/hook-test.bats` | 3985 |
| `tests/test_checkpoint_legacy.py` | 1563 |
| `CLAUDE.md` | 911 |
| `tests/checkpoint.bats` | 695 |

Both pytest files are off the list. The two `.bats` files are steps 2 and 3,
which had not landed at 47b3ab7.
