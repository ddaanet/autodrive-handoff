# Seam C fix review: a2b4250 (`/code-review medium`)

Scope: `git show a2b4250`, which fixes findings 1 and 2 of [seam-c-review.md](seam-c-review.md). I checked each new sentence against the code it describes: `hooks/handoff.ts` and `scripts/drive-take.sh` for `autodrive.failed`, and the sweep's `elif` and every `drive_state` assignment in `scripts/report-drive-failure.sh`. I did not check them against the comments. The verdicts below combine my own pass with the `code-review` skill's run. The skill ran unverified. I checked each of its six findings against the code: two match the findings below and four are declined (end of file).

Checks that passed:
- No non-comment line changed in the script. The diff's `+`/`-` lines, with every line whose first non-blank character is `#` dropped, come out empty. The commit also adds `seam-c-review.md` and touches no other file.
- The node's new sentence (`driving-the-transition.md:227-229`) is true, and its list is closed. `recordFailure` has exactly two call sites in `hooks/handoff.ts`:
  - the `catch` around `runLine` at 49-55, which is a rejected line;
  - the `session === '' && plan.failFile` test at 42-45, which is a turn end with no session id.

  `drive-take.sh` prints a non-empty `failFile` with no session id in two cases. One is an `armed` file (92-96). The other is a malformed file (72-79), whose record then carries the "malformed" message. The sentence states the condition, "a turn end that carried no session id", rather than naming the `armed` case, so it covers both. "Only" makes it a necessary condition. A turn end with no session id and no sentinel prints nothing (37), and nothing is written then, which the sentence does not deny.
- The new sentence agrees with the rest of the node. Lines 128-133 say the no-session-id message is written to `failFile` "as for a rejected line, so the next prompt reports it and sweeps the file". That matches "recorded like one". The sweep half holds too: the record leaves the file `armed`, the failure branch (`report-drive-failure.sh:218-231`) removes only a `pending` file, and the sweep's `elif` then removes the `armed` one. "Nothing is inferred from a file merely being `pending`" (231-233) still carries the observed-versus-inferred contrast.
- The script comment (`report-drive-failure.sh:250-253`) is true. The `elif` at 275-277 removes any non-empty `drive_state` except `pending`, `held`, `foreign`, `unread` and `locked`. The values assigned at 164-191 are `locked`, the parsed `DRIVE_STATE` (`armed`, `pending` or `held`), `unread`, `link`, `malformed` and `foreign`. The sweep therefore removes `armed`, `link` and `malformed`, plus any value a future reader returns, which is what "removes every other one" says. "Rather than keeping only `pending`" agrees with the node's "rather than taking anything that is not `pending`" (`driving-the-transition.md:261`). The queued branch at 265-274 runs before the `elif`, and for a queued `rename` it leaves an `armed` file in place. That branch has its own comment, and the new comment describes the `elif`'s list, so the comment is true of the condition it sits over (see the declined list).
- Lists of cases are closed or stated as rules. The node's two writers are closed, as shown above. The comment says "lists the states it keeps" and points at the condition rather than restating it. Its `held` and `foreign` clauses give reasons and do not claim to be the full list.

## Findings

### 1. `scripts/report-drive-failure.sh:194`: medium, the comment beside the failure branch still names a rejection as the record's only writer

What is wrong: the comment reads "The mod writes the record only on a rejection it observed, and never a link". After this commit, the node at 227-229 states the opposite: the mod also writes the record on a turn end with no session id (`hooks/handoff.ts:42-45`). The commit did not change this comment. [seam-c-review.md](seam-c-review.md) named it as part of finding 1's fix direction, and its Fixes section left it "outside this triage". It is listed here because the fix makes the node and the script disagree about one fact. Before the fix, both were wrong in the same way.

Reading that goes wrong: a maintainer reads the code that consumes `autodrive.failed` and trusts the comment directly above it. They take every record to be a rejected line and reword or restructure the failure branch on that basis, for example by assuming there are lines left over to report. The node and the comment now prescribe different things about the record's writers.

