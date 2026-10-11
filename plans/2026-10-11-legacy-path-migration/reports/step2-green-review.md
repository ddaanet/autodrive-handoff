# Step 2 (Checkpoint migration) — GREEN review

Scope: `git diff scripts/checkpoint.py scripts/_checkpoint_lib.py` against the
amended Checkpoint contract in `plan.md`, with `tests/test_checkpoint.py` as the
spec. Read-only: this file is the only repo write; scratch repos and mutants
under `$TMPDIR/rv` and `$TMPDIR/mut`.

## Verdict: APPROVE WITH CHANGES

Every contract bullet is met and every gate is green. Two fixes are inside the
GREEN scope (F2 a missing test row for a surviving mutant, F3 a regression on
the no-legacy path). F1 is the one that bites in ordinary use, but the code
matches the plan's contract text byte for byte, so it is a contract amendment
for my human partner. F4 and F5 are exotic and listed as decisions.

## Evidence

| check | result |
|---|---|
| `shellcheck -x scripts/*.sh bin/* tests/*.bats` | clean |
| `ruff check scripts tests` | clean |
| `ruff format --check scripts tests` | 8 files already formatted |
| `docformatter --check scripts/*.py tests/*.py` | clean |
| `mypy` | rc 0 |
| `ty check` | All checks passed |
| `pytest -q` (full) | 321 passed, 3 deselected, 55 s |
| `bats tests/hook-test.bats tests/checkpoint.bats tests/drive-take.bats` | 183/183 ok |

Mutants (scratch copy `$TMPDIR/mut`, `tests/test_checkpoint.py` only, each
edit asserted to land once, `diff` against the original shown):

| mutant | result |
|---|---|
| rename replaced by copy + unlink (`plan.path.write_bytes(legacy.path.read_bytes()); legacy.path.unlink()`) | killed by `test_keep_moves_the_legacy_todo_with_its_modification_time` |
| apply order: unlink the legacy file before writing the root file (write/remove arms; move unchanged) | **survives, 309/309 pass** (F2) |

## Findings, ranked

### F1 (high, decision): the git act is cwd-relative and fails silently from a subdirectory

`scripts/_checkpoint_lib.py:46-49` prints
``Before committing, run `git rm --cached --ignore-unmatch -q -- .claude/handoff-task.md .claude/handoff-todo.md`.``
The pathspecs are relative to the agent's Bash cwd, which persists across
calls. The plugin itself expects that cwd to be anywhere under the root:
`inject-checkpoint-root.sh` resolves `HANDOFF_ROOT` by walking up from `.cwd`.

Scenario (run, `$TMPDIR/rv/r1/sub`): a tracked legacy todo, `keep`
with-commit, the agent's cwd is `scripts/`. The act exits 0 and stages
nothing; `git status` still shows ` D .claude/handoff-todo.md`. The commit
carries `TODO.md` as a new file and leaves the legacy path in `HEAD`, with
an unstaged deletion behind it. `--ignore-unmatch -q` makes the miss
invisible to everyone. That is the "silent to everyone" class, and it
breaks the "verbatim-runnable" rule.

Fix: prefix each pathspec with git's top-level magic, so the act is
`git rm --cached --ignore-unmatch -q -- :/.claude/handoff-task.md :/.claude/handoff-todo.md`.
I ran it from the subdirectory: it staged the deletion (`R  .claude/handoff-todo.md -> TODO.md`
once `TODO.md` was added), and the untracked sibling was a silent no-op. It
embeds no root, so a space or newline in the root needs no quoting. The other
option, `git -C <shlex-quoted root> rm ...`, puts the root on the line, and a
newline in it then splits the line.

