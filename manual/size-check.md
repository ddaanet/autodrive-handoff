# The size check

Part of the claude-plugin-dev manual; [README.md](../README.md) is the rest.

`just check-size` refuses a file that has grown too large to read in one go. It
is opt-in: a plugin that does not wire it is unaffected, and `release`,
`precommit` and `prerelease` keep their contract.

## The metric and the caps

A file's size is its **bytes**: exactly what `wc -c` prints, counted per file,
whitespace, indentation and newlines included. The caps aim at about 10k and 5k
tokens as an agent reads the file. Lines are not the measure because a line
count rewards cramming long lines; bytes move little when text is re-wrapped,
which swaps spaces for newlines and repeats only each new line's indentation and
leader.

| File | Cap |
| --- | --- |
| any file | 20000 bytes |
| a `SKILL.md`, at any depth | 10000 bytes |

The hub cap is lower because a `SKILL.md` is paid for on every invocation, while
any other file is read only when opened. A file at exactly its cap passes; one
byte over fails. The caps are constants in the script, not options.

## Wiring it

Add `check-size` beside `check-refs` as a dependency of the commit gate:

```just
precommit: check-refs check-size
```

It runs uncached, on every call. It reads every file git does not ignore, a set
no sentinel's pathspecs cover whole, so inside a narrower cached gate body a
cached pass could commit a file the check never read. A dependency runs before
the recipe body, ahead of any sentinel guard, which is where this check belongs;
it reads every size with one batched `stat`, which takes well under a second on
a repository the size of gitlore (about 0.35 s, measured on Linux under load).
See
[Gate sentinels](gates.md).

It needs `bash`, `git`, `xargs` and a GNU or BSD `stat`.

## What it reads

Every file git lists that is not ignored, tracked or not, read from disk and not
from the index, from the repository root whatever the directory you run it in.
The skips apply in this order; a file stops at the first that takes it:

1. **Ignored files** are not listed at all.
2. **Symlinks** are skipped and counted, never followed.
3. **Anything that is not a regular file**, a gitlink or a file deleted from
   disk but still in the index, is skipped silently.
4. **Unreadable files** are skipped with a stderr line,
   `check-size: unreadable file skipped: <path>`, and counted.
5. **Binary files**, those whose content git detects as binary (`w/-text` in
   `git ls-files --eol`; a `.gitattributes` `binary` or `-text` attribute does
   not skip a text file), are skipped and counted.
6. **Built-ins**: `plugin-dev/` and a root `plans/`, each as a whole leading
   path component (`plans-old/` is not skipped, nor is `docs/plans/`), and a
   file named `uv.lock` or `package-lock.json` at any depth.

What remains is counted. `size.exempt`, below, does not skip a file: it forgives
an overage after the count.

## `size.exempt`

A root file `size.exempt` names files and directories allowed to stay over a
cap, each with a reason. One entry per line, a path relative to the repository
root, then ` #` and the reason:

```text
# Overages that have an end. Each line says why and what ends it.
skills/review/SKILL.md # split into references/ nodes once the checklist settles
docs/legacy # moved out in the 2.0 cleanup
```

Blank lines and lines whose first non-blank character is `#` are skipped. The
path ends where the first space-then-`#` starts, so a path cannot contain one.
Paths are literal, with no globs; a trailing `/` on a directory entry is
accepted, as in `dist.include`. A directory entry covers every file below it.

The list is for overages that have an end. It is not a place to park history:
each entry is checked on every run and refused once it stops being true, so the
list shrinks as the files are split. A file entry is a **ratchet**: it must name
a file that is over its cap now, so a file split below the cap makes its entry
refuse until you delete the line. A directory entry only has to match a counted
file below it, so it does not trip when its files shrink; delete it when the
reason ends.

Every refusal is one stderr line, `size.exempt:<line>: <path> — <why>`, and
fails the run even when no file is over a cap:

| Refusal | Cause |
| --- | --- |
| `no reason after the hash` | no ` #`, or nothing after it |
| `matches no listed file` | the path is not a counted file or a directory holding one: a typo, an ignored, binary or deleted file, a skipped symlink |
| `a built-in is always skipped` | the path is `plugin-dev`, `plans`, or inside either, or a lockfile basename |
| `a file entry must be over its cap` | the named file is at or under its cap (a `SKILL.md` is held to the hub cap) |
| `already listed on an earlier line` | the same path, after trimming a trailing `/` |

`size.exempt` differs from `refs.exempt` (see
[Reference check](../README.md#reference-check)) in two ways. Its entries
**add** to the built-ins, never replace them; `refs.exempt` replaces its
defaults, and an empty one exempts nothing. And its entries are held to being
still needed, where `refs.exempt` is frozen history that is never re-examined.
`size.exempt` is itself a file the check counts.

## The report

A pass prints one line on stdout and exits 0:

```text
check-size: cap 20000 bytes: 74 files; hub cap 10000: 2 SKILL.md; size.exempt: 1 entries, each with a reason and still needed; skipped: 31 plans/plugin-dev/lockfiles, 3 binary, 0 symlinks, 0 unreadable
```

The counts are the files compared against a cap, the `SKILL.md` among them, the
accepted `size.exempt` entries, and each skip category. A failure exits 1 with
one stderr line per overage, sorted by path, then the hint:

```text
oversized-file: docs/guide.md: 20311 bytes > 20000
oversized-file: skills/review/SKILL.md: 10412 bytes > 10000 (SKILL.md hub)
hint: split each file along a seam; do not shave prose or docstrings to fit
```

Running outside a git work tree, an unreadable `size.exempt` and an empty
listing each end the run with one line, `check-size: <reason>`.

## When it fails

Split the file along a seam: a section that stands alone becomes a file of its
own, a source file's second responsibility moves to a sibling, a `SKILL.md` hub
keeps the decision and hands detail to nodes under `references/`. Leave a link
where the text was.

Do not shave prose, docstrings or comments to fit. Removing the words that make
a file understandable lowers the count and the file stays too large; a file
parked just under its cap has stopped signalling that there is a seam to find.
Reach for `size.exempt` only when the overage has a known end.
