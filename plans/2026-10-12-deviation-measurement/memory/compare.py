#!/usr/bin/env python3
"""Join the blind reviewer's verdicts to the frozen human labels.

usage: compare.py <dir> [fact-map.json]

Reads <dir>/blind-verdicts.jsonl, <dir>/withheld/key.jsonl and
<dir>/all-rounds.jsonl; writes <dir>/comparison.json and prints the tables.
A human fact and a reviewer redirection are joined when the reviewer's `fact`
string contains the slug's basename; `fact-map.json` ({pid: {human fact:
reviewer fact or null}}) settles the ones that need a hand.
"""

import collections
import json
import os
import re
import sys

D = sys.argv[1]
FMAP = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else {}
CAT = {"PM": "project-memory", "ST": "shared-tier", "AL": "always-loaded", "SK": "skill", "TOOL": "code-or-tool", "DOC": "design-doc", "TODO": "todo", "NONE": "nowhere"}
PLACES = set(CAT.values())
# rule first present in a written artefact, per cited rule family
SKILL_SHIPPED = "2026-08-28"
SEPT_ADDITIONS = "2026-09-02"  # hook-or-tool owner, the literal-vs-activity test of Q5
PREDECESSOR = "2026-07-26"  # first owner-rule memory fact in the shared tier

key = [json.loads(line) for line in open(os.path.join(D, "withheld", "key.jsonl"))]
verd = {}
problems = []
for n, line in enumerate(open(os.path.join(D, "blind-verdicts.jsonl")), 1):
    line = line.strip()
    if not line:
        continue
    try:
        v = json.loads(line)
    except Exception as exc:
        problems.append(f"line {n}: {exc}")
        continue
    if v.get("id") in verd:
        problems.append(f"duplicate {v.get('id')}")
    verd[v.get("id")] = v
    for r in v.get("redirections", []):
        if r.get("to") not in PLACES or r.get("from") not in PLACES:
            problems.append(f"{v.get('id')}: place outside vocabulary: {r.get('from')} -> {r.get('to')}")
        if r.get("confidence") not in ("high", "low"):
            problems.append(f"{v.get('id')}: confidence {r.get('confidence')!r}")
missing = [k["pid"] for k in key if k["pid"] not in verd]
if missing:
    problems.append("missing: " + ", ".join(missing))
print("validation:", "ok, %d verdicts" % len(verd) if not problems else problems)


def base(slug):
    s = re.sub(r"\(.*?\)", "", slug).strip()
    return s.split("/")[-1].strip().lower()


def join(pid, human_fact, reds):
    m = FMAP.get(pid, {})
    if human_fact in m:
        want = m[human_fact]
        return next((r for r in reds if r["fact"] == want), None) if want else None
    b = base(human_fact)
    for r in reds:
        if b and b in r["fact"].lower():
            return r
    return None


def bucket(date):
    if date < PREDECESSOR:
        return "before any written owner rule"
    if date < SKILL_SHIPPED:
        return "predecessor memory facts only"
    return "skill shipped, gate runs it"


rows = []
fact_rows = []
unmatched_notes = []
for k in key:
    v = verd.get(k["pid"], {"verdict": "missing"})
    reds = v.get("redirections", [])
    used = set()
    hf = []
    for fact, frm, to in k["redirects"]:
        r = join(k["pid"], fact, reds)
        if r:
            used.add(id(r))
        hf.append({"pid": k["pid"], "rid": k["rid"], "date": k["date"], "kind": "redirect", "fact": fact, "human_to": CAT[to], "rev_to": r["to"] if r else None, "rev_conf": r["confidence"] if r else None, "rev_rule": r["rule"] if r else None})
    for fact in k["rejects"]:
        r = join(k["pid"], fact, reds)
        if r:
            used.add(id(r))
        hf.append({"pid": k["pid"], "rid": k["rid"], "date": k["date"], "kind": "reject", "fact": fact, "human_to": "nowhere", "rev_to": r["to"] if r else None, "rev_conf": r["confidence"] if r else None, "rev_rule": r["rule"] if r else None})
    extra = [r for r in reds if id(r) not in used]
    if len(reds) > 0 and len(k["redirects"]) + len(k["rejects"]) > 0 and extra:
        unmatched_notes.append((k["pid"], k["rid"], [h["fact"] for h in hf if h["rev_to"] is None], [r["fact"] for r in extra]))
    fact_rows += hf
    rows.append({"pid": k["pid"], "rid": k["rid"], "class": k["class"], "date": k["date"], "project": k["project"], "n_rev": len(reds), "n_rev_high": sum(1 for r in reds if r["confidence"] == "high"), "extra": [{"fact": r["fact"], "to": r["to"], "conf": r["confidence"], "rule": r["rule"]} for r in extra], "rules": [r["rule"] for r in reds], "facts": hf})

print("\nrounds needing a hand join (human facts unmatched | reviewer facts unmatched):")
for u in unmatched_notes:
    print(" ", u)


def rate(a, b):
    return f"{a}/{b}" + (f" ({100 * a / b:.0f}%)" if b else "")


