#!/usr/bin/env python3
"""Print the report's markdown tables (identifiers, dates, labels and counts only). usage: report_tables.py <dir>"""
import collections, json, os, sys
D = sys.argv[1]
A = [json.loads(l) for l in open(os.path.join(D, "all-rounds.jsonl"))]
R = [a for a in A if a["class"] not in ("SELF", "EXCL")]
C = json.load(open(os.path.join(D, "comparison.json")))
rows = {r["rid"]: r for r in C["rows"]}
RED = ("D", "D+", "Dd")
repo = lambda a: a["project"].replace("-Users-david-code-", "")
print("| Month | Rounds | Redirected | Rejected | Approved as is |\n|---|---|---|---|---|")
g = collections.defaultdict(collections.Counter)
for a in R: g[a["date"][:7]][a["class"]] += 1
for m in sorted(g):
    c = g[m]; n = sum(c.values()); red = sum(c[x] for x in RED)
    print(f"| {m} | {n} | {red} ({100*red/n:.0f}%) | {c['X']} | {c['A']} ({100*c['A']/n:.0f}%) |")
print()
print("| Repository | Rounds | Redirected | Rejected | Approved as is |\n|---|---|---|---|---|")
g = collections.defaultdict(collections.Counter)
for a in R: g[repo(a)][a["class"]] += 1
for m in sorted(g, key=lambda k: (-sum(g[k].values()), k)):
    c = g[m]; n = sum(c.values()); red = sum(c[x] for x in RED)
    print(f"| {m} | {n} | {red} | {c['X']} | {c['A']} |")
print()
def res(r):
    fs = [f for f in r["facts"] if f["kind"] == "redirect"]
    same = sum(1 for f in fs if f["rev_to"] == f["human_to"]); anyd = sum(1 for f in fs if f["rev_to"])
    if len(fs) > 1: return f"{same}/{len(fs)} same" + (f", {anyd-same} other" if anyd > same else "")
    return "same" if same else ("other place" if anyd else "missed")
print("| Round | Date | Repository | Session | Class | Move | Reviewer |\n|---|---|---|---|---|---|---|")
for a in sorted(R, key=lambda a: (a["date"], a["rid"])):
    if a["class"] in RED:
        mv = ", ".join(sorted({f"{frm}→{to}" for _, frm, to in a["redirects"]}))
        print(f"| {a['rid']} | {a['date'][5:]} | {repo(a)} | `{a['sid'][:8]}` | {a['class']} | {mv} | {res(rows[a['rid']])} |")
print()
print("| Round | Date | Repository | Session | Reviewer on the rejected fact |\n|---|---|---|---|---|")
for a in sorted(R, key=lambda a: (a["date"], a["rid"])):
    if a["class"] == "X":
        fs = [f for f in rows[a["rid"]]["facts"] if f["kind"] == "reject"]
        t = sorted({f["rev_to"] for f in fs if f["rev_to"]})
        print(f"| {a['rid']} | {a['date'][5:]} | {repo(a)} | `{a['sid'][:8]}` | {('to ' + ', '.join(t)) if t else 'no objection'} |")
