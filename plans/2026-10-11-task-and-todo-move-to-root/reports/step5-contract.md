# Step 5 contract: the loaders report

The contract both step 5 dispatches work from. It refines the plan's "Hooks"
section where the plan left a choice open, and departs from it in one place,
named below.

## `handoff_frame <task-path> <todo-path>` (`scripts/_lib.sh`)

- A file **counts** when it exists and has a body: `python3
  _checkpoint_lib.py --is-empty-body < file` exits non-zero. A missing file, a
  zero-byte file, a whitespace-only file and a headings-only file do not
  count. `#tag` and `#!/bin/sh` lines are body (the rule is `is_empty_body`'s,
  not a `#` prefix test).
- It prints nothing. It sets three variables in the caller's scope, on every
  call, so nothing survives from an earlier call:
  - `FRAME`: empty when neither file counts; otherwise the header line
    `# Task — <date '+%Y-%m-%d %H:%M:%S %z'>`, then each counting file inlined
    verbatim but for its trailing newlines, task first, each preceded by one
    blank line. No trailing newline.
  - `FRAME_TASK` and `FRAME_TODO`: `1` when that file counts, else `0`.
- It returns 0 when `FRAME` is non-empty and 1 when it is empty. Both loaders
  run under `set -euo pipefail`, so each call site absorbs the 1
  (`handoff_frame … || true`) and reads the variables.
- Existence is tested before the body (`-f`, then the Python call): a
  redirect from an absent path fails in the shell, on stderr, before Python
  runs.

**Departure from the plan.** The plan kept `handoff_frame` printing the frame
and had it "also set" the two flags. Both loaders capture its output with
`$(…)`, and a variable set inside a command substitution dies with the
subshell, so the frame moves into `FRAME` and the callers stop capturing. This
is the idiom `handoff_drive_read` and `handoff_root_read` already use.

## `scripts/load-handoff.sh` (`SessionStart`, `startup|clear`)

The transition consume is unchanged and still comes first. The script then
always emits one JSON object; it has no silent exit left except an unresolvable
root.

`systemMessage` is `handoff: ` followed by the notes joined with `; `, in this
order:

1. the transition note, when there is one (today only
   `autodrive malformed — <DRIVE_ERR>; not resuming`);
2. the frame notes:
   - both files count: `loaded — <size>, saved <age>`
   - the task alone counts: `loaded — <size>, saved <age>`, then `No todo`
   - the todo alone counts: `loaded — <size>, saved <age>`, then
     `No task frame`
   - neither counts: `No task frame or todo.` and nothing else

`<size>` is the length of `FRAME`, formatted as today. `<age>` is formatted as
today and computed from the newest mtime **among the files that count**: a
headings-only file touched a second ago does not make a two-day-old todo read
`just now`.

`hookSpecificOutput.additionalContext`, with `hookEventName` echoing the event:

- both count: `FRAME` plus `\n` (unchanged)
- the task alone: `FRAME`, a blank line, `No todo.`, `\n`
- the todo alone: `FRAME`, a blank line, `No task frame.`, `\n`
- neither: `No task frame or todo.\n`

## `scripts/load-compact.sh` (`SessionStart`, `compact`)

Every gate is unchanged: silent with no sentinel, a malformed sentinel removed
and reported, only a `pending` `compact` consumed. After the consume:

- `FRAME_TODO` is 1: `additionalContext` is `FRAME` plus `\n`, `systemMessage`
  is `handoff: compacted — todo re-injected.`
- `FRAME_TODO` is 0: `systemMessage` is `handoff: compacted — No todo.` The
  frame is still injected when a `TASK.md` with a body is there; when `FRAME`
  is empty there is no `hookSpecificOutput` at all.

The empty-frame note reaches the agent from `load-handoff.sh` only; this
script says `No todo` to the user alone.

## Rows

`handoff_frame`: both files; each alone; neither; zero-byte files; a
headings-only task beside a real todo (the heading is not in `FRAME`,
`FRAME_TASK` is 0); headings-only both (rc 1); a whitespace-only file; a `#tag`
body counts; a second call resets all three variables; nothing on stdout.
These rows call the function directly, never through bats `run`: `run` is a
subshell, and an assertion on a variable it set would read the test's own
unset one. The return code is taken with `rc=0; handoff_frame … || rc=$?`.
The stdout row is the one place a `$(…)` capture is right.

`load-handoff.sh`: the four frame states, each asserting both channels in
full (the `loaded` note by pattern, the rest by equality); a headings-only
`TASK.md` reads as the todo-alone state and a headings-only pair as neither;
the age row (a `TODO.md` with a body whose mtime is set two days back with
`touch -d`, beside a headings-only `TASK.md` written after it, reads
`saved 2d ago`); a driven clear with no frame consumes and reports
`handoff: No task frame or todo.`; a malformed sentinel's note precedes the
frame notes.

`load-compact.sh`: no pending sentinel is silent; pending with a todo; pending
with no todo; pending with a headings-only todo. Two more rows cover a
`TASK.md` written by hand after the checkpoint removed it, the only way one
is there at this event, and are named for that: beside a todo, both are
injected, task first, and the message is still `todo re-injected`; alone, it
is injected and the message is `No todo`.
