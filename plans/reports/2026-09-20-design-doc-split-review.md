# Review — the `docs/design.md` split into a hub plus eight nodes (2026-09-20)

Report-only review of the uncommitted split, against
`craft:design-doc-writing` (hub `SKILL.md` plus `references/splitting-an-oversized-doc.md`,
`references/state-layer.md`, `references/writing-style.md`,
`references/maintaining-entries.md`).

Conservation and links were re-derived independently — `/tmp/claude/dsr/cons.py`,
`/tmp/claude/dsr/cons2.py`, `/tmp/claude/dsr/links.py` — not with the splitter's
script. Both numbers reproduce the splitter's claims exactly. Nothing in the repo
was edited.

**Verdict: fit to commit after the two major fixes below.** No seam should be
redone; every seam verdict is "keep". The majors are both omissions of the
skill's *loading* requirement — the part that decides whether the nodes get read
at all — not defects in the cut.

---

## Findings

### 1. Major — `CLAUDE.md`'s new `docs/design/` bullet is a file list, not a routing table

`CLAUDE.md:795-799` (the added bullet):

```
- `docs/design/` — one node per mechanism or argument, linked from the hub's
  routing table: `the-write-path.md`, `the-skills.md`, `driving-the-tui.md`,
  `the-checkpoint-directive.md`, `scoping.md`, `release-infrastructure.md`,
  `decisions.md`, `rejected-alternatives.md`. Read the node before making a
  claim about, or changing, what it argues.
```

The skill makes this file one of the two that must carry the loading
instruction, and is specific about its shape:

> The repo's `CLAUDE.md` carries a routing table from what the agent touches to
> what it reads first: code symbols, FR ids and decision ids in one column, the
> node path in the other, plus the commit rule … **Symbols are the load-bearing
> column** — an agent about to edit `_worktree_root` matches on the name, not on
> a prose description of worktree handling.

What landed has no symbol column at all. An agent about to edit
`handoff_drive_read`, `hold_decision`, `compose_directives`, `wait_for_idle` or
`handoff_root_read` matches on the name, and nothing in `CLAUDE.md` routes that
name to a node. The eight filenames are already discoverable from the hub; the
column that is not is the one that was dropped.

**Fix.** Replace the bare filename list in that bullet with a symbol/id → node
mapping, one line per node, naming the identifiers already used elsewhere in
`CLAUDE.md`'s own Layout section so the token an agent is looking at is the
match key. Suggested rows (all verified present in the named node):

| touching | read first |
|---|---|
| `checkpoint.py`, `_checkpoint_lib.py`, `bash-post.sh`, `write-stage.sh`, `write-guard.sh`, the manifest, `is_empty_body`, FR1–FR8, NFR1–NFR2 | `docs/design/the-write-path.md` |
| any `skills/*/SKILL.md`, the `skill` enum, `clear`/`compact`/`continue` | `docs/design/the-skills.md` |
| `drive_when_idle.py`, `_watcher_lib.py`, `stop-drive.sh`, `load-compact.sh`, `load-restart.sh`, `session-end.sh`, `handoff_drive_read`/`_arm`/`_spawn_detached`, FR-G, FR-H | `docs/design/driving-the-tui.md` |
| `compose_directives`, `memory_directive`, `commit_directive`, `closing_directive`, `hold_decision`, `arming_directive`, `ledger_path`, `bin/handoff-approved`, FR9, FR12 | `docs/design/the-checkpoint-directive.md` |
| `worktree_root.py`, `handoff_root_read`, `handoff_match_target`, `inject-checkpoint-root.sh`, `session-pointer.sh`, `report-watcher-failure.sh` | `docs/design/scoping.md` |
| `plugin-dev/`, `just release`, `version-guard.sh`, `$MARKETPLACE_DIR` | `docs/design/release-infrastructure.md` |
| weighing or adding a standing call | `docs/design/decisions.md` |
| re-proposing something | `docs/design/rejected-alternatives.md` |