Test impact, red first: `run_printed_git_rm` (`tests/test_checkpoint.py:3473-3482`)
strips only `` `"'( `` and compares tokens with the bare rels, so a `:/` token
empties `paths` and fails `assert paths`. It also runs with `cwd=repo`, so it
could never catch F1. Change it to strip `:/`, run the act from a subdirectory
of the repo, and update `GIT_RM`-based expectations (`:3391`, `:3447`, `:3527`).
The plan's Checkpoint contract names the bare form, so amend it with a
`Corrected at review` blockquote.

From the root, the current act works whatever the root's name: a space in
the root (`$TMPDIR/rv/r 2`, tracked todo plus untracked task) and a newline
in it both run fine. The tracked file comes out staged as `D `, and the
untracked one is a no-op with rc 0.

### F2 (medium, GREEN scope, test row): the write-before-unlink order is unpinned

`scripts/checkpoint.py:648-656` (`apply_plan`) writes the root file and then
unlinks the legacy file. That order is load-bearing, and the mutant that
reverses it survives the whole file.

Scenario (run, `$TMPDIR/rv/r11`): legacy todo `- a / - b`, a headings-only
`TODO.md` that the write cannot open (mode 444, standing in for any write
failure), and `edit` `- a` → `- c`. The real code raises PermissionError and
leaves the legacy file intact. The mutant first unlinks the legacy file, then
fails the write. The todo is gone from disk and survives only as the edit
result in memory, and the next load says `No todo`.

Fix: add a row to `tests/test_checkpoint.py` with that fixture. Assert a
non-zero exit and the legacy bytes unchanged, and skip it when euid is 0. The
same row with a content write also pins the order for `write`. Then
mutation-check it against this mutant.

### F3 (medium, GREEN scope): every half now reads the root file, a regression when no legacy file exists

`scripts/checkpoint.py:575-577` (`read_half`) runs `path.is_file()` and
`path.read_text(...)` for every action, `keep` included, even when no legacy
file is present.

Scenario (run, `$TMPDIR/rv/r4`): no legacy file at all, `TODO.md` mode 000,
`keep`. At HEAD this exits 0. Now it exits 1 with a PermissionError
traceback that names no field. Nothing is written, because resolution comes
first. The contract wants no change in behaviour when no legacy file exists,
and the `FilePlan` docstring (`:518`, "`none` leaves the list as it is,
without a stat (FR4)") is now false.

Fix: compute `has_body` only when `legacy_path.is_file()`. Its only consumers
are `legacy_fate`, which returns None first when there is no legacy file, and
`use_legacy` in `plan_todo`, which also requires the legacy file. That
restores HEAD behaviour byte for byte on the no-legacy path, and the
docstring holds again for that path. Reword it to "without reading the root
file" for the legacy case.

### F4 (low, decision): a legacy path that is a relative symlink becomes a dangling `TODO.md`

`scripts/checkpoint.py:654`: `legacy.path.replace(plan.path)` renames the
link, not its target, and a relative target resolves differently from the
root.

Scenario (run, `$TMPDIR/rv/r3`): `.claude/handoff-todo.md -> ../notes/todo.md`.
`keep` reports "moved to TODO.md", and `TODO.md -> ../notes/todo.md` dangles.
`handoff_frame` gives `FRAME_TODO=0`, so the next session says `No todo`. The
target file survives. An absolute-target link moves fine.

Options:
- (a) Refuse it like the directory case: `legacy_path.is_symlink()` → `err`.
- (b) Write the target's bytes to the root name, keep its mtime with
  `os.utime`, then unlink the link.
- (c) Accept it.

Default (a): one line, beside the existing refusal.

### F5 (low, decision): a cross-device move is a traceback after the task half has been applied

`scripts/checkpoint.py:654`, with `.claude` a symlink to another mount.

Scenario (run, `$TMPDIR/rv/r10`, `.claude -> /dev/shm/...`): `OSError: [Errno 18]
Invalid cross-device link`, exit 1, no field named. `TASK.md` is already
written and the legacy task removed. The legacy todo is intact and no
sentinel is composed. Every later checkpoint that carries the legacy todo
fails the same way until the file is moved by hand.

Options:
- (a) `shutil.move`: a rename, falling back to `copy2` plus unlink, which
  keeps the mtime and would pass the mtime row.
- (b) Catch `OSError` in `apply_plan` and turn it into `err()`.
- (c) Accept it.

Default (a).

### F6 (low): what a failure midway through apply does, compared with HEAD

Within one half nothing is lost on failure:
- `Path.replace` is atomic.
- The trailing unlink is only reached after the write or rename succeeded.
- A failing `write_text` leaves the legacy file in place (F2's real-code run).
- Of the new ordering, only "a body-less root write succeeds, then its legacy
  unlink fails" leaves a legacy file the loader would pick up again. That
  needs a directory the root write can reach but the unlink cannot.

Across halves, the task half applied and the todo half failing is the same
partial shape HEAD had: two `write_text` calls in a row, with an exception
between them leaving the first one done. `compose_sentinel`'s read-back
`err()` still runs after apply. That is pre-existing, but it now also runs
after a move.

**Not worse in kind:** more filesystem steps per half, each ordered so the
root file is current before the legacy file goes.

### F7 (nit): the directory refusal says "cannot move" under `clear` and content writes

`scripts/checkpoint.py:566-574`: "`TODO.md is a directory, not a file, so
.claude/handoff-todo.md cannot move to it`" is also printed when the action
removes rather than moves. The refusal itself is right, because `unlink` on
a directory fails too. Possible wording: "`TODO.md is a directory, not a
file`".

## Contract fit, line by line

- **Effective content.** Met. A root file counts when `is_file()` and the
  `lib.is_empty_body` test show a body (`read_half`). The legacy file counts
  when `is_file()` (`legacy_fate`, the `use_legacy` check in `plan_todo`).
  `keep` keeps it, `edit` reads the root file when it counts and the legacy
  file otherwise, and a content string replaces it.
- **Rename keeps the mtime.** Met: `Path.replace`. Pinned by the mtime row,
  and the copy mutant is killed. A headings-only root file is replaced by
  the move (run: `r6` hardlink, `r5` symlinked root).
- **Root wins.** Met: `has_body and after` → `ignored`, the legacy file left
  alone, one report line.
- **Body-less root after the write.** Met: `after=False` → `removed`, plus
  the report line.
- **`clear` and `precompact`.** Met. Under `precompact`, `validate_task`
  returns `("clear", "")`, so a legacy task file is removed and reported.
  Run (`r7`): both halves legacy, `todo: keep` under precompact. The task was
  removed and the todo moved with its 2026-01-01 mtime kept. The git act
  named both paths, and the line ended `Ready to /compact`.
- **`autoname`.** Met: `plans` stays `[]` and `compose_directives` returns
  `[]`.
- **A directory at the root path.** Refused cleanly, during resolution, with
  exit 2 naming the field (F7 wording).
- **Nothing moves unless everything resolves.** Met for every check that
  exists. Schema, task shape, session id and `memory_directive` all run
  before planning. Both `read_half` refusals and the `edited_body` errors
  run while the `plans` list is being built, and `apply_plan` only runs
  after it. Apply-time failures: see F6.
- **Stdout order.** Met: reports, then memory, then boundary or SDD, then
  the commit act (git act first), then the closing or arming line last.
  Under the refusal: reports, then the git act (with-commit only), then the
  refusal.
- **NFR1.** Met: the diff adds no subprocess and no git call. The git act is
  printed only under with-commit and only for `moved`/`removed` paths
  (`gone`), never for `ignored` ones.

## Adversarial inputs

| input | behaviour | verdict |
|---|---|---|
| legacy is a relative symlink | link moved, `TODO.md` dangles, frame drops the todo | F4 |
| legacy is an absolute symlink | link moved, still resolves | ok |
| legacy unreadable, `keep` | renamed (no read needed) | ok |
| legacy unreadable, `edit` | `edited_body` PermissionError traceback, nothing written | pre-existing class (root edit same at HEAD) |
| root unreadable, no legacy, `keep` | traceback, was rc 0 at HEAD | F3 |
| root symlink → legacy, both with body, `keep` | `ignored` reported (the "two" files are one) | harmless |
| root symlink → legacy, body-less content write | written through the link, then the legacy target is unlinked; `TODO.md` dangles. Lost: only headings, which the loader would not inject | acceptable, note |
| root symlink → legacy, `clear` | both gone | ok |
| root hardlink to legacy (same inode), headings-only, `keep` | `rename` onto the same inode is a no-op, the legacy name is unlinked, `TODO.md` keeps the bytes | ok, no data loss |
| root symlink to a file outside, body-less, legacy with a body, `keep` | the symlink is replaced by the legacy file; the outside target is untouched | exotic, acceptable |
| `.claude/` missing | no legacy possible; `compose_sentinel` mkdirs | ok (existing rows) |
| both halves legacy, todo only, `precompact` | task removed, todo moved, both on the act | ok (`r7`) |
| `keep`, headings-only root, no legacy | bytes and mtime unchanged, no report | ok (`r8`) |
| CRLF legacy, `keep` | bytes kept, `\r\n` intact | ok (`r9`) |
| CRLF legacy, `edit` | written with LF | pre-existing `edited_body` behaviour for root files; not new |
| root path with a space or newline | reports and act use rels; act runs from the root | ok (`r 2`, `r\nnl`) |
| cross-device `.claude` | EXDEV traceback after the task half applied | F5 |
| concurrent loader during the move | rename is atomic; write then unlink leaves root current first. The loaders run at `SessionStart`, after the checkpoint's turn | by reading, no issue |

## One marker

- The Python constants `HANDOFF_LEGACY_REL_TASK` and `HANDOFF_LEGACY_REL_TODO`
  are defined once (`scripts/checkpoint.py:54-55`), beside the
  `HANDOFF_REL_*` mirror. The comment names the retirement condition and
  carries no version and no private path.
- The comment says `` `grep -rni legacy scripts/ tests/` lists all of it ``,
  which overclaims. Lines that exist only for the fallback but that the grep
  does not list:
  - `scripts/checkpoint.py:529` `class Half(NamedTuple):`, its docstring
    (`:530-534`) and fields `path`/`has_body` (`:536`, `:539`). The whole
    record goes, or collapses to `path`.
  - `:575-577`, the `has_body` computation (`counts = path.is_file() and not
    lib.is_empty_body(...)`). It is dead without the fallback.
  - `:523`, `"move"` in the `act` Literal. The `elif plan.act == "move"` arm
    is listed, but the Literal member is not.
  - `:602`, `after = not lib.is_empty_body(content)` in `plan_task`. Ruff
    F841 would flag it once its consumer goes.
  - `:558`, the `field` parameter of `read_half`, used only by the legacy
    refusal. It is listed only because the same line carries `legacy_rel`.
  - `:92` and `:96-99`, the `plans` list in `main`, and the `plans` parameter
    of `compose_directives` (`:760`). They exist only to feed the reports and
    the act.
  - `:748-753`, `Boundary`. It was introduced so `compose_directives` would
    stay under PLR0913 with `plans`. Harmless to keep, but it would no longer
    be needed.
  - `scripts/_checkpoint_lib.py:17`, `from collections.abc import Sequence`.
    Ruff F401 catches it.

  Fix: soften the comment to name the anchors (the two constants, `Legacy`,
  `Half`, `read_half`, `legacy_fate`, `legacy_reports`,
  `legacy_unstage_directive`), or rename `Half` to something the grep finds.
  The plan says the grep covers `scripts/`; the comment adds `tests/`, which
  is also fine.
- The bash side (`_lib.sh`, `load-handoff.sh`, `load-compact.sh`) is listed
  in full by the grep (step 1 reviewed).

## Agent-facing text

- The report lines (`Legacy <rel> moved to TODO.md.`, `... removed.`,
  `... is ignored: TODO.md has a body.`) are facts with no advice. The
  ignored line adds nothing to delete, as the amendment asks.
- The git act is one imperative line, conditioned "Before committing", and
  touches only the index. It is not destructive, and it is runnable as
  printed from the root (see F1 for any other cwd). Its docstring and the
  `commit_directive` docstring are mechanism-free enough for maintainer
  comments.
- Under the clause-file refusal: "Before committing, run ..." is printed
  ahead of the refusal. It is conditional on a commit that may not come in
  that flow, which is acceptable.

## Repo conventions

- **Size.** `scripts/checkpoint.py` went from 677 lines (HEAD) to 811,
  against the 400-line soft cap. It was already over before this change,
  which adds 134. Candidate split, reported and not done: the plan layer,
  i.e. `Legacy`, `FilePlan`, `Half`, `edited_body`, `read_half`,
  `legacy_fate`, `plan_task`, `plan_todo`, `apply_plan`, `legacy_reports`
  (about 190 lines), into its own module. Suggest a `TODO.md` item beside
  the `tests/test_checkpoint.py` split item. `_checkpoint_lib.py` went from
  300 to 318 lines. No function exceeds about 40 lines (`plan_todo`).
- **Ordering.** The new NamedTuples precede their users, as `FilePlan` and
  `Ending` already did. `read_half` and `legacy_fate` precede `plan_task`
  and `legacy_reports` precedes `compose_directives`, the same
  helper-before-user pattern `edited_body` already followed. That is a
  local deviation from entry-points-first, consistent with the file.
  `legacy_unstage_directive` follows its user. Nit only.
- **Stale docstrings.** Three are now false:
  - `FilePlan` (`:518`): "without a stat" (F3).
  - `plan_task` (`:594-597`) and `plan_todo` (`:608-611`): "only `clear`
    removes". A content write or edit now removes a legacy file. Qualify
    it: "only `clear` removes the root file".
  - `apply_plan` (`:642-647`): "Neither arm calls err()". There are now
    three arms and an unlink, so it should say "No arm".
- **Bash 3.2.** No bash changed in step 2.
- **Lint.** mypy, ruff, docformatter and ty are clean.

## Items for step 3

1. `README.md:48-56`. State the automatic behaviour first: the loader reads
   the old names, and the next checkpoint moves the files. Keep the two
   `git mv` lines as the manual route and drop "Nothing reads the old paths"
   (`:56`). Add that under with-commit the checkpoint prints a
   `git rm --cached` line, so git records a rename.
2. A `docs/changelog/2026-10-11-*.md` entry plus its index line in
   `docs/changelog.md`, stating the retirement condition (no sibling
   repository still has `.claude/handoff-*.md`) with no version. Head the
   affected section of `docs/changelog/2026-10-11-task-and-todo-move-to-the-root.md:117,130`
   with a `> **Superseded 2026-10-11**` blockquote and leave the body
   unedited.
3. `docs/design/the-write-path.md`:
   - `:10` and `:34-36`: the frame comes from the root file or the legacy
     file, per half.
   - `:112` and FR5: a content write, `edit` or `clear` also removes the
     half's legacy file, `keep` moves it, and root wins.
   - `:117`, NFR1: the checkpoint renames and removes on the filesystem and
     prints the `git rm --cached` act. It runs none of it, and the act is
     owed only by the call that moved or removed a file.
   - The directory refusal.
4. `docs/design/driving-the-transition.md:142-146`: the loader notes, as the
   step 1 review listed.
5. `docs/design/the-checkpoint-directive.md:52`: "The clause-file refusal
   prints alone" is now false. It prints after the legacy reports and, under
   with-commit, after the git act. Also the commit act's leading git line.
6. `docs/design.md`:
   - `:149` (FR6, "only `clear` removes"): qualify it to the root file.
   - FR9 (`:155-`): the print order now opens with the legacy reports.
   - `:273`, plus `docs/design/rejected-alternatives.md:95`, "Reading the old
     paths as a fallback": rewrite these as what is still rejected (a
     versioned fallback). Add a decision line in `docs/design/decisions.md`
     and the hub.
7. `CLAUDE.md`, Layout:
   - `:66`: "only `{"action": "clear"}` and the compact boundary remove one"
     now also covers legacy removal and moves.
   - `:208`, the `checkpoint.py` bullet: legacy move and removal in plan
     resolution, `FilePlan`'s `move`/`legacy`, the `Half`/`Legacy` records,
     the directory refusal, and `compose_directives(boundary, memory, ending,
     plans)`.
   - `:224`, the `_checkpoint_lib.py` bullet: `commit_directive(legacy_paths)`,
     `legacy_unstage_directive`, and "the clause-file refusal prints alone"
     is now false.
   - Step 1's items: the `_lib.sh` bullet (`handoff_frame`'s legacy
     arguments and flags, `handoff_frame_notes`, `HANDOFF_LEGACY_REL_*`), the
     `load-handoff.sh` and `load-compact.sh` bullets, and "Frame assembly".
8. `CLAUDE.md`, Testing:
   - The `tests/test_checkpoint.py` paragraph: add the migration rows (move
     per action, headings-only root replaced, root wins, body-less-after-write
     removal, precompact, rejection byte-identity, stdout order, the git act
     under with-commit only, NFR1 over a tracked legacy file, autoname
     untouched, mtime, the directory refusal) and their mutation checks.
   - `:442`, "refusal printed alone on a held and an armed fixture": now
     false.
   - The `tests/hook-test.bats` paragraph (step 1's item).
9. `TODO.md`:
   - The retirement item, carrying the condition and
     `ls /Users/david/code/*/.claude/handoff-*.md`.
   - The `checkpoint.py` split suggested above.
   - The pre-existing newline-in-cwd bug in `load-handoff.sh:24-26` (step 1
     review).
10. The loader note "Task loaded from legacy …; the next checkpoint moves it
    to TASK.md." (`scripts/_lib.sh:121`) does not match what the checkpoint
    does with a task. Under `handoff` the task is always a content write or
    `clear`, and under `precompact` it is removed, so a legacy task file is
    never moved: it is removed and its bytes replaced. The design docs
    should say "replaces" for the task half, or the note should change. That
    is a loader wording call, in step 1's territory.
11. The plan's "One marker" wording: the constants are
    `HANDOFF_LEGACY_REL_*` mirrored by hand, not one `LEGACY_RELS` (step 1's
    item 8). If F1 is taken, add a `Corrected at review` blockquote on the
    Checkpoint contract's git act.

## Decisions needing my human partner

1. **F1: the git act's pathspec form.**
   - (a) `:/`-prefixed pathspecs, with the test helper updated and a
     subdirectory-cwd row added, red first. This is the default.
   - (b) `git -C <quoted root> rm ...`.
   - (c) Keep the contract's bare relative form.
2. **F4: a symlink at the legacy path.**
   - (a) Refuse it, like the directory case. This is the default.
   - (b) Move the target's bytes.
   - (c) Accept the dangling link.
3. **F5: a cross-device move.**
   - (a) `shutil.move`. This is the default.
   - (b) Turn the `OSError` into an `err()`.
   - (c) Accept the traceback.
4. **Whether to schedule the `checkpoint.py` split** (811 lines) as a
   `TODO.md` item now. Default: yes, as a separate item, not in this plan.
