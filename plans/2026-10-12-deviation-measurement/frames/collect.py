#!/usr/bin/env python3
"""Inventory every written version of a handoff frame file.

usage: collect.py <code-root> <out-dir>

For each git repository directly under <code-root>, walks `git log --all --raw`
for the frame paths (streamed, one process per repository), records every
(repo, path, blob) with the earliest author date it appears at, fetches each
distinct blob once through `git cat-file --batch`, and adds the working-copy
files (root and linked worktrees), tracked or not. Read-only on the
repositories. Writes <out-dir>/versions.tsv and <out-dir>/blobs/<repo>/<blob>.
"""

import csv
import hashlib
import os
import subprocess
import sys

PATHS = {
    ".claude/handoff-task.md": "task",
    "TASK.md": "task",
    ".claude/handoff-todo.md": "todo",
    "TODO.md": "todo",
    ".claude/handoff.md": "generated",
}
ZERO = "0" * 40


def git(repo, *args):
    return subprocess.Popen(
        ["git", "-C", repo, *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )


def history(repo):
    """Yield (path, blob, sha, author_iso, commit_iso) for every commit side."""
    proc = git(
        repo,
        "log",
        "--all",
        "--raw",
        "--no-abbrev",
        "--no-renames",
        "-m",
        "--format=C %H %aI %cI",
        "--",
        *PATHS,
    )
    sha = adate = cdate = None
    for raw in proc.stdout:
        line = raw.decode("utf-8", "replace").rstrip("\n")
        if line.startswith("C "):
            _, sha, adate, cdate = line.split(" ")[:4]
        elif line.startswith(":"):
            meta, path = line.split("\t", 1)
            blob = meta.split(" ")[3]
            if blob != ZERO and path in PATHS:
                yield path, blob, sha, adate, cdate
    proc.wait()


def fetch(repo, blobs, dest):
    """Write each blob to dest/<blob>; one cat-file process, streamed."""
    os.makedirs(dest, exist_ok=True)
    proc = subprocess.Popen(
        ["git", "-C", repo, "cat-file", "--batch"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    for blob in blobs:
        proc.stdin.write((blob + "\n").encode())
        proc.stdin.flush()
        head = proc.stdout.readline().decode().split()
        if len(head) < 3 or head[1] != "blob":
            continue
        size = int(head[2])
        data = proc.stdout.read(size)
        proc.stdout.read(1)
        with open(os.path.join(dest, blob), "wb") as fh:
            fh.write(data)
    proc.stdin.close()
    proc.wait()


def blob_id(data):
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def worktrees(repo):
    out = subprocess.run(
        ["git", "-C", repo, "worktree", "list", "--porcelain"],
        capture_output=True,
        text=True,
    ).stdout
    return [l[9:] for l in out.splitlines() if l.startswith("worktree ")]


def main():
    root, out = sys.argv[1], sys.argv[2]
    rows = []
    for name in sorted(os.listdir(root)):
        repo = os.path.join(root, name)
        if not os.path.exists(os.path.join(repo, ".git")):
            continue
        seen = {}  # (path, blob) -> [first author date, sha, n commits, commit date]
        for path, blob, sha, adate, cdate in history(repo):
            key = (path, blob)
            cur = seen.get(key)
            if cur is None:
                seen[key] = [adate, sha, 1, cdate]
            else:
                cur[2] += 1
                if adate < cur[0]:
                    cur[0], cur[1], cur[3] = adate, sha, cdate
        dest = os.path.join(out, "blobs", name)
        if seen:
            fetch(repo, sorted({b for _, b in seen}), dest)
        for (path, blob), (adate, sha, n, cdate) in seen.items():
            rows.append([name, path, PATHS[path], "history", blob, sha, adate, cdate, n])
        for tree in worktrees(repo) or [repo]:
            for path in PATHS:
                full = os.path.join(tree, path)
                if not os.path.isfile(full) or os.path.islink(full):
                    continue
                with open(full, "rb") as fh:
                    data = fh.read()
                blob = blob_id(data)
                st = os.stat(full)
                tracked = (
                    subprocess.run(
                        ["git", "-C", tree, "ls-files", "--error-unmatch", path],
                        capture_output=True,
                    ).returncode
                    == 0
                )
                os.makedirs(dest, exist_ok=True)
                with open(os.path.join(dest, blob), "wb") as fh:
                    fh.write(data)
                from datetime import datetime, timezone

                mtime = datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(
                    timespec="seconds"
                )
                src = "working-copy" if tree == repo else "worktree:" + os.path.basename(tree)
                in_hist = (path, blob) in seen
                rows.append(
                    [
                        name,
                        path,
                        PATHS[path],
                        src + (":tracked" if tracked else ":untracked")
                        + (":in-history" if in_hist else ":new"),
                        blob,
                        "working copy",
                        mtime,
                        mtime,
                        0,
                    ]
                )
    with open(os.path.join(out, "versions.tsv"), "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow("repo path kind source blob commit adate cdate ncommits".split())
        w.writerows(rows)
    print(len(rows), "rows")


if __name__ == "__main__":
    main()
