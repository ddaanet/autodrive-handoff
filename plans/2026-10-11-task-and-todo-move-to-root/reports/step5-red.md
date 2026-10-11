# Step 5 RED report: hook-test.bats

Only `tests/hook-test.bats` changed. Against today's code: `bats tests/hook-test.bats` gives 98 ok / 26 not ok (124 rows). All 26 failures are rows added or rewritten. Every untouched row passes. A reference implementation of the contract, written in a scratch copy under `$TMPDIR` (nothing under `scripts/` changed), takes the file to 124 ok / 0 not ok, so the rows are satisfiable and not contradictory.

Helpers added: `assert_framed <text> <expected-rest>` (one header line matching `# Task — YYYY-MM-DD HH:MM:SS +ZZZZ`, then exactly the expected rest), `split_output <json>` (sets `MSG` and `CTX` exactly, trailing newlines kept), `assert_msg_matches <regex>` (anchored at both ends of the whole `systemMessage`) and `loaded_re`. `shellcheck -x tests/hook-test.bats` is clean.

## handoff_frame (all rewritten, called directly, not through `run`; all RED)

Each fails on its first FRAME assertion: `FRAME` is not set today, because the function prints. The rc assertions pass today and are not what fails.

| old name | new name | red on |
|---|---|---|
| task + todo -> one header, both inlined, task first | task and todo count: header, task, then todo; both flags 1 | `assert_framed` (FRAME) |
| todo alone -> frame still assembles | todo alone: the frame is the header and the todo; task flag 0 | `assert_framed` |
| task alone -> unchanged single-file shape | task alone: the frame is the header and the task; todo flag 0 | `assert_framed` |
| neither file -> rc 1, no output | neither file exists: rc 1, FRAME empty, both flags 0 | `[ "${FRAME-unset}" = "" ]` (unset today) |
| empty files count as absent | zero-byte files: do not count | `${FRAME-unset}` |
| (new) | headings-only task beside a todo: the task headings stay out of FRAME | `assert_framed` |
| (new) | headings-only on both sides: rc 1, FRAME empty, both flags 0 | `[ "$rc" -eq 1 ]` (today a headings-only file is non-empty, so rc 0) |
| (new) | whitespace-only task beside a todo: the task does not count | `assert_framed` (today the blank task is inlined) |
| (new) | a #tag line and a #!/bin/sh line: both are body and both count | `assert_framed` |
| (new) | a second call: resets FRAME and both flags | `FRAME_TASK` = 1 after the first call (unset today) |
| (new) | output: nothing on stdout or stderr, with a missing todo | `[ "$out" = "" ]` (the `$(…)` capture, the one place it is right; it prints the frame today). The same fixture is then called directly and asserted to produce a frame, so the silence is not a failure. Stderr is asserted empty. |

## load-handoff

| old name | new name | state | red on |
|---|---|---|---|
| silent no-op without task file | no file at all -> No task frame or todo on both channels | RED | `MSG` equality (today the script is silent, output empty) |
| injects the todo remainder too | task and todo count -> the frame, no gap note | GREEN | the contract leaves this state unchanged |
| todo alone still injects | todo alone -> No task frame on both channels | RED | `[ "$framed" != "$CTX" ]`, because there is no `No task frame.` tail today |
| (new) | task alone -> No todo on both channels | RED | `[ "$framed" != "$CTX" ]`. It also pins the note's size to the length of FRAME, not FRAME plus the gap line. |
| (new) | headings-only task beside a todo -> the todo-alone state | RED | `assert_msg_matches "$loaded_re; No task frame"` |
| (new) | headings-only task and todo -> the neither state | RED | `MSG` equality |
| (new) | age: taken from the files that count, not from a headings-only one | RED | `assert_msg_matches ... saved 2d ago; No task frame` (today the fresh headings-only task makes it `just now`) |
| clear, pending present but NO frame: still consumes | same name plus ", and says so" | RED | `MSG` equality. Previously `[ "$output" = "" ]`. The `[ ! -e autodrive ]` consume assertion before it passes today. |
| (new) | clear, malformed pending: its note precedes the frame notes | RED | `assert_msg_matches "autodrive malformed — [^;]+; not resuming; $loaded_re; No todo"` (today `loaded` comes first) |

The green row (task and todo count) would fail if the loader appended a gap line or note when both count, if the message deviated from `handoff: loaded — <size>, saved <age>` (anchored at both ends), if the context were not exactly FRAME plus `\n`, or if the event were not echoed.

Untouched rows that still pass:
- "injects header + task, echoes event", which is the task-alone state and only greps.
- The KiB-threshold row, whose regex has no end anchor.
- The worktree row.
- All the other clear/startup/armed/compact-kind rows.

## load-compact

| old name | new name | state | red on |
|---|---|---|---|
| pending present: consumes it, frame re-injected | pending present, todo present: consumes it, todo re-injected (TASK.md removed, todo written) | RED | `MSG` = `todo re-injected` |
| no task file: consumed, no frame | pending present, no todo, no task: consumed, No todo, nothing injected | RED | `MSG` = `compacted — No todo.` |
| (new) | pending present, headings-only todo, no task: consumed, No todo, nothing injected | RED | `MSG` (today the headings are injected and the message is `frame re-injected`) |
| task file present: injects the frame | a hand-written TASK.md alone: injected, and the message says No todo | RED | `MSG` |
| (new) | a hand-written TASK.md beside a todo: both injected, task first | RED | `MSG` = `todo re-injected` |
| pending with no continuation: consumed, frame only | same name, message now `No todo` | RED | the `.systemMessage ==` jq line |
| empty after-sequence: frame injected | same name, message now `No todo` | RED | the same jq line |

The no-pending, kind-clear, armed and worktree rows are unchanged and green.

## Removed
Nothing is dropped without a replacement. The old names above are renames or rewrites of the same scenario. The "no task file" compact row's scenario now lives in the "no todo, no task" row.

## Totals
bats against today's code: 98 ok, 26 not ok (11 handoff_frame, 8 load-handoff, 7 load-compact). Against the scratch reference implementation: 124 ok, 0 not ok.

## Flake, unrelated to this slice
`write-guard (trailing whitespace after the name: deny)` failed once in a full run (jq saw no deny). It passed on the next full run and when run alone, and it passed in the later full runs. The cause is not found.

## Contract notes (ambiguous or untestable as written)
1. "Verbatim" vs trailing newlines: the contract says FRAME has no trailing newline and each file is inlined verbatim. A file ending in several newlines cannot be both. The rows use fixtures ending in one newline and expect that newline stripped, as the current `$(cat)` does.
2. `<size>` in a `loaded` note is the length of FRAME, in characters or bytes depending on locale. The task-alone and todo-alone rows compute it with bash `${#framed}` in the same environment as the script, so they agree in any locale.
3. The age row relies on GNU `touch -d '2 days ago'`, as the brief asked, and is not portable to BSD touch.
4. The malformed-note row asserts the `DRIVE_ERR` part as `[^;]+` and does not pin the parser's exact message, which is the parser's contract and not this step's.
5. The loader contract does not say what `hookEventName` is on the neither state. The rows assert it echoes the event, which is the same field as the other states.