Keep the "read the node before making a claim about, or changing, what it
argues" sentence; it is the other half and it is correct as written.

### 2. Major — no requirement in the hub names the node that argues it

`docs/design.md:132-191`. The skill's hub shape:

> Every requirement and decision stub names its node inline, so a reader at the
> FR is one hop from the argument.

The decision and rejected-alternative indexes satisfy this collectively
(`docs/design.md:218-219`, `245-246`). The Requirements section does not: FR1–FR9,
FR-G, FR-H and NFR1–NFR3 carry no pointer of any kind. Confirmed by search —
across all eight nodes there is exactly one FR/NFR citation:

```
$ grep -rnoE '\b(FR|NFR)-?[0-9A-H]+\b' docs/design/
docs/design/the-checkpoint-directive.md:44:NFR1
```

So the ids are cited *into* the hub from `CLAUDE.md`, the skills and the scripts
(FR1–FR9, FR12, FR-G, FR-H, NFR1–NFR3 — all confirmed defined in the hub, none
dangling), a reader lands on the requirement, and the argument is nowhere in
sight. This is the traversal the split exists to make one hop.

**Fix, and it is three lines.** The three bolded group labels in that section are
already the node names. Turn them into links, and override the one requirement
whose argument went elsewhere:

- `docs/design.md:132` — `**The write path.**` → `**[The write path](design/the-write-path.md).**`
- `docs/design.md:168` — `**The driven transition.**` → `**The driven transition** — argued in [Driving the TUI](design/driving-the-tui.md).`
- `docs/design.md:179` — `**Constraints.**` → `**Constraints** — argued in [The write path](design/the-write-path.md) and [Scoping](design/scoping.md).`
- `docs/design.md:161` — FR9's argument is in `the-checkpoint-directive.md`, not
  the write path; append `See [The checkpoint directive](design/the-checkpoint-directive.md).`
  to the FR9 bullet.
- `docs/design.md:193` — the FR12 paragraph likewise: the memory directive it
  keys on is argued in `the-checkpoint-directive.md`.

### 3. Minor — two `below` references the split broke

Both were intra-document in the 1248-line original and now point across a file
boundary at nothing.

`docs/design/the-skills.md:12-14`:

```
`/handoff:restart` is a fourth, separate skill rather than a third row in
this table — it shares the driven-transition machinery below (a `kind` in
the same sentinel, the same walker) …
```

There is nothing below it in `the-skills.md`; the machinery is in
`driving-the-tui.md`. Five lines later the *second* reference to the same
section was repointed (`the-skills.md:19`, "See [Driving the TUI](driving-the-tui.md)
for the kind itself."), so this one was simply missed — the splitter's report
enumerates three repointed cross-references and this is a fourth it did not find.

`docs/design/the-write-path.md:123-124`:

```
`checkpoint.py` and `_checkpoint_lib.py` (with `drive_when_idle.py`
and `_watcher_lib.py` below) are a 2026-08-10 Python port of what was
```

In the original, "below" reached `drive_when_idle.py` at line 468 from line 316.
Confirmed neither symbol appears anywhere else in `the-write-path.md`; both are
in `driving-the-tui.md`.

**Fix.** In `the-skills.md:13`, change "the driven-transition machinery below" to
"the driven-transition machinery ([Driving the TUI](driving-the-tui.md))" — or
just drop the word "below", since line 19 already carries the link. In
`the-write-path.md:124`, change "and `_watcher_lib.py` below)" to "and
`_watcher_lib.py`, in [Driving the TUI](driving-the-tui.md))".

### 4. Minor — `the-skills.md:24` silently narrowed a scope claim

```
It appears nowhere else in this document because there is nothing else to say
about it.
```

Written of `/handoff:pending` when "this document" was the whole 1248-line design
doc. "This document" is now a 78-line node, which makes the sentence both weaker
and no longer checkable against what it was asserting.

