# Step 5: the gate

- `just precommit` now runs `just validate-plugin` and `claude plugin test` (16 pass) ahead of shellcheck.
- `validate-plugin` = `claude plugin validate --strict --json` filtered by jq: any error or warning fails except the repo-root `CLAUDE.md` "not loaded as project context" warning, which is unfixable (it is this repo's own agent instructions). Mutation-checked: restoring the unquoted hook commands reds it (rc 1); quoted is green.
- `hooks/hooks.json`: `${CLAUDE_PLUGIN_ROOT}` paths now double-quoted (8 warnings cleared).
- Left as advisory notes, not warnings: `classic.Stop` "gating hook without .catch" (handler only records the cwd).
- Minimum CC version: no manifest field exists (claude-code-guide, manifest reference: unknown keys are stripped, `dependencies` is for plugins). The 2.1.287 requirement can only be stated in README (step 6); a not-loaded mod is already reported by the sweep note in `report-drive-failure.sh`.
- Precommit: ok (bats 148, pytest 178 passed).
