#!/usr/bin/env python3
"""Class counts over all rounds: overall, per month, per repository. usage: stats.py <dir>"""
import collections, json, os, sys
D = sys.argv[1]
A = [json.loads(l) for l in open(os.path.join(D, "all-rounds.jsonl"))]
O = [json.loads(l) for l in open(os.path.join(D, "other.jsonl"))]
print("episodes:", len({(a["sid"], a["rid"][:4]) for a in A}), "units:", len(A))
print("other:", dict(collections.Counter(o["what"] for o in O)))
cls = collections.Counter(a["class"] for a in A)
print("classes:", dict(cls))
R = [a for a in A if a["class"] not in ("SELF", "EXCL")]
print("rounds:", len(R), "closed:", sum(1 for a in R if a["closed"]), "sessions:", len({a["sid"] for a in R}), "repos:", len({a["project"] for a in R}))
RED = ("D", "D+", "Dd")
def table(keyf, title):
    print("\n" + title)
    g = collections.defaultdict(collections.Counter)
    for a in R: g[keyf(a)][a["class"]] += 1
    for k in sorted(g, key=lambda k: (-sum(g[k].values()), k) if title.startswith("per repo") else k):
        c = g[k]; n = sum(c.values()); red = sum(c[x] for x in RED)
        print(f"  {k:22s} n={n:3d} A={c['A']:3d} W={c['W']} C={c['C']} D={c['D']} D+={c['D+']} Dd={c['Dd']} X={c['X']} S={c['S']} Q={c['Q']} O={c['O']} N={c['N']}  redirected={red} ({100*red/n:.0f}%)  redirected+rejected={red+c['X']} ({100*(red+c['X'])/n:.0f}%)")
table(lambda a: a["date"][:7], "per month")
table(lambda a: a["project"].replace("-Users-david-code-", ""), "per repo")
table(lambda a: "all", "overall")
# half-month view of the last two months
table(lambda a: a["date"][:7] + ("a" if a["date"][8:10] <= "15" else "b"), "per half month")
facts = collections.Counter(); 
for a in R:
    for f, frm, to in a["redirects"]: facts[(a["class"], frm, to)] += 1
print("\nredirected facts by (class, from, to):"); 
for k, v in sorted(facts.items(), key=lambda kv: -kv[1]): print("  ", k, v)
pairs = collections.Counter()
for a in R:
    if a["class"] in RED:
        for p in {(frm, to) for f, frm, to in a["redirects"]}: pairs[p] += 1
print("redirected rounds by (from, to) [a round counts once per distinct pair]:", sorted(pairs.items(), key=lambda kv: -kv[1]))
print("rules invoked by the human:", [a["rid"] for a in R if a["rules_invoked"]])
print("ambiguous:", [(a["rid"], a["amb"]) for a in R if a["amb"]])
print("rejected facts:", sum(len(a["rejects"]) for a in R), "in rounds:", sum(1 for a in R if a["rejects"]))
print("unfinished by class:", dict(collections.Counter(a["class"] for a in R if not a["closed"])))
print("auto-labelled approvals:", sum(1 for a in R if a["auto"]), "hand-labelled:", sum(1 for a in R if not a["auto"]))
print("first/last round:", min(a["date"] for a in R), max(a["date"] for a in R))