**Fix.** "It appears nowhere else in the design because there is nothing else to
say about it." One word, and the claim is restored to its original scope.

### 5. Minor — the hub's `Last updated:` stamp is stale on arrival

`docs/design.md:17`: `Last updated: 2026-09-07.` The split is a change to the
document, made 2026-09-20. The splitter flagged this and left it, reasoning that
the stamp is content and the brief was a pure move. That reasoning is right about
the brief and wrong about the stamp: per `references/state-layer.md` the status
stamp is exactly where an of-a-moment fact lives, and a stamp that is wrong is
worse than no stamp, because it is read as an anchor for `git diff`.

**Fix.** Set it to `2026-09-20` in the commit that lands the split. Per
`CLAUDE.md`'s own rule the split also owes a `docs/changelog/` entry plus an
index line — a restructuring of the living doc is a design-significant change
even though no argument changed — and that entry is the natural place to record
the hub/node shape and the `docs/design/` vs `docs/references/` call.

### 6. Minor — `CLAUDE.md`'s hub-section enumeration is incomplete

`CLAUDE.md:791-794`:

```
It is the **hub**: Problem, Research, Analysis, Requirements, the Architecture
routing table, one index line per design decision and per rejected
alternative, Non-goals and References.
```

The hub has eleven `##` sections. The enumeration omits `Relationship to
/ddaa:handoff` (`docs/design.md:297`) and `Changelog` (`:306`). The skill flags
this class directly: "each reference file's heading enumeration matches the
bodies it actually holds, **since a stale enumeration reads as coverage**."

**Fix.** Add "Relationship to `/ddaa:handoff`" and "Changelog" to the list,
before "and References".

### 7. Minor — the hub's routing table is seven new lines of 121–195 columns

`docs/design.md:205-214`. Measured:

```
docs/design.md:207 (138)   :208 (134)   :209 (137)   :210 (195)
docs/design.md:211 (121)   :212 (146)   :214 (103)
```

The original had 20 lines over 80 columns; the split has 32, and 7 of the 12 new
ones are these rows. The 195-column row is the checkpoint-directive question.
Two rules bear on it: the skill's `references/writing-style.md` ("Keep tables for
genuinely tabular data — short, uniform, scannable cells"; these cells run 44 to
130 characters of prose), and `CLAUDE.md`'s own `craft:plan-contracts` citation
("Never satisfy it quietly, by cramming 150–300-character lines"). At 326 lines
the hub is not near its cap, so nothing is being bought by the cramming.

**Fix.** Convert the table to a bulleted list, one bullet per node, link then
em-dash then the question, wrapped at 80 columns. That also makes the fix for
finding 2 natural to fold in — the symbol/id hints can ride the same bullets —
and it costs about eight lines of hub.

### 8. Minor — one index name is bolded in the hub that is not bolded in the node

`docs/design.md:255-256` carries `**recording the root via
`WorktreeCreate`/`CwdChanged`**` as a rejected-alternative name. The node,
`docs/design/rejected-alternatives.md:45-46`, reads "**Trusting the raw `.cwd`
field**, or recording the root via `WorktreeCreate`/`CwdChanged` — …" with the
second half unbolded. Bold-span comparison: 30 in the hub, 29 in the node, with
that one the sole difference; every other name matches verbatim and the 21
decision lead-ins match verbatim **and in order**.

This is coverage improving rather than degrading — the hub names a rejected
alternative that the node argues but does not headline — but it breaks the
"lead-ins are quoted, not authored" invariant the splitter's report claims, and
any future checker comparing bolded names across the two files will flag it.

**Fix.** Bold the phrase in the node too:
`**Trusting the raw \`.cwd\` field**, or **recording the root via
\`WorktreeCreate\`/\`CwdChanged\`** — …`. One-character-class change, and the two
files agree.

### 9. Minor — `driving-the-tui.md` is 200 lines with no subheadings

