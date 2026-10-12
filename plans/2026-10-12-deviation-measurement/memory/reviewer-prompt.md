You are reviewing proposed memory commits against a set of written rules. This is a
measurement: your verdicts will be compared with decisions taken elsewhere, so apply
the rules as written and nothing else.

## What you may read

Exactly these seven files, and no others. Do not list directories, do not search the
filesystem, do not read any other file or any transcript, and do not use the network.

- /tmp/claude/handoff-measure/memory/blind/rules.md
- /tmp/claude/handoff-measure/memory/blind/records-1.md
- /tmp/claude/handoff-measure/memory/blind/records-2.md
- /tmp/claude/handoff-measure/memory/blind/records-3.md
- /tmp/claude/handoff-measure/memory/blind/records-4.md
- /tmp/claude/handoff-measure/memory/blind/records-5.md
- /tmp/claude/handoff-measure/memory/blind/records-6.md

Each records file is about 40-50 KB. If a read comes back truncated, read the rest
with an offset before judging; never judge a record you have not read in full.

## The situation each record describes

An agent has written or edited facts in a repository's memory store and is about to
commit them. It shows its user a summary of the pending memory changes and waits for
approval. Each record is one such moment: the repository's name, which stores existed
at the time, the files the gate listed as changed (when known), the agent's message
proposing the summary, and excerpts of the memory edits made earlier in that session
(when known; excerpts are cut short and some records have none).

A fact can live in one of these places:

- `project-memory` — the repository's own memory store
- `shared-tier` — a memory tier shared by several repositories (`memory/ddaanet/`),
  only where the record says it exists
- `always-loaded` — a file loaded whole into every session (`CLAUDE.md`, or the shared
  `memory/ddaanet/shared-claude.md` where the record says it exists)
- `skill` — the body of a skill or agent definition that owns the activity
- `code-or-tool` — the code, hook, template or tool that owns the behaviour, including
  its own runtime output
- `design-doc` — a design document or other project documentation
- `todo` — the todo list or task file
- `nowhere` — it should not be recorded at all

## Your task

Read `rules.md` first. Then, for every record `P001` … `P084`, decide whether the
written rules require any fact in the proposal to live somewhere other than where the
agent put it. Judge destination only: do not report wording, body style, index-line
quality or factual doubts. A fact that the rules say should be discarded has the
destination `nowhere`.

Both kinds of error cost the user something. A redirection you raise that the rules do
not actually require costs them a correction at the approval prompt; one you miss
costs them a redirection they have to make themselves. Raise a redirection when the
rules, applied to what the record shows, call for it, and say `high` or `low` for how
clearly they do. The skill listing in your own context shows which
skills are installed today; you may use it to name an owner. Beyond that and what a
record itself mentions, you do not know which hooks or documents exist; where a rule
points at an owner you cannot name, give the destination category and say so in the
reason.

## Output

Write one JSON object per line to
/tmp/claude/handoff-measure/memory/blind-verdicts.jsonl, one line per record, in
record order, 84 lines in all. Work through one records file at a time and write its
verdicts before reading the next, appending to the output file (for example with a
Bash heredoc using `>>`), so nothing is lost. Do not create any other file.

A record with no objection:

    {"id": "P001", "verdict": "no-objection"}

A record with one or more redirections:

    {"id": "P002", "verdict": "redirect", "redirections": [{"fact": "<tier/slug or a few identifying words>", "from": "<place>", "to": "<place>", "rule": "SKILL §1 Q2", "confidence": "high", "reason": "<one sentence>"}]}

`from` and `to` take the place names listed above. `rule` cites `rules.md` the way its
first paragraph says: `SKILL §<n>` with `Q<k>` for a numbered question of §1, `TIER`,
or `SHARED`. List only the facts you would redirect.

When all 84 lines are written, reply with exactly one line:
`verdicts: /tmp/claude/handoff-measure/memory/blind-verdicts.jsonl`
