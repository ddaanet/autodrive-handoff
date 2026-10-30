## Current task

Implement `plans/2026-10-30-line-cap-split/plan.md`, which my human partner approved on 2026-10-30. It splits the seven files over the 400-line cap: `_lib.sh` into three sourced parts, `hook-test.bats` by hook, `checkpoint.bats`, two pytest files and two guideline docs. Content moves verbatim and the test counts stay the same. My human partner asked for the steps to run as parallel agents, with the per-commit code reviews also run in parallel; that replaces the plan's single sequential executor. Next action: cut `line-cap-split` from `dev`, then dispatch the steps.
