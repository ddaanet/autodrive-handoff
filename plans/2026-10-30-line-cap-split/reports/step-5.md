# Step 5 report, phase A: the two guideline docs

Work is in the copy `/tmp/claude/line-cap-split/step-5/repo` (tag `base` is
the `c2fff7c` tree). Nothing is staged there; the real tree was not touched
except this report.

## What moved where

Both boundaries exist as the plan describes them, at `##` headings.

`tests/bats-best-practices.md` (574 lines):

- `tests/bats-best-practices.md` (kept path, 334 lines): the intro, `## 1`
  to `## 4` (original lines 1 to 287, through the `---` before section 5),
  then a `## Sources` block.
- `tests/bats-tooling-and-checklist.md` (new, 293 lines): `## 5` (sourcing and
  `load`), `## 6` (version pinning, skip, retries), `## 7` (ShellCheck),
  `## 8` (mocking, parameterization, diagnostics), `## 9` (anti-patterns),
  `## Reviewer checklist` and its `### Sources`. Original lines 289 to 574,
  verbatim.

`tests/mypy-guidelines.md` (404 lines):

- `tests/mypy-guidelines.md` (kept path, 279 lines): the intro, `## Strict
  mode`, `## Config hygiene`, `## Annotation practices` (original lines 1 to
  263), then a `## Sources` block.
- `tests/mypy-suppressions-and-tooling.md` (new, 137 lines): `## Avoiding
  suppression debt`, `## mypy + ruff: division of labor`, `## mypy vs ty
  (Astral)`, `## Practical gotchas`, `## Sources` (original lines 265 to 387
  plus its sources).

## Names

- `bats-tooling-and-checklist.md`: sections 5 to 9 are helper loading, version
  floors, ShellCheck, mocking and anti-patterns, and the checklist is the
  closing half.
- `mypy-suppressions-and-tooling.md`: suppression debt, then the ruff and ty
  comparisons and the gotchas.
- First halves keep their paths and still match: `bats-best-practices.md`
  holds the core rules (masked failures, `run`, isolation, naming) and
  `mypy-guidelines.md` the strict, config and annotation rules. No rename
  proposed.

## Added lines

Only these are new (the `comm -13` output, folded):

- bats half 1: a two-line cross-link after the intro paragraph, a blank line,
  and `## Sources` followed by the whole original Sources body (original lines
  533 to 574, duplicated, since sections 1 to 4 cite `[writing-tests]`,
  `[gotchas]` and the empirical bullets). The heading is `##` here, not the
  original `###`, because under half 1 a `###` would nest below section 4.
- bats half 2: a title (`# Bats-core best practices, part 2: sourcing
  through the checklist`), a two-line cross-link, and a `---` separator
  before section 5.
- mypy half 1: a two-line cross-link after the intro paragraph, `## Sources`
  and ten source entries (the nine it cites plus the Adam Johnson one),
  duplicated from the original list, of which three (command line, config
  file, common issues) also stay in half 2.
- mypy half 2: a title (`# mypy guidelines, part 2: suppression debt through
  gotchas`) and a two-line cross-link.

Source lists are split by citation: each mypy half lists the sources whose
URL it inlines. Half 2's list lost seven entries (getting started, optional
error codes, changelog, 2.0 blog, #11760, TypedDict, Adam Johnson) that only
half 1 cites; they sit in half 1, so the union holds every original line. The
bats Sources block is duplicated whole, because its trailing "Empirically
verified" bullets span sections 1, 6 and 7.

## Checks

```
== bats-best-practices.md
comm -23 <(git show c2fff7c:tests/bats-best-practices.md | sort) <(cat halves | sort)
(no output)
== mypy-guidelines.md
comm -23 ... (no output)
```

`comm -13` prints only the added lines listed above (title lines, the two
cross-link pairs per file, `---`, `## Sources`, and the duplicated Sources
lines; a multiset comparison, so lines that now occur twice show once).

```
bash plugin-dev/check-refs.sh   (from the copy)
check-refs: resolves: 260 references in 27 files, 306 exempt files skipped; shipped stays shipped: 2 references from 6 shipped files
rc=0
```

Line counts:

| File | Lines |
| --- | --- |
| tests/bats-best-practices.md | 334 |
| tests/bats-tooling-and-checklist.md | 293 |
| tests/mypy-guidelines.md | 279 |
| tests/mypy-suppressions-and-tooling.md | 137 |

None passes 400. The verbatim checker, bats, pytest and the Python linters do
not apply (Markdown only).

## References

Grep for `bats-best-practices` and `mypy-guidelines`, outside `plans/`,
`docs/changelog/`, `TASK.md` and `TODO.md`: one hit, `CLAUDE.md:623`
("`bats run` captures exit codes and output … see
`tests/bats-best-practices.md`"). It points at the `run` rules, which stay in
`bats-best-practices.md` (section 2), so no change. Nothing else cites the
checklist heading or either name. Phase B should grep again for hits in files
the other steps have since split (`CLAUDE.md` and `docs/design/` are the
candidates).

## Departures from the plan

None. One judgement call worth a glance in review: the `##` heading of the
duplicated bats Sources block in half 1 (see Added lines).

## Phase B

Commit `192b0de` (`📝 split the two guideline docs under the 400-line cap`),
four paths only. HEAD was still `c2fff7c` when the patch applied (clean
`--3way`), so no conflict. Grep for both old names outside the excluded paths:
the same single hit, `CLAUDE.md:623`, unchanged. In the real tree
`comm -23` against `HEAD:` prints nothing for both originals, line counts are
334 / 293 / 279 / 137, and `check-refs.sh` passes.

`just precommit` (unsandboxed, Python env exported) green: check-plugin and
check-code passed; bats 352 passed, 0 failed; pytest 520 passed, 3 deselected;
check-refs 260 references in 28 files; `precommit: check-plugin check-code
passed`. ` M memory` left unstaged.
