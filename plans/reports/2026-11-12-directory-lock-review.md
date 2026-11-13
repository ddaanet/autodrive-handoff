# Review: 21db19a "take the sentinel's lock on .claude/ itself, leaving no lock file"

Method: `code-review medium HEAD~1..HEAD` (forked skill run), triaged and
probed by hand. Probes ran against a `git archive HEAD` copy in `$TMPDIR` and
against the repo's scripts sourced read-only; nothing in the repo was edited.

Gates run on the copy: `bats tests/sentinel-lock.bats tests/drive-take.bats
tests/bin-commands.bats tests/drive-cancel.bats` exit 0, 69 `ok`, 0 `not ok`;
`pytest tests/test_drive_lock.py tests/test_checkpoint_readback.py
tests/test_checkpoint_root_files.py` 65 passed. Mutant spot-check on the copy:
replacing `wait`'s device/inode comparison with `if False:` reds exactly
`test_wait_refuses_a_descriptor_that_is_not_what_the_path_names` (1 failed,
27 passed), as the commit body says.

Checked and found sound (no finding):

- Same inode for every actor in every root shape. Every bash actor passes
  `$root/` or `$cwd/` + `HANDOFF_REL_DRIVE_LOCK_DIR`, the same base each used
  for the old lock file, so the root resolution is unchanged by this commit.
  Python follows a `.claude` link (`os.open` without `O_NOFOLLOW`), bash's
  `exec 9<` follows it, and `wait` compares with `os.stat`. Probe: a holder
  locks `lp/real` directly, `handoff_lock_take lp/root/.claude` (a link to
  `../real`) with `HANDOFF_LOCK_WAIT_SECS=0.2` returned `1` (busy) on 8/8 runs.
- fd 9: on `[[ -d ]]` failure nothing is opened; on a failed `exec` nothing
  is opened; on any `wait` failure `exec 9>&-` closes it before returning;
  on success it is held by design. No path leaks it. Python's `os.open` fd is
  non-inheritable, so the checkpoint's read-back child does not hold it.
- No test row passes vacuously. Each `fail_lock_helper` row asserts the
  "could not be set up" message, which a take that skipped the lock (rc 0)
  would not produce. The checkpoint's ENOLCK row asserts the message and the
  empty `.claude/`. In `tests/test_drive_lock.py` the old `create`/0600/
  `O_NOFOLLOW` rows are replaced by rows on the directory: no new entry
  (Python and bash), a link followed to the same inode (Python and bash),
  non-directory shapes unavailable (absent, file, fifo, dangling link,
  link to file), `wait` refusing a swapped directory and a regular file,
  and `create` now a usage error. Line 245's `autodrive.lock` is that last
  row's target, used to assert nothing is created.
- NFS (raised by the skill run, checked and dropped): the `man 2 flock` rule
  that an exclusive lock on NFS needs a descriptor open for writing applies
  through `nfs_flock`, which only regular files reach.
  `nfs_dir_operations` in mainline `fs/nfs/dir.c` defines no `.flock` or
  `.lock`, while `nfs_file_operations` and `nfs4_file_operations` do. So
  `flock` on an NFS directory falls back to a local lock, which works on a
  read-only descriptor and is enough for actors on one host. This was read
  from the kernel source, partly through a fetch summary, and not run on a
  mount.

## Medium

### M1. The new rejected-alternative's reason for ruling out a lock outside the tree is contradicted by a probe and by the plugin itself

- `docs/design/rejected-alternatives.md:249-251`: "A lock outside the tree
  fails because the checkpoint runs in the command sandbox and the hooks do
  not, so they share no writable location but the root."
- Defect: `/tmp/claude` is writable from the command sandbox and is already
  written by the plugin's unsandboxed hooks (`HANDOFF_POINTER_DIR`, default
  `/tmp/claude`, `scripts/_lib.sh:60`; README rows for
  `/tmp/claude/handoff-drift-*` and `handoff-prompt-*`).
- Failure scenario: a later reader takes "a lock outside the tree" as
  impossible on a false premise (the hub, `docs/design.md`, lists it as ruled
  out), and the real reasons, if any, go unrecorded.
- Evidence: from this agent's sandboxed Bash,
  `touch /tmp/claude/review-probe-$$ && echo sandboxed-write-ok` printed
  `sandboxed-write-ok`; `grep -n tmp/claude README.md scripts/*.sh` shows
  README.md:212-213 and `scripts/_lib.sh:60`.
- Smallest fix: replace the reason with one that holds (for instance that a
  lock under `/tmp/claude` must be keyed by the resolved root path, which a
  link, a worktree or a moved checkout makes ambiguous, if that is the real
  reason), or drop the "outside the tree" half of the entry and its hub line.

## Low (declined)

- `scripts/_lib.sh:98-108`: the comment says the `-d` test "keeps bash from
  opening anything else, a FIFO say", but `[[ -d ]]` and `exec 9<` are two
  steps; a FIFO swapped in between would block the read-only open (the old
  `9<>` could not block). Needs an adversarial swap of `.claude`, which
  nothing produces; at most soften the comment.
- Mixed versions: an old-version actor locks `.claude/autodrive.lock`, a
  new-version one locks `.claude/`, so they do not exclude each other during a
  mid-session plugin update. Transient and rare.
- `docs/design/sentinel-lock.md:115`: the safety argument rests on nothing in
  the plugin removing `.claude/`; a user's `rm -rf .claude` while a bash actor
  holds fd 9 lets the checkpoint lock a new inode. Python `locked()` does no
  inode re-check. Requires deleting `.claude/` mid-transition.
- `scripts/checkpoint.py:253,259`: the messages hard-code `.claude/` instead
  of interpolating `HANDOFF_REL_DRIVE_LOCK_DIR`; drift only if the constant
  changes.
- `docs/design/sentinel-lock.md:139-145`: "a second row per actor gives the
  unavailable cause" while `tests/drive-cancel.bats` has a busy row
  (line 135) and no unavailable row; the sentence's own file list omits
  drive-cancel.bats, and the gap predates this commit.
- `scripts/load-compact.sh:45`: an unreadable but writable `.claude` reports
  "lock could not be set up" without naming permissions as the cause. No
  realistic producer.
- `scripts/_lib.sh:33` points at `driving-the-transition.md`, "The sentinel's
  lock"; that section exists (line 219) and links on to `sentinel-lock.md`,
  so the pointer resolves, one hop longer than needed.
- `scripts/_lib.sh:80`: `handoff_lock_take`'s header still names its argument
  `<lockfile>`; it is now the `.claude` directory. Stale wording only.

END OF REVIEW
