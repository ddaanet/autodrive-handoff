# Memory commits go through the skill (2026-10-30)

gitlore's D70 removed the file handshake the memory directive drove. The
directive now prints the dirty listing and one sentence sending the agent to the
`gitlore:commit` skill, the same text under both commit modes. It ships as
handoff 0.19.0 together with gitlore's D70 release.

## What gitlore removed

A memory commit used to be a side effect of files. The agent wrote the approved
summary to `.claude/gitlore-memory-message`; under `without-commit` it also wrote
`.claude/gitlore-commit-memory`, which gitlore's `PostToolBatch` hook consumed to
commit standalone; under `with-commit` the message file alone left the commit to
the parent commit's pre-commit hook. The approval wording came from a file named
by `gitlore.memoryApprovalClauseFile`, and the directive refused when that key
was unset or its file missing.

D58 retired the parent pre-commit pickup. D70 retired the rest: no hook commits
memory, the two files are read by nothing, the clause file is not shipped, and
the key is no longer set. A memory commit is the agent's act through the
`gitlore:commit` skill, which owns the summary format and the approval protocol
(show the summary, end the turn, run `gitlore-commit` with the approved text on
stdin once the reply approves it). `gitlore-commit` stages the moved memory
gitlink in the parent index. Separately, gitlore stopped reading
`gitlore.precommitCommand` and its install deletes the key, so this repo's claim
that `just precommit` runs on every memory commit went with it.

## The two failures against gitlore `dev`

Gitlore's inbox note of 2026-10-30 described both; each leaves the agent unable
to commit memory, and the second says nothing:

- On a fresh install the clause key is unset, so the directive refused and told
  the agent to restart and retry. A restart cannot set a key gitlore no longer
  sets: the advice looped.
- Where a stale key survives from before D70, the directive wrote the message
  and trigger files, which nothing consumes. Memory stayed uncommitted with
  nothing reporting it, under both modes.

## The change

`memory_directive(root)` returns a plain string: under the same gate as before
(registered, materialized, `status --porcelain` non-empty) the status listing and
one sentence — commit through the `gitlore:commit` skill, invoked before a
summary is drafted. Gone with the mechanism: the message and trigger files, the
mode split, the clause lookup and its refusal, and `MemoryPart` (a directive that
cannot refuse has nothing to carry beside its text). `compose_directives` loses
the refusal branch; the part order is unchanged. `commit_directive` takes
`memory: bool` and, when memory was owed, adds the gitlink to what the commit
includes.

**Point at the skill; do not restate it.** The summary format changed in the same
gitlore release (one section per store), which is the drift a copy invites.
Whatever the directive copies is a second
owner that drifts, and whatever mechanism it narrates (the command, the stdin
form, what the script stages) is something the reader cannot act on and gets
verified back. The reader needs the skill's name and the order: invoke it before
drafting. The earlier decision to withhold the trigger filename
([Commit awareness](2026-07-25-commit-awareness.md)) was this cut applied to one
identifier; the identifier is gone, and the cut now removes the whole protocol.

**The listing stays.** It is what tells the agent that memory is owed at this
boundary at all, and the hold rule keys on the directive being emitted.

**The gitlink is named.** `gitlore-commit` stages the moved memory gitlink in the
parent index, and the commit act is the one place that says what the commit
includes. Left unnamed, an agent that stages the two files by path commits the
source change and leaves the pointer floating in the index for a later commit.
It is named only when memory was owed: with clean memory no gitlink has moved,
and the sentence stays byte-identical to what it was.

**The hold rule is unchanged.** The turn still ends on the summary awaiting
approval, so a sentinel that names a command and a memory directive still holds
until `handoff-approved`, and a driven `with-commit` transition still holds
behind the commit. Under `with-commit` the approval now takes a turn before the
parent commit rather than riding inside it.

**The commit answer no longer decides where memory lands.** Both modes commit
memory immediately, in its own repository; the mode now decides only whether a
parent commit follows and whether the gitlink is in it. A wrong answer to *does
the ask imply a commit?* therefore costs a parent commit that is made or
skipped. It no longer strands an approved summary on the far side of a `/clear`,
which was the hazard [Transitions become
modes](2026-08-05-transitions-become-modes.md) named for the deferred path.

## No shim

The directive needs a gitlore that ships `gitlore:commit`. Detecting the old
protocol and speaking it would keep alive a handshake no gitlore release
consumes, and both plugins are the maintainer's and release together: 0.19.0
goes out with gitlore's D70 release. A repository on an older gitlore updates it
before taking this version; the plugin names no gitlore version number, since the
skill's existence is the contract.

## Rows

Dirty memory prints the status line and the exact sentence and none of the
retired words (the file names, the clause key, `trigger`); the memory part is
byte-identical under both modes; the commit act names the gitlink with dirty
memory and is today's sentence exactly with clean memory. The clause-file
refusal rows, the trigger-file rows, `unset_clause_file` and the clause setup in
the repository builders are deleted with the mechanism. Mutation-checked: the
commit act ignoring `memory`, in both directions, and the memory part differing
by mode.
