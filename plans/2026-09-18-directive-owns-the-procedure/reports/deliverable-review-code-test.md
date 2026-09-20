# Deliverable review — code and tests, "the directive owns the procedure"

Scope: `scripts/_checkpoint_lib.py`, `scripts/checkpoint.py`,
`bin/handoff-approved`, `tests/test_checkpoint.py`, `tests/checkpoint.bats`,
as they stand in the working tree on 2026-09-20. Baseline:
`docs/changelog/2026-09-18-the-directive-owns-the-procedure.md` and
`plans/2026-09-18-directive-owns-the-procedure/outline.md`. Plan range
`411f2c7~1..6866a4e`.

Report only — nothing was fixed. Two temporary mutations were applied to
`scripts/checkpoint.py` and one to `bin/handoff-approved` to test vacuity
claims; each was restored by copying back a byte-identical backup, and
`git diff --stat` afterwards shows only the four pre-existing out-of-plan
changes (`CLAUDE.md`, `README.md`, `docs/design.md`, `scripts/_checkpoint_lib.py`,
`scripts/_lib.sh`, `scripts/checkpoint.py`, `tests/test_checkpoint.py`,
`tests/test_tui_conformance.py`, plus the `memory` gitlink).

## /Users/david/code/handoff/scripts/_checkpoint_lib.py

1. **Minor** — `scripts/_checkpoint_lib.py:196-211`
   `closing_directive` punctuates its two arms differently: the untyped arm
   emits `` …end on one line: `Ready to /clear`. `` (period outside the
   backticks, so the quoted line is `Ready to /clear`), while the typed arm
   emits `` …end on one line: `Clear armed — it runs when this turn ends.` ``
   (period inside, so the quoted line carries it). An agent relaying the
   quoted span literally therefore ends one boundary on an unpunctuated
   fragment and the other on a sentence. No functional consequence; it is a
   consistency wrinkle in text whose whole purpose is to be relayed verbatim.
   Fix: settle one convention (period inside the backticks for both, or
   outside for both) and mirror it in the three literals in
   `bin/handoff-approved`. Evidence: read `_checkpoint_lib.py:206-211`; the
   two shapes are visible side by side.

2. **Minor** — `scripts/_checkpoint_lib.py:208`
   `closing_directive` derives the boundary from `skill` by an `else` branch
   (`name = "Clear" if skill == "handoff" else "Compaction"`, and the same
   shape on line 210). Any skill string other than `"handoff"` silently
   produces the precompact wording rather than an error. In practice
   `compose_directives` only reaches this with `"handoff"`/`"precompact"`
   (it returns `[]` for the other two skills — `checkpoint.py:651`), and the
   bats helper calls it directly with those two, so this is unreachable
   today. It is still a silent-wrong-answer default in a function that
   `tests/checkpoint.bats` invokes as a standalone oracle. Fix: raise on an
   unknown skill rather than falling through to the precompact wording.
   Evidence: read `_checkpoint_lib.py:196-211`.

No Critical or Major findings in this file. The design record's two named
text requirements are met exactly: `commit_directive()` (line 178-186) is
`"Once everything above is done, make the commit the request called for."`
with no git verb, and the `with-commit` memory arm (line 146-153) keeps
"The commit that lands these changes carries the memory." having dropped
"Nothing further is needed from you", while never naming
`.claude/gitlore-commit-memory` or the word "trigger".

## /Users/david/code/handoff/scripts/checkpoint.py

