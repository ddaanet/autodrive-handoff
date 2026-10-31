# Step 5 review: `192b0de` (the two guideline docs)

Read-only against the commit (`git show 192b0de…`, `git grep … 192b0de`), plus
an export at `/tmp/claude/line-cap-split/review-5/tree`. Nothing read from the
working tree, nothing fixed.

Verdict: no high or medium finding. The split is verbatim, the cuts sit where
plan step 5 puts them, every half carries every source it cites, the
cross-links resolve, all four files are under 400 lines, and the one remaining
reference to an old name is still correct.

## Findings

All proposed low. The severity reasoning is given for each so that triage can
raise one if it reads it differently.

1. `tests/bats-best-practices.md:14`: "Skim the numbered sections, then audit
   against the **Reviewer checklist** at the end." This is now false of this
   file, which ends with `## Sources`. It is the closest item to the brief's
   "a reader would follow it to the wrong place" bar. Proposed low because the
   correction, with the link, sits two lines below (16–17: "Sections 5–9 and
   the **Reviewer checklist** are in [bats-tooling-and-checklist.md](…)"), so a
   reader reaches it before acting on line 14. The no-reword invariant is why
   the sentence itself was left untouched.
2. `tests/bats-tooling-and-checklist.md:151`: "Pair with `fail "…"` messages
   (§1d)." §1d is now in the other file. Proposed low: half 2 has no §1, so the
   reader cannot land on a wrong place, and the header (lines 3–4) says where
   §1–4 live.
3. `tests/mypy-guidelines.md:3`: "Engineering-grade rules for type-checking
   Python with mypy (plus ruff and ty)." The ruff and ty material is now in
   half 2. Proposed low on the same reasoning, since the cross-link at lines
   13–14 names the ruff and ty comparisons and links to them.
4. `tests/bats-best-practices.md:292–334` (half 1's duplicated Sources block)
   lists sources half 1 does not cite: `[usage]` (cited only in §8c),
   `[faq]` (only in §8b), the `shellcheck.sh` bullet (§7), and two
   "Empirically verified" bullets (ShellCheck 0.10.0 / SC2154, and
   `BATS_RUN_SKIPPED` absent), whose prose is only in half 2. This is a
   surplus, not a gap. It is also inconsistent with the mypy split, which
   splits its list exactly by citation. The executor's stated reason (the
   empirical bullets span §1, §6 and §7) justifies duplicating the empirical
   bullets but not the five-label list. Proposed low or declined: nothing
   misleads a reader.

Not a finding: the executor's flagged judgement call, `## Sources` in bats
half 1 where the original had `### Sources`, is sound. Under half 1 a `###`
would nest below `## 4.`. Half 2 keeps the original `### Sources` under
`## Reviewer checklist`, unchanged.

## Pre-existing, not against this commit

- `tests/mypy-guidelines.md` cites three URLs inline that its Sources list does
  not carry: `https://docs.pydantic.dev/latest/integrations/mypy/`,
  `https://mypy.readthedocs.io/en/stable/additional_features.html#dataclasses`
  and `https://mypy.readthedocs.io/en/stable/literal_types.html` (all in
  Annotation practices). `192b0de^` has the same three-URL gap, so the split
  carried it over and did not cause it.
- The original `tests/mypy-guidelines.md` ended with an extra blank line
  (`\n\n`). Neither half does. This is end-of-file formatting, not prose, and
  `comm -23` stays empty because the added cross-link blocks bring blank lines
  of their own.

## Protocol correction (affects other step reviewers)

The brief's `bash plugin-dev/check-refs.sh --tree <dir>` on an export cannot
work: `--tree` takes a git tree-ish (`git rev-parse "$1^{tree}"`), so a
directory fails with `'<dir>' is not a tree`, rc 1. Run in the repo,
`check-refs.sh --tree 192b0de` applies no exemptions (it is the dist-tree
mode) and prints 11 failures, all under `plans/` and `docs/changelog/`. That is
the same count as at `192b0de^`, with none under `tests/`. What I ran instead
was the default mode inside the export after `git init -q && git add -A`,
which reads `refs.exempt` (absent, so the default `plans` and `docs/changelog`
are exempt) and covers `tests/*.md`.

## Re-run checks

Line multiset (`comm -23 <(git show 192b0de^:tests/<orig> | sort)
<((git show 192b0de:tests/<h1>; git show 192b0de:tests/<h2>) | sort)`):

```text
== bats-best-practices.md  -23: (no output)
== mypy-guidelines.md      -23: (no output)
```

`comm -13` breaks down as follows:

- bats: the half-2 title, the two cross-link pairs, one `---`, `## Sources`,
  and the duplicated Sources body (original lines 533–574, each line printed
  once by the multiset compare), plus blank lines. Nothing else.
- mypy: the half-2 title, the two cross-link pairs, `## Sources`, and three
  duplicated source lines (command line, config file, common issues), plus
  blank lines. Nothing else.

Exact range diffs, stronger than the multiset check:

- bats half 2, lines 8–293, is identical to original lines 289–574.
- bats half 1, lines 1–14 and 18–290, is identical to original lines 1–287.
  Its Sources body (293–334) is identical to original lines 533–574.
- mypy half 1 is identical to original lines 1–264 once the cross-link
  (lines 13–15) is dropped.
- mypy half 2, from line 6, is identical to original lines 265–403, except
  for the seven Sources entries that moved to half 1 (getting started,
  optional error codes, changelog, 2.0 blog, #11760, TypedDict, Adam
  Johnson) and the trailing blank line.

No prose was reworded, cut or reflowed. Every added line is at most 80
columns. The lines over 80 are all pre-existing ones.

Sources against citations, per half:

- mypy half 1: every inline URL is in its Sources except the three
  pre-existing gaps above. It lists nothing it does not cite.
- mypy half 2: inline URLs and the Sources list match exactly, in both
  directions.
- bats half 1: it cites `[writing-tests]` ×10, `[gotchas]` ×4 and `[BW01]`
  ×1. Its Sources defines all five labels (surplus: finding 4).
- bats half 2: it cites `[writing-tests]` ×6, `[usage]` ×1 and `[faq]` ×1,
  and the gotchas page in prose in §7. Its Sources defines all five labels.
- The union of the halves' Sources holds every original source line.

Cross-links and check-refs:

```text
$ cd /tmp/claude/line-cap-split/review-5/tree && git init -q && git add -A && bash /Users/david/code/handoff/plugin-dev/check-refs.sh
check-refs: resolves: 260 references in 27 files, 306 exempt files skipped; shipped stays shipped: 2 references from 6 shipped files
rc=0
```

Mutation check in the export: breaking the link target in
`tests/mypy-guidelines.md` and in `tests/bats-tooling-and-checklist.md` gave
the following, and restoring the targets brought rc 0 back.

```text
tests/bats-tooling-and-checklist.md:4: bats-best-practice.md — does not exist
tests/mypy-guidelines.md:14: mypy-suppressions-and-toolin.md — does not exist
rc=1
```

Cut points against plan step 5:

- bats: §1–4 in half 1, §5 through the checklist in half 2.
- mypy: Strict mode, Config hygiene and Annotation practices in half 1;
  suppression debt, ruff, ty and Practical gotchas in half 2.

Both cuts are at `##` boundaries, as planned.

Intra-document pointers in each half (`§`, "above", "below") all resolve
within the same half, except findings 1 and 2. The ones checked:

- mypy half 1: "(below)" at 80, "above" at 134 and 204.
- mypy half 2: "below" at 64 and "(above)" at 96, both pointing to the "No
  strict-mode parity" bullet in the same section.
- bats half 1: §1b and §1c at 36, 48 and 159.

Line counts (`git show 192b0de:<path> | wc -l`):

| File | Lines |
| --- | --- |
| tests/bats-best-practices.md | 334 |
| tests/bats-tooling-and-checklist.md | 293 |
| tests/mypy-guidelines.md | 279 |
| tests/mypy-suppressions-and-tooling.md | 137 |

The originals were 574 and 404 lines.

The commit touches only these four files (`M`, `A`, `M`, `A`), so the
verbatim checker, the `@test`/`def test_` counts and `pytest --collect-only`
do not apply.

References: `git grep -nE
'bats-best-practices|mypy-guidelines|guidelines\.md|best-practices|tests/[a-z-]+\.md'
192b0de -- . ':!plans' ':!docs/changelog' ':!TASK.md' ':!TODO.md'`, excluding
the four files themselves, returns one hit, `CLAUDE.md:623`: "`bats run`
captures exit codes and output without the `set +e` dance; see
`tests/bats-best-practices.md`". It is still correct, because `run` usage is
§2, which stays in that file. The `memory` gitlink at `192b0de` (`d0ae87d`)
has no hit for either old name.
