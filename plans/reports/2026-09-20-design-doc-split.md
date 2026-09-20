# Splitting `docs/design.md` into a hub plus nodes — 2026-09-20

`docs/design.md` was 1248 lines against the repo's 400-line soft cap. It is
now a 326-line hub with eight nodes under `docs/design/`. Nothing was
rewritten: every line of the original survives verbatim except nine heading
levels, forty-one relative changelog links and three intra-document
cross-references.

## The nodes

| file | lines | the question it answers |
|---|---|---|
| `docs/design.md` (hub) | 326 | What is the plugin, what is the residual it captures, what does it require, and where does each argument live? |
| `docs/design/the-write-path.md` | 129 | What crosses the boundary, who is allowed to write it, and what does one checkpoint call do? |
| `docs/design/the-skills.md` | 78 | Which skills exist, and why is the transition a payload field rather than a skill of its own? |
| `docs/design/driving-the-tui.md` | 200 | How does a transition get typed into the composer, and what confirms each line landed? |
| `docs/design/the-checkpoint-directive.md` | 128 | What does the checkpoint print for the agent to do next, when is the transition held, and where does gitlore meet this plugin? |
| `docs/design/scoping.md` | 61 | Which root does a hook anchor on, and how is a session that drifts out of it reported? |
| `docs/design/release-infrastructure.md` | 34 | Why is the release machinery vendored from claude-plugin-dev rather than inlined? |
| `docs/design/decisions.md` | 224 | Why is each standing call the way it is? |
| `docs/design/rejected-alternatives.md` | 159 | What was ruled out, and on what grounds? |

Total 1339 lines across nine files (the split raises total bytes by design;
the saving is the reader not following most pointers).

## How the seams were chosen

The distribution was flat rather than dominated by one entry — the largest
single section, `### Driving the TUI`, was 16% of the document — so per the
skill's "flat distribution" case the boundary is *need-time*: what a reader
needs while building or debugging one component against what they need to
understand the system. The `##` headings already drew most of that line.

- **The hub keeps the six-section frame** minus the two argument sections:
  Problem, Research, Analysis, Requirements (all cited by FR/NFR id from
  `CLAUDE.md`, the skills and the scripts, so they must stay at the entry
  point), the Architecture opening, Non-goals, Relationship to
  `/ddaa:handoff`, Changelog and References.
- **`### The seam` merged with `### One channel, one writer`** into
  `the-write-path.md`. The seam's two files are exactly what the checkpoint
  writes; separated, the seam would have been a 23-line node nobody reads
  without immediately following a pointer.
- **`### What the checkpoint prints` + `### Held: …` + `### The gitlore
  seam`** merged into `the-checkpoint-directive.md`. The hold decision is
  computed by the same call that prints the procedure, and the memory
  directive — the procedure's first part — is the gitlore seam. This is the
  one place where original document order changed: the gitlore seam sat after
  `### Scoping` and now sits after `### Held`. No text changed.
- **`### Driving the TUI` stands alone** at 200 lines. It is one mechanism
  (sentinel, walker, pane predicates, confirmation primitives) and splitting
  it would have cost more in cross-references than the size saved.
- **`## Design decisions` and `## Rejected alternatives` moved whole**, as
  the skill's "last seam" cut prescribes, but into *two* files rather than
  one combined `decisions.md`. See the skill-conflict note below.

## Conflicts with `craft:design-doc-writing`

1. **Node directory.** The skill says nodes go in `docs/references/<topic>.md`;
   the task's default says `docs/design/<topic>.md`. I used `docs/design/`.
   Reason: this repo already runs the index-plus-directory shape for its
   changelog (`docs/changelog.md` + `docs/changelog/`), so `docs/design.md` +
   `docs/design/` is the same pattern a reader of this repo already knows, and
   `references/` is taken here by `skills/handoff/references/`, a different
   thing. Flagging it as the one place the skill lost.
2. **One combined decisions index vs. two node files.** The skill's floor
   lever folds `## Design decisions` and `## Rejected alternatives` into one
   `docs/decisions.md`. Combined they are 381 lines — at the cap on arrival,
   with no headroom for the next decision. The skill itself frames that cut as
   "the lever at the floor rather than a shape every design doc starts in",
   and this hub is not at its floor (326 lines), so I kept them as two nodes
   with adjacent routing lines. Not treated as a conflict the skill lost, but
   worth naming.
3. **Conclusion coverage vs. "do not author new prose".** The skill requires
   that "every argument that leaves must leave a one-line statement of its
   conclusion behind", and that a reader weighing a decision sees every
   conclusion and every rejected name in the hub. The task forbids rewriting.
   Resolved by leaving, in the hub's two stub sections, each entry's **bolded
   lead-in verbatim** — 21 decision leads and 19 rejected leads (30 names,
   since six rejected paragraphs carry "Also rejected:" siblings, all of which
   are listed). No new argument prose was written; the leads are quoted, not
   summarised.

## Verification

### 1. Content conservation

