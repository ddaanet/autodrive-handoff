# Item 5.2 — design doc states the directive's procedure

Scope: `docs/design.md` only. `just precommit` green (lint, shellcheck,
ruff/docformatter/mypy/ty, bats, pytest 261 passed / 11 deselected).

## Passages changed

1. **FR9** (Requirements).
   - Old: directive output — memory gate and SDD ledger nudge — composed in a
     fixed order, memory first.
   - New: everything the agent does after the checkpoint call is printed by
     the checkpoint in a fixed five-part order (memory directive, todo
     boundary / SDD nudge, commit act, then arming instruction or closing
     line), each under its own condition; the skill's last step is to follow
     it in order.

2. **"One channel, one writer" — checkpoint paragraph.**
   - Old: the checkpoint "prints a directive on stdout".
   - New: it prints what the agent does next, pointing at the new subsection.

3. **New subsection "What the checkpoint prints"** (Architecture, before
   §Held). This is where the directive composition is now described.
   - The five parts and their conditions; the commit act names no git verb.
   - The "Once everything above is done" anchor on the commit act, arming
     instruction and closing line, and the untyped-precompact-with-dirty-memory
     case (armed, not held) that needs it on the closing line.
   - Commit placement (after the checkpoint, before release) is carried by
     the print order, not skill prose.
   - Closing line's two producers: the checkpoint when not held,
     `bin/handoff-approved` when held (after its status fact, text chosen by
     `DRIVE_KIND` alone, literal for NFR1, compared with
     `closing_directive()` by a test); one hold decision drives both the
     sentinel state and the printed ending.
   - The clause-file refusal prints alone; sentinel composed as usual.
   - `autoname`/`restart` print nothing. Links the 2026-09-18 changelog entry.

4. **§"Held: a transition an approval has not released".**
   - Old: `held` exactly when the sentinel types anything and a memory
     directive was emitted; the release instruction is composed onto the end
     of that directive.
   - New: `held` iff (types anything ∧ memory directive) ∨ (typed ∧
     `with-commit`); the release instruction is its own part, after the commit
     act. Existing first-disjunct rationale kept; a new paragraph gives the
     second disjunct's reason (a failed commit ends the turn, `Stop` would run
     the transition over uncommitted work) and why an untyped handoff's
     `/rename` is exempt under `with-commit`.

5. **"The agent supplies one fact; the code owns the branch."** (≈780)
   - Old: commit awareness changes what memory *says* (under `with-commit`,
     bodies state present-tense truth …) and where the memory commit lands.
   - New: it changes where the memory commit lands and whether the checkpoint
     prints a commit act and holds a typed transition; how memory is written,
     present tense included, is `gitlore:memory-writing`'s rule in every mode,
     reached through the memory directive's approval clause.

6. **"With nothing to approve, the wrap-up completes in a single turn."**
   (not in the item list; stale terminology)
   - Old: "a driven skill therefore arms the sentinel only in the turn after
     the answer" — driven skills no longer exist.
   - New: "a driven transition is therefore held and released only in the
     turn after the answer".

7. **"Deciding makes no tool call but the memory writes."** (≈926–947)
   - Old title and body: memory writes are the step's stated exception, sit
     inside it after the commit answer that sets their tense; the commit
     comes after the checkpoint as skill-prose discipline.
   - New title "Deciding makes no tool call."; memory writes are not an
     exception because they are the step before (the skill's first), with no
     dependency on the commit answer; still before the checkpoint call. The
     commit is the printed commit act: after the checkpoint so it carries the
     staged files, before the arming instruction. The 2026-09-17 link stays,
     and the 2026-09-18 entry is linked beside it.

8. **Rejected alternatives — new entry "One hold predicate".**
   - New: the uniform predicate (types anything ∧ (memory ∨ commit)),
     differing only in the untyped-handoff + `with-commit` + clean-memory cell,
     rejected for holding no protected state, adding a `handoff-approved` call
     to the most common invocation, and a silent forget-risk. Linked to the
     2026-09-18 entry.

## Checked, unchanged

- ≈1063 (now ≈1154) "arming discipline would stay a rule the agent is asked
  to follow rather than one the code enforces": consistent — the rejected
  skill-body sentinel would still leave arming as prose, and commit-before-arm
  is now code-enforced by the hold rule, which strengthens the contrast.
- ≈351 "the arming discipline and the sentinel's line shapes stated twice in
  prose": a description of the retired driven-skill shape; still accurate as
  history of that alternative.
- `skills/handoff/references/design.md`: grep for held/closing/tense/commit
  act/arming/ready to finds nothing; no stale statement.

## Note

`docs/design.md` is 1246 lines, far past the 400-line soft cap; it was 1155
before this pass. Not addressed here (split is out of this item's scope).
