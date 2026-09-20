# Dogfood run — 2026-09-19

Promoted 2026-09-20 from the dogfood session's own scratch notes, verbatim below
the rule. Answers the deliverable review's open question Q4
(`deliverable-review.md`): the typed + `with-commit` + clean-memory cell — the
one the `T ∧ C` disjunct changed — is Run 1, and it was covered end to end,
`handoff-approved` release included. The one defect found (the doubled blank
line) was fixed in "one blank line between checkpoint directive parts".

---

# Dogfood notes — directive-owns-the-procedure (2026-09-19)
Base commit to reset to afterward: 17d9acc (all commits above it are dogfood test commits).

## Run 1 — typed (clear) + with-commit + clean memory
- Checkpoint printed two parts (commit act, then "run `handoff-approved`"), separated by TWO blank lines rather than one — cosmetic, check print_output's join.
- No memory directive (memory clean) — correct. Sentinel held as expected (typed ∧ with-commit).
- Commit: my own first message used an emoji prefix and was refused by the conventional-commit hook (my error, not the plugin's). Second try landed as bbee910 carrying dogfood-1.txt + the staged handoff-task.md — manifest staging worked.
- Far side (session ad3489de): rename landed (`custom-title` "Dogfood Directive-Owns-the-Procedure" in 6227f1be's transcript), `/clear` landed (the new session opens on the /clear command), and the continuation landed verbatim as the first prompt ("carry out dogfood run 2 and the cleanup described in the task file"). No `autodrive` or `autodrive.failed` left behind. Frame injected with task file.

## Run 2 — prepared (clear: false, continue: null) + with-commit
- Checkpoint printed two parts: the commit act ("Once everything above is done, make the commit the request called for.") then the closing line ("…end on one line: `Ready to /clear`."). Again separated by TWO blank lines — confirms run 1's cosmetic finding in print_output's join.
- No memory directive (memory clean), no todo-boundary part (todo `keep`) — correct.
- Sentinel `armed` / `rename` / `/rename Dogfood Run 2 and Cleanup` — untyped + with-commit is armed, not held, as the hold rule's second disjunct scopes. No handoff-approved instruction printed — correct.
- Manifest staged .claude/handoff-task.md; commit 8e555ae carried it with dogfood-2.txt. Procedure held.
- Rename lands at this turn's Stop — not observable from inside the turn; check the session title.

## Follow-up
- Double-blank-line finding fixed: `print_output` joined parts that already end in a newline, so each seam printed two blank lines (and a trailing one). It now strips each part's trailing newline before joining. New row `test_parts_are_separated_by_one_blank_line`, mutation-checked.
