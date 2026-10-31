# Review of d80b311 at medium

Commit: `d80b311` "correct four design claims the CLAUDE.md inventory
contradicted". Method: `/code-review medium d80b311` plus each claim checked
against its primary source (the sentinel's writers and removers in `scripts/`,
`bin/` and `hooks/handoff.ts`; `TODO.md`; both `.envrc` files; the direnv
stdlib). Severity is assigned here by the brief's bar: a reader following the
text would do the wrong thing.

## Findings

### 1. `docs/design/decisions.md:185` still says the sentinel has a single writer — medium

- Claim: "which is why the file has a single writer: the checkpoint composes
  it, and a direct agent Write or Edit is denied outright."
- Contradicted by: `scripts/_lib_drive.sh:278-286` (`handoff_drive_arm`
  rewrites line 1), called from `scripts/drive-take.sh:102` (`pending`) and
  `bin/handoff-approved:82` (`armed <owner>`); and by the sentences this commit
  corrected, `docs/design.md:139-141` (FR3: "past that, the plugin's own
  scripts only rewrite its state line (`handoff_drive_arm`) or remove it") and
  `docs/design/driving-the-transition.md:42-43` ("`handoff_drive_arm` rewrites
  only line 1"), as well as `driving-the-transition.md:60` ("Both writers
  rename a file into place: the checkpoint, and `handoff_drive_arm`").
- Why it meets the bar: it is the same fact the commit set out to correct, in
  a node the commit edited, and the sentence is the *reason* clause of the
  decision ("the state being content … makes a wrong one writable, which is why
  the file has a single writer"). A reader taking it as the invariant treats
  `handoff-approved`'s rewrite as a violation, or audits only `checkpoint.py`
  for state-line correctness and misses the two `handoff_drive_arm` callers.
  The commit message's "carries no stale claim forward" does not hold for this
  copy.
- Proposed fix (same shape as the two sentences the commit did fix, keeping
  the sentence as the reason it is):

  > The state being content rather than a name also makes a wrong one
  > writable, which is why the file's writers are a closed set: the checkpoint
  > composes it, `handoff_drive_arm` rewrites only its state line, and a direct
  > agent Write or Edit is denied outright.

## Declined (out of scope or low, not dispatched)

Listed so the fixer can grep them in the same pass if wanted; each is a
prohibition or a user-facing table whose reader does the right thing (does not
write the file), and none is in the commit's files or in `docs/design.md`:

- `README.md:198` "written only by `handoff-checkpoint`";
  `skills/autoname/SKILL.md:44` "The checkpoint is its one writer";
  `scripts/write-guard.sh:2,51` deny text. Raised by `/code-review`; declined.
- `CLAUDE.md:58-59` (FR3 "written **only** by the checkpoint"), `CLAUDE.md:83`
  (retirement condition without the date), `CLAUDE.md:488` ("`.envrc` —
  exports `MARKETPLACE_DIR`"). Out of the commit's scope; the inventory's C1
  and C2 already track them and the split deletes the sections. Note that
  `CLAUDE.md:488` is the one copy a reader does act on wrongly (looks in the
  repo's `.envrc`), so the split should not slip past it.
- `docs/design/release-infrastructure.md:29` naming `~/code/.envrc` rather
  than "an ancestor `.envrc`": true on this machine, phrasing otherwise.
- `docs/design/decisions.md:63` carrying a calendar date in a living node: the
  brief asked for the date to match `TODO.md`, and it does.
- `docs/design/driving-the-transition.md:42` read-back guarantee: the sentence
  attributes the read-back to `checkpoint.py` only, and both `handoff_drive_arm`
  callers pass a state line that cannot fail the parser (`pending`, or
  `armed <owner>` with the owner the parser just accepted). Guards a state
  nothing produces.

## Checks passed

- FR3 / `driving-the-transition.md:42-43`: `checkpoint.py` alone composes the
  sentinel (`scripts/checkpoint.py:210` via `write_replacing`; its own unlink at
  `:222` and `:227` is the read-back failure path). `handoff_drive_arm`
  (`scripts/_lib_drive.sh:278-286`) writes the given line 1 into a `mktemp`
  sibling, appends `tail -n +2` of the file, and renames; callers
  `scripts/drive-take.sh:102` and `bin/handoff-approved:82`. Every other touch
  is a removal: `scripts/load-handoff.sh:68,74`, `scripts/load-compact.sh:58,71`,
  `scripts/drive-take.sh:75,104`, `scripts/report-drive-failure.sh:285,337,349`.
  `hooks/handoff.ts` writes only `failFile` (`:71`) and never the sentinel.
- `decisions.md:63` dates: `TODO.md:7` says "not before 2026-11-16 … one month
  past 2026-10-16, when no sibling repository had `.claude/handoff-*.md` any
  more"; the TODO line itself landed on 2026-10-16 (`654a549`). Match.
- `release-infrastructure.md:28-30`: `/Users/david/code/.envrc:4` exports
  `MARKETPLACE_DIR="$HOME/code/claude-plugins"`; the repo's `.envrc:1` is
  `source_up_if_exists`; `direnv stdlib` defines `source_up_if_exists`. Match.
- Same-node and `docs/design.md` consistency of the corrected sentences:
  `driving-the-transition.md:60` ("Both writers rename a file into place") and
  `the-checkpoint-directive.md:123-126` (`handoff_drive_arm` writes the line 1
  it is given) agree with the new wording; `docs/design.md:208` "one write path"
  is about `TASK.md`/`TODO.md`, not the sentinel. The one disagreement is
  finding 1.
- No changelog file touched; the four edits are prose only.