It is the largest node and the only one whose content is a mechanism narrative
rather than bolded-lead-in entries, and it has exactly one heading, its own
title. As a `###` section inside a 1248-line doc that was fine — the document's
outline carried the navigation. As a standalone document it offers no scan
structure and no anchor targets, which matters because it is the node most likely
to be opened mid-debug and read partially. Half-introduced: the content is
unchanged, the reading context is not.

**Fix (optional, and it breaks the pure-move property).** Add three or four `##`
headings at existing paragraph boundaries — the sentinel's shape, the walker's
per-line loop, the pane predicates, the confirmation primitives — inserting
heading lines only, changing no prose. If the pure-move property is to be
preserved for this commit, defer it to a follow-up and note it.

---

## Seam verdicts (item 3)

**`the-write-path.md` = "The seam" + "One channel, one writer" — keep.** The two
sections have one subject between them: the seam names the two files that cross
the boundary and what each is for; one-channel-one-writer says who may write them
and what one checkpoint call does. The node opens on the seam and the reader has
the two filenames before the writer rules that govern them, which is the right
order. Separated, the seam is a 23-line node whose every reader immediately
follows a pointer — the skill's own 1:1-return case ("a ratio near 1:1 means the
material was never separable"). The merged node is 129 lines with genuine
internal structure. Keep.

**`the-checkpoint-directive.md` = "What the checkpoint prints" + "Held" + "The
gitlore seam" — keep, including the reorder.** This is the one place document
order changed (the gitlore seam sat after Scoping and now sits after Held), and
the reorder is an improvement rather than a cost: the memory directive *is* the
gitlore seam and *is* the directive's first printed part, and `ledger_path` feeds
its second, so the section it was separated from is the section that depends on
it. Held belongs here because the same call computes `hold_decision` and prints
the procedure, and the state the hold leaves is released by the command the
arming instruction names. Read cold (checked at `the-checkpoint-directive.md:108`
onward), the gitlore section stands on its own — it reintroduces gitlore with a
link and does not lean on the two sections above it. Keep.

**`release-infrastructure.md` at 34 lines — keep.** The size objection is real
and does not win here. The skill's test is not "is the node big" but "is the
moved material self-contained and is skipping it safe". This is the most
skippable content in the document — a reader debugging a hook, a directive, or
the walker never needs it, and a reader cutting a release reaches it from
`plugin-dev/README.md` and `just release` first. It has zero inbound
cross-references from the other seven nodes and zero outbound links into them
(verified: its only links are one external URL). Returning it to the hub costs 34
of the hub's 326 lines for material that is read once a quarter, and the hub is
where every trip starts. The one thing it does forfeit is the 10:1-type return
the skill measures for cohesive clusters — a 34-line move against ~4 lines of
pointer and framing is more like 8:1, still well clear of the 1:1 floor. Keep.

**`decisions.md` + `rejected-alternatives.md` as two, where the skill prescribes
one — keep.** The splitter's arithmetic is right and the skill's own framing
concedes the point. Combined they are 377 lines against a 400 cap, i.e. at the
cap on arrival with room for roughly two more decisions, and the skill calls the
combined `docs/decisions.md` "the lever at the floor rather than a shape every
design doc starts in". This hub is at 326, not its floor. The property the
combined cut exists to preserve — that a reader weighing a decision sees every
conclusion and every rejected name *together, without traversing* — is preserved
here by the hub, which carries both indexes adjacently at `docs/design.md:216-273`,
so the two-node shape costs nothing at decision time. It also keeps the floor
lever available for later: if the hub is squeezed again, folding the two indexes
into one combined file is still the next move and has not been spent. Keep, and
the splitter's note that both indexes are ordered exactly as their nodes are is
what makes that later fold mechanical.

