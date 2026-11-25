## Open decisions

- Whether check-versions should also refuse when a tag for the current Claude version exists and that tag's vibe-plugin/plugin.json differs from it. Without it, a Vibe bump of another tier than the release tags mismatched manifests unseen, and a forgotten Vibe bump is caught only on the next commit, forcing a post-tag sync commit (gaps named in docs/design/release-infrastructure.md). Default offered: no new check, bump Vibe at the release tier by hand, add a todo whose trigger is the first mismatched tag.

## Remaining

- Ship per plans/2026-11-25-symmetric-session-files.md step 3: Vibe manifest bump commit to 0.24.0, push dev, /ddaa:preflight, `just release minor`, push dev.
- Drop the gitlore launcher note into the gitlore repo so gate runs here stop needing GITLORE_LAUNCHED=1: its launcher injects --settings ahead of the subcommand, and claude 2.1.330 refuses any option before plugin.
- Headless live-probe of a ported Vibe skill end to end in a consumer repo, the last "not yet verified live" line in docs/design/vibe-port.md.
- Durable learnings since memory froze under Vibe (adapter alias naming, the symlink ruling, the review-loop pattern) ride gitlore's memory flow when its Vibe port lands.