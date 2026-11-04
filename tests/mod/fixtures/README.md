# drive-take.sh contract fixtures

Each `*.json` file is the exact stdout of `scripts/drive-take.sh <cwd>` for one
sentinel case: one line of compact JSON plus a trailing newline. The token
`@ROOT@` stands for the absolute session root (the cwd, or the worktree root);
`tests/drive-take.bats` substitutes it before comparing. The mod tests
stub `process.run` with the same files, substituting the same way.

`cancel-*.json` are instead the stdout of `scripts/drive-cancel.sh`: `{kind,
message, note}`, pinned by `tests/drive-cancel.bats`. Empty stdout from it means
nothing was cancelled.

Empty stdout (no fixture) means nothing is armed for this session: no file,
`pending`, `held`, or `armed` by another session.

Choices the contract fixes for `drive-take.sh`:
- The plan is data: key order is `kind, arg, continue, failFile, message`,
  `continue` a JSON boolean; no command name or prompt text. `failFile` is
  always `<root>/.claude/autodrive.failed`, even when the plan runs nothing.
- `message` is `handoff: will run <first rendered line> once the turn ends.`
  (`/rename <arg>`, `/compact[ <arg>]`), the line a person would type.
- FR-G (`prepare`, `prepare.json`): file left `pending`, kind `prepare`,
  `arg` `""`, `continue` `false`, message `handoff: prepared for compact;
  nothing to run, frame will be re-injected.`
- Malformed: file removed, `kind` is `null`, `arg` `""`, `continue` `false`,
  message is the old `autodrive malformed — <DRIVE_ERR>; discarded, transition
  not armed.` Exit 0. The malformed check precedes the state gate.
- No session id given and the file `armed`: file left as it is, `kind` is
  `null`, `arg` `""`, `continue` `false`, `failFile` as always, and the message says the turn
  ended with no session id (`no-session.json`). The mod writes `failFile` on
  it, as for a rejected command, so the next prompt reports it.
- The lock cannot be taken (`lock-busy.json`: the wait passed with another
  actor holding it): file left exactly as it is, `kind` is `null`, `arg` `""`,
  `continue` `false`,
  `failFile` empty (the sentinel is still `armed`, so the next prompt's sweep
  deals with it), and the message names the lock. A lock that could not be set
  up at all prints the same shape with "could not be set up" for "was busy".