**`docs/design/` where the skill says `docs/references/` — keep.** Two
independent reasons, both stronger than the skill's default. First, this repo
already runs the index-plus-directory shape for `docs/changelog.md` +
`docs/changelog/`; `docs/design.md` + `docs/design/` is the pattern a reader of
this repo already holds, and consistency inside one repo beats consistency with a
skill's example path. Second, `references/` is occupied here by
`skills/handoff/references/` — a *different* thing (a condensed, separately
maintained doc read by the skill, confirmed at
`skills/handoff/references/design.md:3`), and a second `docs/references/` would
put two unrelated meanings on one word in one repo. The skill's requirement is
that nodes live in a directory the hub routes to and `CLAUDE.md` names; the
directory's name is not load-bearing. Keep, and it is worth one line in the
changelog entry so the next reader of the skill does not re-open it.

---

## The hub as an entry point (item 4)

**Conclusion coverage: complete.** Every one of the 21 decisions and all 19
rejected-alternative paragraphs — 30 names, counting the six "Also rejected:"
siblings — has an index line. Verified by extracting every bolded span from each
node and diffing against the hub's index sections:

- decisions: 21 lead-ins in the node, 21 index lines in the hub, **set-equal and
  order-equal**, zero on either side only.
- rejected: 29 bolded spans in the node, 30 in the hub, nothing in the node
  missing from the hub, and the single hub-only span is finding 8.

**The lead-ins state conclusions, not topics.** Checked all 21. They are
sentences with verbs and objects — "The task file is checkpoint-only; the todo
file is not.", "Nothing that asks whether an action took effect reads the pane.",
"A foreign ledger scopes the todo file; it does not replace it." A reader
weighing a change can tell what was decided from the index alone, which is the
property the skill demands. Two are weaker than the rest and both are
pre-existing wordings, not artifacts of the split: "A context-size nudge was
tried and dropped." states an outcome rather than a standing rule (see
pre-existing issues), and "Withholding is a mechanism." is a slogan that needs
its node to mean anything — though it is at least unambiguous about there being a
decision there.

**The rejected-alternative index lines are names only**, which is exactly what the
skill prescribes ("one line per rejected alternative", "every rejected name").
No conclusion text is owed there.

