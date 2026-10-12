#!/usr/bin/env python3
"""Print every table the report cites, from the files the other scripts wrote.

usage: tally.py <frames-dir> <code-root>

<code-root> is read only for one question (section E): which files the commit
that first carried a frame also touched (`git show --name-only`, read-only).
"""

import csv
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

import collect
import frames as F  # the classifier, for its sentence splitter and regexes

F.PATHS = collect.PATHS

base, code = sys.argv[1], sys.argv[2]
ERAS = ["e1", "e2", "e3", "e4", "e5"]


def tsv(name):
    return list(csv.DictReader(open(os.path.join(base, name)), delimiter="\t"))


versions = tsv("versions.tsv")
fr = tsv("frames.tsv")
hits = tsv("hits.tsv")
plug = [f for f in fr if f["authored"] == "plugin"]


def pct(n, d):
    return f"{n}/{d} ({100 * n / d:.0f}%)" if d else f"{n}/0"


print("== A. inventory")
hist = [v for v in versions if v["source"] == "history"]
wc = [v for v in versions if v["source"] != "history"]
print("repos with a .git under the root:",
      sum(os.path.exists(os.path.join(code, d, ".git")) for d in os.listdir(code)))
print("history rows (repo, path, blob):", Counter(v["path"] for v in hist))
print("commit sides touching:", {p: sum(int(v["ncommits"]) for v in hist if v["path"] == p)
                                 for p in F.PATHS})
print("working-copy files:", Counter(v["path"] for v in wc), "of which not in history:",
      sum(v["source"].endswith(":new") for v in wc),
      "untracked:", sum(":untracked" in v["source"] for v in wc))
print("distinct versions (repo, kind, blob):", Counter((f["kind"], f["authored"]) for f in fr))
print("hand-kept by repo:", Counter(f["repo"] for f in fr if f["authored"] == "hand"))
print("plugin versions only in a working copy:",
      Counter(f["kind"] for f in plug if f["in_history"] == "0"))
glob = Counter((f["kind"], f["blob"]) for f in plug)
print("blobs present in more than one repo:", sum(1 for v in glob.values() if v > 1),
      "extra copies:", sum(v - 1 for v in glob.values() if v > 1))
for kind in ("task", "todo"):
    rows = [f for f in plug if f["kind"] == kind]
    by = Counter(f["repo"] for f in rows)
    print(kind, "repos:", len(by), "private repos:",
          len({f["repo"] for f in rows if f["private"] == "1"}),
          "versions in private repos:", sum(f["private"] == "1" for f in rows))
    print("  per repo:", ", ".join(f"{r} {n}" for r, n in by.most_common()))
    print("  per era:", {e: sum(f["era"] == e for f in rows) for e in ERAS})
    print("  distinct (repo, day):", len({(f["repo"], f["date"]) for f in rows}))

print("\n== B. mechanical classes, deviations only where the rule was in force")
den = {(k, e): sum(1 for f in plug if f["kind"] == k and f["era"] == e)
       for k in ("task", "todo") for e in ERAS}
classes = sorted({(h["kind"], h["class"]) for h in hits})
for kind, cls in classes:
    dev = Counter(h["era"] for h in hits if h["kind"] == kind and h["class"] == cls
                  and h["in_force"] == "1")
    tod = Counter(h["era"] for h in hits if h["kind"] == kind and h["class"] == cls
                  and h["in_force"] == "0")
    repos = len({h["repo"] for h in hits if h["kind"] == kind and h["class"] == cls
                 and h["in_force"] == "1"})
    print(f"{kind:5} {cls:24} dev " + " ".join(
        f"{e}:{dev[e]}/{den[(kind, e)]}" for e in ERAS) + f"  repos:{repos}  not-in-force " +
        " ".join(f"{e}:{tod[e]}" for e in ERAS if tod[e]))
t4 = [f for f in plug if f["kind"] == "task" and f["era"] == "e4"]
over = sum(int(f["body_chars"]) > 1000 for f in t4)
lst = sum(bool(f.get("x_fr13_list")) for f in t4)
both = sum(int(f["body_chars"]) > 1000 or bool(f.get("x_fr13_list")) for f in t4)
print("FR13 against e4 task versions: over 1000:", pct(over, len(t4)), "any list:",
      pct(lst, len(t4)), "either:", pct(both, len(t4)))
