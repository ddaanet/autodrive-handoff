# Seam D report: the files reference, and the relaxed no-tool-call rule

## Byte counts (`wc -c`)

| file | before | after |
|---|---|---|
| `skills/handoff/SKILL.md` | 10476 | 7471 |
| `skills/handoff/references/files.md` | (new) | 3681 |
| `skills/precompact/SKILL.md` | 6625 | 6733 |

`size.exempt` lost its `skills/handoff/SKILL.md` line; `check-size` reports "3 entries, each with a reason and still needed".

## Moved text

`## File templates` and `## The seam: files vs. continuation` moved verbatim into `skills/handoff/references/files.md`, under one added lead line. Left behind in `SKILL.md`: a one-line pointer before `## Anti-patterns`, the "using the task template" / "using the todo template" wording in Step 2 (it said "below"), and an `## Additional resources` entry.

## Statements of the rule, rewritten

- `docs/design/decisions.md:248` (retitled "Between deciding and the checkpoint, no tool call"; the Read exception and why it is safe at :265-273)
- `docs/design.md:272` (index line, same new title)
- `.claude/rules/skills.md:12-16` (templates and seam live in `references/files.md`) and `:21-27` (two kinds of call ahead of the checkpoint)
- `skills/handoff/SKILL.md:21-24` (Step 1), `:28-31` (the Read, placed ahead of the imperative at `:32`), `:115` (anti-pattern now says "any other project file")
- `skills/precompact/SKILL.md:17-20` (Step 1), `:24-29` (the pointer moved to the head of Step 2, ahead of the imperative at `:30`, with the condition "when the rules matter" kept)
- `docs/design/the-skills.md:16-22` (new paragraph: where the templates live, and the one extra call; the file did not state the rule before)
- Inbound references to the moved text: `docs/design.md:332`, `skills/handoff/references/design.md` (two mentions of the template in `SKILL.md`), `scripts/_lib_frame.sh:35` (comment), `CLAUDE.md` Components (updated line plus a new line), `README.md` Further reading.

Not touched: the `autoname` and `pending` no-tool-call statements.

Judgement call: in `precompact` the old pointer sat after the todo-deciding prose and before the checkpoint, i.e. a Read inside the window the rule forbids. I moved the pointer paragraph to the head of Step 2 so the Read precedes deciding, as in `handoff`.

## Changelog links settled (the three in the decision entry)

- `2026-08-11-decide-with-zero-tool-calls.md`: its argument (the `cat` incident, the habit that overrode the wording, the wording-over-hook choice) was in the entry except the last point; folded in as one sentence ("Wording is the fix; a hook ... was not built, and is the next escalation..."), link dropped.
- `2026-09-17-memory-moves-inside-the-deciding-step.md`: superseded; the argument that survives (memory precedes the checkpoint because its directive keys on a dirty submodule, the commit comes after the checkpoint) was already in the entry. Dropped.
- `2026-09-18-the-directive-owns-the-procedure.md`: the entry already carries the commit-act placement and the memory-tense point. Dropped.

No `../changelog/` link remains in that entry.

## Gates

- `just precommit` (unsandboxed): passed. check-plugin, check-code (bats 352 passed; pytest 520 passed, 3 deselected), check-refs (260 references resolve), check-size.
- No test pinned the moved text; none was edited.
- `just mod-smoke` (unsandboxed, background): 3 passed (rename row, clear row, compact row).

## Live run

Run in a throwaway repo (`git init`, one commit), unsandboxed:

```
claude -p --plugin-dir /Users/david/code/handoff --model sonnet --output-format stream-json --verbose "save handoff: we were drafting a README; next step is the install section"
```

Flags as given, no adaptation. Exit 0, 38 stream lines. The tool_use events in order, by stream line number:

```
19 Skill {"skill": "autodrive-handoff:handoff"}
23 Read {"file_path": "/Users/david/code/handoff/skills/handoff/references/files.md"}
28 Bash {"command": "handoff-checkpoint <<'JSON'\n{\n  \"skill\": \"handoff\",\n  \"commit\": \"without-commit\",\n  \"rename\": \"Draft Project README\",\n  \"clear\": false,\n  \"continue\": false,\n  \"tas...
```

The Read of `references/files.md` (line 23) precedes the `handoff-checkpoint` Bash call (line 28), with no other tool call between them. The agent made no memory write (nothing durable).
