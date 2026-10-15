# Handoff-continue at a context threshold, and a fixed continuation

## Context

Evidence: the previous session (the 0.16.0 move to the root, 5.3 MB, 226 API
calls) ran steps 4 to 6, the dogfood and the handoff in one context. 130 of
its calls ran at 91k-448k tokens and carried 40.6M of the 53.7M summed
context tokens. Tool results were 680 KB; the cost was re-paying a large
prefix, not any one read. A boundary at about 200k would have cut that tail.

Two changes, independent, in this order:

1. **The continuation becomes a constant.** After a driven `/clear` or
   `/compact` the mod submits a fixed `Continue per handoff`. The payload
   stops carrying a continuation line, so an agent can no longer pass a task
   description through that channel; the task and todo files are the only
   carrier.
2. **A two-tier context hook.** `PostToolBatch` measures the main thread's
   prompt and injects a directive once at a soft threshold (default 150k) and
   once at a hard one (default 200k). The hard directive tells the agent to
   run the handoff skill as clear-and-continue now.

This re-opens a decision. A single-tier nudge (150k, naming
`/handoff:precompact`) was built on 2026-08-01 and removed on 2026-08-10,
see `docs/changelog/2026-08-10-drop-context-threshold-nudge.md` and the
paragraph "A context-size nudge was tried and dropped" in
`docs/design/decisions.md`. The reasons then were a premature fire on a
legitimately large context, a fire right after a driven compaction, and a
directive "sometimes followed, sometimes ignored" with no record of which.
Step 2 answers each below; it is not a retry of the old design with a
different number.

Starting point for step 2's script: `git show d964474^:scripts/context-threshold.sh`
(the last version, with the 2026-08-09 compaction scoping). Its tests are in
`git show d964474^:tests/hook-test.bats`.

## Decided

- Two tiers, defaults 150k and 200k, both overridable by the user.
- Soft wording is a preference at a boundary: "at the next step boundary".
  Hard wording is imperative: "Context budget exceeded. Handoff-continue now."
- The remedy at both tiers is clear-and-continue through the handoff skill.
  `/compact` stays available on request and is not what the hook names.
- The continuation text is `Continue per handoff`, one constant, both
  boundaries.

"Plan phase" is edify vocabulary and means nothing without it. The soft
directive defines the boundary by the act: *finish the work item you are on
(tests pass, change committed or its remainder written to `TODO.md`), then
run the handoff before starting the next one.*

## Step 1: the continuation is a constant

Contract.

- `continue` in the checkpoint payload is a required boolean. `true` is legal
  only when the transition is carried out (`clear: true`, or `compact` true or
  a focus directive); `false` otherwise. `null`, a string, a missing key and
  `true` against a non-driven transition are rejected, each naming the field.
- The composer writes the literal line `Continue per handoff` where it wrote
  the agent's prose. The sentinel's shape and `handoff_drive_read` do not
  change; only the bytes of that one line become constant. `require_one_line`
  and the `/` check on `continue` go, since nothing authored reaches it.
- Both skills lose the "Is there a continuation prompt?" prose and the
  good/bad examples at the end of `handoff`'s seam section. They keep one
  sentence: whether to continue after the reset is a boolean the user's ask
  decides.
- The constant is defined once, in the composer, and read back by name by
  every consumer; tests assert against that definition, not a retyped string.

Touches: `scripts/checkpoint.py` (the `continue` validation, the composer),
`skills/handoff/SKILL.md`, `skills/precompact/SKILL.md`,
`tests/test_checkpoint.py` (the `continue` matrix and the six legal sentinel
rows), `tests/mod/fixtures/*.json` and the regenerated `fixtures.ts`,
`tests/drive-take.bats`, `tests/test_mod_live.py`, and the prose in
`README.md`, `CLAUDE.md`, `docs/design/the-skills.md`,
`docs/design/driving-the-transition.md`, `docs/design/the-write-path.md`.

> **Corrected at review, 2026-10-15.** The list above says the `continue`
> validation is in `scripts/checkpoint.py`, the rows are in
> `tests/test_checkpoint.py`, and (in the contract) `require_one_line` goes.
> Three things were wrong when written. `validate_continuation` is in
> `scripts/_checkpoint_payload.py`; `scripts/checkpoint.py` holds the composer
> and the constant. `tests/test_checkpoint.py` does not exist (`ls` finds no
> such file): the `continue` rows are in `tests/test_checkpoint_transition.py`,
> with the payload builders in `tests/conftest.py`, and the other
> `tests/test_checkpoint_*.py` files carry `"continue": None` payloads that
> became `False`. `require_one_line` is not removed: the `compact` focus
> directive still goes through it (`scripts/_checkpoint_payload.py`); only its
> use on `continue`, and the leading-`/` check, went. The rest of the list
> stands, with `tests/test_mod_fixtures.py` added for the row that ties every
> fixture prose line to the constant.

Verification: pytest, bats and `claude plugin test` green; `just mod-smoke`
shows the continuation arriving as the next session's first user prompt with
the new text. Mutation-check: the composer writing the agent's string
through, and the validator accepting a string.

0.16.0 is unreleased and already breaking, so this rides it.

> **Corrected at review, 2026-10-15.** "0.16.0 is unreleased and already
> breaking, so this rides it" was false when step 1 landed: `git tag` lists
> `v0.16.0` (commit dated 2026-10-11) and `v0.16.1` (2026-10-15). Step 1
> changes the payload's `continue` field, so it is a breaking change of its own
> and takes the next minor release, not an already-open one. The contract
> above stands.

