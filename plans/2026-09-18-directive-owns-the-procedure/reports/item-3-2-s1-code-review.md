# Item 3.2 slice 1 — code review

Scope: `bin/handoff-approved` as changed by `fcc6d00`. The fixes below are
applied and not committed.

## Findings

1. **`*)` fallback: dead branch, removed (minor).** A held sentinel is composed
   only by `checkpoint.py`'s hold decision, which means `(K and M) or (T and C)`.
   `restart` composes no memory directive and carries no commit awareness, so it
   never holds. `autoname` composes no directive and types no transition, so its
   `rename` never holds. An untyped `compact` is the two-line marker, which types
   nothing (K false, T false). So the kinds this command can reach are exactly
   `{rename, clear, compact}`. The fallback, the `closing=''` sentinel value and
   the `if/else` over it guarded a case no producer writes, and the comment
   described them as present-tense behaviour ("falls back … rather than
   guessing"). Now the status fact prints unconditionally, followed by
   its blank line, and each of the three `case` arms prints its own closing
   line. There is no `*)`, no intermediate variable and no `$(...)` subshell for
   the status fact. Under `set -u` nothing is left unbound. A hand-made held
   `restart` still arms and prints the status fact, which is the pre-slice
   behaviour.
2. **Comment accuracy (minor).** "held whole by NFR1's shape rather than
   shelling out to Python" was obscure. It now reads: literal rather than
   composed in Python, so the command stays one file rewrite (NFR1), and it
   must match `closing_directive()` byte for byte. The comment also says which
   kinds the case covers and why `restart` is absent. The rationale for single
   quotes is kept.

## Checked, no change

- **Byte identity.** For each kind, everything after the blank line equals
  `closing_directive(skill, typed=…)` exactly, with `(handoff, False)`,
  `(handoff, True)` and `(precompact, True)`. This was verified by hand with
  `LC_ALL=C` (all 3 match). Slice 2 turns that check into a test.
- **Em dash / locale.** The literal is single-quoted and printed through
  `printf '%s'`, so the bytes pass through untouched under any locale and are
  never read as a format string. Bash 3.2 is fine: the change uses no arrays
  and no bash-4 constructs.
- **SC2016 scope.** A directive placed above a compound command covers only
  that command, so here it covers the `case … esac` and nothing else, and no
  code follows it. `shellcheck -x` is clean.
- **Printed sequence.** The pair is the status fact
  `handoff: clear armed; it runs at the end of this turn.`, then
  ``End on one line: `Clear armed — it runs when this turn ends.` ``. It
  overlaps in content, but each line does a different job. The first is the
  tool's report of what happened. The second is an act: the one line the reply
  ends on, quoted so it is relayed rather than paraphrased. A fresh agent reads
  that as "done; now end with this". It does not read as a second thing to do.
  The outline requires the status fact, for the held-`rename` path. Rewording
  the closing text to remove the overlap would change the checkpoint's own
  non-held output as well, where there is no status fact to overlap. So there
  is no gain on that path, and 3.1/2's constraints bind the wording anyway. No
  change.

## Verification

`just precommit` passed (rc 0): manifest/settings lint, `shellcheck -x`, ruff
check + format, mypy/ty, bats 169/169, pytest 261 passed / 11 deselected.

Refactor flagged: none.
