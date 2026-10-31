# f1-fix report

Patch: /tmp/claude/line-cap-split/f1-fix.patch (against 1304efb; `git apply` from repo root). Export: /tmp/claude/line-cap-split/f1-fix/tree.

## Changes
tests/bats-tooling-and-checklist.md (§7)
- ~L74-75: dropped the quoted command; now "straight to `shellcheck -x` (the `check-plugin` gate does exactly this; see that recipe in `justfile` for the file lists)".
- ~L79-83: SC2154 not fired for `$status`/`$output`/`$lines`; fires for `$stderr`, which bats sets only under `run --separate-stderr`. Example disable comment now matches tests/bin-commands.bats:2.
- ~L90-97: example replaced by `# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash` + `source "$BATS_TEST_DIRNAME/hook-helpers.bash"`; reason clause "shellcheck does not follow `load`".
- ~L291-293 (appendix gotcha bullet): same `$stderr` correction.

tests/bats-best-practices.md
- ~L331-333: identical `$stderr` bullet, same correction.

## Copies found (grep outside plans/, docs/changelog/, plugin-dev/)
- `tests/*.sh`: only bats-tooling L75 (fixed).
- `load helpers` / `source=tests/helpers.bash`: only bats-tooling L92-93 (fixed).
- `$stderr` SC2154-not-raised claim: bats-tooling L80 and L291-292, bats-best-practices L331-332 (all fixed).
- Left as is: bats-tooling L245 checklist ("SC2154 suppressions are narrow and source directives present for sourced helpers") is still true. TODO.md:7 mentions the load/source-path fact as a pending item, not a false claim (not edited).

## Verify (in export)
- Probe tests/zz-probe.bats with the new form, referencing `$repo_root` and `$loaded_re` from hook-helpers.bash: `shellcheck -x` rc=0. Negative control (old `source=tests/hook-helpers.bash` + `load hook-helpers`): SC2154 on repo_root and loaded_re, rc=1. Probe deleted (git status shows only the two docs).
- Gate line from justfile:43, from $D: `shellcheck -x bin/* scripts/*.sh tests/*.bats tests/*.bash` rc=0.
- `wc -l`: bats-tooling-and-checklist.md 297, bats-best-practices.md 335 (both <= 400). No new line over 80 columns (existing long lines are table rows / L192 of best-practices).