## Step 2: the two-tier hook

Contract. `scripts/context-threshold.sh`, registered for `PostToolBatch`
with `timeout: 5`, stdin JSON in, optional `hookSpecificOutput` out. Not
cwd-scoped.

Measurement.

- Exit at once when `agent_id` is present (a subagent has no boundary to
  prepare, and `transcript_path` there names the parent file).
- Read the main transcript's tail, take the last `message.usage` sample
  newer than the last `isCompactSummary` entry, sum input, cache-creation and
  cache-read tokens. No sample after the last compaction means nothing is
  measured and nothing fires; never fall back to the sample above the
  boundary (see memory `session-jsonl-schema`).
- Outlier rule is decided from evidence, not assumed: inspect the entries at
  11:45 and 12:29 of session `8148578c-cd8c-4069-8ddb-c5d254b7d265` (481k
  and 846k against neighbours of 243k and 423k). If they are real transcript
  entries, the hook requires the last two distinct `message.id` samples to
  both cross a threshold; if they are an artefact of the earlier analysis, the
  rule is one sample.

Firing.

- Per-session markers under `HANDOFF_POINTER_DIR`: one for the soft tier,
  one for the hard. A tier whose marker exists never fires again. Crossing the
  hard tier from below the soft one fires the hard directive only and writes
  both markers.
- `session-pointer.sh` removes this session's markers on every
  `SessionStart` source, as the old design did: re-arming is the harness's
  signal that the context was rebuilt, never an inference from a smaller
  number. A `/clear` gets a new session id and so fresh markers anyway.
- A marker carries tier, size and a timestamp, so whether the agent obeyed is
  answerable afterwards: a handoff checkpoint or a `SessionStart(clear)`
  following the marker, or not. The old design could not tell.
- The user-facing `systemMessage` leads with the ANSI reset and names the
  size and the threshold, so a handoff that starts on its own has a stated
  cause.

Directives (wording written with `craft:directive-writing`; acts, no
narration). Draft intent, not final text:

- Soft: the prompt is N tokens, past the soft threshold. Finish the work item
  you are on, then run `/handoff:handoff` as clear-and-continue before
  starting another. If background agents are running, let them finish first.
- Hard: "Context budget exceeded. Handoff-continue now." Stop starting new
  work, run `/handoff:handoff` as clear-and-continue in this turn. If
  background agents are running, wait for their notifications first.

The background-agent clause is conservative on purpose; the probe below
decides whether it stays.

Configuration. `plugin.json` gains `userConfig` with two `number` options
(soft, hard; defaults 150000 and 200000, `min` set), read in the script
through `CLAUDE_PLUGIN_OPTION_*`. The script also falls back to the literal
defaults, so an unconfigured or older host behaves the same. A soft value not
below the hard one disables the soft tier. Values live in
`pluginConfigs` in user settings only; project settings entries are ignored
by the host, so there is no per-repo threshold.

Tests (bats, synthetic transcripts): below soft is silent; between fires soft
once; over hard fires hard once; soft fired then hard crossing fires hard;
a jump over both fires hard only; neither repeats; a subagent payload is
silent; samples above the last compaction are ignored and none after it is
silent; no transcript, no usage, a partial first line are silent; a
re-arm after each `SessionStart` source; both configured values, a
misordered pair, and none set. Mutation-check the compaction scoping, the
subagent skip, once-per-tier and hard-over-soft.

Docs, same pass: a changelog entry that reverses the removal, with a
`Superseded` blockquote at the head of the 2026-08-10 entry scoped to what
changed; the paragraph in `decisions.md` rewritten; README gets the two
options; `CLAUDE.md` gets the hook, the script and the userConfig.

## Step 3: probes and dogfood (not started; deferred by my human partner)

- **Background agents across `/clear`.** Start a background unnamed agent,
  trigger a driven clear-and-continue, and observe whether the agent
  completes, is killed, or its notification is lost, and where it lands. The
  result decides whether the "wait for background agents" clause stays. The
  stub rig cannot answer this; it needs a live run in the `mod-smoke`
  style.
- **`CLAUDE_PLUGIN_OPTION_*` naming and defaults.** Confirm the exact
  variable name for a declared key, and whether a default reaches the
  environment when the user never configured the option.
- **`PostToolBatch` payload.** Confirm `agent_id` is present when a subagent's
  batch resolves and absent on the main thread; the docs list `tool_calls`
  and no agent fields for this event.
- **Dogfood.** Run the hook in a real session with both thresholds lowered to
  a few thousand tokens, then watch one session cross both tiers and obey.
  Needs a restart, since `hooks.json` is frozen at session start.

## Open decisions

1. Does the hard tier repeat if ignored (once per further 50k, say), or is the
   stronger lever a `continue: false` halt? Default: neither. Fire once per
   tier, and reopen only when an ignored hard directive is observed in the
   marker log, as the 2026-08-01 design reasoned.
2. Fold step 1 into 0.16.0? Default: yes, nothing is released.

   > **Corrected at review, 2026-10-15.** "Default: yes, nothing is released"
   > was wrong: 0.16.0 and 0.16.1 are tagged (`git tag`). The default was not
   > available; step 1 ships as its own breaking change.
3. Which boundary does the hook name once `handoff` is not what the user
   wants (a session with no task file worth keeping)? Default: always
   `handoff`; the user can run `/compact` by hand.

## Out of scope

The delegation and scope lines for `shared-claude.md` (already applied), a
per-repo threshold, a `/compact` remedy, and any change to the held/approved
mechanics.
