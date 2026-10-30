## Current task

Two threads in parallel, per my human partner on 2026-10-31: "run the branch
review against dev; merge dev into main, preflight, release". Review: an Opus
agent reviews `dev...line-cap-split` at medium from refs only (the tree moves
to `main`), reporting to
`plans/2026-10-30-line-cap-split/reports/branch-review.md`; triage high and
medium. Release 0.19.0: check out `main`, merge `dev`, run `ddaa:preflight`,
load `plugin-craft:toolkit-release`, then `just release 0.19.0`, which bumps
`handoff` (tag + GH release) and `claude-plugins` (marketplace entry). 0.19.0
was to ship with gitlore's D70 release, because its memory directive names
`gitlore:commit`, absent from this session's skill list: check that gitlore
release is out, and ask before `just release` if not. First action: dispatch
the reviewer, then check out `main`.
