# Seam B report: the checkpoint directive's arguments

Commit: `git log -1 --format=%h -- plans/2026-11-01-size-splits/reports/seam-b.md` (the report is inside the commit, so its sha cannot be written here).

`just precommit` passed (check-plugin and check-code cached on unchanged inputs; check-refs and check-size ran).

## Byte counts (`wc -c`)

| file | before | after |
|---|---|---|
| `docs/design/decisions.md` | 20263 | 17392 |
| `docs/design/rejected-alternatives.md` | 21389 plus about 100 from seam A's fixes | 19963 |
| `docs/design/the-checkpoint-directive.md` | 9779 (as in the brief; 9767 at the time of the move) | 14620 |

Both `size.exempt` lines are deleted. `docs/design.md` is untouched.

`rejected-alternatives.md` first came to 20134 after the moves, 134 bytes over. I shortened the conclusion clauses and the link text of my own four pointers, not any existing prose, which brought it to 19963. It sits only 37 bytes under the cap, so the changelog-link sweep below is what would give it real room.

## Where each of the nine went (all in `the-checkpoint-directive.md`)

All five decisions keep their bold lead in `decisions.md`, followed by "The argument is in [The checkpoint directive](...)". All four rejections keep their bold names with a one-clause conclusion and a pointer. The brief does not require that the pointer for item 7 carry every bold name; it does.

| # | entry | now in | notes |
|---|---|---|---|
| 1 | The agent supplies one fact | `### Decisions` under "The gitlore seam" | Moved sentences 1, 3 and 4. Sentence 2 ("It changes whether the checkpoint prints a commit act, holds a driven transition behind it, and names the memory gitlink in it") is not copied: the node already says it (the seam section's "What the mode changes is the commit act ... names it", and the second hold disjunct). |
| 2 | Ask the question the request can answer | `### Decisions` | Whole entry; the node had none of it. |
| 3 | The directive points at the skill | `### Decisions` | Only "The reader is a fresh agent ... would need forbidding" moved. The first two sentences (dirty listing plus skill name; skill owns the format, a copy drifts) are already the seam section's first paragraph. |
| 4 | A directive is correct only where in the turn it lands | `### Where in the turn a directive lands`, end of "What the checkpoint prints" | Whole entry. |
| 5 | With nothing to approve | `### Decisions` | Whole entry. The last sentence constrains the gitlore seam, so it sits there. |
| 6 | A `PreCompact` hook | `### Rejected alternatives` under "The gitlore seam" | Whole entry plus a fold, below. |
| 7 | Merging handoff into gitlore | `### Rejected alternatives` | Whole entry. |
| 8 | Detecting commit awareness | `### Rejected alternatives` | Whole entry. |
| 9 | One hold predicate | `### One hold predicate, rejected`, end of "Held" | Whole entry. The node's existing parenthetical pointer to it now links this subsection instead of `rejected-alternatives.md`. |

For 9, the node's hold text already says why the second disjunct is scoped to a driven transition, and the moved rejection also says "protecting no state". I did not split that sentence, because the rest of it (the extra `handoff-approved` call) is what the node lacked.

## Changelog links

Settled, on the nine moved entries. Links moved into the node were dropped or folded, and no link into the archive was added to the node.

- `2026-07-25-commit-awareness.md` (entries 1, 3, 8): dropped. Its live argument (the answer is a fact, a transcript scrape or default is wrong, withhold mechanism a reader cannot act on) is in the moved text; the rest of the record is superseded mechanism.
- `2026-08-05-transitions-become-modes.md` (entries 1, 2): dropped. Entry 2 makes its argument (unanswerable in prepare-only modes, uniform sentence, wrong-guess cost). Entry 1's fields-not-skills claim is argued in `the-skills.md` (routing, duplication, expressiveness).
- `2026-10-30-memory-commits-go-through-the-skill.md` (entries 1, 3): dropped. The node's seam section already says "point at the skill, no copy", the mode-independent memory part and the gitlink naming. The node keeps its own link to this record.
- `2026-07-22-directive-fits-where-it-lands.md` (entry 4): dropped. The entry carries the argument. The record's worked example (the todo-suppression sentence, and precompact's cross-reference to the handoff skill) is not folded: its claims about the wipe trigger may be stale and I did not verify them.
- `2026-07-12-session-compaction.md` (entries 6, 7): entry 7 dropped. Entry 6 folded. The moved sentence "Compaction threatens conversation state only, so the flush can wait for any later turn" was superseded in the record (2026-07-20: precompact commits memory before the compaction because the summary is a paraphrase). I added one sentence saying so. This sentence is mine; please check it against the precompact skill, which I did not read in full.
- `2026-10-15-the-mechanical-principle-is-narrowed.md` (entry 6): dropped. The entry states only the factual ground, which is the one the record keeps.
- `2026-09-18-the-directive-owns-the-procedure.md` (entry 9): dropped. The rejection's argument is in the entry in full. The node keeps its own link to the record.

## Links left in the two sources: not settled

After the moves, `decisions.md` holds 27 changelog links and `rejected-alternatives.md` 28, 55 in all, which is over the brief's ~30, so I stopped and list them. Grouped by the entry they sit under; `[legacy]` marks the entries that mention legacy paths (skip for the legacy removal).

