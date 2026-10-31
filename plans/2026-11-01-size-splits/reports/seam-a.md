# Seam A report: `sessions-sharing-a-root.md`

Commit: see `git log -1 --format=%h -- docs/design/sessions-sharing-a-root.md` (the commit contains this report, so its own sha cannot be written into it).

## Byte counts (`wc -c`)

| file | before | after |
|---|---|---|
| `docs/design/driving-the-transition.md` | 22747 | 19083 |
| `docs/design/sessions-sharing-a-root.md` | (new) | 7501 |
| `docs/design/decisions.md` | 21107 | 20263 |
| `docs/design/rejected-alternatives.md` | 22438 | 21389 |

`driving-the-transition.md` is under the cap and its `size.exempt` line is deleted. `decisions.md` and `rejected-alternatives.md` are still over 20000, so both stay listed. `docs/design.md` went from 19146 to 19296 (the one bullet plus the repointed link).

## What moved

All five spans from `driving-the-transition.md` (the sentinel section's owner sentences, the sweep section's liveness text, the `held` paragraph, the sweep-record paragraph, the whole `## Sessions sharing a root` section), the argument of the `decisions.md` owner entry, and the arguments of the two `rejected-alternatives.md` entries. The moved prose is verbatim apart from link fixes and the folds below. The new node's sections are: The owner, Liveness, The `held` exemption, The sweep's record, Limits, Decision, Rejected alternatives.

Non-verbatim text written:
- The node header, plus one lead sentence in "Liveness" that points at the sweep section, so that "Another session's prompt can arrive ... too" has an antecedent.
- Pointer sentences left at the three sources: one in the sentinel section, one in the sweep section (for spans 2 to 4 together), a conclusion plus pointer in each of the three kept entries.
- The fold below.

The decisions entry's opening sentences repeat the owner paragraph (both verbatim), so the new node says the owner point twice, once under "The owner" and once under "Decision".

## Changelog links in moved text

1. `2026-10-13-the-armed-sentinel-has-an-owner.md` appeared three times: in the liveness paragraph, in the decisions entry and in the sidecar rejection. Fold, as you decided. I read the record. The node lacked: the premise that was wrong (a prompt that sees `armed` is a turn later holds only within one session, and the hook runs in every session, as the 2-second background-review sweep showed); two failure modes of liveness (a long subagent dispatch, "not observed", and a transcript in another project directory); and the reverse error (a quit session's recent transcript keeps its file, but `drive-take.sh` checks the owner and the first prompt after the window sweeps it). I folded those into "Liveness" in about six sentences and dropped all three links. Not folded, because it is not an argument for these rules: the record's note that `autodrive.failed` has no owner, so a live session's prompt reports another session's drive failure. `sentinel-lock.md` line 80 touches `autodrive.failed`, and no node states that limit plainly. It is a candidate for the Limits list if you want it, and I did not add it.
2. `2026-10-14-cross-session-limits-documented.md` appeared after the `held` paragraph, after the decisions entry and after the per-session rejection's tail (the last one stays in the source; see below). Dropped without a fold. The `held` paragraph and the decisions entry already carry the exemption argument (human approval of unbounded length, idle transcript looks like waiting, dead owner's file arms nothing and is replaced by the next checkpoint). The Limits section and the per-session rejection carry the limits and the "shared state by design" argument. The record's "take is not atomic" limit was superseded by the lock, which the rejection already says.
3. `2026-07-22-stale-autocompact.md` appeared in the sidecar rejection. Dropped without a fold. The moved text already makes both arguments (an Esc leaves the file in the same session so the id matches; a timeout is a guess and a wrong guess drops a wanted compaction). The record's structural-discriminator argument was superseded and is not part of this rejection.

A link left in a source: the trailing `[Cross-session limits, documented]` line under the paragraph that holds **Recording the root in the sentinel** and **Refusing a symlinked `.claude/`** in `rejected-alternatives.md` stays, since that paragraph stays. I did not settle it (B or a later pass).

## Inbound references changed

- `docs/design.md` Non-goals: link now `design/sessions-sharing-a-root.md` (text "Sessions sharing a root").
- `docs/design.md` Architecture "Where the argument lives": one bullet added after "The sentinel's lock" (the first dependent sibling is Scoping, so it sits just before it), question form.
- `docs/design/scoping.md` line 15: `driving-the-transition.md#sessions-sharing-a-root` becomes `sessions-sharing-a-root.md#limits`.
- `docs/design/driving-the-transition.md` line 67: `#sessions-sharing-a-root` becomes `sessions-sharing-a-root.md#limits`.
- `scripts/_lib_drive.sh` line 134 (comment only): now cites `docs/design/sessions-sharing-a-root.md`.
- `CLAUDE.md` Routing: the driving-the-transition bullet gains "a second session in the root, `handoff_owner_live`, `HANDOFF_OWNER_LIVE_SECS`, `autodrive.swept` → `sessions-sharing-a-root.md`" (no `foreign`). `scripts/_lib.sh` and `scripts/report-drive-failure.sh` Components lines gain `sessions-sharing-a-root.md`.
- `size.exempt`: the `driving-the-transition.md` line removed.
- Left alone: `README.md` lines 99 and 244 name the topic in prose with no link; `docs/changelog.md` is frozen. `git grep` for `driving-the-transition.md#` finds no remaining tracked anchor links.

## Unsure or worth a look

- `docs/design.md` line 312 (the rejection index) still names all three rejections and each is still named in its source, as required.
- The kept decisions pointer says "The owner rides on line 1 of `armed` and `held`" as its conclusion. The bold lead sentence is the conclusion itself, and the added clause is only a pointer's lead-in.
- The rejected-alternatives pointers' conclusion clauses ("neither is used: the owner rides on line 1 and its transcript is what is timed"; "out of proportion to a setup a worktree per session already avoids") paraphrase the moved text, and I wrote them.
