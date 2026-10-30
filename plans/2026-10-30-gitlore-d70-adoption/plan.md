# Adopt gitlore D70 in the memory directive

Source: gitlore's inbox note of 2026-10-30 (D70 on gitlore `dev`), triaged
2026-10-30. Released together with gitlore's D70 release as handoff 0.19.0, no
compatibility shim for the retired file handshake. Decisions taken by my human
partner, 2026-10-30: the dirty listing stays in the memory part; the commit act
names the staged memory gitlink when memory was owed; the stale
`gitlore.precommitCommand` goes from `.claude/settings.json` and CLAUDE.md.

## What gitlore D70 changed (verified in `../gitlore` on `dev`)

- No hook commits memory: the `PostToolBatch` commit hook, the message file
  `.claude/gitlore-memory-message` and the trigger file
  `.claude/gitlore-commit-memory` are gone, as is the parent `pre-commit`
  pickup (the shim there is `exit 0`).
- `gitlore.commitCommand`, `pushCommand`, `mergeCommand` and
  `memoryApprovalClauseFile` are no longer set; the clause file is not shipped.
  `precommitCommand` was retired earlier (gitlore's install `del`s it).
- A memory commit is the agent's act through the `gitlore:commit` skill, which
  owns the summary format and the approval protocol (show the summary, end the
  turn, run `gitlore-commit` on approval). `gitlore-commit` stages the memory
  gitlink in the parent index (`scripts/commit-memory.sh`, the D58 block).
- Whether gitlore manages a repo is still read from `.gitmodules`
  (`submodule.gitlore-memory.path`).

## Contract

1. `memory_directive(root: str) -> str` (no `mode`). Same gate as today
   (registered, materialized, `status --porcelain` non-empty), else `""`. When
   owed, exactly these lines, identical under both commit modes:

   ```text
   gitlore memory has uncommitted changes:

   <git -C <mempath> status --porcelain, as today>

   Commit them through the gitlore:commit skill: invoke it before drafting a summary, and follow it.
   ```

   Gone: `_resolve_approval_clause`, the clause-file refusal, the message and
   trigger files, the `approve_files` split, `MemoryPart` (the directive is a
   plain `str`).
2. `compose_directives`: the `if memory.refusal:` branch goes; the part order is
   otherwise unchanged. `hold_decision` is unchanged (`memory=bool(text)`): the
   turn still ends on the summary, so a pending approval still holds a sentinel
   that names a command.
3. `commit_directive(root, legacy_paths, *, memory: bool)`. With `memory` false
   the sentence is byte-identical to today's. With it true:

   ```text
   Once everything above is done, make the commit the request called for, including any change to `TASK.md` and `TODO.md` and the memory gitlink `gitlore:commit` staged.
   ```

   `compose_directives` passes `memory=bool(memory_text)`.

## Tests (red, then green)

Red rows go through `run_checkpoint` where they can, so the red is a failed
assertion and not a `TypeError` on a new signature.

- Dirty memory: stdout holds the status line and the exact closing sentence of
  item 1, and none of `gitlore-memory-message`, `gitlore-commit-memory`,
  `memoryapprovalclausefile` (case-insensitive), `trigger`, `blockquote`.
- The memory part is byte-identical under `with-commit` and `without-commit`.
- `with-commit` + dirty memory: the commit act is item 3's sentence;
  `with-commit` + clean memory: today's sentence, exactly.
- Composition/order rows locate the memory part by `gitlore:commit` instead of
  the message-file path.
- Deleted with the mechanism (no replacement row): every clause-file refusal
  row (`test_checkpoint_directives.py`, `test_checkpoint_composition.py`,
  `test_checkpoint_hold.py`, `test_checkpoint_legacy.py`), the trigger-file
  rows, `unset_clause_file` and its isolation row, the clause setup in
  `make_gitlore_repo` (`conftest.py`) and in `tests/probe-helpers.bash`, the
  `GITLORE_MEMORY_APPROVAL_CLAUSE` constant, `checkpoint.bats:76`'s clause
  assertion. `checkpoint.bats:687` asserts `gitlore:commit` instead of the
  trigger path.
- Mutation-checked after green: the commit act ignoring `memory` (both
  directions), and the memory part differing by mode.

## Docs (same commit)

`CLAUDE.md` (Layout's second paragraph, the `_checkpoint_lib.py` bullet, the
test bullets naming the clause/trigger rows, the `just precommit` line's
`precommitCommand` claim), `README.md:71` and `:138-141`,
`docs/design/the-checkpoint-directive.md` (the refusal paragraph goes; "The
gitlore seam" rewritten), `docs/design/decisions.md:100-125`,
`docs/design/rejected-alternatives.md:28`, `docs/design.md` index lines that
name the mechanism, one changelog file plus its index line, and `Superseded`
blockquotes on the changelog entries whose mechanism this replaces.
`.claude/settings.json` drops `gitlore.precommitCommand`.
