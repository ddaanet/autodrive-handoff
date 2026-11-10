# Proposal: the cancel acts on the window's own take

2026-11-10. Status: approved 2026-11-10 with the default on each open
question, problem 1 kept as part of the case. It settles the `TODO.md` item
"Decide whether to rework the prompt-after-`Stop` cancel". Mechanism today:
[A prompt after `Stop`](../docs/design/queued-prompts.md#a-prompt-after-stop).

## The problem

**1. A cancel in a later window can stop the wrong drive.** This is unprobed.

Here is the sequence. Turn A arms a `clear` and ends, so `Stop` opens window
A. The drive takes the file, which goes to `pending`, and starts on `/rename`.
Before A issues `/clear`, a second turn runs and ends. Its `Stop` opens window
B. One way this can happen: you type a slash command that runs a turn. A slash
command passes the handler untouched, so window A asks nothing. You then type
a prompt. It falls in window B, and `drive-cancel.sh` finds `pending`.
`pending` has no owner, so the script cannot tell this file is A's. It
records a sweep and removes the file. You get the toast "transition cancelled",
and the agent gets the note telling it to re-run the skill. Meanwhile A only
checks its own window's answer, which is empty, so it issues `/clear`
anyway. The loader then finds no sentinel, so the fresh session gets no frame.
The prompt was answered in the context that `/clear` just discarded. The
toast and the sweep record both describe a cancel that did not happen. This
outcome is pinned as intended, by the `pending)` arm of the script and the
rows of `tests/mod/window.test.ts`.

What makes it plausible: the probe
([report](reports/2026-11-01-prompt-after-stop-probe.md)) saw a prompt's turn
run to completion between the take and `/rename` (row "clear, sleep after the
take"). It also saw a later `Stop` still unconsumed while a drive was running.
In that run the gap was a sleep the probe inserted. Without it, the gap is the
take's own runtime plus up to `HANDOFF_LOCK_WAIT_SECS` (5 s) of lock wait.
Whether a real turn fits into that gap is not established. **If you judge that
nothing in practice produces this sequence, this part falls and is declined
under the rare-state rule.**

**2. Two scripts make the same decisions.** This one you can check by grep.
`drive-take.sh` and `drive-cancel.sh` each read the sentinel under the lock.
Each judges the state (`armed`, `pending`, `held`), the owner and the kind,
and each moves the file. `drive-cancel.sh` repeats the take outright for an
armed `rename` (removes it and prints the take's plan) and for an armed
`prepare` (moves it to `pending`). So a new kind has to be added in both
scripts. In `hooks/handoff.ts`, the window's one answer means two different
things depending on whether it has a `note`: with one it is a cancel,
without one it is a rename plan the drive must run in place of the take's.

## The proposal

The window keeps a promise of its take's plan (`plan`) and a promise of its
cancel (`cancelled`), as separate fields.

- **Take once per window.** Whichever comes first in the window, the
  `turn.complete` that starts the drive or the first non-command prompt, runs
  `drive-take.sh` and stores the promise. The fast path (no sentinel at the
  session root) applies to both. The drive awaits `plan` and no longer reads
  stdout itself.
- **Cancel only what the take moved.** A prompt in the window first awaits
  `plan`. It calls the cancel only when that plan's kind is `clear` or
  `compact`, the kinds that left a `pending` file. The cancel becomes
  `drive-cancel.sh <cwd> <session-id> <kind>`. Under the lock it removes the
  file only if the file is `pending` with that kind. It records the sweep and
  prints `{message, note}`. The texts stay in `_lib_drive.sh`.
- **The drive checks `cancelled`** before each command, as it checks the
  answer today.

Per kind and state, at a prompt in the window:

| The take found | The take did | The cancel | Then |
| --- | --- | --- | --- |
| this session's armed `clear`/`compact` | moved it to `pending` | removes it, records, notes | the drive stops before its next command |
| this session's armed `rename` | removed it, returned the plan | not called | the drive runs the plan after the prompt's turn, as today |
| this session's armed `prepare` | moved it to `pending` | not called | the sweep spares `pending`, so a hand-typed `/compact` finds it, as today |
| `pending` (another drive's), `held`, another session's file, nothing | nothing | not called | the prompt passes unchanged |
| a file it could not take (lock busy, reader failed) | left it `armed`, returned a `kind: null` message | not called | see open question 2 |

What this fixes and removes:

- Problem 1 goes away by construction. Window B's take finds `pending`,
  which is not armed, so it takes nothing, and B cancels nothing. A's `/clear`
  runs with its `pending` file intact. The prompt is still answered in a
  context the `/clear` then discards. That loss remains, but no toast or record
  claims a cancel.
- `drive-cancel.sh` loses its armed branches and its owner check (it never
  reads `armed` again). It no longer prints a rename plan, and the mod no
  longer tells answers apart by `note`. The Bounds item "`pending` has no
  owner, the cancel relies on the window" narrows: the `pending` file it
  removes is the one its own take made in the same window.
- The sweep no longer depends on reading `armed` ahead of the take. At a
  prompt in the window the take has already run, and the sweep spares
  `pending`.

## Open questions

1. **The toast for a take made at a prompt.** When the prompt beats
   `turn.complete`, the take's message (for example "prepared for compact")
   could show at the prompt or wait until the drive runs. Default: the drive
   shows it, as now, and shows nothing for a cancelled plan.
2. **A take that fails at the prompt.** The file stays `armed`. The
   `UserPromptSubmit` sweep then removes it as stale and blames an unloaded
   mod. Today's cancel fails closed on the same lock, so this is the current
   behaviour too, not a regression. The difference is that the take now
   returns a `kind: null` message, which the drive toasts. Default: leave it
   as it is.
3. **The blocked-`Stop` bound.** A rename taken in a window that the next
   `Stop` replaces still loses its title, as today. Default: unchanged.

## Cost, if approved

These go out to one implementer after approval:

- Code: `hooks/handoff.ts`, `scripts/drive-cancel.sh`, and the header of
  `scripts/drive-take.sh`, which says the cancel "leaves `armed`".
- Tests: rows in `tests/mod/window.test.ts` (the rename-answer rows go, and
  the later-window rows flip to "B cancels nothing"),
  `tests/drive-cancel.bats` (19 tests, most of the armed ones dropped), the
  `cancel-*.json` fixtures and the regeneration, and a new mutation-checked
  row for "B cancels nothing".
- Docs: `queued-prompts.md` (the handler and the Bounds),
  `sentinel-lock.md` (lines 11, 82, 115), `driving-the-transition.md:225`,
  `sessions-sharing-a-root.md:60`, `README.md:132` and `.claude/rules/mod.md`.
- `just mod-smoke`, plus one live run with a prompt in the window for `clear`
  and for `rename`.
