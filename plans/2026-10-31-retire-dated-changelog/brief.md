# Brief: the dated changelog, and what handoff would need to retire it

2026-10-31. From a claude-plugin-dev session surveying the changelog convention
across the ddaanet repos. A proposal, not a decision, and here more than
anywhere a question rather than a recommendation. Nothing in this repo was
edited.

## The proposal

My human partner proposed retiring dated write-time records
(`docs/changelog/YYYY-MM-DD-slug.md`) and their index (`docs/changelog.md`) in
favour of git history, keeping the living design as it is. The reasons: a record
restates its commit; the shared rule says a summary of a change points at the
diff rather than narrating it; git keeps the archaeology; and the size check
being designed in claude-plugin-dev loses an exemption. The source of the
convention is craft's `design-doc-writing` skill; its brief is
`craft/inbox/2026-10-31-brief-retire-dated-changelog.md`.

## Why handoff is not a deletion case

Here the records are the argument layer, not a log. At HEAD, live files link
into `docs/changelog/` about 127 times:

- `docs/design/decisions.md` (36) and `docs/design/rejected-alternatives.md`
  (35) cite records as the argument behind decisions;
- `docs/design/the-write-path.md` (11), `driving-the-transition.md` (6),
  `docs/design.md` (5, including "the argument, in full"), and one or two each
  in `queued-prompts.md`, `scoping.md`, `sentinel-lock.md`,
  `the-checkpoint-directive.md`, `the-skills.md`;
- `CLAUDE.md` (14 at HEAD);
- code and test comments: `bin/handoff-checkpoint`, `scripts/_lib.sh`,
  `scripts/load-handoff.sh`, `scripts/checkpoint.py`,
  `scripts/_checkpoint_lib.py`, `tests/bin-commands.bats`,
  `tests/checkpoint-helpers.bash`, `tests/conftest.py`,
  `tests/inject-checkpoint-root.bats`, `tests/probe-helpers.bash`,
  `tests/test_checkpoint_directives.py`;
- the shipped `skills/handoff/references/design.md:5, 70`, which links GitHub
  URLs on `main` into `docs/changelog/`; deleting the files breaks those URLs
  for installed users.

The records also carry reasoning the commits lack: 20 of the 93 record-adding
commits have no body, and `16f5fc1` moved 26 episodes out of the old `DESIGN.md`
verbatim. For example `2026-07-17-task-frame-drops-transcript.md` (67 lines)
argues the register hazard that the skill reference condenses to a paragraph.

`CLAUDE.md` is mid-split by another session (959 lines at HEAD, a much shorter
working copy and new `.claude/rules/` files). The paths above are at HEAD; grep
for `changelog` again before acting.

## Touch points if the convention goes

- `docs/changelog.md` (103 lines, about 50 KB of non-whitespace text) and
  `docs/changelog/` (93 records).
- `CLAUDE.md`'s layout entry for the two, and its rule that a design change
  lands with its changelog entry; wherever the split moves them.
- `docs/design.md:7–10` and its `## Changelog` section (363–366).
- Every link listed above.
- `plugin-dev/check-refs.sh` exempts `docs/changelog/` by default; a frozen
  archive stays exempt with no change here.

Release notes are out of scope: nothing user-facing reads the changelog, and
`dist.include` does not ship `docs/`.

## Options, for my human partner to choose between

1. **Fold, then delete.** Move each cited argument into the node that cites it,
   then delete the records. Most work; no frozen archive remains.
2. **Freeze the archive.** Keep `docs/changelog/` as it is, write no new
   records, retire the index or leave it frozen too. New reasoning goes in
   commit bodies and nodes. Least work; the exemption stays.
3. **Point at commits.** Replace each link with the commit that added the
   record, and delete. The shipped skill's URLs would need pinning to a sha or
   tag so they survive.

No default is offered: the choice turns on how often the argument layer is read,
which this survey could not measure.

## Triage, 2026-10-31

My human partner chose option 2, freeze the archive, to be applied only once
craft rules on its main brief (`craft/inbox/2026-10-31-brief-retire-dated-changelog.md`):
craft's `design-doc-writing` skill is the convention's source. Until then,
records are written as before.

At triage, about 115 live links pointed into `docs/changelog/` (the CLAUDE.md
split took `CLAUDE.md` from 14 to 1). Touch points the list above misses,
created by that split: `.claude/rules/docs.md` (the index format and the
same-pass rule) and `.claude/rules/tests.md` (a mutant is recorded "in the
changelog entry or plan report"). In `CLAUDE.md`, the layout entry and the
same-pass rule sit under "Where documents go" and "Conventions".
