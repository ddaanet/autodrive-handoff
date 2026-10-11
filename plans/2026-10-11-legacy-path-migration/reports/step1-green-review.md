# Step 1 (Loader) — GREEN review

**Verdict: APPROVE WITH CHANGES.** The loader meets the plan's Loader contract
and every Decision I could check. All gates pass, and the no-legacy path
spawns exactly what HEAD spawns. Nothing blocks step 2.

Which changes are allowed when, since the tests are the spec:

- **Executor may apply now (comments only, no behaviour change):** F3
  (marker comment), F4 (comment inaccuracies).
- **Need a red row first, so not GREEN edits:**
  - F2 (unreadable file): pre-existing on root files at HEAD; a `TODO.md`
    item.
  - F1 (note wording): needs my human partner's call, then a red-row edit.
- **Process gate:** F0. Do not tag or release between step 1 and step 2.

Scope reviewed: `git diff scripts/_lib.sh scripts/load-handoff.sh
scripts/load-compact.sh` (uncommitted), against `plan.md` (including the
Amended blockquote), the four step 1 reports and `CLAUDE.md`. Read-only. The
only file written in the repo is this report. Probes ran under `$TMPDIR`.

## Evidence

| gate | result |
|---|---|
| `shellcheck -x scripts/*.sh bin/* tests/*.bats` | clean |
| `bats tests/hook-test.bats` (one full run, `$TMPDIR/hook-test.out`) | 155 ok, 0 not ok, rc 0 |
| `bats tests/checkpoint.bats tests/drive-take.bats` | 28 ok, 0 not ok |
| `pytest -q` | 224 passed, 3 deselected |

**Spawn count.** A `python3` shim on `PATH` counted every python3 process per
`load-handoff.sh` run (startup, cwd = project root), for HEAD's scripts
(`git archive HEAD scripts`) and for the working tree:

| fixture | HEAD | work |
|---|---|---|
| both root files with a body, no legacy | 3 | 3 |
| both root files headings-only, no legacy | 2 | 2 |
| no files | 0 | 0 |
| both halves legacy only | 0 | 3 |
| both root files with a body + both legacy | 3 | 3 |

The no-legacy and shadowed paths are unchanged. The extra cost appears only
when a half is actually read from a legacy file. A shadowed legacy file is
checked with `-f` and never sent to python.

**Dogfood.** This repo really has both legacy files (673 B and 2189 B,
untracked; not sandbox phantoms) next to `TASK.md` and `TODO.md`. Running
`load-handoff.sh` (startup, which writes nothing) prints `handoff: loaded —
1.8 KiB, saved 52m ago; .claude/handoff-task.md ignored, TASK.md wins;
.claude/handoff-todo.md ignored, TODO.md wins`, and both "is ignored" notes
appear in the context, after the frame.

## Contract checklist (1)

| item | status | where |
|---|---|---|
| Root wins (root with a body is the frame) | yes | `_lib.sh:85-98` |
| A body-less root file does not shadow | yes | the `elif` reads the legacy file only when the root has no body; probe 8 also shows a *directory* at `TASK.md` falls through |
| Shadowed is decided by legacy existence | yes (`-f`) | `_lib.sh:87,94`; a body-less legacy file behind a root file with a body is shadowed (probe 6) |
| Flags reset by plain assignment | yes | `_lib.sh:82-84`; `handoff_frame_notes` resets its arrays at `:121` |
| `FRAME` never holds a note | yes | notes go into `context`; size stays `${#FRAME}` |
| Age taken from the files that count | yes | `load-handoff.sh:70-74` |
| Both channels | yes | both loaders |
| Same note order on both channels | yes | one producer (`handoff_frame_notes`), appended in array order; the gap note comes last on both channels in `load-handoff.sh` |
| Anchored on `handoff_root` | yes | `$cwd` in both loaders; the red review's worktree row (its F5) covers it |
| bash 3.2 | yes, by reading (no 3.2 binary on this box) | no `mapfile`, no associative arrays, no case modification; arrays expanded `${A[@]+"${A[@]}"}`; `counted` is never empty inside its branch |

