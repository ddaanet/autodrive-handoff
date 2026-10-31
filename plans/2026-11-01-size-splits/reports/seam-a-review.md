# Seam A review: b18e342 (`/code-review medium`)

Scope: `git show b18e342`, with the moved text compared word by word against `git show b18e342^:` of the three sources, and the folds checked against `docs/changelog/2026-10-13-the-armed-sentinel-has-an-owner.md`, `2026-10-14-cross-session-limits-documented.md` and the dropped `2026-07-22-stale-autocompact.md` link. The verdicts below combine my own pass with the `code-review` skill's run. I verified each of the skill's findings and rejected two of them (end of file).

Checks that passed:
- The move is verbatim. A word-level diff of the removed lines against the new node shows only the header, the Liveness lead sentence, the fold, the section headings, the `(#rejected-alternatives)` relink and the dropped changelog links. No moved sentence is missing.
- Every anchor added resolves: `#limits`, `#decision`, `#rejected-alternatives`, `driving-the-transition.md#reporting-a-failure-sweeping-a-stale-sentinel`, `driving-the-transition.md#the-sentinels-lock`.
- Outside the frozen changelog and `plans/`, no tracked file still links `driving-the-transition.md#sessions-sharing-a-root`.
- The hub index lines (owner decision, sidecar rejection, per-session rejection) still name entries that exist in `decisions.md` and `rejected-alternatives.md`.
- The `held` exemption argument from `2026-10-14` is fully present in the node, so that link was safe to drop. The same goes for `2026-07-22`: the Esc and timeout arguments are in the moved sidecar text.
- The `size.exempt` removal matches the byte counts in the report.

## Findings

### 1. `docs/design/sessions-sharing-a-root.md:27`: medium, dangling "as below"

What is wrong: "one whose owner is not live (...) is swept as below." This came over verbatim. In the source, "below" was the next paragraph of `driving-the-transition.md` ("For the owner's own `armed` file, or another's whose owner is not live, there are two causes..."), which describes how the sweep runs: aborted turn against mod not loaded, the note, and lines offered only for the owner's own file. That paragraph stayed in `driving-the-transition.md`. Below line 27 in the new node are the `held` exemption, the record, the limits, the decision and the rejections. None of them describes the sweep.

Reading that goes wrong: a reader looks below for what happens to a not-live owner's file and does not find it. The nearest sweep text they do find is the record section. The fact that another session's file gets no replayed lines ("Lines are offered only for the owner's own `armed` file") is never reached from here.

Fix direction: point it at the source, e.g. "is swept as in [Reporting a failure, sweeping a stale sentinel](driving-the-transition.md#reporting-a-failure-sweeping-a-stale-sentinel)". That anchor already appears at line 18.

### 2. `docs/design/sessions-sharing-a-root.md:30-32`: medium, the fold restates a premise the record marks superseded

