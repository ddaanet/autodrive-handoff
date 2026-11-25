# Symmetric session files, the Vibe compact seam, and the coupled release

Decisions my human partner made on 2026-11-25, mid-release (`edify:release`
had finished steps 2–5 on `dev`, last commit `2be7e3b`; step 6, ship, not
started). Recorded here verbatim with their reading; the next session
implements them, then ships.

## Decision 1 — the tagged release carries both manifests at one version

Asked whether the tag may carry a Vibe manifest one release behind (the
toolkit's `release.sh` bumps and tags `.claude-plugin/plugin.json` alone):
"no lag by one, that's nonsense". Offered (A) a Vibe-manifest bump commit
*before* `just release`, with `check-versions` accepting the Vibe manifest
equal to the Claude one or exactly one patch/minor/major bump ahead, so the
release's bump commit is the one where they meet and that commit is tagged;
or (B) a toolkit hook in claude-plugin-dev. Answer: "A: vibe and claude
plugins are interdependant but separate".

Reading: option A. The Vibe surface's bump is its own commit, made ahead of
the release; the gate enforces the coupling. This replaces the post-release
sync commit in `docs/design/release-infrastructure.md` ("The Vibe surface
and the coupled version") and the 2026-11-25 coupling entry in
`docs/design/decisions.md`; both get rewritten, with the reason
("interdependent but separate": no lag at the tag, no toolkit change).

## Decision 2 — Vibe precompact drives no compaction and needs no seam guard

Asked about the compaction-prompt guard missing a non-plugin custom prompt:
"that's nonsense. There is no way to drive compaction in vibe. So
precompact just does the memory flush and update the handoff files."

Reading: under Vibe, `precompact` is the memory flush plus the TASK.md /
TODO.md update, then the closing line naming `/compact` for the user. The
compaction-prompt guard (`compaction_prompt_guard`, `_compaction_prompt_id`,
`_vibe_home` in `vibe-plugin/scripts/_checkpoint_lib.py`, its tests, its
skill and doc prose) goes. Open at implementation: whether
`vibe-plugin/prompts/compaction.md` and README install step 3 stay at all
once TASK.md survives (see decision 3) — recommendation: keep only a short
optional prompt that tells the summary to send the next turn to re-read
TASK.md and TODO.md from disk, or drop it if the AGENTS.md loader line
already covers the compacted session; settle by reading what Vibe's
`/compact` keeps and whether the loader line fires again.

## Decision 3 — precompact stops removing TASK.md; handoff and precompact symmetric

"By the way, precompact should stop clearing TASK.md, it's causing
confusion. Make precompact and handoff symmetric in session files
handling."

Reading: in both surfaces (the Claude plugin's `skills/precompact` +
`scripts/` write path and the Vibe fork), `precompact` handles TASK.md
exactly as `handoff` does: it carries `task` (content, keep, edit, clear —
the same field, rules and FR13 shape) as well as `todo`. This reverses
"precompact removes TASK.md" and "Only handoff carries task" in
`CLAUDE.md`, `docs/design/the-skills.md`, `docs/design/the-write-path.md`,
`docs/design.md` (FR13 and wherever precompact's TASK.md removal is
stated), the precompact skill (templates and rules move in, mirroring
handoff), `_checkpoint_payload.py` (`validate_task`'s precompact branch)
in both trees, `load-compact.sh` if it reasons about TASK.md's absence,
and every test pinning the removal. If the scope looks wrong once the code
is read — say, the confusion is Vibe-only — stop and ask before the Claude
side changes.

## Sequence

1. Decision 3 (+ decision 2's guard removal), dispatched per
   `edify:dispatch`, gate, commit, `/code-review medium` loop per
   `edify:review`.
2. Decision 1: `check-versions.sh` + `tests/check-versions.bats` + the two
   doc nodes, gate, commit, review.
3. Ship (`edify:release` step 6, `plugin-dev` 0.17.1 ≥ 0.16.0 so all on
   `dev`): tier `minor` (precompact's payload gains `task`, an installed
   setup change). Bump `vibe-plugin/plugin.json` to the next minor in its own
   commit, push `dev`, `/ddaa:preflight`, `just release minor` — bumps
   `handoff` (tag + GH release) and `claude-plugins` (marketplace entry) —
   then push `dev`.
