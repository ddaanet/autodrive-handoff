# The design doc becomes a hub (2026-09-20)

> **Superseded 2026-10-08** (see [The plugin becomes a
> mod](2026-10-08-the-plugin-becomes-a-mod.md)) on one name: the node `driving-the-tui.md`
> this entry links is now `driving-the-transition.md`, rewritten for the mod. The
> hub split itself stands.

`docs/design.md` was 1248 lines — three times the 400-line soft cap this repo
applies to anything a reader takes in at one go. It got there the way living
docs do: every design change rewrites the prose it invalidates and adds the
argument behind the new one, so the file grows even when nothing is appended.
The 2026-09-18 run alone added 136 lines and removed 43. An earlier rule —
append a dated subsection per change instead of rewriting — had already taken
the same file to 2036 lines of mostly superseded machinery before it was
dropped; trimming is not what fixes this, and past a point neither is
discipline.

The cut is the one `craft:design-doc-writing` prescribes: a hub plus one node
per argument. The hub is 336 lines and holds what every reader needs at the
entry point — Problem, Research, Analysis, Requirements (cited by FR/NFR id
from `CLAUDE.md`, the skill bodies and the scripts' own comments, so the ids
must resolve where the trip starts), the Architecture routing list, Non-goals,
the `/ddaa:handoff` relationship, Changelog and References. Under it,
`docs/design/` holds eight nodes:

- `the-write-path.md` (130) — what crosses the boundary, who may write it,
  what one checkpoint call does
- `the-skills.md` (78) — which skills exist, and why the transition is a
  payload field rather than a skill
- `driving-the-tui.md` (200) — how a transition gets typed, and what confirms
  each line landed
- `the-checkpoint-directive.md` (129) — what the checkpoint prints, when the
  transition is held, where gitlore meets this plugin
- `scoping.md` (61) — which root a hook anchors on, and how drift is reported
- `release-infrastructure.md` (34) — why the release machinery is vendored
- `decisions.md` (224) — why each standing call is the way it is
- `rejected-alternatives.md` (160) — what was ruled out, and on what grounds

Nothing was rewritten. Each argument leaves its conclusion behind in the hub
as an index line, and those lines are the entries' own bolded lead-ins,
**quoted verbatim** rather than authored: 21 decisions and 30 rejected names,
in the nodes' own order, so a reader weighing a change sees every conclusion
without traversing anything, and a later fold of the two indexes into one
stays mechanical.

## A pure move, checked twice

The split's value depends on it being a move and not a rewrite, so that was
verified rather than asserted — and verified twice, by the splitter and then
independently by a reviewer running its own scripts against
`git show HEAD:docs/design.md`.

Comparing the multiset of non-blank lines, 53 lines of the original appear in
none of the new files: 9 heading lines whose text is byte-identical and whose
`#` count changed, 41 lines that are a changelog link and nothing else,
repointed `](changelog/…)` → `](../changelog/…)`, and 3 lines carrying an
intra-document cross-reference that now crosses a file boundary. The
categorization is mechanical — a line counts as a heading-level change only if
the same text exists at another depth in the new graph, and as a link repoint
only if the rewritten path is present with at least the same multiplicity — so
the residue is what the checker could not explain, and it is exactly those
three declared cross-references. No sentence was dropped, reworded or
condensed. No line appears more often in the new graph than in the original,
so nothing is carried in both hub and node.

The link checker resolves every relative target across the nine files and
every `#anchor` against GitHub-style slugs of the target's headings: 84 links,
0 broken.

## What the review then changed

Both checks passing is not the same as the graph being usable, and the review
found three places where it was not.

Requirements cited by id landed a reader on the requirement with the argument
nowhere in sight — the traversal the split exists to make one hop. The three
group labels in the hub's Requirements section were already the node names, so
they became links, with FR9 and FR12 overridden to the checkpoint directive,
where their argument actually is.

Two `below` references pointed across a file boundary at nothing
(`the-skills.md`'s driven-transition machinery, `the-write-path.md`'s watcher
pair); both now name the node. A third, `driving-the-tui.md`'s
`wait_for_consumed`, dangled in the original too and is left as found.

`CLAUDE.md`'s new `docs/design/` bullet was a list of the eight filenames —
the column that is discoverable from the hub anyway. It is now keyed on what
an agent is actually holding when it needs a node: `checkpoint.py`,
`handoff_root_read`, `ledger_path`, `wait_for_idle`, FR-G, `$MARKETPLACE_DIR`.
A name matches a name; a prose description of a subsystem does not.

The hub's routing table became a bulleted list in the same pass: its rows ran
to 195 columns, which is the cramming the line cap exists to prevent, and the
hub is nowhere near its own cap.

## Alternatives weighed

**`docs/design/` rather than the skill's `docs/references/`.** Two reasons,
both local and both stronger than the skill's default. This repo already runs
the index-plus-directory shape for `docs/changelog.md` + `docs/changelog/`, so
`docs/design.md` + `docs/design/` is a pattern its readers already hold; and
`references/` is taken here by `skills/handoff/references/`, a different thing
entirely — a condensed doc the skill itself reads. The skill's requirement is
that the nodes live somewhere the hub routes to and `CLAUDE.md` names; the
directory's name is not load-bearing.

**Decisions and rejected alternatives as two nodes, where the skill's floor
lever folds them into one.** Combined they are 384 lines against a 400 cap —
at the cap on arrival, with room for roughly two more decisions. The skill
frames that fold as the lever at the floor rather than a shape every doc
starts in, and this hub is not at its floor. What the combined file buys —
that a reader weighing a decision sees every conclusion and every rejected
name together — is already bought here by the hub, which carries both indexes
adjacently. The lever stays available for the next squeeze, and both indexes
are ordered exactly as their nodes are so that spending it is mechanical.

**`release-infrastructure.md` kept as a 34-line node.** Size is not the test;
self-containment and skippability are. It is the most skippable content in the
document — a reader debugging a hook, a directive or the walker never reaches
it, and a reader cutting a release arrives from `plugin-dev/README.md` first —
and it has no inbound or outbound links to the other seven nodes. Returning it
to the hub spends 34 of the hub's lines, where every trip starts, on material
read once a quarter.

**The gitlore seam moved.** It is the one place document order changed: the
section sat between Scoping and Release infrastructure, belonging with
neither, and now opens the tail of `the-checkpoint-directive.md`. The memory
directive *is* the gitlore seam and *is* the directive's first printed part,
and `ledger_path` feeds its second — so the section it was separated from is
the one that depends on it. No text changed.

## Deferred

`driving-the-tui.md` is 200 lines with one heading, its own title. As a `###`
section inside a 1248-line document the outline carried its navigation; as the
node most likely to be opened mid-debug and read partially, it now offers no
scan structure. Adding three or four `##` headings at existing paragraph
boundaries is the fix, and it is deliberately not in this pass: inserting
headings changes the line multiset, and the pure-move property is what makes
the conservation check mean anything.

There is still no docs gate. `just precommit` runs jq over the manifests,
`shellcheck -x`, the Python linters, bats and pytest — no hard-wrapping
formatter, no line-cap check, no link checker. The split raises what that
costs: one file became nine, one document became 84 relative links, and the
invariant that every node argument has a hub conclusion is enforced by nothing
but review. Both of the review's mechanical findings are the kind a checker
would have caught for free.