**Routing-table questions: accurate.** Checked each against its node's actual
contents. All eight describe what the node holds; none over-promises. The
driving-the-TUI row ("How does a transition get typed into the composer, and what
confirms each line landed?") slightly under-sells a node that also carries the
sentinel's file format and state machine, but the sentinel *is* the transition
being typed, so the row is not wrong.

**Requirement ids: all defined, none dangling.** Every `FR*`/`NFR*` cited anywhere
outside `plans/` and `docs/changelog/` — FR1–FR9, FR12, FR-G, FR-H, NFR1–NFR3 —
resolves in the hub. FR12 is explicitly marked as gitlore's at
`docs/design.md:193`, which is the right handling for a borrowed id. The gap is
the reverse direction, finding 2.

**What is thin.** The Architecture section is now one sentence plus the table:
"Five skills, one write path, eleven hooks, and two files that cross a boundary."
The skill's hub-floor description expects "the six mandated sections, **a
component map**, one conclusion line per decision and one line per rejected
alternative". There is no component map — no enumeration of the eleven hooks, the
five skills, or the scripts. It exists in `CLAUDE.md`'s Layout section, so
nothing is lost repo-wide, and the original had no component map either. Not a
finding against the split; worth knowing that the hub's one countable claim
("eleven hooks") now has no body anywhere in `docs/`.

---

## Node self-sufficiency (item 5)

Every node opens with a `#` title and, on line 3, the identical backlink
`Part of [handoff — Design](../design.md).` — verified present in all eight.

Read cold, each node's first paragraph stands without the hub and without a
sibling:

- `the-write-path.md` opens by naming both files and what they are — no
  antecedent needed.
- `the-skills.md` opens on the boundary/skill table.
- `driving-the-tui.md` defines "a **driven transition**" in its first sentence
  before using the term.
- `the-checkpoint-directive.md` opens with "Both boundary skills end the same
  way", which leans on the reader knowing there are two boundary skills — the
  lightest dependency in the set, and the sentence goes on to name what they do,
  so it resolves in place.
- `scoping.md`, `release-infrastructure.md`, `decisions.md`,
  `rejected-alternatives.md` all open on content that needs nothing prior.

None of the eight has a title-plus-one-line statement of the question it answers;
those questions live only in the hub's routing table. The skill does not require
them in the node, and the backlink covers the return trip, so this is a note
rather than a finding — but if the routing table becomes a bulleted list per
finding 7, copying each question into its node's line 5 is nearly free and makes
a node opened directly from a `grep` hit self-describing.

Directional-phrase sweep over all nine files (`above|below|earlier|the next
section|previous section|as described|further down|later in this document|the
section`) returned ten hits. Two are broken by the move (finding 3). One is
broken and was broken before (`driving-the-tui.md:84`, pre-existing). Six are
historical narration inside a node ("An earlier design published…", "was the
earlier shape") or semantic rather than positional ("no state below `held`"),
all correct in place. One (`decisions.md:186`) is inside a link title. A second
sweep for `this document|this section|the table above|the list above` returned
two hits: `docs/design.md:5`, correct, and `the-skills.md:24`, finding 4.

---

## Conservation and link numbers

**Conservation — independently reproduced, and it holds.** Multiset comparison of
non-blank lines, `git show HEAD:docs/design.md` against
`docs/design.md` + `docs/design/*.md`:

```
orig non-blank lines: 1089 total, 1064 distinct
MISSING (present in original, absent from every new file): 53 distinct

categorized: {'heading-level': 9, 'changelog-repoint': 57}
UNEXPLAINED: 3
  x1 'does next (see "What the checkpoint prints" below). It **changes no git'
  x1 '"Driving the TUI" below for the kind itself.'
  x1 '(see "One hold predicate" under Rejected alternatives).'
```

Categorization was mechanical, not by eye: a line counts as `heading-level` only
if the same heading *text* exists at some other `#` depth in the new graph, and as
`changelog-repoint` only if `](changelog/` → `](../changelog/` produces a line
present with at least the same multiplicity. The three unexplained lines are
exactly the three intra-document cross-references the splitter declared, and each
has a verified counterpart (`the-write-path.md:94-95`, `the-skills.md:19`,
`the-checkpoint-directive.md:92-93`). **No sentence was dropped, reworded or
condensed.** The splitter's 53 is right; its "41 changelog links" is 41 distinct
lines / 57 with multiplicity, which is a presentation difference, not an error.

**Extras, classified.** 126 distinct lines / 149 with multiplicity exist in the
new files and not in the original. Every one falls in a sanctioned class: 57
`../changelog/` counterparts, 13 node titles and promoted headings, 8 backlinks
(one per node), 10 routing-table lines, 40 index lines (21 decisions + 19
rejected), 4 hub-paragraph lines, 4 index lead-in lines, 7 continuation lines of
wrapped index entries, 6 lines of the three repointed cross-references, and one
extra `|---|---|` (the routing table's separator; the original had two such
lines, the new files have three). **"Other" is empty.** No finding here.

**Duplication: none beyond the deliberate indexes.** No line of the original
appears more times in the new graph than in the original, so no paragraph is
carried in both hub and node. The 21 decision lead-ins and 30 rejected names do
appear in both places, but in different line forms (`- **X**` in the hub,
`**X** <argument>` in the node), which is the conclusion-stub shape the skill
prescribes, not accidental double-carry.

**Links — independently reproduced.**

```
checked 84 relative links, 0 broken
```

Checker resolves every non-`http` markdown target across all nine files against
the filesystem, and every `#anchor` against GitHub-style slugs of the target
file's headings (strips backticks and emphasis, lowercases, drops non-word
characters, spaces to hyphens), following wrapped link text. The one new
cross-file anchor link,
`the-write-path.md → the-checkpoint-directive.md#what-the-checkpoint-prints`,
resolves against `## What the checkpoint prints` at line 5 of that file. All 57
`../changelog/` repoints resolve to existing files.

**Inbound links from elsewhere in the repo.** Grepping `*.md`/`*.py`/`*.sh`/
`*.bats`/`justfile` outside `.venv`, `plugin-dev`, `memory` and `node_modules`:

| citation | cites | status |
|---|---|---|
| `README.md:161` | "the research and analysis behind this split" | correct — both sections stayed in the hub |
| `README.md:218-219` | doc as a whole + `docs/design/` | correct, and the new clause is the right addition |
| `CLAUDE.md:117-118`, `CLAUDE.md:841` | doc as a whole | correct |
| `CLAUDE.md:790-799` | hub sections + node list | finding 1 and finding 6 |
| `CLAUDE.md:809` | the coupling rule | correct, see item 6 |
| `scripts/_lib.sh:21-22` | `docs/design/decisions.md`, "The armed transition is one file whose body names the transition." | **verified** — exact string present at `docs/design/decisions.md:108` |
| `tests/test_tui_conformance.py:405` | `docs/design/rejected-alternatives.md` as where the `#{pane_pid}` fallback is recorded | **verified** — `#{pane_pid}` present at `docs/design/rejected-alternatives.md:148` |
| `docs/changelog.md:8` | "`design.md` is the other half" | still true of the hub |
| `skills/handoff/references/design.md:3` | `../../../docs/design.md`, no section named | resolves; its FR citations (FR4 etc.) all resolve in the hub |
| `skills/handoff/SKILL.md:226` | `references/design.md`, not this doc | unaffected |

Both source-file repoints are accurate and minimal. No inbound citation outside
the write-time records is stale.

**Stale pointers in write-time records — listed, not counted as defects.** Per
`CLAUDE.md` these are never edited after the fact.

- `docs/changelog/2026-08-13-first-driven-transition-lands.md:47` — "`docs/design.md`'s pane-reading paragraph" → now `docs/design/driving-the-tui.md`
- `docs/changelog/2026-07-29-driven-transitions.md:201` — "see `docs/design.md`" for a rejected alternative → now `docs/design/rejected-alternatives.md`
- `plans/2026-08-13-restart-drive-repair.md:618` — `### Driving the TUI` by heading and by line number
- `plans/2026-08-03-transition-state-machine-plan.md:143, :499` — the driving-the-TUI section; `"The armed transition is a singleton"` (a wording that had already moved on before this split)
- `plans/2026-08-02-transition-modes-design.md:269` — "the skill roster, one-channel-one-writer, driving the TUI"
- `plans/2026-09-04-checkpoint-null-no-task-file/**` — `docs/design.md:212–223`, `:139–141`, `:219-234`, `:911-921` and a dozen more line-number citations
- `plans/2026-09-08-apply-before-mutate/**` — `docs/design.md:240`, `:243`, `:244-246`, `:257-259`, §"One channel, one writer"
- `plans/2026-09-18-directive-owns-the-procedure/**` — §"What the checkpoint prints", §"Held", §"Deciding makes no tool call", `docs/design.md:156`, `:593`, `:926`

Section-name citations survive as names (every one of those headings still exists,
one file deeper); line numbers are dead, as they already were after the 2026-09-18
run. Nothing to do.

---

## The `CLAUDE.md` edits (item 6)

Two bullets edited plus one added. Accuracy and minimality:

- **The `docs/changelog/` bullet** (`CLAUDE.md:806-811`) is the strong one.
  "rewrites whatever `docs/design.md` or `docs/design/` prose it invalidates —
  **the hub conclusion and the node argument change together** — all three in the
  same pass, not as an optional follow-up." This is actionable as written: it
  sits in the bullet that already enumerates a design change's obligations, it
  names both artifacts, and the em-dash clause tells an agent that moving a
  decision's argument without touching its index line is an incomplete change.
  The "all three" still counts changelog file + index line + prose, which remains
  right — the coupling clause refines the third item rather than adding a fourth.
  Minimal, accurate, and it is the rule the skill asks for.
- **The `docs/design.md` bullet** (`CLAUDE.md:790-794`) — accurate except for the
  incomplete section enumeration, finding 6.
- **The new `docs/design/` bullet** (`CLAUDE.md:795-799`) — accurate as far as it
  goes, and short of the skill's requirement, finding 1.

`README.md`'s one-line addition is accurate and minimal.

---

## Pre-existing issues (not findings against the split)

Present in the 1248-line original; the split neither caused nor worsened them,
though two are now more load-bearing.

1. **No state layer.** The doc has none of the five additions
   `references/state-layer.md` prescribes: no `Status:` line, no
   `Verified against: <commit> (<date>)` stamp, no **Now** section (Focus / Next
   / Do-not-re-litigate), no status legend, no `Where · pinned by` clause on any
   FR or NFR, and no **Limitations** section split from Non-goals. The FRs in
   particular read as assertions with no pin, in a repo where nearly every one
   *is* pinned by a named test. This is the largest standing gap against the
   skill and it is orthogonal to the split; it wants its own pass.
2. **`driving-the-tui.md:84` — "`wait_for_consumed`: see below"** dangles, and
   dangled in the original too: `wait_for_consumed` occurs at exactly one place
   in the original (line 481) and one in the new graph, with nothing below it
   defining the split of delivery from confirmation. Pre-existing, but now inside
   a 200-line node where "below" is even less recoverable.
3. **No docs gate.** `just precommit` runs jq over three manifests, `shellcheck
   -x`, ruff/docformatter/mypy/ty, bats and pytest — no markdown formatter, no
   line-cap check, no link checker. The skill asks for all three ("a formatter
   that hard-wraps the prose so a line count means something, and a gate that
   fails a hub or node over the cap (400 lines) and any pointer that stops
   resolving"; `rumdl` with MD013 reflow at 80). The split raises the stakes: one
   file became nine, one link graph became 84 relative links, and the
   conclusion-coverage invariant between hub and nodes is now enforced by nothing
   but review. Both findings 7 and 8 are the kind a checker would have caught for
   free. Worth its own item.
4. **20 lines over 80 columns in the original**, unwrapped because no formatter
   is wired in. The split carries them forward (`driving-the-tui.md:57`,
   `rejected-alternatives.md:108`, `the-write-path.md:98` and `:113` among them)
   and the `../changelog/` repoint pushed already-long link lines three columns
   further. Inherited, and it goes away with item 3.
5. **`**A context-size nudge was tried and dropped.**`** (`decisions.md:178`,
   indexed at `docs/design.md:239`) is a decision entry whose subject is a
   retirement. Per the skill's two-documents split that narrative is changelog
   material — and it *has* a changelog entry
   (`2026-08-10-drop-context-threshold-nudge.md`, linked from the body). It earns
   its place only as a standing "do not re-propose", which is a
   rejected-alternative's job rather than a decision's. Defensible as-is; noted
   because it is the one index line that states an outcome rather than a rule.
6. **The one countable architecture claim has no body.** "Five skills, one write
   path, eleven hooks, and two files that cross a boundary" is asserted at
   `docs/design.md:200` and enumerated nowhere in `docs/`. True before the split
   as well.

---

## Tree untouched

```
$ git status --short | grep -v '^??'
M  .claude/handoff-todo.md
 M CLAUDE.md
 M README.md
 M docs/design.md
 m memory
 M scripts/_checkpoint_lib.py
 M scripts/_lib.sh
 M scripts/checkpoint.py
 M tests/test_checkpoint.py
 M tests/test_tui_conformance.py
```

Identical to the session-start snapshot. Nothing was edited, staged, committed or
run from the test suites. Scratch scripts are under `/tmp/claude/dsr/`.
