## Brief: handoff must carry the session-start skill across the clear

2026-09-25

Written from a session in the `Emploi` repo (private job-search repo, governed
by the `candidature` skill in `../candidature`) that resumed from a handoff and
silently did the wrong thing.

### The failure observed

The previous session ran `/handoff` with a typed transition. The task file, the
todo file and the continuation prompt all landed correctly. The continuation
prompt was:

> recap the Goodvest state from the task and todo files, then re-pose the six
> open decisions to the candidate and start drafting the four texts as they
> answer

The fresh session executed it verbatim: read the dossier, drafted a recap,
started posing decisions — **without ever loading the `candidature` skill**,
which is what governs every rule the work depends on (etayage against the
candidate sheet, cover-letter structure, relecture protocol, submission steps).
Nothing errored. The work simply proceeded outside the rules that apply to it.

The session had every cue and none of them fired: `CLAUDE.md` names the skill
and its location, the task frame described a `candidature`-shaped task in
`candidature` vocabulary, and the prompt named a `candidature` action. Prose
cues are not a mechanism.

### Proposed fix

Add a question to the `handoff-checkpoint` payload, answered at Step 2 with the
other decisions: **which skill the next session must load at start**, accepting
an explicit `none`.

Two effects, both needed:

1. **Forcing function on the outgoing session.** Like `commit` and `clear`, the
   field has no default — considering the question is the contribution. The
   outgoing session is the only one that knows a skill governs the work; the
   incoming one, by construction, does not yet.

2. **Validation of the continuation prompt.** When the answer names a skill and
   `continue` is non-null, the checkpoint rejects a `continue` that does not
   begin with that skill's trigger. The prompt above would have had to read
   `/candidature recap the Goodvest state from the task and todo files, …`, and
   the fresh session would have entered the skill before touching anything.

`none` must be a real, accepted answer — most repos have no governing skill, and
forcing one invented would make the field a formality rather than a decision.

### Constraints

- The payload already has a `skill` key, carrying the *calling* skill
  (`"skill": "handoff"` / `"precompact"`). The new field needs a different name.
- `precompact` calls the same checkpoint. Decide whether the field applies there
  too: a compaction keeps the conversation, so the skill may already be loaded —
  but after a long compaction that is not guaranteed.
- The constraint only binds when a skill is named *and* a typed transition
  carries a `continue`. Named skill with `continue: null` is legal (nothing is
  typed, nothing to validate).
- Trigger form is repo-specific (`/candidature`, `/ddaa:brief`, a plugin-scoped
  name). The checkpoint cannot verify the skill exists; validating the prefix
  literally against the answered value is enough.
- The continuation prompt must stay a single line, and must still carry a handle
  plus the next action — the trigger prefixes it, it does not replace it.

### Rejected approaches

- **Documenting it in the SKILL.md prose** ("name the governing skill in the
  prompt"). This session is the counterexample: prose available to the model at
  the moment of the decision did not produce the behaviour. The point of the
  checkpoint question is that the payload is rejected without an answer.
- **Putting the instruction in the task file body.** Same failure: the task file
  was re-injected in full and read, and the skill still was not loaded. A fact
  in the frame is not an action taken.
- **Auto-detecting the skill from `CLAUDE.md`.** The checkpoint would have to
  guess which of several referenced skills governs *this* task; the outgoing
  session already knows.

### Additional context

Repo where the failure occurred: `/Users/david/code/Emploi`, skill at
`/Users/david/code/candidature` (public, never modified from an `Emploi`
session). The task frame from the failed resume is still in that session's
`handoff-task.md` / `handoff-todo.md` if the wording is wanted verbatim.

Relevant handoff files: `skills/handoff/SKILL.md` Step 2 (decision list and
payload shape), the "seam" section (what the prompt may carry), and
`skills/handoff/references/design.md`.
