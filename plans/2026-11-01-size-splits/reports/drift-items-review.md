# Review of 1461ea6 (drift items), medium effort

Scope: `1461ea6^..1461ea6`. I reviewed the diff directly because the
`code-review` skill takes a diff, PR, branch or path as its target, not a
commit. I checked every changed claim against the code it describes, not
against `drift-items.md`.

## The four claims in the commit message: all hold

- `skills/handoff/references/design.md:26`, "Goal (if task-scoped) | current
  task". This is consistent with `docs/design/decisions.md:92` ("The frame
  carries no transcript") and with the hub's residual table
  (`docs/design.md:79-98`). Nothing in the frame reads prompts.
- `.gitignore`: the two `gitlore-*` IPC entries were removed. Outside `plans/`
  and the archive, `git grep` finds nothing that writes or reads
  `.claude/gitlore-memory-message` or `.claude/gitlore-commit-memory`. The
  only hit is `tests/test_checkpoint_directives.py:86-87`, which asserts that
  the directive does *not* name them. `the-checkpoint-directive.md:175`
  already states that no file-handshake fallback is kept.
- `docs/design/sessions-sharing-a-root.md:94-97`, "`.claude/autodrive.failed`
  has no owner". This is confirmed:
  - `hooks/handoff.ts:64-72` (`recordFailure`) writes only the reason text.
  - `scripts/report-drive-failure.sh:203-232` reads and removes the record on
    any session's prompt without checking the owner.
  - On `drive_state == pending`, the same script runs `record_sweep` and
    removes the sentinel (`:226-229`).
- `docs/design/the-checkpoint-directive.md:80-82`, "the SDD nudge's 'Keep them
  out of TODO.md' prints in the call that writes `TODO.md`". This is confirmed:
  - The text is at `scripts/_checkpoint_lib.py:242`.
  - `scripts/checkpoint.py:371-372` emits it under precompact from the
    checkpoint call, and that call is the one that writes the todo.
  - `grep -i 'sdd|ledger'` finds nothing in `skills/precompact/SKILL.md` or
    `skills/handoff/references/files.md`.

## Findings

1. **Medium: `TODO.md:8`, "find them with `git grep -n 'changelog/'`, 192
   outside `plans/` and the archive".** A probe contradicts the count. At
   1461ea6, `git grep -n 'changelog/' -- . ':!plans' ':!docs/changelog'
   ':!docs/changelog.md'` returns 97 lines, which hold 102 occurrences
   (`git grep -o`). The only way to get close to 192 is to count the
   archive's own index, `docs/changelog.md`, which adds 94 occurrences for a
   total of 196. The item names that file as part of the archive, so it should
   be excluded. A reader using 192 as the completeness check for the link pass
   would look for about 90 links that do not exist, or would distrust a
   correct pass. The count should become the real figure (102 occurrences in
   97 lines), or the count should be dropped and the grep kept.
   - This item is also new in this commit, and the commit message does not
     mention it. The message lists four drift fixes, and `git log -S`
     confirms this commit introduces the text. Its other checkable facts
     hold:
     - `rejected-alternatives.md` is 19963 bytes and holds 28 links.
     - The five split files are under the cap, and none of them is listed in
       `size.exempt`.
     - The shipped `design.md:5` does link `tree/main/docs/changelog`.

2. **Low (declined): `docs/design/sessions-sharing-a-root.md:94`, "The mod's
   record of a rejected line".** The mod also writes the record on a `Stop`
   with no session id (`hooks/handoff.ts:39-44`). The limit holds for both
   writes, and no reader would act wrongly on the narrower wording.

3. **Low (declined): `docs/design/the-checkpoint-directive.md:83`, "Shared
   prompt text is shared only where the flows agree".** This sentence
   originally followed a contrast between the two flows. It now follows "no
   different" and no longer says why `todo_boundary` and `sdd_directive`
   differ. The reasoning is weaker, but it prescribes nothing wrong.

END OF REPORT

Fix: finding 1 fixed in ff2a353 (count dropped; the grep stays as the source of truth).