out = {}
print("\n== round level")
dcls = ("D", "D+", "Dd")
dr = [r for r in rows if r["class"] in dcls]
for label, pred in (("any confidence", lambda f: f["rev_to"] is not None), ("high confidence", lambda f: f["rev_conf"] == "high")):
    hit_any = [r for r in dr if any(f["kind"] == "redirect" and pred(f) for f in r["facts"])]
    hit_same = [r for r in dr if any(f["kind"] == "redirect" and pred(f) and f["rev_to"] == f["human_to"] for f in r["facts"])]
    print(f"recall on redirected rounds, {label}: same fact any destination {rate(len(hit_any), len(dr))}; same destination {rate(len(hit_same), len(dr))}")
    out[f"round_recall_{label}"] = {"any_dest": len(hit_any), "same_dest": len(hit_same), "n": len(dr)}
    for b in ("before any written owner rule", "predecessor memory facts only", "skill shipped, gate runs it"):
        sub = [r for r in dr if bucket(r["date"]) == b]
        ha = [r for r in sub if r in hit_any]
        hs = [r for r in sub if r in hit_same]
        print(f"   {b}: any {rate(len(ha), len(sub))}; same {rate(len(hs), len(sub))}")
        out[f"round_recall_{label}"][b] = {"any_dest": len(ha), "same_dest": len(hs), "n": len(sub)}
    for c in dcls:
        sub = [r for r in dr if r["class"] == c]
        print(f"   class {c}: any {rate(len([r for r in sub if r in hit_any]), len(sub))}; same {rate(len([r for r in sub if r in hit_same]), len(sub))}")
xr = [r for r in rows if r["class"] == "X"]
x_now = [r for r in xr if any(f["kind"] == "reject" and f["rev_to"] == "nowhere" for f in r["facts"])]
x_any = [r for r in xr if any(f["kind"] == "reject" and f["rev_to"] is not None for f in r["facts"])]
print(f"rejected rounds: reviewer said nowhere on the rejected fact {rate(len(x_now), len(xr))}; objected to it at all {rate(len(x_any), len(xr))}")
out["reject_rounds"] = {"nowhere": len(x_now), "any": len(x_any), "n": len(xr)}

print("\n== false alarms on approved-as-is rounds (sampled)")
ar = [r for r in rows if r["class"] == "A"]
fa = collections.OrderedDict()
for m in sorted({r["date"][:7] for r in ar}):
    sub = [r for r in ar if r["date"][:7] == m]
    a = sum(1 for r in sub if r["n_rev"])
    h = sum(1 for r in sub if r["n_rev_high"])
    fa[m] = {"n": len(sub), "any": a, "high": h}
    print(f"  {m}: any {rate(a, len(sub))}; high-confidence {rate(h, len(sub))}")
tot = len(ar)
print(f"  all: any {rate(sum(v['any'] for v in fa.values()), tot)}; high {rate(sum(v['high'] for v in fa.values()), tot)}")
out["false_alarm_sample"] = fa
other = [r for r in rows if r["class"] in ("S", "Q")]
for r in other:
    print(f"  class {r['class']} {r['rid']}: reviewer redirections {r['n_rev']}")

print("\n== fact level")
hr = [f for f in fact_rows if f["kind"] == "redirect"]
hx = [f for f in fact_rows if f["kind"] == "reject"]
print("human-redirected facts:", len(hr), "| reviewer same destination", sum(1 for f in hr if f["rev_to"] == f["human_to"]), "| other destination", sum(1 for f in hr if f["rev_to"] not in (None, f["human_to"])), "| missed", sum(1 for f in hr if f["rev_to"] is None))
print("human-rejected facts:", len(hx), "| reviewer nowhere", sum(1 for f in hx if f["rev_to"] == "nowhere"), "| other destination", sum(1 for f in hx if f["rev_to"] not in (None, "nowhere")), "| missed", sum(1 for f in hx if f["rev_to"] is None))
print("destination pairs (human -> reviewer):", collections.Counter((f["human_to"], f["rev_to"]) for f in hr).most_common())
extra_in_flagged = sum(len(r["extra"]) for r in rows if r["class"] != "A")
print("reviewer redirections on facts the human kept, inside redirected/rejected rounds:", extra_in_flagged)
print("reviewer redirections in approved rounds:", sum(r["n_rev"] for r in ar))
print("rules cited:", collections.Counter(re.sub(r"\s+", " ", x) for r in rows for x in r["rules"]).most_common())
out["fact_level"] = {"redirect_n": len(hr), "redirect_same": sum(1 for f in hr if f["rev_to"] == f["human_to"]), "redirect_other": sum(1 for f in hr if f["rev_to"] not in (None, f["human_to"])), "reject_n": len(hx), "reject_nowhere": sum(1 for f in hx if f["rev_to"] == "nowhere"), "reject_other": sum(1 for f in hx if f["rev_to"] not in (None, "nowhere")), "extra_in_flagged": extra_in_flagged}
out["rows"] = rows
out["problems"] = problems
json.dump(out, open(os.path.join(D, "comparison.json"), "w"), indent=1, ensure_ascii=False)
