# The continuation is a constant

2026-10-15.

## The defect

`continue` was `null` or one line of prose the agent wrote, and the mod
submitted it as the first prompt after a driven `/clear` or `/compact`. The
files carry the task across the transition, and the prompt was meant to be a
handle to them. Nothing held it to that: an agent could put the task
description, or the facts a decision hinged on, in the prompt instead of in
`TASK.md` and `TODO.md`. A prompt is a single line the next `/clear` does not
carry, so what went into it was gone at the next boundary, and the files, the
only durable carrier, stayed thin.

The skills tried to prevent it with prose: an "Is there a continuation
prompt?" question at each boundary and a good-and-bad pair of examples in the
seam section of `handoff`. That is guidance against a channel the schema left
open, which is the defect the closed-vocabulary payload exists to prevent
elsewhere.

## The change

- `continue` is a required boolean at both boundaries. `true` is legal only
  when the transition is carried out (`clear: true`, or `compact` true or a
  focus directive) and is an error naming the field otherwise; `false` is legal
  everywhere. `null`, a string, a number and a missing key are errors, each
  naming the field.
- When `continue` is `true` the composer writes the fixed line `Continue per
  handoff` (`CONTINUATION` in `scripts/checkpoint.py`) where the agent's prose
  went. The sentinel's shape and `handoff_drive_read` are unchanged, and the
  parser still refuses a prose line that begins with `/`, now as the bound on a
  file something other than the checkpoint wrote.
- `require_one_line` stays for the `compact` focus directive, which is still
  agent-authored and still lands on one line of the sentinel. The leading-`/`
  check on `continue` goes with its input.
- Both skills ask one yes-or-no question of the user's request, whether the
  session carries on after the reset, and lose the prose rules and the
  examples. The seam section of `handoff` now says the files are the only
  carrier. This is a breaking change to the payload.
- The constant is defined once. Tests import it, and a row in
  `tests/test_mod_fixtures.py` fails when a fixture submits a prose line other
  than the constant, so the mod's fixtures cannot describe a continuation the
  composer would never write.

## What stands

The decision to make driving a transition and submitting a prompt separate
fields stands, and with it the six combinations of transition and
continuation; only the type of the second axis changed. So does the rule that
a commit on the far side of a transition is not evidence of `with-commit`; the
agent can no longer write such a commit into the prompt, but the user's ask can
still name one.

## Rows

`tests/test_checkpoint_transition.py`: `continue` null, a string, an empty
string, a number, a list and an object refused at every boundary with no
sentinel written; `true` refused against `clear: false` and `compact: false`
and legal against `clear: true`, `compact: true` and a focus directive;
`false` legal at all five; the sentinel's exact bytes for each legal
combination, built from the imported constant; the constant itself one line,
not beginning with `/`. Every other checkpoint test file moved its payload
builders from `None` to `False`. `tests/test_mod_fixtures.py` carries the
fixture row, and `tests/mod/fixtures/armed-clear.json` and
`armed-compact.json` carry the constant.
