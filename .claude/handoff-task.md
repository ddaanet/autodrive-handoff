## Current task

Executing `plans/2026-10-08-plugin-becomes-a-mod/plan.md` through a delegated `/build`: the tmux walker, `/handoff:restart` and the autoname skill give way to one mod module (`hooks/handoff.ts`) that runs the armed transition with `$.command.run` / `$.prompt.submit`, while the sentinel, the `held` gate and the `SessionStart` loaders stay. Step 1 is the live smoke test, which is also the spike settling four API facts; fact (b) — `SessionStart(clear)` firing for a mod-run `/clear` — changes the plan if it fails, so stop and report then.