`decisions.md`
- Both files are plain files; only the sentinel is guarded: 2026-07-27-one-channel-one-writer, 2026-10-11-task-and-todo-move-to-the-root
- Both files are tracked, and for the same reason: 2026-07-23-overflow-deserves-persistence, 2026-10-11-task-and-todo-move-to-the-root
- The task is bounded, and the bound is set from the residual: 2026-10-11-task-and-todo-move-to-the-root
- The old paths are read and moved, and the bridge retires by a condition [legacy]: 2026-10-11-legacy-paths-are-read-and-moved
- The compact boundary carries no task: 2026-07-20-one-task-file-two-transitions, 2026-10-11-task-and-todo-move-to-the-root
- Commit/push status never appears in either file: 2026-06-24-commit-status-excluded
- The frame carries no transcript: 2026-07-17-task-frame-drops-transcript
- Mechanical logic lives in a script or hook: 2026-10-15-the-mechanical-principle-is-narrowed
- The armed transition is one file whose body names the transition: 2026-07-29-driven-transitions
- The transition carries its own state: 2026-08-03-one-transition-one-file
- The continuation is a constant: 2026-10-15-the-continuation-is-a-constant
- A prompt queued into the arming turn cancels a `clear` or `compact`: 2026-10-16-a-prompt-queued-into-the-arming-turn
- The sentinel's actors hold a lock: 2026-10-16-the-sentinel-takes-a-lock
- Observability is not gated on the happy path: 2026-07-20-watcher-failure-becomes-a-file
- The drive runs inline at `turn.complete`: 2026-10-08-the-plugin-becomes-a-mod
- A foreign tool's state file is detected by liveness: 2026-07-26-orphaned-ledger
- A foreign ledger scopes the todo file: 2026-08-08-ledger-and-todo-are-different-scopes
- The design names no todo tool: 2026-07-22-a-place-for-the-todo-list
- A context-size nudge was tried and dropped: 2026-08-01-context-threshold-trigger, 2026-08-09-samples-are-scoped-to-the-compaction, 2026-08-10-drop-context-threshold-nudge
- Deciding makes no tool call: 2026-08-11-decide-with-zero-tool-calls, 2026-09-17-memory-moves-inside-the-deciding-step, 2026-09-18-the-directive-owns-the-procedure

`rejected-alternatives.md`
- A bare magic-string sentinel for the payload's actions: 2026-09-07-the-payload-names-its-actions
- Loading via an `@.claude/handoff.md` reference: 2026-05-19-original-activation-and-loading
- A generated `handoff.md` artifact: 2026-06-05-read-time-assembly
- Live `git status` in `load-handoff.sh`: 2026-06-24-commit-status-excluded
- Trusting the raw `.cwd` field: 2026-06-09-per-worktree-handoff-root
- Sparing every kind of queued prompt: 2026-10-16-a-prompt-queued-into-the-arming-turn
- Injecting the remainder at the first `UserPromptSubmit`: 2026-07-22-a-place-for-the-todo-list
- Accepting SDD's pre-6.2.0 flat ledger path: 2026-07-26-orphaned-ledger
- Letting the plan's tasks live in both files: 2026-08-08-ledger-and-todo-are-different-scopes
- A cap fitted to how often task files exceed it: 2026-10-11-task-and-todo-move-to-the-root
- A fallback for the old paths that retires by version [legacy]: 2026-10-11-legacy-paths-are-read-and-moved, 2026-10-11-task-and-todo-move-to-the-root
- Protecting a foreign `TODO.md`: 2026-10-11-task-and-todo-move-to-the-root
- A bare relative path in the printed `git rm --cached` line [legacy]: 2026-10-11-legacy-paths-are-read-and-moved, 2026-10-12-the-git-line-names-paths-from-the-top, 2026-10-13-the-unstage-line-runs-from-the-root
- A parallel pipeline per transition: 2026-07-29-driven-transitions
- Keeping the sentinel a skill-body write: 2026-08-05-transitions-become-modes
- Injecting the frame on any compaction where one exists: 2026-07-29-driven-transitions
- Driving the TUI through tmux: 2026-08-13-predicates-match-the-real-pane, 2026-09-22-the-composer-row-carries-its-own-gap, 2026-10-08-the-plugin-becomes-a-mod
- Reading the pane to confirm an action: 2026-07-22-confirm-the-compaction
- A `restart` kind, and identifying the exiting process: 2026-08-14-the-relaunch-stops-replaying-argv, 2026-08-13-restart-drive-repair
- Per-session sentinels or checksums for sessions sharing a root (the paragraph that also holds Recording the root and Refusing a symlinked `.claude/`): 2026-10-14-cross-session-limits-documented
- For memory destinations, a blind reviewer's yield: 2026-10-15-the-mechanical-principle-is-narrowed
- An agent-authored continuation prompt: 2026-10-15-the-continuation-is-a-constant

(Some list lines cover a multi-entry paragraph, so the lead named is the first.)

## Inbound references

- `docs/design/the-checkpoint-directive.md`: the Held section's `(see "One hold predicate" under [Rejected alternatives](rejected-alternatives.md))` now links `#one-hold-predicate-rejected` in the same node.
- No other tracked file cites the nine entries by anchor or by name (`git grep` over `docs/`, `CLAUDE.md`, `skills/`, `scripts/`, `.claude/rules/`, `README.md`, excluding `plans/` and `docs/changelog*`). The other `decisions.md` and `rejected-alternatives.md` links in the tree point at the files, not at these entries.
- `docs/design.md`'s index lines for all nine still name entries that exist, since each lead remains.

## Doubts

- The 55 unsettled links are the work that gives `rejected-alternatives.md` headroom; as it stands it passes the cap by 37 bytes.
- The `precompact` fold in the `PreCompact` rejection rests on the record's own supersession note and on the node naming precompact's memory directive; I did not re-verify it against the skill body.
- The node now carries two "Rejected alternative" style headings in different places (`One hold predicate, rejected` under Held; `Rejected alternatives` under The gitlore seam).
