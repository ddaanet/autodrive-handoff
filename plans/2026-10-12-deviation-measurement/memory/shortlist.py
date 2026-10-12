#!/usr/bin/env python3
"""Shortlist transcripts naming a memory-approval anchor; print layout stats."""
import os, sys, subprocess, collections
root = sys.argv[1]
anchors = ["gitlore-memory-message", "gitlore-commit-msg", "commit-memory.sh", "gitlore-commit-memory", "memory has uncommitted changes"]
args = ["grep", "-rlF", "--include=*.jsonl"]
for a in anchors:
    args += ["-e", a]
out = subprocess.run(args + [root], capture_output=True, text=True).stdout.split("\n")
files = [f for f in out if f]
kinds = collections.Counter()
proj = collections.Counter()
mains = []
for f in files:
    rel = os.path.relpath(f, root).split(os.sep)
    if len(rel) == 2:
        kinds["main"] += 1; proj[rel[0]] += 1; mains.append(f)
    elif "subagents" in rel:
        kinds["subagent"] += 1
    else:
        kinds["other:" + "/".join(rel[1:-1])[:40]] += 1
print(kinds)
for p, n in proj.most_common():
    print(n, p)
with open(sys.argv[2], "w") as fh:
    fh.write("\n".join(sorted(files)) + "\n")