Fix direction: a comment-only edit in the node's words: "The mod writes the record only on what it observed itself (a rejected line, or a turn end with no session id), and never a link: ...". This finding covers the comment only. The user-facing wording of the failure branch (213, 230) also says "rejected line" and "failed to run its line", but it predates seam C and is outside this commit's scope. See the declined list.

### 2. `docs/design/driving-the-transition.md:261`: medium, "the sweep names its states" reads in the direction the fixed comment corrected

What is wrong: the node says the sweep "names its states rather than taking anything that is not `pending`". The natural reading pairs "names its states" with "taking", so the named states are the ones taken. The code does the opposite: the `elif` at 275-277 names the states it keeps. [seam-c-review.md](seam-c-review.md) rated this "ambiguous but not false" and left the change optional. There is evidence that readers take it the wrong way, though. Seam C's own comment was written from this node, and its author read it exactly that way ("names the states it removes"). That is the error finding 2 of the earlier review fixed. After a2b4250, the script comment says "lists the states it keeps" while the node, which the comment cites as its authority, still invites the reverse reading.

Reading that goes wrong: someone adding a sentinel state reads the node, takes the named list to be the states removed, and leaves the new state out of the condition, expecting it to be kept. The sweep then records and deletes a live file in that state. This is the scenario finding 2 of the earlier review described, now coming from the node rather than the comment.

Fix direction: align the node with the comment: "that is why the sweep lists the states it keeps rather than keeping only `pending`".

## Considered and declined

- **Skill findings: `report-drive-failure.sh:230` and `:213`, the user-facing notes say "failed to run its line", that "lines after it in the sequence were never run", and "records a rejected line", which misdescribe a no-session-id record.** The skill adds that at the same prompt the sweep removes the still-`armed` file with "Most likely the drive mod did not load", which gives the same event a second, conflicting cause. Both points are accurate. They are declined here as out of scope: the text predates seam C, neither commit touched it, and changing it changes what the user sees. The state is also rare, since it needs a host `Stop` with no `session_id`. This is a `TODO.md` candidate for the coordinator, not a fix to this commit.
- **Skill finding: `report-drive-failure.sh:250`, "removes every other one" is false for a queued `rename`, which the queued branch leaves `armed`.** Low. The comment describes the `elif`'s condition. The queued branch comes earlier, carries its own comment ("left in place: the drive takes it at the end of the turn the prompt is in"), and `queued-prompts.md` treats the queued case as an exception to the sweep. A reader adding a state, or reading the condition, is not misled. The old wording had the same scope.
- **Skill finding: `TODO.md:8` still lists seam (C) as open.** Declined, as in [seam-c-review.md](seam-c-review.md): the coordinator owns `TODO.md`, and this commit does not touch it.
- **`report-drive-failure.sh:252`: the comment line is over 80 columns.** Low: wrapping only.

The skill's line-194 and line-259 findings are findings 1 and 2 above.

## Fixes

Triage: findings 1 and 2 fixed. Everything under "Considered and declined" stays declined, the four skill findings included.

- **1.** `scripts/report-drive-failure.sh:194-196`: the comment now says the mod writes the record only on what it observed itself, a rejected line or a turn end with no session id. This matches `hooks/handoff.ts:40-45` and the node at 227-229. "No evidence of one" became "no record the mod wrote", because "one" no longer has a single antecedent. I diffed `HEAD` against the working copy with every line whose first non-blank character is `#` stripped, and the two are identical, so no code line changed.
- **2.** `docs/design/driving-the-transition.md:260-262`: the sentence now says the sweep keeps the states it lists (`pending`, `held`, `foreign`, `unread` and `locked`) and removes any other, rather than keeping `pending` alone. That is the `elif` at `report-drive-failure.sh:276-278`. The `held` reason before it is kept. The list is closed: it is the condition's full set of exclusions. The node is 19465 bytes.