1. **Minor** — `scripts/checkpoint.py:589-592` (with `scripts/_lib.sh:190-201`)
   When the sentinel is held and `CLAUDE_CODE_SESSION_ID` is unset,
   `compose_sentinel` writes the line `"held "` (state plus an empty owner),
   the bash read-back rejects it, the sentinel is unlinked, and the run exits
   2 with `handoff-checkpoint: transition: composed a sentinel this version
   cannot read back — line 1 state \`held\` must name the session holding
   it`. By then `handoff-task.md` and the manifest are already on disk, so
   the wrap-up is half-applied: the files land and get staged by
   `PostToolUse(Bash)`, but no transition exists and none of the printed
   procedure (memory approval, commit act, closing line) reaches the agent.
   The message also misattributes the cause — it blames the composer, not the
   missing environment variable, giving the agent nothing to act on.
   This cell is not new in kind (`held` predates the plan), but the plan's
   second disjunct `(T ∧ C)` newly routes "handoff, drive the clear, and
   commit" — a common invocation — through it. `_build_restart_transition`
   (line 281-288) already treats an unset `CLAUDE_CODE_SESSION_ID` as a
   named schema error; the held path does not.
   Fix: validate `CLAUDE_CODE_SESSION_ID` the way the restart branch does —
   before any write, so the all-or-nothing guarantee holds — and name the
   variable in the message.
   Evidence:
   ```
   printf '%s' '{"skill":"handoff","commit":"with-commit","rename":"T",
     "clear":true,"continue":null,"task":"# X\n\nbody\n",
     "todo":{"action":"keep"}}' \
     | env -u CLAUDE_CODE_SESSION_ID HANDOFF_ROOT=$T/repo python3 scripts/checkpoint.py
   → rc=2, message as quoted above; .claude/ holds checkpoint-manifest and
     handoff-task.md, no autodrive.
   ```

No Critical or Major findings in this file.

The hold rule is exactly the design's. `hold_decision`
(`checkpoint.py:567-579`) is
`(bool(transition.cmds) and memory) or (transition.typed and commit)` —
`(K ∧ M) ∨ (T ∧ C)` with `K = transition.cmds`, `M = bool(memory.text)`,
`T = transition.typed`, `C = commit_mode == "with-commit"`. It is computed
once in `main` (line 86-88) and the single resulting `held` flows into both
`compose_sentinel(..., held=held)` and `Ending(held=held, ...)`, so the
sentinel state and the printed ending cannot disagree. The refusal counts
as `M` (its text is non-empty), which is what the outline specifies.

`compose_directives` (line 637-664) orders the parts memory → todo/SDD →
commit act → arming-or-closing, each under its own condition, with the
ending always last and the two endings mutually exclusive by `if/else`.
`memory.refusal` returns `[memory.text]` before any other part is computed,
so the refusal prints alone on both the held and the armed path.

## /Users/david/code/handoff/bin/handoff-approved

1. **Minor** — `bin/handoff-approved:73-83`
   The `case "$DRIVE_KIND"` has no `*)` arm. A held sentinel of any other
   kind — a hand-written one, or a kind added later — prints the status fact,
   prints no closing line, and exits 0. The agent gets a successful arm with
   no instruction about how to end the reply, and nothing reports the gap.
   `restart` is the concrete near-miss: the checkpoint never holds it
   (`validate_commit_mode` returns `""` for `restart`, so `C` is false, and
   no memory directive is composed, so `M` is false — `checkpoint.py:216-229`,
   `84-85`), so this is unreachable through the checkpoint today. Fix: add a
   `*)` arm that errors, naming the kind, rather than falling through
   silently.
   Evidence: read `bin/handoff-approved:73-83`; no default arm present.

2. **Minor** — `bin/handoff-approved:68`
   The comment block is mis-wrapped: line 68 runs "…always a driven one.
   Literal rather than composed in Python, so this command stays one file"
   well past the column the surrounding comment lines keep to. Cosmetic;
   fix by re-wrapping the paragraph.
   Evidence: `git diff 411f2c7~1..6866a4e -- bin/handoff-approved` shows the
   line added unwrapped.

No Critical or Major findings in this file. The three literals match
`closing_directive()` byte for byte — verified by running the bats rows, and
by mutation (below). The status fact keeps its own line and the blank line
that separates it from the closing line, per the outline. NFR1 holds: no git,
no tmux; the addition is three `printf`s.

## /Users/david/code/handoff/tests/test_checkpoint.py

1. **Minor (specificity)** — `tests/test_checkpoint.py:2262-2267`
   `test_commit_act_names_no_git_verb` pins the "no git verb" requirement by
   three substring absences (`"git commit"`, `"--amend"`, `"git add"`). A
   rewording that did name a verb in another spelling — "commit with
   `git ci`", "stage and commit" — would pass. The requirement it stands for
   is a prose property that a substring blacklist cannot fully express; the
   current list is a reasonable proxy but reads as stronger than it is.
   Fix: either narrow the test's docstring to say it guards the three
   spellings that were actually at risk, or invert it into a whitelist
   assertion (the exact expected sentence), which the design record already
   quotes verbatim. Evidence: read `test_checkpoint.py:2262-2267`.

