# drive-take.sh contract fixtures

Each `*.json` file is the exact stdout of `scripts/drive-take.sh <cwd>` for one
sentinel case: one line of compact JSON plus a trailing newline. The token
`@ROOT@` stands for the absolute session root (the cwd, or the worktree root);
`tests/drive-take.bats` substitutes it before comparing. The mod tests
stub `process.run` with the same files, substituting the same way.

Empty stdout (no fixture) means nothing is armed for this session: no file,
`pending`, `held`, or `armed` by another session.

Choices the contract fixes for `drive-take.sh`:
- Key order is `kind, before, after, failFile, message`; `failFile` is always
  `<root>/.claude/autodrive.failed`, even when the plan carries no lines.
- `message` is `handoff: will run <before[0]> once the turn ends.`
- FR-G (`compact` kind line alone): file left `pending`, `before`/`after` `[]`,
  message `handoff: prepared for compact; nothing to run, frame will be
  re-injected.` (old wording, `$k` fixed to the kind).
- Malformed: file removed, `kind` is `null`, lists empty, message is the old
  `autodrive malformed — <DRIVE_ERR>; discarded, transition not armed.`
  Exit 0. The malformed check precedes the state gate.
