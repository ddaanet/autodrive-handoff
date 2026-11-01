# Seam D fix review: 5b85a17 (`/code-review medium`)

Scope: `git show 5b85a17`, which changes two lines that ship or govern (`skills/handoff/SKILL.md:28`, `.claude/rules/skills.md:14-16`) and adds `reports/seam-d-review.md`. The verdicts below combine the `code-review` skill's run, which returned eight findings, with my own pass. Under the brief's bar, a finding is high or medium only if an agent following the text would do the wrong thing at a wrap-up. Nothing reaches that bar. **No high or medium findings.**

## Checks that passed

- **`handoff/SKILL.md:28` against both skills' Steps 1–2.** "Read `references/files.md` … before deciding" sits above the bold imperative (32) and above "Decide the following" (34), where deciding starts, so the Read falls before the window. Step 1 (22-24) allows "Step 2's read of the files reference" as one of the only calls before `handoff-checkpoint`, and nothing there times it otherwise. `precompact` has the same shape: Step 1 (18-20) allows the read, Step 2 (27) says "Read that file, before deciding, when the rules matter", and the imperative (30) and "Decide the following" (32) come after it. The two skills now give the same timing word and the same order.
- **Against the decision entry.** `decisions.md:272-273` says "The read comes before deciding, so the window between deciding and the checkpoint still holds no call", which is the timing line 28 now gives. The title rule (248) and the imperative (255-256) agree with both skills.
- **Against `.claude/rules/skills.md:21-26`.** "The Read comes before deciding, and nothing else is read" agrees with line 28.
- **`.claude/rules/skills.md:12-16`.** "Neither loader restates them" is true. `git grep` over `scripts/` and `hooks/` finds no `## Current task`, `## Open decisions` or `## Remaining` in a loader. The only hit is a docstring in `_checkpoint_lib.py:36`, which is not a loader. It is the claim the bullet made before seam D (`git show da2dde0^:.claude/rules/skills.md`), so dropping the `SKILL.md` clause restores a known-true claim.
- **No statement prescribes the opposite of another.** `git grep -i` for "before draft", "drafting", "before deciding" and "before they d", outside `docs/changelog/`, `plans/` and `plugin-dev/`, finds "before deciding" at `rules/skills.md:24`, `decisions.md:272`, `handoff/SKILL.md:28` and `precompact/SKILL.md:27`. "Before deciding what to write" appears at `handoff/SKILL.md:116`, the anti-pattern, which forbids reading project files to check. The only drafting wordings are the three already triaged as low (`the-skills.md:19`, `decisions.md:268`, `files.md:1`). `_checkpoint_lib.py:103` and `tests/conftest.py:41` ("invoke it before drafting a summary") refer to the gitlore commit summary after the checkpoint, not to this Read. No line now in the skills tells an agent to Read inside the window.
- **The anti-pattern (`handoff/SKILL.md:115-119`) still agrees.** It forbids reading `TASK.md`, `TODO.md` or "any other project file" to check, and the prescribed Read is instructions, not a check. Seam D's review declined this as low (its item 2), and the fix leaves it unchanged.

## Code-review skill findings, triaged

1. **`the-skills.md:19-20`, "before they draft".** Already triaged as low. Not re-raised.
2. **`decisions.md:268`, "as part of drafting".** Already triaged as low. Not re-raised.
3. **`files.md:1`, "before they draft".** Already triaged as low. Not re-raised.
4. **`.claude/rules/skills.md:12-13`, "live only in `files.md`" is still false, because `precompact/SKILL.md:60-62` names the todo headings.** Low. The reader who goes wrong is a maintainer renaming a heading, not an agent at a wrap-up. The "live only in" clause also predates seam D (it used to name `handoff/SKILL.md`), and this commit did not touch it. Whether naming two headings counts as restating a template is arguable.
5. **The commit body's "every other statement says before deciding" is false, since three drafting wordings remain.** Low. It is the commit message, a historical record that no wrap-up reads. It is true of every statement that prescribes the timing, and the three it misses are the ones triaged as low. Fixing it would take an amend, which is outside this review.
6. **`handoff/SKILL.md:110-111`, the leftover pointer in Step 3. The skill's scenario is an agent that, after a non-zero exit, Reads `files.md` before retrying, which puts the Read in the window.** Low. Seam D's review declined it (item 4), and this commit did not touch it. The pointer describes where the templates are and prescribes no Read. The agent read `files.md` in Step 2, so its content is already in context. The scenario takes a failed call followed by a needless re-read.
7. **`decisions.md:255`, "one prohibition at the head of the one step", while the Read paragraph now precedes the imperative.** Low. Seam D's review declined it (item 1), and this commit did not touch it.
8. **`precompact/SKILL.md:27`, where "when the rules matter" has to be judged before deciding.** Low. Seam D's review declined it (item 9) as a design change outside the seam, and this commit did not touch it.

## My own pass, beyond the skill

9. **`.claude/rules/skills.md:14`, "Both boundary skills read it", unconditionally.** Low. `precompact` reads it only "when the rules matter" (`precompact/SKILL.md:27`, `the-skills.md:19-20`). The sentence sits in the edited bullet, and the rule file goes to maintainers editing `skills/`, not to a wrap-up agent. A maintainer who took it literally would make `precompact`'s Read unconditional, which reopens no window and contradicts no rule.

## Verdict

The two fixes do what they claim. `handoff`'s timing now matches `precompact`, the rule file and the decision entry. The rule file's dropped clause leaves a claim that is true. No statement prescribes the opposite of another, and no wrap-up reading leads to reading project state or reading inside the window. All nine findings are low, and none needs a fix.

END OF REPORT