for e in ERAS:
    rows = [f for f in plug if f["kind"] == "task" and f["era"] == e]
    b = sorted(int(f["body_chars"]) for f in rows)
    s = sorted(int(f.get("ct_sentences") or 0) for f in rows)
    print(f"  task {e}: n={len(rows)} body median {b[len(b) // 2]} p90 {b[int(len(b) * .9)]}"
          f" sentences median {s[len(s) // 2]}; one sentence or fewer:",
          pct(sum(x <= 1 for x in s), len(s)))
td = [f for f in plug if f["kind"] == "todo"]
print("todo: unchecked boxes in", sum(int(f.get("unchecked_boxes") or 0) > 0 for f in td),
      "versions; items over 300 chars in", pct(sum(int(f.get("todo_items_over_300") or 0) > 0
                                                 for f in td), len(td)),
      "; prose outside items in", pct(sum(int(f.get("todo_prose_units") or 0) > 0 for f in td),
                                      len(td)))
any_dev = defaultdict(set)
for h in hits:
    if h["in_force"] == "1":
        any_dev[(h["kind"], h["repo"], h["blob"])].add(h["class"])
for kind in ("task", "todo"):
    for e in ERAS:
        rows = [f for f in plug if f["kind"] == kind and f["era"] == e]
        if rows:
            n = sum((kind, f["repo"], f["blob"]) in any_dev for f in rows)
            n2 = sum(bool(any_dev.get((kind, f["repo"], f["blob"]), set())
                          - {"commit_status_done"}) for f in rows)
            print(f"  {kind} {e}: any mechanical deviation {pct(n, len(rows))};"
                  f" not counting done-statements {pct(n2, len(rows))}")

print("  clusters: (repo, day) pairs with at least one deviating version / all pairs")
for kind, cls in (("task", "commit_status_pending"), ("task", "commit_status_done"),
                  ("task", "list_in_current_task"), ("task", "h1_heading"),
                  ("task", "extra_section"), ("task", "open_decisions_in_task"),
                  ("task", "no_template_heading"), ("todo", "commit_act_item"),
                  ("todo", "commit_status_pending")):
    line = []
    for e in ERAS:
        allp = {(f["repo"], f["date"]) for f in plug if f["kind"] == kind and f["era"] == e}
        devp = {(h["repo"], h["date"]) for h in hits if h["kind"] == kind
                and h["class"] == cls and h["in_force"] == "1" and h["era"] == e}
        if allp:
            line.append(f"{e}:{len(devp)}/{len(allp)}")
    print(f"   {kind} {cls}: " + " ".join(line))
od = [h for h in hits if h["class"] == "open_decisions_in_task"]
print("  open decisions still in the task: within 3 days of the release",
      sum(h["date"] <= "2026-08-15" for h in od), "later", sum(h["date"] > "2026-08-15" for h in od))

print("\n== C. the commit-status filter against the hand verdicts")
cand = tsv("commit-candidates.tsv")
NARROW = re.compile(
    r"\buncommit+ed\b|\bunpushed\b|\bnot\s+(?:yet\s+)?(?:been\s+)?(?:commit+ed|pushed)\b"
    r"|\bready\s+to\s+(?:commit|push)\b|\bnothing\s+(?:is|has\s+been)\s+(?:commit+ed|pushed)"
    r"|\babout\s+to\s+(?:be\s+)?commit|\bpending\s+commit\b|\bnon\s+commit[ée]e?s?\b"
    r"|\brien\s+n'est\s+pouss", re.I)
print("unique sentences:", len(cand), Counter(c["verdict"] for c in cand))
for name, rx in (("broad", None), ("narrow", NARROW)):
    sub = [c for c in cand if rx is None or rx.search(c["text"])]
    v = Counter(c["verdict"] for c in sub)
    print(f"  {name}: matched {len(sub)}; pending-status or act {v['status'] + v['act']}"
          f" ({100 * (v['status'] + v['act']) / len(sub):.0f}%); done-statement {v['log']};"
          f" sanctioned decision {v['decision']}; borderline {v['border']}; unrelated {v['no']}")
    per = defaultdict(Counter)
    for c in sub:
        for r in c["repos"].split("|"):
            per[r][c["verdict"]] += 1
    print("   per repo (matched: status+act / decision / no+border+log):", "; ".join(
        f"{r} {sum(x.values())}: {x['status'] + x['act']}/{x['decision']}/"
        f"{x['no'] + x['border'] + x['log']}" for r, x in sorted(per.items())
        if sum(x.values()) >= 5))
print("  narrow filter misses", sum(1 for c in cand if c["verdict"] in ("status", "act")
                                    and not NARROW.search(c["text"])),
      "of", sum(1 for c in cand if c["verdict"] in ("status", "act")), "true sentences")