2. **Minor (coverage)** — `tests/test_checkpoint.py:2276-2288`
   `test_handoff_parts_print_in_order` asserts `memory < todo < commit` but
   stops there; its fixture (dirty memory, `with-commit`, `clear=False`) is
   held, so no closing line exists to order. The four-part chain ending in
   the closing line is pinned only on the precompact side
   (`test_precompact_parts_print_in_order`, line 2308-2330, which asserts
   `memory < sdd < commit < closing` and `out.endswith(closing)`). On the
   handoff side, `commit < closing` is never asserted — only
   `commit < arming` (line 2406-2427). The composition code is shared, so
   the risk is low, but the handoff boundary has no row pinning that its
   closing line comes after the commit act. Fix: add a handoff row over an
   armed `with-commit` fixture asserting `commit_index < closing_index` and
   `out.endswith(closing)`, mirroring the precompact row.
   Evidence: read `test_checkpoint.py:2276-2330` and `2429-2441`.

3. **Minor (coverage)** — `tests/test_checkpoint.py:2235-2246`
   No row asserts the sentinel state for untyped *precompact* +
   `with-commit` + clean memory (`¬K ∧ ¬T ∧ C`, the FR-G marker cell).
   `test_with_commit_prints_the_commit_act[precompact_payload]` exercises
   that payload but asserts only that the commit act is printed. The cell is
   covered in spirit by `test_sentinel_typing_nothing_arms_even_with_memory_gate_pending`
   (line 1821) and by the untyped-handoff row, so this is a completeness nit
   rather than a gap in the design's named matrix. Fix: assert
   `first_line == "armed"` in the precompact parametrization of the commit-act
   row, or add a dedicated row. Evidence: read `test_checkpoint.py:2235-2246`
   against the hold matrix at `1740-1841` and `2400-2441`.

No Critical or Major findings in this file, and no vacuous rows found.

Both hold-rule rows are genuinely load-bearing — verified by mutation, not
by observation:

- Dropping the second disjunct (`hold_decision` → `bool(transition.cmds) and
  memory`) reds exactly
  `test_typed_with_commit_clean_memory_is_held[handoff_payload-clear]`,
  `[precompact_payload-compact]` and the two
  `test_held_sentinel_prints_no_closing_line` parametrizations; 24 other
  selected rows stay green.
