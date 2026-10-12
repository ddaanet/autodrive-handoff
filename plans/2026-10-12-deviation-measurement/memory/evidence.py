#!/usr/bin/env python3
"""Render evidence.md: every round with its proposal, the human's reply and the blind verdict.

usage: evidence.py <dir>

Verbatim transcript material; stays under /tmp, never goes into the repository.
"""

import json
import os
import sys

D = sys.argv[1]
A = [json.loads(line) for line in open(os.path.join(D, "all-rounds.jsonl"))]
key = {}
for line in open(os.path.join(D, "withheld", "key.jsonl")):
    k = json.loads(line)
    key[k["rid"]] = k["pid"]
verd = {}
vp = os.path.join(D, "blind-verdicts.jsonl")
if os.path.exists(vp):
    for line in open(vp):
        line = line.strip()
        if line:
            v = json.loads(line)
            verd[v["id"]] = v
others = [json.loads(line) for line in open(os.path.join(D, "other.jsonl"))]

NAMES = {
    "A": "approved as is",
    "W": "wording edited",
    "C": "content corrected",
    "D": "destination redirected (moved or removed)",
    "D+": "destination added (fact kept, also sent to an owner)",
    "Dd": "destination redirected, deferred",
    "Q": "destination questioned, kept",
    "X": "rejected as not worth a memory",
    "S": "split or merged",
    "O": "other",
    "N": "no human reply",
    "SELF": "summary written with no human turn in between (not a round)",
    "EXCL": "not an approval round (excluded)",
}


def quote(text, limit):
    text = text[:limit] + (" […]" if len(text) > limit else "")
    return "\n".join("    " + ln for ln in text.split("\n"))


out = [
    "# Evidence: memory-approval rounds",
    "",
    "Verbatim transcript material. Not for the repository.",
    "",
    f"{len(A)} units: {sum(1 for a in A if a['class'] not in ('SELF', 'EXCL'))} rounds, "
    f"{sum(1 for a in A if a['class'] == 'SELF')} self-approved writes, {sum(1 for a in A if a['class'] == 'EXCL')} excluded.",
    "A round id with a letter suffix is a later proposal the episode cutter had merged into the same episode.",
    "",
]
for a in sorted(A, key=lambda a: (a["date"], a["rid"])):
    out += [f"## {a['rid']} — {a['date']} — {a['project'].replace('-Users-david-code-', '')}", ""]
    out += [f"- session: `{a['sid']}`", f"- class: **{a['class']}** — {NAMES[a['class']]}" + (" (auto-labelled bare approval)" if a["auto"] else "")]
    out += [f"- reached the write: {'yes' if a['closed'] else 'no'}; proposal found by: {a['why']}"]
    for fact, frm, to in a["redirects"]:
        out.append(f"- human redirect: `{fact}` {frm} → {to}")
    for fact in a["rejects"]:
        out.append(f"- human reject: `{fact}`")
    if a["note"]:
        out.append(f"- note: {a['note']}")
    if a["amb"]:
        out.append(f"- ambiguous: {a['amb']}")
    if a["rules_invoked"]:
        out.append("- the human's reply invoked the written rules by name")
    out += ["", "Proposal:", "", quote(a["proposal"], 3500), ""]
    if a["replies"]:
        out += ["Human replies, in order:", ""]
        for r in a["replies"][:12]:
            out += [f"- [{r['how']}] {r['ts'][:16]}", "", quote(r["text"], 1500), ""]
        if len(a["replies"]) > 12:
            out += [f"- … {len(a['replies']) - 12} later replies not shown", ""]
    else:
        out += ["Human replies: none in the episode window.", ""]
    pid = key.get(a["rid"])
    if pid:
        v = verd.get(pid)
        out += [f"Blind reviewer ({pid}):", ""]
        if not v:
            out += ["    (no verdict recorded)", ""]
        elif v["verdict"] == "no-objection":
            out += ["    no objection", ""]
        else:
            for r in v.get("redirections", []):
                out += [f"    redirect `{r['fact']}`: {r['from']} → {r['to']} [{r['rule']}, {r['confidence']}] — {r['reason']}"]
            out.append("")
    else:
        out += ["Blind reviewer: not in the sample.", ""]

out += ["## Writes with no approval round found", ""]
for o in others:
    if o["what"].startswith("write"):
        out.append(f"- {o['ts'][:16]} `{o['sid']}` {o['project'].replace('-Users-david-code-', '')} ({o['what']}, {o['target'][-40:]})")
out += ["", "## Other exclusions", ""]
for o in others:
    if not o["what"].startswith("write"):
        out.append(f"- {o['what']}: {o.get('project', '')} `{o.get('sid', '')}`")
open(os.path.join(D, "evidence.md"), "w").write("\n".join(out) + "\n")
print("evidence.md", os.path.getsize(os.path.join(D, "evidence.md")), "bytes")
