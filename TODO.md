## Remaining

- Run the Claude release cascade (`just release` at the repo root, clean tree), then the vibe-plugin/plugin.json sync commit to the released version; policy: docs/design/release-infrastructure.md. Tier: minor by the feature rule (the port and the coupling are features) unless my human partner says otherwise.
- Drop the gitlore launcher note into the gitlore repo so gate runs here stop needing GITLORE_LAUNCHED=1 (its launcher injects --settings ahead of the subcommand, and claude 2.1.330 refuses any option before plugin).
- Headless live-probe of a ported skill end to end in a consumer repo — the last "not yet verified live" line in docs/design/vibe-port.md.
- Durable learnings since memory froze under Vibe (adapter alias naming, the symlink ruling, the review-loop pattern) ride gitlore's memory flow when its Vibe port lands; the boundary directive prints but cannot be acted on until then.