## Current task

Release `dev` onto `main` with `edify:release` (bumps `handoff` with a tag and GH release, and `claude-plugins` with its marketplace entry). Start by loading `edify:release` and run it from step 1.

The vendored toolkit stays at 0.16.2 for this release: my human partner declined updating to `dist-v0.17.0` first. A toolkit change letting the release commit carry `TASK.md` and `TODO.md` is briefed in `claude-plugin-dev/inbox/2026-11-20-brief-release-commit-carries-handoff-files.md`; until it lands, the toolkit refuses a dirty `TASK.md`/`TODO.md`, so write no handoff between preflight and `just release`.