Compared the multiset of non-blank lines in `git show HEAD:docs/design.md`
against `cat docs/design.md docs/design/*.md`.

- original non-blank lines: **1089**
- new non-blank lines: **1169**
- lines present in the original and in none of the new files: **53**, all
  accounted for:
  - **9** heading lines, changed only in level: `### The seam`,
    `### One channel, one writer`, `### The skills`, `### Driving the TUI`,
    `### What the checkpoint prints`,
    `### Held: a transition an approval has not released`, `### Scoping`,
    `### The gitlore seam`,
    `### Release infrastructure delegated to claude-plugin-dev`. Heading text
    is byte-identical; only the `#` count moved (`###` → `##` inside a
    multi-section node, `###`/`##` → `#` where the section became a node
    title).
  - **41** lines that are a changelog link and nothing else, repointed
    `](changelog/…)` → `](../changelog/…)`. Link text unchanged.
  - **3** lines carrying an intra-document cross-reference that now crosses a
    file (listed under "Cross-references repointed" below).
- lines present in the new files and not in the original: **126**:
  - 41 — the `../changelog/` counterparts of the 41 above
  - 13 — node `#` titles and promoted `##` section headings
  - 1 — the `Part of [handoff — Design](../design.md).` backlink (identical in
    all eight nodes)
  - 10 — the hub's routing table (header, separator, 8 rows)
  - 40 — the hub's decision index (21) and rejected-alternative index (19)
  - 21 — the hub's four-line "this document is a hub" paragraph, the four
    lead-in/pointer lines of the two indexes, the 7 continuation lines of
    wrapped multi-name index entries, and the 6 lines of the three repointed
    cross-references

**No line of the original exists in none of the new files without being one
of those 53, and each of the 53 is a heading level, a link path, or a named
cross-reference repoint.** No sentence was dropped, reworded or condensed.

### 2. Link check

A throwaway checker at `$TMPDIR/linkcheck.py` extracts every relative
markdown link from `docs/design.md` and `docs/design/*.md`, resolves the
target file, and — where the link carries a `#anchor` — matches it against
GitHub-style slugs of the target's headings.

```
checked 84 relative links, 0 broken
```

The original document contained **no** `](#…)` intra-document anchor links,
so no anchor conversion was needed beyond the one new cross-file anchor link
introduced (`the-checkpoint-directive.md#what-the-checkpoint-prints`), which
the checker verifies.

### 3. `wc -l`

```
  326 docs/design.md
  224 docs/design/decisions.md
  200 docs/design/driving-the-tui.md
  159 docs/design/rejected-alternatives.md
   34 docs/design/release-infrastructure.md
   61 docs/design/scoping.md
  128 docs/design/the-checkpoint-directive.md
   78 docs/design/the-skills.md
  129 docs/design/the-write-path.md
 1339 total
```

Every file is under the 400-line cap; the largest is the hub at 326.

### 4. Docs lint

`justfile`'s `precommit` has **no** markdown or docs lint step (jq over three
manifests, `shellcheck -x`, ruff/docformatter/mypy/ty over Python, then bats
and pytest). Nothing to run, so nothing was run — consistent with the
instruction not to run the suites.

Two non-markdown files were touched (one comment, one assertion message), so
their own linters were run in isolation rather than through `precommit`:

```
shellcheck -x scripts/_lib.sh          → ok
ruff check tests/test_tui_conformance.py      → All checks passed!
ruff format --check tests/test_tui_conformance.py → 1 file already formatted
```

## Cross-references repointed inside the split

| where | was | now |
|---|---|---|
| `the-write-path.md` | `(see "What the checkpoint prints" below)` | `(see [What the checkpoint prints](the-checkpoint-directive.md#what-the-checkpoint-prints))` |
| `the-skills.md` | `See "Driving the TUI" below for the kind itself.` | `See [Driving the TUI](driving-the-tui.md) for the kind itself.` |
| `the-checkpoint-directive.md` | `(see "One hold predicate" under Rejected alternatives)` | `(see "One hold predicate" under [Rejected alternatives](rejected-alternatives.md))` |

All 41 `](changelog/…)` links inside nodes became `](../changelog/…)`. The
hub's own changelog links were left alone — the hub did not move.

## Inbound references changed

