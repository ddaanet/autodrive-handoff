# Shipping to the plugin directory

2026-10-15.

## The question

The plugin is being submitted to Anthropic's plugin directory, which holds
each plugin as a tree of its own. Four things stood between the repository as
it was and a submission: the name, what the tree contains, what a reviewer is
told about the mod, and one hook output a reviewer would read as a standing
approval.

## The name

The plugin was `handoff`. The directory already has a connector with that name,
and three plugins look alike in a listing: `handoff` and two called
`claude-handoff`. It is now `autodrive-handoff`, after the drive that sets it
apart from the others: it carries the transition out instead of printing
instructions. The GitHub repository is `ddaanet/autodrive-handoff`, the
skills are `/autodrive-handoff:<skill>`, and the README tells an install under
the old name to uninstall it first.

Rejected:

- **`taskframe`.** `precompact` removes `TASK.md`, so the name fits only the
  `/clear` boundary.
- **`mem-handoff`.** The plugin holds what memory avoids, so the name points the
  wrong way.
- **`native-handoff`.** Reads as built in.
- **`ddaanet-handoff`.** Clashes with `ddaa-handoff`, the other provider the
  README already tells the reader not to enable beside this one.
- **`gitlore-handoff`.** Implies gitlore is required; it is optional.
- **A plugin in a subfolder of the repository.** The stricter script hold
  applies to it.

## What ships

The directory takes a `dist` branch holding only the paths in `dist.include`:
`.claude-plugin`, `skills`, `hooks`, `scripts`, `bin`, `README.md` and
`LICENSE`. `LICENSE` is the MIT text, new here. `README.md` is the listing
page, so a link to `docs/`, `plans/` or `CLAUDE.md`, none of which the branch
holds, is now an absolute `github.com/ddaanet/autodrive-handoff` URL
(`/blob/main/` for a file, `/tree/main/` for a directory); a link into the
allowlist stays relative. The validator flags a file that names the literal path of the mod or the
hooks manifest, so the comments in `scripts/`, the manifest's own description
and the README now say "the mod" and "the hooks manifest". The one occurrence
that is code stays, in `tests/checkpoint.bats`, which reads the manifest by its
path; `tests/` is not shipped.

## The injector no longer allows

`inject-checkpoint-root.sh` returned `permissionDecision: "allow"` beside its
`updatedInput`. With an `allow` from a hook, Claude Code treats the call as
settled and does not consult the permission classifier or the user's rules. The
hook's match is a loose substring (`handoff-checkpoint` or `handoff-approved`
anywhere in the command, deliberately, because a missed match leaves
`HANDOFF_ROOT` unset), so any command that merely contained either name was
pre-approved, a chained tail included: `handoff-checkpoint </dev/null; <anything>`
ran without a prompt. The loose match is right for an environment-variable
prefix and wrong for an approval.

It now returns `updatedInput` alone. The rewritten command goes through the
full permission pipeline, as the agent's own would have: a user who has allowed
`handoff-checkpoint` sees no prompt, and one who has not is asked. The row in
`tests/checkpoint.bats` asserts `permissionDecision` is absent.

## The disclosure

Directory reviewers flagged the mod for running a program, writing files other
tools obey, submitting a prompt, running slash commands, and possibly reading
local data and sending it out. The README's "Files touched on your system"
section is now "What the plugin runs and writes", checked against the code line
by line: each hook and its event, the one program the mod starts
(`drive-take.sh`, only when a sentinel may exist), the commands the agent runs,
the three slash commands and the single resume prompt (`CONTINUATION`, quoted),
every file written and what reads it, the injector and the write guard, and a
list of what it does not do. Grepping `scripts/`, `bin/` and `hooks/` for
`curl`, `wget`, `fetch(`, `http` and sockets finds nothing, so "no network call"
stands. "No git" did not: `checkpoint.py` runs `git config --file` and, when a
gitlore memory submodule exists, `git -C <memory> status --porcelain` and `git
config --get`, all read-only, so the section says that rather than "no git".
The commit the checkpoint prints instructions for is the agent's, under the
user's permission rules.

## What stands

The design of the drive, the sentinel and the write path is unchanged; the
changelog and design nodes that call the plugin `handoff` were written when it
was, and are not rewritten for the name. `docs/design/scoping.md` already said
the injector acts through `updatedInput`; it now also says the hook makes no
permission decision.