## Findings, ranked

### F0 (process, high if ignored): step 1 alone brings stale legacy halves back — do not tag or release between step 1 and step 2

The loader now reads the legacy files, but nothing removes them yet:

- Under `precompact` the checkpoint removes `TASK.md` and leaves
  `.claude/handoff-task.md`. `load-compact.sh` then injects that stale legacy
  task with "the next checkpoint moves it" (probe 4c shows the shape).
- `{"action": "clear"}` on a half has the same effect: the root file goes,
  and the legacy file becomes the frame.

Step 2's contract covers both (`clear` and `precompact` remove a legacy file
that would otherwise be read). The plan's "Ships as 0.16.1" implies a single
release. State it at the step boundary so no intermediate commit is tagged.

### F1 (medium, contract-level; needs my human partner's call and a red-row edit): the from-legacy note does not say where to edit in the meantime — `scripts/_lib.sh:123,127`

A session whose todo was loaded from `.claude/handoff-todo.md` has no
`TODO.md`. The shared convention sends work found mid-step to `TODO.md`
("appended to `TODO.md`"), and the plugin's own FR4 calls `TODO.md` a scratch
list edited all session.

- Failure scenario: the agent appends one item. `Edit` refuses a missing
  file, so it uses `Write`, and a new one-item `TODO.md` now has a body.
- From then on the legacy list is shadowed. The next checkpoint's `keep`
  keeps the one-item root file, and the legacy file is "ignored".
- The handed-over list drops out of the frame. It is still on disk, and the
  next load names it, but nothing brings it back.

The note tells the agent about the move but not where to edit before it. Two
options:

- (a) Add an act: `Todo loaded from legacy .claude/handoff-todo.md; edit it
  there until the next checkpoint moves it to TODO.md.` Default.
- (b) Accept the risk: one user, and the loss is reported.

Either way it changes wording that `tests/hook-test.bats` pins (spec), so it
needs a red-row edit first, not a GREEN edit. Step 2's checkpoint stdout
should mirror whichever wording is chosen. The task note has the same shape,
but `TASK.md` is not edited mid-session, so the risk there is negligible.

The other three notes pass the directive-writing test:

- "the next checkpoint moves it" is the one reassuring clause that stops an
  invented `git mv`.
- "is ignored: TASK.md has a body." states a fact and offers no
  self-authorising advice; the Amended blockquote dropped the deletion
  advice.
- The user-channel fragments are lowercase, curt and carry no instructions.

### F2 (low; pre-existing; `TODO.md` item with a red row first, not a GREEN edit): an unreadable file counts as "has a body" — `scripts/_lib.sh:111`

`! python3 … <"$2"`: when the redirect fails (permission denied), bash gives
the command status 1, and `!` turns that into "has a body". Then `cat` fails
too, and the half is injected empty. Probe 3 (`chmod 000` legacy todo, no
root):

- the context is the header, then blank lines, then `Todo loaded from legacy
  .claude/handoff-todo.md; the next checkpoint moves it to TODO.md.`
- the message says `todo from .claude/handoff-todo.md, next checkpoint moves
  it`
- stderr carries `Permission denied` twice.

Probe 3b shows HEAD already does this for an unreadable *root* file. The
pattern is inherited, and the legacy fallback adds a false note on top of it.

Fix, after a row pins it: `[[ -n "$2" && -f "$2" && -r "$2" ]] && ! python3
…`. That fixes root and legacy in one place. It changes what "counts", so it
is outside this GREEN.

### F3 (medium; comment only, executor may apply now): the marker comment ships a private absolute path, and "every use of them" is not true — `scripts/_lib.sh:17-22`

