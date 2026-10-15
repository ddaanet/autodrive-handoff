## Brief: rename to autodrive-handoff and prepare the directory submission

2026-10-15

### Decisions

- Rename the plugin from `handoff` to **`autodrive-handoff`**. The repo stays ddaanet/handoff unless decided otherwise.
- Ship to the Anthropic plugin directory from a **`dist` branch** with only the plugin files. The claude-plugin-dev toolkit is gaining that support in a separate brief; vendor it with `just update-plugin-dev` once it's released.
- Dist allowlist: `.claude-plugin/`, `skills/`, `hooks/`, `scripts/`, `bin/`, `README.md`, `LICENSE`.
- The ddaanet marketplace entry becomes `autodrive-handoff`, with its source ref set to `dist`.
- The directory submission tracks the `dist` branch, uses the GitHub push webhook, and has auto-publish off. David does the portal Compliance step himself.

### Constraints

- Why the rename: the portal's Validate on main@5e517b1 held `handoff` for review, for four reasons:
  - A directory **connector** is already named `handoff` ("Only its owner can publish under this name").
  - Look-alike: ApurvBazari's `handoff`.
  - Look-alike: amu815's `claude-handoff`.
  - Look-alike: TheFlow0360's `claude-handoff`.
  - `autodrive-handoff` may still be held as a look-alike of `claude-handoff`. That's accepted.
- The icon is locked by the first save or submission in the portal. `.claude-plugin/icon.png` (square PNG, 512–2048 px, under 2 MB) must be on `dist` before anyone selects Save or Submit. David supplies the image.
- The README is the listing page, and the dist tree has no `docs/`, `plans/` or `CLAUDE.md`. Turn README links to those into absolute github.com/ddaanet/handoff/blob/main/... URLs.
- Add an MIT `LICENSE` file at the root. It's missing; plugin.json says MIT.

### Portal findings to act on (validated at 5e517b1)

- **Blocking: the `memory` submodule.** The dist branch fixes it.
- **Dist also clears:**
  - credential holds on `plugin-dev/install.sh`, `plugin-dev/release.sh`, `tests/bats-best-practices.md`, and `.envrc` together with `.gitlore/bin/claude`;
  - the mod-integrity hold triggered by `justfile`;
  - the warnings on `CLAUDE.md` and on the download-and-run command in `plugin-dev/README.md`.
- **Mod holds on `hooks/handoff.ts`, which stay.** It:
  - starts programs through a shell, with a command the validator can't read in full (line 36);
  - writes a file other tools obey (line 73);
  - submits a prompt (line 78);
  - runs slash commands (line 82);
  - can read the conversation or local data and also send data out.
  - **Fix:** add a README section, e.g. "What the plugin runs and writes":
    - the exact programs and slash commands (`/rename`, `/clear`, `/compact`) and when;
    - the exact content of the resume prompt it submits;
    - every file it writes (`.claude/autodrive`, `.failed`, `.swept`, `TASK.md`, `TODO.md`);
    - that it makes no network calls and no pushes.
  - Where line 36 can run one program by name with fixed arguments instead of through a shell, do it.
- **"Hook can approve tool calls or change their input"** (`PreToolUse`): `inject-checkpoint-root.sh` rewrites `handoff-checkpoint` calls. Make sure it never returns `permissionDecision: allow` (only `updatedInput`), and disclose the rewrite in the README.
- **Mod integrity:** `scripts/_lib.sh`, `scripts/drive-take.sh` and three other files name `hooks/handoff.ts` or `hooks/hooks.json`. If those mentions are only comments, reword them so the literal path disappears; otherwise accept the hold.
- **`scripts/write-guard.sh`:** the validator can't follow the files it calls. Accept the hold, or inline what it calls.

### Rename checklist

- `plugin.json` `name`.
- Every `/handoff:*` skill reference in the README and the SKILL.md files (the namespace becomes `/autodrive-handoff:*`).
- Install and uninstall lines (`autodrive-handoff@ddaanet`).
- The README section "Choosing a handoff provider".
- Outside this repo:
  - ddaanet/claude-plugins entry: add a top-level `"renames": {"handoff": "autodrive-handoff"}`. The community marketplace uses that key; check that `claude plugin validate` accepts it.
  - The `ddaa-handoff` and `ddaa-passation` descriptions in ddaanet/skills ("the lightweight `handoff` plugin").
  - The onekeys example `h → /handoff:handoff` and David's `~/.claude/onekeyers.txt`.

### Rejected approaches

- **Bare `handoff`:** held, see above.
- **`taskframe`:** precompact removes `TASK.md`, so the name fits only the `/clear` path.
- **`mem-handoff`:** contradicts the design; the plugin holds what memory avoids.
- **`native-handoff`:** reads as if Claude Code built it in.
- **`ddaanet-handoff`:** clashes with `ddaa-handoff`.
- **`gitlore-handoff`:** implies gitlore is required.
- **Plugin in a subfolder:** stricter script holds on every version.

### Submission (after the dist branch exists and the README and icon are in place)

1. Go to claude.ai/directory/manage, select **Submit new**, then **Plugin bundle**.
2. Repository `ddaanet/handoff`, branch `dist`. Validate, and fix anything marked Blocking.
3. Data handling:
   - Personal data: only the user's own task notes, written locally to `TASK.md`/`TODO.md`.
   - Data sent to other services: none.
   - Retention: until the user or the next checkpoint clears the files.
   - Intended for under-18s: no.
