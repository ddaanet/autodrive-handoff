# Seam A fix review: a4c8d39 (`/code-review medium`)

Scope: `git show a4c8d39`, i.e. the fixes for findings 1 to 5 of `seam-a-review.md`. Each fix was checked against its finding, against `docs/changelog/2026-10-13-the-armed-sentinel-has-an-owner.md` (including its 2026-10-16 supersession note), `docs/design/queued-prompts.md`, `docs/design/driving-the-transition.md` and `scripts/report-drive-failure.sh`. The verdicts combine my own pass with the `code-review` skill's run. Findings 6 to 8 and the earlier declined items were not re-raised.

Checks that passed:
- `just check-refs` resolves all 265 references. The new links (`driving-the-transition.md#reporting-a-failure-sweeping-a-stale-sentinel`, `queued-prompts.md`, `sessions-sharing-a-root.md#the-owner`) point at headings that exist.
- **Fix 1** resolves its finding. The target section's paragraph "For the owner's own `armed` file, or another's whose owner is not live …" (`driving-the-transition.md`, Reporting a failure) is the sweep that "as in" now points at.
- **Fix 2** resolves its finding. The premise is now qualified by the queued-prompt case, which matches `queued-prompts.md:6-13`. A queued prompt fires `UserPromptSubmit` inside the arming turn whatever the kind, so "a turn later" fails for every queued prompt, and the qualifier is accurate as worded.
- **Fix 3** resolves its finding. The 2-second incident is now framed "Before the owner", in the record's words ("as one that outlived its turn"). The quiet-transcript mode and its likely cause, a subagent dispatch (not observed), now read as one failure mode. The other-directory case reads as a second. Both match the record's bullets at `:115-126`.
- **Fix 5** resolves its finding. `#the-owner` states why the owner exists ("the owner is what tells one session's sentinel from another's"), which is the reason the sentence cites.
- `report-drive-failure.sh` agrees with the node on the liveness inputs: `HANDOFF_OWNER_LIVE_SECS` defaults to 600 (`_lib.sh:87`), and `transcript_path` is read from the input (`:59-60`, `:248`).
- The `seam-a-review.md` Fixes section's line numbers match the tree.

## Findings

### 1. `docs/design/rejected-alternatives.md:57-58`: medium, "unless that prompt was queued" overstates the exemption

What is wrong: fix 4's new kept conclusion reads "the owner's own sentinel is swept by its next prompt, unless that prompt was queued into the arming turn". A queued prompt spares only a `rename`. A queued `clear` or `compact` is still swept and recorded, as a cancel ("transition cancelled — a prompt arrived before it ran").

Evidence: `queued-prompts.md:30-37` ("**`clear` and `compact`** are swept and recorded (state `armed`)"), and `report-drive-failure.sh:333-344`, where the `queued == 1` branch for a non-`rename` kind runs `record_sweep; rm -f "$drive"`.

Reading that goes wrong: a reader who stops at the kept conclusion, which is what a kept conclusion is for, expects a prompt typed during the arming turn to leave a driven `/clear` in place. The code cancels it.

Note: the clause did not start here. It is copied from the moved sidecar text, `sessions-sharing-a-root.md:119-120` ("which its next prompt sweeps unless that prompt was queued into the arming turn"). That text sat verbatim in `rejected-alternatives.md` before b18e342. This commit is what lifted it into the one-line conclusion. Following the grep-every-copy rule, the fix should cover both places. `sessions-sharing-a-root.md:104-106` (Decision) is already correct, because it says "sweeps one *as an aborted turn*, unless …". So is the new fold at `:42`, which qualifies the turn-ordering premise and not removal.

Fix direction: "swept by its next prompt as an aborted turn, unless that prompt was queued into the arming turn", in both places.

## Low (listed, not for dispatch)

- `sessions-sharing-a-root.md:40-42`: the paragraph uses the past tense ("rested") next to a present-tense qualifier ("holds … there only for a prompt not queued"). It reads correctly as a current truth about the premise, and it does not date the queued-prompt handling to before the owner.
- `sessions-sharing-a-root.md:29-34`: the dash after "each way it can be wrong" names one mode, and "also" then adds a second. This is phrasing only, since the record has the same two modes. The sentence is pre-existing.
- `rejected-alternatives.md:57-58`: the kept conclusion still omits the main reason for the rejection (an Esc in the same session matches the id). Finding 4 mentioned this, and the Fixes entry in `seam-a-review.md` does not say that this half was left out. The pointer leads to the full argument, so no reader action goes wrong.
- `the-checkpoint-directive.md:114`: `#decision` would also carry the line-1 owner and the take rule. `#the-owner` supports the sentence as written, and finding 5 offered either target.
- `rejected-alternatives.md` goes from about 21389 to 21515 bytes. It is listed in `size.exempt` pending its split, so the gate passes, but the fix adds to the overage.
- Unwrapped long lines: `rejected-alternatives.md:58`, `sessions-sharing-a-root.md:19` and `:121`.

## Considered and declined

- **Skill finding: `sessions-sharing-a-root.md:42` makes the same overbroad claim as finding 1.** Declined. The qualifier limits the premise "a `UserPromptSubmit` which sees an `armed` file is a turn later than the one that wrote it", and a queued prompt of any kind breaks that premise. It makes no claim about whether the file is removed.

END OF REPORT

## Fixes

Triage: finding 1 fixed; the six lows declined.

- **1.** `docs/design/rejected-alternatives.md:57` and `docs/design/sessions-sharing-a-root.md:119`: "swept by its next prompt" / "which its next prompt sweeps" now carry "as an aborted turn", matching the Decision text at `sessions-sharing-a-root.md:104-106`.