- The comment carries `ls /Users/david/code/*/.claude/handoff-*.md`. `_lib.sh`
  is distributed plugin code, so that path dangles for every other install
  (directive-writing: distributed text never cites private files). The plan
  puts this check in the `TODO.md` item (Decisions, "Retirement is
  conditional"). The comment should carry the condition only.
- "deleting these two constants and every use of them removes it" is not
  true:
  - `FRAME_*_LEGACY`, `FRAME_*_SHADOWED`, the `$3`/`$4` parameters,
    `handoff_frame_notes`, the age branch in `load-handoff.sh:71-74` and the
    note loops in both loaders are not uses of the constants.
  - A maintainer who greps `HANDOFF_LEGACY_REL` and deletes the hits leaves
    dead flags and loops behind, and `set -u` does not catch it.
  - `grep -rni legacy scripts/ tests/` does reach all of them: the
    constants, the flags, the `legacy_task`/`legacy_todo` locals, the lines
    that set `SHADOWED` (they test `$legacy_*`), the note text and every
    comment.
- Fix (comment only, no rename, since the tests pin the names):
  - drop the `ls` line;
  - replace "deleting these two constants and every use of them removes it"
    with "`grep -rni legacy` over scripts/ and tests/ lists the whole
    fallback".
- Plan follow-up: step 2 adds a Python twin, because `checkpoint.py:44-45`
  already duplicates `HANDOFF_REL_*` and Python cannot read a bash constant.
  So the plan's "single constant both the loader and the checkpoint read" is
  already false. The One marker Decision should read "one name per language,
  found by one grep", and the Python constant's comment should point here.

### F4 (low; comment only, executor may apply now): comment inaccuracies the change introduced — `scripts/_lib.sh:60`, `scripts/load-compact.sh:44-45`, `scripts/_lib.sh:18`

- `_lib.sh:60`: "sets in the caller's scope on every call, each 1 or 0:"
  then lists `FRAME`, which is a string. Fix: "each flag 1 or 0", or move
  `FRAME` above that clause.
- `load-compact.sh:44-45`: "The checkpoint removes the task file at this
  boundary, so one with a body was written by hand since". Until step 2 the
  task half can come from the legacy file, which `precompact` does not
  remove (F0). After step 2 the sentence is true again. Re-check it then; no
  edit now.
- `_lib.sh:18`: "the checkpoint moves a file off them" describes step 2. It
  is fine if both steps ship together (F0).
- `load-handoff.sh:45-47` still says "either file alone is enough. A file
  missing from it is named". Close enough ("half" would be exact). Nit.

### F5 (observation for the plan): an ignored legacy file is reported at every session start, with no end — this repo is the live instance

The dogfood above: this repo has both legacy files beside root files with a
body. By contract, step 2 leaves a shadowed legacy file untouched, and the
Amended blockquote dropped the advice to delete it. Nothing ever clears the
condition, so both "ignored" notes ride on every startup, clear and driven
compact in this repo until someone deletes the files by hand. This is a
consequence of the settled design, not a GREEN defect. My human partner will
see it at the next startup. A one-line acknowledgement in the plan, or a
decision to accept it, closes it.

### F6 (nit): the note-append loops are written four times — `load-handoff.sh:87-92`, `load-compact.sh:59-66`

The wording comes from one place, and that is the part that matters. The
two-loop append (context and message) is repeated in both loaders, with
slightly different message joining. About 6 lines each. Leave it unless
step 2 adds a third consumer.

## Adversarial probes (`$TMPDIR/probe-legacy/probe.sh`)

| input | what the loader does | what it should do | verdict |
|---|---|---|---|
| legacy task path is a directory, no root | neither state | same: not a file | ok |
| legacy task path is a directory, root task with a body | root frame, no ignored note | same: `-f` is false, so there is nothing to report | ok; step 2 must use the same predicate (`Path.is_file()`) |
| legacy task is a dangling symlink, root task with a body | no ignored note | same: there is no content to name | ok; same step 2 note |
| legacy todo is a symlink to a real body, no root | loaded from legacy, with notes | same | ok |
| unreadable legacy todo (`chmod 000`) | empty half injected, false "loaded from legacy" note, two stderr lines | not counted (no body readable), or at least no note | F2 |
| unreadable root todo (HEAD and work) | empty half injected | not counted | pre-existing, fixed by F2 |
| root with a space in its path | correct frame and notes | same | ok |
| root with a newline in its path, `load-handoff.sh` | `No task frame or todo.` | the frame | **pre-existing**: HEAD gives the same. `load-handoff.sh:24-26` reads `jq -r` output line by line (`read -r hook_cwd`), so a newline in `.cwd` splits it. Not this slice. Add a `TODO.md` item (read with `jq -j` and NUL separators, or one `read -r -d ''` per field) |
| same root, `load-compact.sh` | correct frame and notes | same | ok |
| legacy todo CRLF, headings only | not counted | same | ok (python's universal newlines) |
| legacy todo CRLF with a body, no trailing newline | counted, inlined verbatim with `\r` kept | same (verbatim) | ok |
| both halves shadowed, legacy todo zero bytes, startup and compact | two ignored notes, task first, on both channels | same (existence, F4 of the red review) | ok |
| headings-only legacy, no root | neither state, no note | per the contract, silent | ok; step 2 will still move it, so the agent hears about it only from the checkpoint |
| `TASK.md` is a directory, legacy task with a body | loaded from legacy, "the next checkpoint moves it to TASK.md" | arguably the same; the promise is false, because a rename onto a directory fails | exotic; step 2 should refuse cleanly rather than crash |

## Items for step 3 (docs)

1. **`docs/design/rejected-alternatives.md:95`** and the **`docs/design.md:273`**
   index line both list "Reading the old paths as a fallback" as rejected.
   This change reverses that, so the entry must go (or be rewritten as what
   is still rejected, i.e. a *versioned* fallback). A decision line goes into
   `docs/design/decisions.md` and the hub. The plan's step 3 names neither
   file.
2. **`docs/changelog/2026-10-11-task-and-todo-move-to-the-root.md:117,130`**
   ("a fallback read of the old paths would outlive…", "Nothing reads the old
   paths"). Head the affected section with a `> **Superseded 2026-10-11**`
   blockquote pointing at the new entry; do not edit the body.
3. `README.md:48-56`: as the plan says (automatic behaviour first, keep the
   two `git mv` lines, drop "Nothing reads the old paths").
4. `docs/design/the-write-path.md:10,34-36`: the frame is assembled from the
   root file or the legacy file per half, and `load-handoff.sh`'s reported
   states now include the from-legacy and ignored notes.
5. `docs/design/driving-the-transition.md:142-146`: what each loader says
   afterwards now includes the legacy notes. `load-compact.sh`'s message is
   `todo re-injected|No todo` followed by `; <fragment>` per note.
6. `CLAUDE.md` Layout:
   - the `_lib.sh` bullet (`:157`, `handoff_frame()` sets only
     `FRAME`/`FRAME_TASK`/`FRAME_TODO`; it now takes two optional legacy
     paths and sets the four legacy flags; mention `handoff_frame_notes` and
     the `HANDOFF_LEGACY_REL_*` constants beside `HANDOFF_REL_*`)
   - the `load-handoff.sh` (`:130`) and `load-compact.sh` (`:137`) bullets
   - "Frame assembly" (inlined `TASK.md` and `TODO.md`, now "or their legacy
     path")
   - Testing, the `tests/hook-test.bats` paragraph (`:381`, add the legacy
     and shadowed rows and their mutation checks).
7. The `TODO.md` retirement item carrying the condition and the `ls` check
   (the plan already has it). F3 moves the `ls` line out of `_lib.sh` and
   into this item.
8. The One marker Decision wording in `plan.md` (F3), as a `> **Corrected at
   review**` blockquote if it is changed.
9. `TODO.md` (not docs): the pre-existing newline-in-cwd bug in
   `load-handoff.sh:24-26`.