- **`CLAUDE.md` §Layout, `docs/design.md` bullet** — extended to say the file
  is the hub and to enumerate its sections, plus a new sibling bullet for
  `docs/design/` naming all eight nodes and carrying the skill's loading
  instruction ("read the node before making a claim about, or changing, what
  it argues"). This is the routing table the skill requires the repo's
  `CLAUDE.md` to carry.
- **`CLAUDE.md` §Layout, `docs/changelog/` bullet** — "rewrites whatever
  `docs/design.md` prose it invalidates" became "rewrites whatever
  `docs/design.md` or `docs/design/` prose it invalidates — the hub conclusion
  and the node argument change together".
- **`scripts/_lib.sh:21`** (comment above `HANDOFF_REL_DRIVE`) — cited
  `docs/design.md, "The armed transition is one file whose body names the
  transition."`; that decision moved, so it now cites
  `docs/design/decisions.md`. Re-wrapped across two comment lines;
  `shellcheck -x` still clean.
- **`tests/test_tui_conformance.py:405`** (assertion message) — cited
  `docs/design.md's rejected alternatives`; now
  `docs/design/rejected-alternatives.md`. Shorter than the original string, so
  ruff/format are unaffected.
- **`README.md` §Further reading** — the `docs/design.md` bullet gained "; the
  hub for the nodes under [`docs/design/`](docs/design/)" so a reader of the
  README finds the graph.

Note on scope: the task's concurrency warning said "your files are markdown
only", but the repoint instruction explicitly grepped `.py` and `.sh`. The two
source files touched are neither of the files the concurrent agents own
(`scripts/_checkpoint_lib.py`, `tests/test_checkpoint.py`,
`scripts/checkpoint.py`), and each edit is one comment or one string literal.

## Inbound references deliberately left

- **`README.md:161`** — `See [docs/design.md](docs/design.md) for the research
  and analysis behind this split.` The research and analysis sections stayed
  in the hub, so the link still lands on exactly what it promises.
- **`docs/changelog.md:8`** — `[design.md](design.md) is the other half`. Still
  resolves; the hub is still the other half.
- **`CLAUDE.md:117-118`** (`skills/handoff/references/design.md` — "full
  rationale is in `docs/design.md`") and **`CLAUDE.md:832`** ("move detailed
  rationale to references or `docs/design.md`") — both name the doc as a
  whole, not a section, and the hub is still the way in.
- **`skills/handoff/references/design.md:3`** — `Full design doc is
  ../../../docs/design.md`. Names no section and links no moved anchor;
  content left untouched as instructed.
- **`skills/handoff/SKILL.md:226`** — refers to `references/design.md`, not to
  `docs/design.md`.
- **`plugin-dev/install.sh:16`** — `see docs/design.md "Consumers …"`. Vendored
  subtree, never hand-edited; also a section that does not exist in this
  repo's design doc at all (it is the toolkit's own design doc the comment
  means). Left alone.
- **Everything under `docs/changelog/` and `plans/`** — write-time records, not
  edited after the fact. The ones that name a section that has now moved are:
  - `docs/changelog/2026-08-13-first-driven-transition-lands.md:47` —
    "`docs/design.md`'s pane-reading paragraph" → now in
    `docs/design/driving-the-tui.md`
  - `docs/changelog/2026-07-29-driven-transitions.md:201` — "see
    `docs/design.md`" for a rejected alternative → now
    `docs/design/rejected-alternatives.md`
  - `plans/2026-08-13-restart-drive-repair.md:618` — "`### Driving the TUI`"
  - `plans/2026-08-03-transition-state-machine-plan.md:143,499` — the
    driving-the-TUI section and the armed-transition decision
  - `plans/2026-08-02-transition-modes-design.md:269` — "the skill roster,
    one-channel-one-writer, driving the TUI"
  - `plans/2026-09-08-apply-before-mutate/**` and
    `plans/2026-09-04-checkpoint-null-no-task-file/**` — many line-number
    citations into `docs/design.md` (`:240`, `:212–223`, `:139–141`, …), all
    now stale as line numbers were already going to be. These were frozen
    write-time records before this pass.
  - `plans/2026-09-18-directive-owns-the-procedure/**` — §"What the checkpoint
    prints", §"Held", §"Deciding makes no tool call" by name.

## Surprising / worth a second look

- **`Last updated: 2026-09-07.` in the hub was left verbatim.** Splitting the
  document is a change to it, so the stamp is now a turn stale. I did not
  touch it because the task framed this as a pure move and the stamp is
  content. Worth a one-line edit by whoever commits this, together with a
  `docs/changelog/` entry — per `CLAUDE.md`, a design change owes an entry, an
  index line, and the invalidated prose in the same pass, and this pass wrote
  no changelog entry because it changed no design.
- **`### The gitlore seam` was the only section that did not fit its
  neighbours cleanly.** At 22 lines it is too small to stand alone but sat, in
  document order, between Scoping and Release infrastructure — neither of
  which it belongs with. It went with the checkpoint directive because the
  memory directive is the directive's first printed part and `ledger_path`
  feeds the directive's second. That is the one reordering in the whole split.
- **Four overlong lines (95–109 columns) inside the nodes are inherited**, not
  introduced: `driving-the-tui.md:57`, `rejected-alternatives.md:108`,
  `the-write-path.md:113` and `the-write-path.md:98` were already over 80 in
  the original. The `../changelog/` repoint added three columns to 41 link
  lines that were already long. No hard-wrapping formatter is wired into this
  repo's gate, so nothing reflowed them and I did not either — reflowing would
  have broken the verbatim-line conservation check.
- **The hub's decision index is 40 lines of the hub's 326.** If the hub is ever
  squeezed again, the skill's floor lever (fold the rejected names under the
  decision they protect, one *Rejected* line per group) is the next move, and
  it is the reason both indexes are ordered exactly as their nodes are.