What is wrong: "The sweep's first premise, that a `UserPromptSubmit` which sees an `armed` file is a turn later than the one that wrote it, holds within one session only". The record's own head note ("Superseded 2026-10-16", pointing at `2026-10-16-a-prompt-queued-into-the-arming-turn.md`) says this premise fails within one session too: a prompt typed while the arming turn still runs fires the owner's `UserPromptSubmit` inside that turn. The design handles that case by `prompt_id` (`queued-prompts.md`; the node's own Decision text says "unless the prompt was queued into the arming turn").

Reading that goes wrong: in the present tense, the node tells a reader that within one session a prompt that sees `armed` is always a turn later. That contradicts `queued-prompts.md` and the `prompt_id` check in `report-drive-failure.sh`. The fold copied the record's body and missed its supersession note.

Fix direction: either qualify the premise ("holds within one session only, and there only for a prompt not queued into the arming turn ([queued-prompts.md])"), or fold only the cross-session half ("a prompt that sees `armed` can come from another session...").

### 3. `docs/design/sessions-sharing-a-root.md:32-37`: medium, the 2-second incident reads as a current liveness failure

What is wrong: the fold describes the incident ("a background review session's prompt, two seconds after the write, swept a live owner's file as stale"). It then goes on: "Two more ways to read a live owner as gone: a long subagent dispatch ..., and a transcript in another project directory". "Two more" makes the 2-second incident the first item of a list of liveness failure modes. It is not one. It is the pre-owner bug that the owner and the liveness test fixed. Under the current rule, an owner whose turn wrote its transcript two seconds ago is live, and its file is left untouched (line 25). Separately, in the record the long subagent dispatch is the likely cause of the quiet-transcript failure already named at line 29 ("an owner turn that writes nothing to its transcript for the whole window"), not an extra way. So "two more" also double-counts it.

Reading that goes wrong: a reader concludes that a background session's prompt seconds after the write can still sweep a live owner's `armed` file. That would contradict the liveness rule two sentences earlier and send them looking for a bug that does not exist. Or they count three independent failure modes where the record has two.

Fix direction: frame the incident as why the owner exists, with the past tense kept explicit and the "before the owner" framing ("Before the owner, a background review session's prompt ... swept a live owner's file"). Then state the failure modes in the record's terms: a quiet transcript, the likely cause being a long subagent dispatch (not observed), and a transcript in another project directory.

### 4. `docs/design/rejected-alternatives.md:57-59`: medium, the kept conclusion misstates the own-session case

What is wrong: the new conclusion "neither is used: the owner rides on line 1 and its transcript is what is timed" drops the moved text's qualifier "Across sessions". For the owner's own sentinel nothing is timed: its next prompt sweeps it outright, unless that prompt was queued into the arming turn (moved text, now `sessions-sharing-a-root.md:113-115`). It also drops the main reason for the rejection, an Esc in the same session, which matches the id.

Reading that goes wrong: a reader who stops at the pointer (the purpose of a kept conclusion) learns that a stale sentinel is judged by timing the owner's transcript. That is false for the case the rejection is mostly about. It could make a timeout for the own-session case look consistent with the design.

Fix direction: "neither is used: the owner's own sentinel is swept by its next prompt, and across sessions the owner rides on line 1 and its transcript is what is timed".

### 5. `docs/design/the-checkpoint-directive.md:111-114`: low to medium, inbound reference not repointed

What is wrong: "`armed` names its owner the same way, because other sessions sharing the root take prompts and end turns while it waits for its own (see [Driving the transition](driving-the-transition.md))". This cites the owner argument, which this commit moved to `sessions-sharing-a-root.md`. The commit's inbound sweep missed it: it repointed `scoping.md`, the hub, `CLAUDE.md` and `_lib_drive.sh`, but not this.

Reading that goes wrong: the link lands on a node that now holds only a one-line forward pointer (`driving-the-transition.md:78-80`). That is one extra hop, not a dead end, hence the low end of the range. It is the kind of stale routing the brief asked to catch.

Fix direction: link `sessions-sharing-a-root.md#the-owner` (or `#decision`).

### 6. `docs/design/sessions-sharing-a-root.md:17-19`: low, the new lead sentence names the less relevant case

What is wrong: "The prompt-time sweep of an `armed` sentinel (...) runs on the owner's own next prompt after an aborted turn." The sweep runs on every prompt in every session. The lead names only the owner's case, and the section is about the other case. "Another session's prompt can arrive ... too" then reads as an exception. Taken with the rest of the paragraph it is not wrong, so low.

### 7. `docs/design/sessions-sharing-a-root.md:28-40`: low, the fold dropped the record's reason the heuristic is accepted

What is wrong: the moved text pointed at the record for "the argument" behind accepting liveness as a heuristic. The fold brought over the failure modes and the reverse error. It left out the record's reason the subagent case is tolerable: "A sentinel is composed by the turn's last call, so a live `armed` file and a long dispatch rarely overlap". It also left out the "no case made worse than before" argument, though that one is historical and arguably rightly dropped. Without the first, the node lists the failure modes and does not say why they are acceptable. Low, since no reader action goes wrong.

### 8. `docs/design/sessions-sharing-a-root.md:9-13` and `:94-97`: low, The owner duplicates Decision

The seam report says this itself: both copies are verbatim moves. Two copies of one argument in one node invite drift. A fix commit could fold "The owner" into a pointer at `#decision`, or drop it.

## Considered and declined

- **Skill finding: `driving-the-transition.md:244` "not live" undefined with no pointer.** Declined. The pointer two lines above (`:239-242`) names "liveness" and links the new node.
- **Skill finding: the `driving-the-transition.md:78` pointer promises the take rule, which the new node does not state.** Declined. `sessions-sharing-a-root.md:98` (Decision) states "Only the owner's turn end takes an `armed` file".
- **Skill finding: `sessions-sharing-a-root.md:126` links the stub `driving-the-transition.md#the-sentinels-lock` rather than `sentinel-lock.md`.** Low. The link is verbatim from the source and resolves. A direct link to `sentinel-lock.md` would save a hop.
- **Skill finding: `plans/2026-11-01-size-splits/reports/seam-a.md:44` says "`git grep` for `driving-the-transition.md#` finds no remaining tracked anchor links", while the new node has two.** Low. Read in context the claim means links to the removed `#sessions-sharing-a-root` anchor, and that holds. As literally worded it is false. If it is fixed, use a `> **Corrected at review**` blockquote per `.claude/rules/docs.md`.
- **The `autodrive.failed` ownerless limit** (record's last paragraph), which the fold left out. That is correct by the contract, since it is not an argument for these rules, and it is already queued in `TODO.md`.

## Fixes

Triage: 1 to 5 fixed; 6, 7, 8 and the "Considered and declined" items declined.

- **1.** `docs/design/sessions-sharing-a-root.md:27-28`: "is swept as below" now reads "is swept as in [Reporting a failure, sweeping a stale sentinel](driving-the-transition.md#reporting-a-failure-sweeping-a-stale-sentinel)".
- **2 and 3.** `docs/design/sessions-sharing-a-root.md:32-46`: the fold is rewritten against the record and its 2026-10-16 supersession note, and against `queued-prompts.md`. The subagent dispatch is now given as the likely cause of the quiet transcript (lines 32-33), not as an extra way to fail. The other-directory case is at lines 33-34. The 2-second incident is a paragraph of its own, opened "Before the owner" (lines 40-46). The premise now "holds within one session only, and there only for a prompt not queued into the arming turn", with a link to `queued-prompts.md`, and the incident's wording follows the record's ("as one that outlived its turn").
- **4.** `docs/design/rejected-alternatives.md:57-60`: the conclusion now says the owner's own sentinel is swept by its next prompt unless that prompt was queued into the arming turn, and that across sessions the owner rides on line 1 and its transcript is what is timed.
- **5.** `docs/design/the-checkpoint-directive.md:114`: the owner argument's link now points at `sessions-sharing-a-root.md#the-owner`.
