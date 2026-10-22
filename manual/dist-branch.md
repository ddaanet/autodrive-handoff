# The dist branch

Part of the claude-plugin-dev manual; [README.md](../README.md) is the rest.

The Anthropic plugin directory refuses a plugin folder that holds a gitlink, and
a plugin shipped from its repo root cannot drop one it mounts there, a gitlore
`memory` mount for one. A plugin can instead publish a branch, `dist`, holding
only the paths it lists. Nothing changes for a plugin without a `dist.include`.

To opt in:

1. Create `dist.include` at the repo root, one path per line, relative to the
   root: the plugin's shipped paths, for example

   ```text
   .claude-plugin
   skills
   hooks
   scripts
   README.md
   LICENSE
   ```

   Blank lines and lines starting with `#` are skipped, and a trailing `/` is
   allowed. `dist.include` ships only if it lists itself. Keep user
   documentation and design material apart: put what a user reads in `manual/`
   and list `manual`; never list `docs`, where design records live, since
   listing it ships them. The README links into `manual/` relatively, and
   reaches design by at most one absolute URL, in a Development line. A
   relative link into an unlisted directory dangles in the `dist` tree.
   `just check-refs` finds such links at commit time; a link to a file not yet
   committed passes it and still refuses the release.

2. Commit it. A release reads the list from the release commit, not the
   worktree.
3. Run `just release`. The first release creates `dist` as a root commit;
   each later one adds a commit on top. Each also pushes a `dist-vX.Y.Z` tag at
   that commit, and the marketplace entry gets `ref: dist`.
4. Point the plugin directory submission at the `dist` branch.

Opting in needs `claude` on PATH, because the release validates the tree with
`claude plugin validate --strict` before it commits or tags anything.
`just dogfood` then copies only the listed paths into `dist/plugin/`, so the
session loads what the branch will hold.

What each check does:

- **Refuses the release** (no commit, no tag, nothing pushed): a listed path
  that matches nothing; a symlink or gitlink inside a listed path; no
  `.claude-plugin/plugin.json`, or one that is not JSON; `claude` missing from
  PATH or a validation failure; a Markdown reference in the tree whose target
  the tree does not hold, one `dist:` line each, as
  [`check-refs`](../README.md#reference-check) reports it; `dist.include`
  present with `dist.sh` not vendored beside `release.sh`, which
  `just update-plugin-dev` fixes.
- **Refuses a line** of `dist.include`, naming it: an absolute path; a `..`, `.`
  or `.git` component; an empty component; a leading or trailing blank; any of
  `*`, `?`, `[`, `]` or a backslash, since paths are literal; a CRLF file.
- **Refuses the dogfood sync**, leaving the previous copy: the same bad lines, a
  listed path missing from the working tree, or `dist.include` present with
  `dist.sh` missing.
- **Warns and goes on**, saying the plugin goes to directory review rather than
  that it is blocked: more than 512 files; a file over 256 KiB that is not an
  image or a font; a root `README.md` under 40 words; no `LICENSE` file and no
  `license` in `plugin.json`.

A release that stopped partway is finished with `just resume-release`, which
rebuilds the same dist commit and pushes only what is missing. A `dist-vX.Y.Z`
tag that already points elsewhere, locally or on origin, is refused and never
moved, and nothing is pushed.
