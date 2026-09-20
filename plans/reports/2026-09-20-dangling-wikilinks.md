# Dangling wikilinks in the ddaanet memory tier — 2026-09-20

## 1. `[[errexit-blind-inside-test]]` in `git-add-untracked-deletion.md`

**Dangling confirmed:** `grep -rn "^name:" memory --include='*.md' | grep -i errexit` returns no
match anywhere in the store; no near-miss renamed slug found either.

**Sentence before** (line 38-41):
> So read its exit status explicitly and test the output separately. Do not fold
> the two into `[ -z "$(git ls-files -- "$p")" ]`: that spelling discards the
> command's status and reads a git failure as "not tracked"
> ([[errexit-blind-inside-test]]).

**Sentence after:**
> So read its exit status explicitly and test the output separately. Do not fold
> the two into `[ -z "$(git ls-files -- "$p")" ]`: that spelling discards the
> command's status and reads a git failure as "not tracked" (the
> `shell-scripting:shell-gotchas` skill).

**Skill file:** `/Users/david/.claude/plugins/cache/ddaanet/shell-scripting/0.4.0/skills/shell-gotchas/references/robustness.md`
(latest cached version; 0.3.2 also present but superseded).

**Passage that covers the fact** (`references/robustness.md`, "Exit status and `set -e`"):
> - **Off inside conditions, transitively:** any command in `if`, `while`, `&&`/`||` chains, or
>   after `!` runs with `-e` disabled — *including every function called from there*. […]
> - **Command substitution does not inherit `set -e` (bash):** in `var=$(f)`, `f` runs with
>   errexit *off* unless `shopt -s inherit_errexit` (bash ≥ 4.4) or POSIX mode. A failing
>   pipeline inside `$(…)` sails through. […]

Together these two bullets are exactly the mechanism the memory sentence describes: a command
substitution (`$(git ls-files …)`) sitting inside a `[ ]` test condition has its exit status
discarded regardless of `set -e`, so only the *string* it produced is tested — a git failure
(empty stdout) reads identically to "untracked" (also empty stdout). Confirmed the skill covers
it; swapped the wikilink for the prose form already used elsewhere in this tier (`` the
`shell-scripting:shell-gotchas` skill `` / `` (`shell-scripting:shell-gotchas`) ``, matching the
existing `` (`craft:test-discipline`) `` convention found via
`grep -rn "the \`.*:.*\` skill" memory/ddaanet/*.md`).

## 2. `[[mutation-check-discipline]]` in `sandbox-effects.md`

**Dangling confirmed:** `grep -rn "^name:" memory --include='*.md' | grep -i mutation` returns no
match; no near-miss renamed slug found.

**Sentence before** (line 278-279):
> end. See [[mutation-check-discipline]] for why a restore path that silently
> resolves elsewhere is the expensive case.

**Sentence after:**
> end. See the `craft:test-discipline` skill for why a restore path that silently
> resolves elsewhere is the expensive case.

**Skill file:** `/Users/david/.claude/plugins/cache/ddaanet/craft/0.2.0/skills/test-discipline/references/genuine-red.md`
(0.2.0 is the latest cached version over 0.1.0).

**Passage that covers the fact** ("Restore by inverting the edit, never from a copy"):
> Mutating, running the suite and restoring are separate tool calls, so any restore that depends
> on state surviving between calls is the hazard. Measured: a backup written to `$TMPDIR`
> succeeded, the suite redded as intended, and the restore one call later read an empty
> `$TMPDIR` — `cp` failed, and the mutation stayed live in a tree holding uncommitted work. The
> `&&` that chained the backup proved it was written, never that it could be found again.
>
> Apply the mutation as an exact string replacement, and restore by applying it again with the
> two strings swapped. No backup file, no scratch directory, and the string pair is itself the
> record of what was changed.

This is the exact case the memory sentence points at ("a restore path that silently resolves
elsewhere is the expensive case") — confirmed and swapped the same way as link 1.

Note: editing `sandbox-effects.md` (even for this one-line link swap) tripped the store's
oversize-file warning (34.2KB, over the 4KB recall cap). Per the task brief this file's size is
known and being handled elsewhere; left untouched beyond the single link.

## 3. Sweep — other `[[slug]]` wikilinks in `memory/` with no matching `name:` (report-only)

Extracted every `[[slug]]` occurrence store-wide and diffed against every `name:` frontmatter
value:

```
comm -23 <(grep -rhoE '\[\[[a-zA-Z0-9_-]+\]\]' memory | sed -E 's/\[\[(.*)\]\]/\1/' | sort -u) \
         <(grep -rhoE '^name:\s*\S+' memory --include='*.md' | sed -E 's/^name:\s*//' | sort -u)
```

Result (before fixing the two links above; both are gone from the diff now):

- `green-is-not-evidence` — genuine dangling link, in
  `memory/project_pane-fixtures-are-captures.md:32`:
  > `docs/changelog/2026-08-13-predicates-match-the-real-pane.md`, and
  > [[green-is-not-evidence]] for the wider class.
  No file with `name: green-is-not-evidence` exists anywhere in the store. Left untouched per
  scope (fix only the two links named in the brief).
- `wikilink` — **false positive**, not an actual link: it's a syntax example inside prose, in
  `memory/ddaanet/extracting-memory-into-skills.md:12`:
  > mechanical, and a `[[wikilink]]` / `memory/`-path check catches most of it.

## Anything surprising

- Both target links turned out to be genuinely orphaned (no renamed-slug near-miss) and both
  hypotheses in the brief (shell-gotchas / test-discipline) checked out on inspection of the
  actual skill passages, not just by plausible title match.
- The store carries duplicate/stacked plugin cache versions for both skills (shell-scripting
  0.3.2 vs 0.4.0, craft 0.1.0 vs 0.2.0); read the latest cached version in each case.
- The sweep surfaced one more dangling link (`green-is-not-evidence`) beyond the two named in the
  task, which is out of scope to fix here but worth flagging for a future pass.
