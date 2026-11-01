# Seam C review: b8a37cf (`/code-review medium`)

Scope: `git show b8a37cf`. I compared every removed comment block of `git show b8a37cf^:scripts/report-drive-failure.sh` (header 2-51, lock 191-202, owner and `held` 230-246, queued 291-300, sweep state list 314-323) sentence by sentence against the five nodes. I checked each new node sentence against the code it describes, which is `scripts/report-drive-failure.sh`, `hooks/handoff.ts` and `scripts/drive-take.sh`, and not against the comments. The verdicts below combine my own pass with the `code-review` skill's run. I verified each of the skill's findings, kept one and declined the rest (end of file).

Checks that passed:
- No non-comment line changed. I diffed the old and new script with every line whose first non-blank character is `#` stripped, and the two are identical. This is stronger than the report's `grep '^[-+][^-+#]'` check, which skips lines that start with `-`, `+` or `#`. No line carrying a trailing comment changed either. Byte counts: 21821 to 17089.
- Nothing the old comments said is lost. Every removed sentence is in a node, either already or added by this commit:
  - the mod's non-delivery, the `pending` window and "the first moment anything can act": `driving-the-transition.md` 224-235;
  - the three causes, the Esc and the not-loaded list: 244-255;
  - `held` naming its owner: 37-38;
  - the `prompt_id` distinction, the marker's writers, the rename / clear / compact outcomes and the `marker_unsettled` cases: `queued-prompts.md` 6-54;
  - the background commit session: `sessions-sharing-a-root.md` 11-13;
  - liveness and `foreign`: 20-29;
  - a dead owner's `held` file: 51-56;
  - the lock's interleaving, its scope, the busy and unavailable causes and the take-only-when-present rule: `sentinel-lock.md` 13-49;
  - cwd drift's two directions: `scoping.md` 47-54.

  One phrase is dropped: "possibly in an unrelated session", about a stale file being taken later. Dropping it is correct, since `drive-take.sh` takes only this session's `armed` file (`driving-the-transition.md` 123-127).
- Every kept pointer resolves to the node that holds the material. The header's job 1 points at the section title "Reporting a failure, sweeping a stale sentinel", which exists at `driving-the-transition.md:222`. Job 2 points at that section, `queued-prompts.md` and `sessions-sharing-a-root.md`. Job 3 points at `scoping.md`. The lock comment points at `sentinel-lock.md`, which has the fail-closed bounds at 41-54 and the sweep's case at 78-83. The owner comment points at `sessions-sharing-a-root.md`, and the queued comment at `queued-prompts.md`, which has the unsettled cases at 46-54.
- The new node sentences hold against the code, except the one in finding 1:
  - Esc fires no `Stop`, consistent with `driving-the-transition.md:98`.
  - `held` is exempt whoever owns it: the script's `elif` at 275 excludes it with no owner test.
  - `held` waits on an approval whose answer arrives at this hook: the user's approval comes as a prompt, and `handoff-approved` runs in that turn.
  - `foreign` is never removed: the `elif` at 275-277 excludes it, and the failure branch removes only `pending`.
  - `locked` leaves the file unread: script 163-165, with the failure record kept at 214-217.
  - Drift's sentence matches the note the script prints at 78.
- Anchors and links resolve: `just check-refs` resolves 261 references in 35 files. Outside `plans/` and the frozen changelog, no tracked file refers to the script's header or its numbered points. The `CLAUDE.md` Routing row names "the sweep's `foreign` state" as the brief asked, and the qualifier keeps it apart from the resolver label `foreign` in `scoping.md`.
- Removing the `size.exempt` line matches the new byte count.

## Findings

### 1. `docs/design/driving-the-transition.md:227-228`: medium, the new sentence contradicts the mod and the same node

What is wrong: the sentence "The mod writes the record only on a rejection it observed itself." was added. The mod also writes `autodrive.failed` when no rejection happened. A turn end with no session id over an `armed` file makes `drive-take.sh` print a `kind: null` plan carrying `failFile`. `hooks/handoff.ts:42-45` then calls `recordFailure` with that plan's message, outside any rejected line. The same node already says this at 129-133: "The mod writes that message to `failFile`, as for a rejected line, so the next prompt reports it". The old comment's point was the contrast between observed and inferred. "Nothing is inferred from a file merely being `pending`" (230-232) already makes that point.

Reading that goes wrong: a reader of the failure section takes `autodrive.failed` to mean a rejected line. The report in the failure branch ("failed to run its line: $reason") reads the same way. They miss the no-session-id record, and could change the failure branch or the mod on that basis. Two places in one node now prescribe different things.

Fix direction: drop the sentence, since 230-232 already carries the "never inferred" half. Or say "only on what it observed itself, a rejected line or a turn end with no session id". The script comment at 194, "The mod writes the record only on a rejection it observed", is the old wording and was not changed by this commit. It is the same inaccuracy, and the same fix can cover it as a comment-only edit.

### 2. `scripts/report-drive-failure.sh:250-251`: medium, the comment inverts what the condition lists

What is wrong: "The sweep names the states it removes rather than taking anything that is not `pending`". The condition beneath (275-277) lists the states the sweep keeps: `pending`, `held`, `foreign`, `unread` and `locked`. It removes every other non-empty state: `armed`, `link`, `malformed`, and any value a future version adds. The old comment did not say which way the list ran ("the reason this is a list rather than 'anything but pending'"). The node's "names its states" (`driving-the-transition.md:259`) is ambiguous but not false. The new comment picked the wrong direction.

Reading that goes wrong: a maintainer who adds a sentinel state trusts the comment that the sweep removes only the states it names. They leave the new state out of the condition, expecting it to be kept. The sweep then records and deletes a live file of that state.

Fix direction: "The sweep lists the states it keeps rather than keeping only `pending`: `held` is exempt whoever owns it, ...". The node's "names its states" could take the same direction ("names the states it spares"). That second change is optional.

## Considered and declined

- **Skill finding: `sessions-sharing-a-root.md:25`, `foreign` applies only when the input has a `session_id`.** Declined as a rare state. Claude Code's `UserPromptSubmit` input carries a `session_id`. The unconditional "left untouched" was already there before this commit, which only named the state.
- **Skill finding: `report-drive-failure.sh:8`, job 2 names only `armed`, not `link`, `malformed` or the stranded `pending`.** Low. The header is a three-line index with pointers. The old header's job 2 named only the outlived `armed` file too. The failure branch's `pending` removal has its own comment at 220-224.
- **Skill finding: `CLAUDE.md:117` routes `foreign` to `sessions-sharing-a-root.md` while the state list's reason is in `driving-the-transition.md`.** Declined. The brief prescribed this row, `sessions-sharing-a-root.md:25-26` is where `foreign` is named, and that node links the sweep section at 17-18 and 28-29.
- **Skill finding: overlong lines at `driving-the-transition.md:247` and `:258-260`.** Low: wrapping only.
- **Skill finding: `sentinel-lock.md:78`, the parenthetical splits "The sweep judges nothing" from its colon.** Low: phrasing.
- **Skill finding: the report's non-comment-line grep is weak.** Low. The report's claim holds: my comment-stripped diff above finds no code change.
- **Skill finding: `driving-the-transition.md` is now 19317 bytes against the 20000 cap.** Low. It is under the cap, and the next addition that reaches the cap gets the split the cap asks for. Nothing in this commit is wrong because of it.
- **`scoping.md:47-50` repeats "every handoff file" in consecutive sentences.** Low: redundancy from the verbatim move.
- **`driving-the-transition.md:245-246`: "(three, when the input carries no `prompt_id`)" leaves out the unsettled-marker case.** Low. This wording predates the commit, and `queued-prompts.md:46-54`, linked from 239-240, states the full rule.
- **`TODO.md:8` still lists seam (C) as open**, naming the blocks this commit moved, and the uncommitted working-tree edit to `TODO.md` keeps it. Low, and not a defect of this commit, which does not touch `TODO.md`. Under the repo's convention a done item still listed reads as outstanding, so (C) should be dropped from that item when the seam closes, leaving (D).
- **The lock comment at `report-drive-failure.sh:152` ("Held from the read to the exit") no longer names the lock as its subject.** Low. The `handoff_lock_take` call beneath it makes the subject plain.

## Fixes

Triage: 1 and 2 fixed; everything under "Considered and declined" declined, the `TODO.md:8` item included (the coordinator owns `TODO.md`).

- **1.** `docs/design/driving-the-transition.md:227-229`: the sentence now reads "The mod writes the record only on what it observed itself: a rejected line, or a turn end that carried no session id, which is recorded like one", matching `hooks/handoff.ts:40-45` and the node's 129-133. The script's own comment at 194 keeps its older wording, outside this triage.
- **2.** `scripts/report-drive-failure.sh:250-253`: the comment now says the sweep lists the states it keeps and removes every other one, rather than keeping only `pending`; the pointer stays. A comment-stripped diff against the commit under review shows no code change.