print("  frames carrying a sanctioned commit decision:",
      sum(int(f.get("commit_decision") or 0) > 0 for f in plug))

print("\n== D. judgement classes")
plugkeys = {(f["repo"], f["blob"]) for f in plug}
pl = [r for r in tsv("prior-labels.tsv") if (r["repo"], r["blob"]) in plugkeys]
for e in ("e3", "e4"):
    s = [r for r in pl if r["era"] == e]
    n = len(s)
    print(f" prior labelling {e} n={n}: done-log (D>1 unit) {pct(sum(int(r['D_units']) > 1 for r in s), n)};"
          f" conventions (any C) {pct(sum(int(r['C_units']) >= 1 for r in s), n)};"
          f" C at least 2 units {pct(sum(int(r['C_units']) >= 2 for r in s), n)};"
          f" plan (B>=1) {pct(sum(int(r['B_units']) >= 1 for r in s), n)};"
          f" plan (B>=2) {pct(sum(int(r['B_units']) >= 2 for r in s), n)};"
          f" none of D>1, C, B>=2 {pct(sum(int(r['D_units']) <= 1 and int(r['C_units']) == 0 and int(r['B_units']) < 2 for r in s), n)}")
    rp = defaultdict(list)
    for r in s:
        rp[r["repo"]].append(r)
    print("   repos with a done-log version:", sum(any(int(r["D_units"]) > 1 for r in v) for v in rp.values()),
          "of", len(rp), "; with a conventions version:",
          sum(any(int(r["C_units"]) >= 1 for r in v) for v in rp.values()))
