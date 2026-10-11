# Step 2 RED report: task shape (body cap, no list items)

Only `tests/test_checkpoint.py` changed (224 insertions, no deletions). New section "Task shape" sits before the "Manifest -- FR7" section. Helpers added there: `TASK_BODY_LIMIT`, `shaped_payload`, `prose`, `assert_task_shape_error`. The last asserts exit 2, exactly one stderr line starting `handoff-checkpoint: task: `, the given facts, and the fragments `"todo"`, `one sentence` and `memory`.

## Whole file

- Before: 195 total in the file with my 25 new; `pytest tests/test_checkpoint.py -q` gives 14 failed, 181 passed.
- All 14 failures are new tests. Every pre-existing test passes.
- `ruff check tests` and `ruff format --check tests` pass.

## Reds (14), all failing the same first assertion

Each fails on `assert result.returncode == 2` (got 0, because nothing is rejected yet). None is a collection, NameError or fixture error.

- `assert_task_shape_error` (helper): `test_task_body_cap_boundary[one_over_rejected]`, `test_task_body_cap_counts_characters_not_bytes[1001_characters_rejected]`, `test_task_hash_without_space_is_body_not_a_heading` (1000 prose chars plus a `#tag` line, so 1005), `test_task_list_item_rejected_naming_its_line[...]` x8, `test_task_over_the_cap_with_a_list_item_is_one_error_with_both_facts`.
- Inline `assert result.returncode == 2` in the test body: `test_task_shape_failure_writes_nothing[over_the_cap]` and `[list_item]`.
- The 8 list ids are: `dash_after_heading_and_blank` (line 3), `star_after_two_prose_lines` (line 3), `plus`, `numbered_dot`, `numbered_paren`, `indented_dash_quote_is_stripped`, `first_of_two_items_is_named` (two items, the first is named), `long_line_quote_cut_to_40` (line 4). Each asserts the exact fragment `line <n> is a list item ("<quote>")`.

The message-content assertions (count, limit text, quote, closing-sentence fragments) are behind the returncode assertion, so they are not yet exercised. They get their first run in the green phase.

## Green before the change (11): need a mutation in the green phase

Each is green only because nothing is rejected today. The mutation is applied to the future implementation, and the test should then go red.

- `test_task_body_cap_boundary[exactly_the_limit_accepted]`: use `>=` instead of `>`, or a limit of 999.
- `test_task_body_cap_does_not_count_headings[headings_around_the_body]` and `[heading_splits_the_body]`: count heading lines in the body. Both fixtures are over 1010 characters when headings are counted, and 1000 without them. The second also pins that the heading line is removed before joining with `\n`.
- `test_task_body_cap_ignores_blank_lines_and_whitespace_around_the_body`: drop the final `.strip()` on the body. The fixture then measures 1000 plus the leading blank lines and the whitespace-only line, which is over 1000.
- `test_task_body_cap_counts_characters_not_bytes[1000_characters_are_2000_bytes_accepted]`: measure `len(s.encode())` instead of `len(s)`.
- `test_task_lines_that_are_not_list_items_accepted[...]` (5 ids, one mutation each):
  - `bold`: marker class `\*` matched without requiring `\s` (`**bold**` has `*` first), or a regex like `^\s*[-*+]`.
  - `mid_line_hyphen`: drop the `^` anchor or the `\s*`-then-marker position, so a hyphen anywhere matches.
  - `marker_without_space`: drop the trailing `\s` after the marker (`-flag`).
  - `year`: relax `\d+[.)]` to `\d+`.
  - `decimal`: make the `\d+[.)]` marker not require whitespace after it, or `[.)]` become `.` anywhere (`3.5`).
- `test_task_clear_is_not_subject_to_the_shape_rules`: apply the shape check to the `clear` branch or to the pre-existing file. Green today and stays green with a correct implementation, so it is not a red.

## Fixture notes

- `#tag` fixture: 1000 prose characters plus a `#tag` line gives 1005. It is rejected only if `#tag` is counted as body (a regex of `#+` without the whitespace rule would accept it).
- The both-violations test computes the count as `len(content.strip())`. The content has no heading lines, so that equals the body length by the spec's definition.
- The nothing-written test uses a pre-existing task file (`stale`) and a `todo` content string, then asserts the task bytes are unchanged, no todo file and no manifest.
