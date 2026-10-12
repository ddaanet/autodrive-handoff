#!/usr/bin/env python3
"""Draw the reading sample for the judgement classes.

usage: sample.py <frames-dir>

Stratified by era, seeded, at most one version per (repo, day) so that
near-copies written minutes apart do not fill the sample. Writes
<frames-dir>/sample-task.txt and sample-todo.txt (frame text under an id line)
and sample.tsv (id, repo, blob, date, era, kind).
"""
import csv, os, random, sys
base = sys.argv[1]
QUOTA = {"task": {"e1": 8, "e2": 6, "e3": 10, "e4": 20, "e5": 6},
         "todo": {"e3": 10, "e4": 26, "e5": 5}}
frames = [f for f in csv.DictReader(open(os.path.join(base, "frames.tsv")), delimiter="\t")
          if f["authored"] in ("plugin", "copy")]  # drawn before copies were told apart
rng = random.Random(20261012)
rows = []
for kind, quota in QUOTA.items():
    out = open(os.path.join(base, f"sample-{kind}.txt"), "w")
    for era, n in quota.items():
        pool = sorted((f for f in frames if f["kind"] == kind and f["era"] == era),
                      key=lambda f: (f["repo"], f["date"], f["blob"]))
        rng.shuffle(pool)
        seen, picked = set(), []
        for f in pool:
            k = (f["repo"], f["date"])
            if k in seen:
                continue
            seen.add(k)
            picked.append(f)
            if len(picked) == n:
                break
        for i, f in enumerate(sorted(picked, key=lambda f: (f["repo"], f["date"]))):
            sid = f"{'T' if kind == 'task' else 'D'}-{era}-{i+1:02d}"
            fn = [x for x in os.listdir(os.path.join(base, "blobs", f["repo"]))
                  if x.startswith(f["blob"])][0]
            text = open(os.path.join(base, "blobs", f["repo"], fn), encoding="utf-8",
                        errors="replace").read()
            out.write(f"\n=== {sid} {f['repo']} {f['date']} {f['paths']} body={f['body_chars']}\n{text}\n")
            rows.append([sid, f["repo"], f["blob"], f["date"], era, kind, f["body_chars"]])
    out.close()
with open(os.path.join(base, "sample.tsv"), "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t")
    w.writerow(["id", "repo", "blob", "date", "era", "kind", "body_chars"])
    w.writerows(rows)
print(len(rows), "sampled")
