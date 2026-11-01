# Seam C: `scripts/report-drive-failure.sh` under the byte cap

## Byte counts

| File | Before | After |
| --- | --- | --- |
| `scripts/report-drive-failure.sh` | 21821 | 17089 |
| `docs/design/driving-the-transition.md` | 19083 | 19317 |
| `docs/design/sessions-sharing-a-root.md` | 7798 | 7871 |
| `docs/design/sentinel-lock.md` | 8485 | 8556 |
| `docs/design/scoping.md` | 7502 | 7733 |

`docs/design/queued-prompts.md` (5049) is unchanged. The script's `size.exempt`
line is deleted; `CLAUDE.md`'s routing row gains "the sweep's `foreign` state".

## Per block

Only comment lines changed in the script. The check
`git diff -U0 scripts/report-drive-failure.sh | grep '^[-+][^-+#]' | grep -v '^[-+][[:space:]]*#'`
printed nothing.

**Header (old 2-51).** Already in a node and dropped: the mod's non-delivery and
the unchecked `pending` inference (driving-the-transition sweep section); the
stale file firing days later into unrelated work; the mod-not-loaded causes and
versions; the `prompt_id` test, the per-session prompt marker and the
rename / clear / compact outcomes (queued-prompts.md); the owner, the liveness
test and the `held` exemption (sessions-sharing-a-root.md); lines offered only
to the owner (driving-the-transition.md); the drift marker (scoping.md). Added
to nodes:

- driving-the-transition.md, sweep section: "The mod writes the record only on a
  rejection it observed itself."
- Same section, the aborted-turn cause: "an aborted turn (an Esc, which fires no
  `Stop`, a crash or a quit)".
- scoping.md, drift paragraph: "Nothing else announces that, and it is silent in
  both directions: the environment block, `gitStatus` and the project
  `CLAUDE.md` all follow cwd, while the transcript, the scratchpad,
  `CLAUDE_PROJECT_DIR` and every handoff file do not, so the agent reasons about
  the repo under cwd while the plugin reads and writes the one under the root."

Kept: the three jobs, one line each with pointers (job 2 names no causes), and "It fires on every
prompt, so the no-file path must be silent and cheap."

**Lock block (old 191-202).** Already in sentinel-lock.md: the interleaving,
the lock covering `record_sweep` and the stranded-`pending` removal, the fail-
closed busy and unavailable causes, locking only when a sentinel is on disk.
Added to sentinel-lock.md, in the sweep bullet: "(its state `locked`, as
`unread` is for a reader that could not run)". Kept: held from the read to the
exit so the decision and every removal are one step; a lock not taken leaves the
file unjudged (state `locked`, as `unread` is); taken only for a file that is
there so the ordinary prompt forks nothing; the second test is for a file
removed while the lock waited.

**Owner and `held` block (old 230-246).** Everything was already in
sessions-sharing-a-root.md (Liveness, The `held` exemption), so nothing added
there for this block. Added the `foreign` naming, below. Kept: another session's
live `armed` file is reclassified `foreign`, left untouched, nothing said; only
`armed` is asked about liveness, `held` never.

**Queued block (old 291-300).** Everything already in queued-prompts.md (what
the id and marker are, reading only for an armed file this session owns, the
unsettled-marker cases). Nothing added. Kept: only an armed file this session
owns is judged against the marker, so an ordinary prompt forks nothing and
nothing is written; `marker_unsettled` is the input-has-an-id-and-marker-could-
not-answer flag.

**Sweep state-list block (old 314-323).** Already in the sweep section: an
`armed` file not taken unless queued; `held` exempt. Added:

- driving-the-transition.md, sweep section: "`held` is exempt whoever owns it: it
  waits on an approval whose answer arrives at this very hook, so surviving the
  turn boundary is what it is for, and that is why the sweep names its states
  rather than taking anything that is not `pending`." (the reason was missing)
- sessions-sharing-a-root.md, Liveness, after "left untouched and nothing is
  said": "(the sweep classifies it as the state `foreign`, which it never
  removes)".

Kept: the sweep names its states instead of taking anything not `pending`;
`held` is exempt whoever owns it; another session's live `armed` file is
`foreign`, not this session's to take; pointers to both nodes.

## Gate

`just precommit` passed: bats, shellcheck and pytest (520 passed, 3 deselected)
under `check-code`, `check-plugin`, `check-refs` (261 references) and
`check-size` (233 files; `size.exempt` 4 entries, each still needed). A first run
finished while the header comment was being shortened and recorded no pass; the
second run, on the final tree, is the one reported. The non-comment-line check
was re-run on the final tree and printed nothing.

## Doubts

- The sweep-block comment no longer lists the excluded states (`pending`,
  `held`, `foreign`, `unread`, `locked`); the condition beneath lists them, and
  `unread` and `locked` are named in the lock and driving nodes. Listing them in
  prose would be a second copy of the code.
- The new `held` sentence puts the reason in the sweep section, which already
  held the exemption; the "Sessions sharing a root" node argues the same
  exemption from the other side (human approval takes as long as it takes).
  Both stand.
- Pointers in the script cite node file names, not anchors, except the header's
  section title, to stay short.
