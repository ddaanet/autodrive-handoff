#!/usr/bin/env python3
"""Join the 2026-10-11 overflow labelling to this inventory.

usage: join_labels.py <code-root> <labels.tsv> <frames-dir>

labels.tsv (plans/2026-10-11-task-and-todo-move-to-root/reports/overflow/)
holds one row per sentence-unit of 441 task-file versions, labelled by a Haiku
reader: A task in hand, B plan and open decisions, C rules and conventions,
D already done. It keys a version by commit sha8 and a pseudonymous repo name,
so the commit is resolved to its task blob by walking each repository's log
(read-only) and the blob to a frame of frames.tsv.

Writes <frames-dir>/prior-labels.tsv: one row per frame, the unit and
character counts per label.
"""

import csv
import os
import subprocess
import sys
from collections import defaultdict

PATH = ".claude/handoff-task.md"


def commit_blobs(repo):
    proc = subprocess.Popen(
        ["git", "-C", repo, "log", "--all", "--raw", "--no-abbrev", "--no-renames",
         "-m", "--format=C %H", "--", PATH],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    sha = None
    for raw in proc.stdout:
        line = raw.decode("utf-8", "replace").rstrip("\n")
        if line.startswith("C "):
            sha = line[2:]
        elif line.startswith(":"):
            blob = line.split("\t")[0].split(" ")[3]
            if set(blob) != {"0"}:
                yield sha[:8], blob
    proc.wait()


def main():
    root, labels, base = sys.argv[1:4]
    sha_to = defaultdict(set)
    for name in sorted(os.listdir(root)):
        repo = os.path.join(root, name)
        if os.path.exists(os.path.join(repo, ".git")):
            for sha8, blob in commit_blobs(repo):
                sha_to[sha8].add((name, blob[:10]))
    per = defaultdict(lambda: defaultdict(lambda: [0, 0]))
    order = {}
    for r in csv.DictReader(open(labels), delimiter="\t"):
        cell = per[r["sha"]][r["label"]]
        cell[0] += 1
        cell[1] += int(r["chars"])
        order.setdefault(r["sha"], r["unit"].split(".")[0])
    frames = {
        (f["repo"], f["blob"]): f
        for f in csv.DictReader(open(os.path.join(base, "frames.tsv")), delimiter="\t")
        if f["kind"] == "task"
    }
    out, seen, miss = [], set(), 0
    for sha, labs in per.items():
        hits = [k for k in sha_to.get(sha, ()) if k in frames]
        if len(hits) != 1:
            miss += 1
            continue
        k = hits[0]
        if k in seen:  # two commits, one blob: the labelling saw it twice
            continue
        seen.add(k)
        f = frames[k]
        out.append([f["repo"], f["blob"], f["date"], f["era"]]
                   + [labs[x][i] for x in "ABCDE" for i in (0, 1)])
    with open(os.path.join(base, "prior-labels.tsv"), "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["repo", "blob", "date", "era"]
                   + [f"{x}_{s}" for x in "ABCDE" for s in ("units", "chars")])
        w.writerows(out)
    print(len(per), "labelled versions;", len(out), "distinct frames joined;",
          miss, "unresolved")


if __name__ == "__main__":
    main()
