# CLAUDE.md split — probe results

Sequencing step 2 of `proposal.md`, run 2026-10-31 on Claude Code 2.1.316 with a stub
`.claude/rules/probe.md` scoped `paths: ["scripts/**/*.sh"]` and carrying an
unguessable token. The stub was deleted afterwards.

## Can the agent create the files?

Yes. The `Write` tool created `.claude/rules/probe.md` in auto mode with no
sandbox or classifier denial, and a sandboxed `rm` removed it.

## Does a path-scoped rule reach a subagent?

Yes, on a matching read and not otherwise. Each row is a fresh
`claude -p --model haiku` in this repository; the subagent rows had the parent
read nothing and spawn one general-purpose subagent.

| Who reads                | File                      | Token seen |
| ------------------------ | ------------------------- | ---------- |
| main session             | `scripts/drive-take.sh`   | yes        |
| main session             | `README.md`               | no         |
| general-purpose subagent | `scripts/load-compact.sh` | yes        |
| general-purpose subagent | `README.md`               | no         |

The subagent reported the rule as a system-reminder carrying the file's
contents. So a convention moved into a rules file reaches whoever makes a
dispatched edit, provided the edit starts with a Read of a matching file; a
dispatch brief does not need to name the rules file.

The rule did not load in the session that created it, on a later read of a
matching file: `.claude/rules/` did not exist when that session launched. It
did load in a general-purpose subagent of that session, spawned before the
file existed, on a Bash `cat` of `scripts/drive-take.sh` (reported unprompted
by the inventory agent). So a `cat` of a matching file is enough in a
subagent, and rules files created by the split commit reach every session
launched after it and the subagents of the session that creates them.

## Does `validate-plugin` report a new finding?

No. `just validate-plugin` exits 0, and the raw
`claude plugin validate --strict --json .` lists `CLAUDE.md` and
`hooks/hooks.json` as its contents and nothing under `.claude/rules/`; its one
warning is the exempt root `CLAUDE.md` one.
