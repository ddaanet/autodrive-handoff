# Item 3.1, slice 1 — code review

Scope: `scripts/_checkpoint_lib.py:closing_directive` and
`scripts/checkpoint.py:compose_directives` + `main`, as changed by 111cc33.
I applied the fixes below and did not commit them. `just precommit` passes in
full: jq ×3, shellcheck, ruff check, ruff format, docformatter, mypy, ty, bats
(hook-test + checkpoint), and pytest (254 passed, 11 deselected).

## 1. The hold decision is computed once (fixed)

The GREEN computed `held` twice, once in `main` for `compose_sentinel` and
again inside `compose_directives`. Each computation had its own copy of the
`hold_decision(...)` arguments. The formula was shared, but the arguments
were two copies, and that is where the two could drift apart. For example,
if one copy's `memory=` were later changed to `bool(memory.text) and not
memory.refusal`, the sentinel and the closing line would disagree.

`compose_directives` genuinely needs six inputs: skill, root, commit mode,
memory, held and typed. None of them can be derived from the others:

- `root` is used only to build part 2.
- `commit_mode` is used only to build part 3.
- `typed` cannot be recovered from `held`.

Dropping a parameter would therefore just move logic into `main`, which
leaves grouping as the way to stay under ruff's five-parameter limit.
`held` and `typed` together decide the last part, so they are grouped:

```python
class Ending(NamedTuple):
    """What ends the directive output: the arming instruction or closing line.

    `held` is the one hold decision, shared with the sentinel; `typed` picks the
    closing line when not held.
    """

    held: bool
    typed: bool


def compose_directives(
    skill: str, root: Path, commit_mode: str, memory: lib.MemoryPart, ending: Ending
) -> list[str]:
```

In `main`, `held` is computed once and passed to both consumers:
`compose_sentinel(..., held=held)`, then
`ending = Ending(held=held, typed=transition.typed)` and
`compose_directives(skill, root, commit_mode, memory, ending)`. The docstring
sentence that justified the recomputation is deleted. `Ending` sits
immediately above its consumer, following the placement `FilePlan` and
`Transition` already use. The module has `from __future__ import
annotations`, so there is no ordering constraint either way. No test calls
`compose_directives` directly, so no caller needed patching. There is no
`noqa`.

## 2. Closing texts (driven reworded)

Final texts, verbatim. Each one gets a trailing `\n` from `_printf_lines`.

| cell | text |
|---|---|
| handoff, untyped | ``End on one line: `Ready to /clear`.`` |
| precompact, untyped | ``End on one line: `Ready to /compact`.`` |
| handoff, typed | ``End on one line: `Clear armed — it runs when this turn ends.` `` |
| precompact, typed | ``End on one line: `Compaction armed — it runs when this turn ends.` `` |

(The two typed rows have no space before the closing backtick. The space in
the table cells only lets the markdown render.)

- **Ambiguity.** The old driven text, `End on one line: the transition is
  armed and runs at the end of this turn.`, did not quote the line. It could be
  read either as the line to say or as a description of what to say, and the
  agent would paraphrase it. The prepared texts quoted their line. All four now
  quote one.
- **Per skill.** The old driven text was the same for both skills. Item 3.2
  already maps two kinds to two driven lines (`clear` → the driven-handoff
  line, `compact` → the driven-precompact line). The line the user reads should
  say which transition is armed, the same way the prepared line names its
  boundary. Naming it as a noun ("Clear", "Compaction") rather than a slash
  command keeps the reply line from looking like something to type.
- **Near-duplicate with `handoff-approved`.** The status fact there is
  `handoff: <kind> armed; it runs at the end of this turn.`. After this
  change, the two lines do different jobs. The status fact is tool output the
  agent reads, while the closing instruction quotes the line the agent says to
  the user. The overlap is in content, not in the act, and each line stands on
  its own. I did not reword the status fact: it belongs to Item 3.2 and the
  outline keeps it.
- **"Everything above" with nothing above** (phase-2 note). One cell prints
  only the commit act followed by the closing line: clean memory, no todo or
  ledger, `with-commit`, not held. In that cell the commit act's "Once
  everything above is done" has no printed antecedent. It reads as "once the
  skill's earlier steps are done", which is true, and the closing line after it
  is unambiguous. I left it unchanged. Rewording it to depend on its position
  would fork `commit_directive` for no gain in what the agent actually does.
- **Opener.** I kept `End on one line` in all four texts, as slice 3.1/2
  requires. The quoted line and the colon make it clear that this is the final
  line of the reply.

Slice 3.1/2's constraints still hold:

- The untyped handoff text contains `Ready to /clear`.
- The untyped precompact text contains `Ready to /compact`.
- Both typed texts contain `armed` (lowercase, inside "Clear armed" and
  "Compaction armed") and neither contains `Ready to`.
- All four open with `End on one line`.

The docstring is trimmed to the contract. The earlier "so the driven text
stands alone…" narration is replaced by the one constraint that matters: the
line is quoted so it gets relayed as written, and `handoff-approved` prints
the same text.

## 3. Mutations (in place, restored by inverting the edit)

- `Ending(held=held, typed=False)` → 164 passed. This is expected, not a
  defect. All four slice-1 rows are untyped, and typed-axis discrimination
  belongs to slice 3.1/2's content-per-cell row. That row must red this
  mutation.
- `if ending.held:` → `if not ending.held:` → 13 failed, including the
  slice's `…_closing_only` rows. The held/not-held branch is exercised.

After restoring both, `pytest tests/test_checkpoint.py` shows 164 passed.

## Refactor flagged

Refactor flagged: none.