- Widening to the rejected uniform predicate `K ∧ (M ∨ C)` reds exactly
  `test_untyped_handoff_with_commit_clean_memory_is_armed` and
  `test_rename_only_manifest_present_empty_sentinel_written` (the older row
  pinning the same cell's sentinel bytes), as the changelog claims.

Commands:
```
cd /Users/david/code/handoff && direnv exec . pytest tests/test_checkpoint.py -q \
  -k "hold or held or closing or commit_act or parts_print or arming or refusal or rename_only"
cd /Users/david/code/handoff && direnv exec . pytest tests/test_checkpoint.py -q \
  -k "untyped_handoff_with_commit_clean_memory_is_armed"
```

The refusal is pinned on both fixtures the design record demands:
`test_clause_refusal_is_followed_by_no_commit_or_arming` (line 2368, held —
asserts the todo boundary, commit act, arming instruction and the string
"end on one line" are all absent, and that the sentinel is still
`held sess-checkpoint`) and `test_refusal_prints_alone_when_not_held`
(line 2660, armed — asserts `result.stdout == refusal.text` exactly).

`assert_stdout_is_closing` (line 2066-2076) guards its own vacuity with
`assert closing != ""` before the equality, so it cannot pass against an
unwritten `closing_directive`. The same guard pattern (`assert commit_act`,
`assert arming`, `assert boundary`) appears on every row that compares
against a library-produced string. Independence: every row takes `tmp_path`
and builds its own repo; the only shared state is the autouse `_session_id`
fixture (line 39-42), which sets `CLAUDE_CODE_SESSION_ID` and deletes
`CLAUDE_PROJECT_DIR` per test.

## /Users/david/code/handoff/tests/checkpoint.bats

No findings at any severity.

The three drift rows (line 221-252) are specific and non-vacuous. They
compare `handoff-approved`'s full output against a literal status fact plus
`$'\n\n'` plus `closing_directive()`'s own output, obtained by importing the
Python module (`expected_closing`, line 213-219), and they guard the empty
case with `[ -n "$expected" ]`. The kind→(skill, typed) mapping is spelled
per row, so a swap inside `closing_directive` moves the Python side alone and
reds the affected row.

Verified by mutation: deleting the trailing period from the `rename` arm's
literal in `bin/handoff-approved` reds row 1 alone; rows 2 and 3 stay green.
The file was restored from a byte-identical backup and
`git diff --stat -- bin/handoff-approved` afterwards is empty.

```
cd /Users/david/code/handoff && direnv exec . bats tests/checkpoint.bats -f "closing line"
→ 3/3 ok unmutated; 1 not ok / 2 ok under the mutation
```

The comment at line 207-212 correctly records the one difference these rows
cannot see — `$(...)` strips trailing newlines on both sides, so a change in
the *number* of trailing newlines on either producer would not red them. That
is a bounded, documented residual, not a finding.

## Clean

Checked and found correct:

- **Hold rule conformance.** `hold_decision` is `(K ∧ M) ∨ (T ∧ C)` exactly;
  one computation feeds both the sentinel state and the arming-versus-closing
  choice (`checkpoint.py:86-92`).
- **Part ordering and conditions.** memory → todo/SDD → commit act →
  arming-or-closing, each gated on its own condition, ending always last and
  the two endings mutually exclusive (`checkpoint.py:637-664`).
- **Refusal prints alone**, on both the held and the armed fixture, with the
  sentinel state left unchanged so a retry recomposes it.
- **`print_output` separator.** `rstrip("\n")` before a `"\n\n"` join, so
  every gap is exactly one blank line; pinned by
  `test_parts_are_separated_by_one_blank_line` (which also pins that stdout
  ends on the closing line).
- **Byte-for-byte match** between `closing_directive(skill, typed=…)` and the
  three literals in `bin/handoff-approved`, for all three reachable kinds,
  and the mapping's own soundness: `autoname` and `restart` never hold, an
  untyped precompact never holds, so a held `rename` is always an untyped
  handoff and a held `clear`/`compact` always driven.
- **`commit_directive` names no git verb** and matches the design record's
  quoted sentence verbatim.
- **The load-bearing negative survives**: `with-commit` output never mentions
  `gitlore-commit-memory`, "trigger", or "two file writes"
  (`test_with_commit_summary_write_only_no_trigger_mention`), and the commit
  act added above it introduces none of those strings.
- **"Nothing further" removed** from the `with-commit` memory text, asserted
  by `test_with_commit_memory_text_drops_nothing_further`.
- **`arming_directive` reworded** to "Once everything above is done", with
  `test_arming_text_refers_to_everything_above` plus
  `assert "Once that is done" not in out` on the ordering row.
- **`autoname` / `restart` still print nothing**: `compose_directives`
  returns `[]` for both before touching memory, and `validate_commit_mode`
  returns `""` so neither can hold. Covered by
  `test_autoname_against_dirty_memory_no_directive_at_all` and
  `test_restart_never_holds_even_with_dirty_memory`.
- **Error signaling on the schema paths** is unchanged and correct: `err()`
  exits 2 naming the offending field on stderr; the plan touched none of it.
- **Idempotency of `handoff-approved`**: a second invocation finds state
  `armed` and exits 2 naming it, before printing anything.
- **Excess**: nothing found beyond the outline's five per-file items. The
  `MemoryPart` and `Ending` NamedTuples are each justified by a value that
  must travel with a flag, and both are defined below their users per the
  repo's entry-points-first convention.
- **Tree restored**: `git diff --stat` after all mutations shows only the
  four documented out-of-plan changes.

## Unverified suspicions

None. Every suspicion raised during the review was settled by running the
command or reading the lines cited above.

## Severity counts

Critical 0 · Major 0 · Minor 8

By file: `_checkpoint_lib.py` 2, `checkpoint.py` 1, `bin/handoff-approved` 2,
`tests/test_checkpoint.py` 3, `tests/checkpoint.bats` 0.