samp = {r["id"]: r for r in tsv("sample.tsv")}
mine = {}
for line in open(os.path.join(base, "my-labels.tsv"), encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    p = line.rstrip("\n").split("\t")
    mine[p[0]] = set(p[1].split(","))
for kind in ("task", "todo"):
    for e in ERAS:
        seen, ids = set(), []
        for i, s in samp.items():  # a copy in a second repository is read once
            if s["kind"] == kind and s["era"] == e and s["blob"] not in seen:
                seen.add(s["blob"])
                ids.append(i)
        if not ids:
            continue
        c = Counter(l for i in ids for l in mine[i])
        print(f" my reading {kind} {e} n={len(ids)}: " + ", ".join(
            f"{k} {v}" for k, v in sorted(c.items())))

print("\n== E. what happened to a frame carrying pending commit status")
first = {}
for v in versions:
    if v["source"] == "history":
        k = (v["repo"], F.PATHS[v["path"]], v["blob"][:10])
        if k not in first or v["adate"] < first[k][0]:
            first[k] = (v["adate"], v["commit"])
FRAME = set(F.PATHS) | {"memory"}
with_work = total = 0
for h in hits:
    if h["class"] != "commit_status_pending" or h["commit"] == "working copy":
        continue
    k = (h["repo"], h["kind"], h["blob"])
    out = subprocess.run(["git", "-C", os.path.join(code, h["repo"]), "show", "--name-only",
                          "--format=", first[k][1]], capture_output=True, text=True).stdout
    others = [p for p in out.split("\n") if p and p not in FRAME]
    total += 1
    with_work += bool(others)
print("frames with a pending-status sentence, committed:", total,
      "; whose first commit also carried other files:", with_work)

# Sentences carried verbatim from one version to the next, per repo and kind.
order = defaultdict(list)
for f in plug:
    k = (f["repo"], f["kind"], f["blob"])
    when = first.get(k, (f["date"] + "T99", ""))[0]
    order[(f["repo"], f["kind"])].append((when, f))
texts = {}


def sentences(f):
    key = (f["repo"], f["blob"])
    if key not in texts:
        fn = [x for x in os.listdir(os.path.join(base, "blobs", f["repo"]))
              if x.startswith(f["blob"])][0]
        t = open(os.path.join(base, "blobs", f["repo"], fn), encoding="utf-8",
                 errors="replace").read()
        texts[key] = {F.norm(u) for _, _, ls in F.sections(t) for u in F.units(ls)
                      if len(u) > 40}
    return texts[key]


for kind in ("task",):
    runs = Counter()
    long_lived = set()
    for (repo, k), lst in order.items():
        if k != kind:
            continue
        lst.sort(key=lambda x: x[0])
        age = {}
        for when, f in lst:
            cur = sentences(f)
            age = {s: (age[s][0] + 1, age[s][1] | {f["date"]}) if s in age
                   else (1, {f["date"]}) for s in cur}
            if any(n >= 3 and len(days) >= 2 for n, days in age.values()):
                long_lived.add((repo, f["blob"]))
    e4 = [f for f in plug if f["kind"] == kind and f["era"] == "e4"]
    print(f"{kind}: e4 versions holding a sentence unchanged through 3+ versions on 2+ days:",
          pct(sum((f["repo"], f["blob"]) in long_lived for f in e4), len(e4)))
pend = [c for c in cand if c["verdict"] == "status"]
print("pending-status sentences:", len(pend), "; appearing in more than one version:",
      sum(int(c["n"]) > 1 for c in pend), "; in more than one repo:",
      sum("|" in c["repos"] for c in pend))

print("\n== F. what a check beside FR13 would add, and what FR13 leaves")
STRUCT = {"h1_heading", "extra_section", "subheading", "no_template_heading",
          "open_decisions_in_task"}
t4 = [f for f in plug if f["kind"] == "task" and f["era"] == "e4"]
fr13 = lambda f: int(f["body_chars"]) > 1000 or bool(f.get("x_fr13_list"))
st = [f for f in t4 if any(f.get("x_" + c) == "dev" for c in STRUCT)]
print("e4 task versions with a heading-shape deviation:", pct(len(st), len(t4)),
      "; of those FR13 would already refuse:", sum(fr13(f) for f in st),
      "; after the first three days of the open-decisions move:",
      sum(f["date"] > "2026-08-15" for f in st),
      "of which FR13 refuses", sum(fr13(f) for f in st if f["date"] > "2026-08-15"))
plk = {(r["repo"], r["blob"]): r for r in pl}
passing = [plk[(f["repo"], f["blob"])] for f in t4
           if not fr13(f) and (f["repo"], f["blob"]) in plk]
failing = [plk[(f["repo"], f["blob"])] for f in t4
           if fr13(f) and (f["repo"], f["blob"]) in plk]
for name, s in (("would pass FR13", passing), ("would be refused by FR13", failing)):
    n = len(s)
    print(f" e4 versions that {name}, prior labelling n={n}:"
          f" done-log {pct(sum(int(r['D_units']) > 1 for r in s), n)};"
          f" conventions {pct(sum(int(r['C_units']) >= 1 for r in s), n)};"
          f" plan (B>=2) {pct(sum(int(r['B_units']) >= 2 for r in s), n)};"
          f" none {pct(sum(int(r['D_units']) <= 1 and int(r['C_units']) == 0 and int(r['B_units']) < 2 for r in s), n)}")
ids = [i for i, s in samp.items() if s["kind"] == "task" and s["era"] in ("e4", "e5")]
byblob = {(f["repo"], f["blob"]): f for f in plug}
p = [i for i in ids if not fr13(byblob[(samp[i]["repo"], samp[i]["blob"])])]
print(" my reading, e4+e5 sample versions that would pass FR13:", len(p), "of", len(ids),
      Counter(l for i in p for l in mine[i]))

hand = [f for f in fr if f["authored"] == "hand"]
chk = hdr = 0
for f in hand:
    fn = [x for x in os.listdir(os.path.join(base, "blobs", f["repo"]))
          if x.startswith(f["blob"])][0]
    t = open(os.path.join(base, "blobs", f["repo"], fn), encoding="utf-8",
             errors="replace").read()
    chk += any(F.CHECKED.match(l) for l in t.split("\n"))
    hdr += bool(set(f["h2"].split("|")) - {"Open decisions", "Remaining", ""}) or t.startswith("# ")
print("hand-kept TODO.md versions:", len(hand), "; with a checked box:", chk,
      "; with a heading outside the template:", hdr)

verd = {c["key"]: c["verdict"] for c in cand}
for kind in ("task", "todo"):
    rows = [f for f in plug if f["kind"] == kind and f["era"] == "e4"]
    fire = true = 0
    for f in rows:
        fn = [x for x in os.listdir(os.path.join(base, "blobs", f["repo"]))
              if x.startswith(f["blob"])][0]
        t = open(os.path.join(base, "blobs", f["repo"], fn), encoding="utf-8",
                 errors="replace").read()
        vs = [verd.get(F.key(u), "no") for _, _, ls in F.sections(t) for u in F.units(ls)
              if NARROW.search(u)]
        fire += bool(vs)
        true += any(v in ("status", "act") for v in vs)
    print(f"narrow commit filter over e4 {kind} versions: fires on {pct(fire, len(rows))};"
          f" rightly on {true}; wrongly on {fire - true}")
