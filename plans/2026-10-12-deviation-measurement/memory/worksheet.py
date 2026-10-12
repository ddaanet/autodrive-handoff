#!/usr/bin/env python3
"""Assign round ids, auto-label bare approvals, and print the rest for hand classification.

usage: worksheet.py rounds.jsonl ids.jsonl review.txt
"""
import json, re, sys
src, ids_out, review_out = sys.argv[1:4]
AFFIRM = re.compile(r"^\s*(ok(ay)?|oui|yes|y|go|c|d|a|approved?|approuv[ée]e?|lgtm|good|parfait|valid[ée]?|d'accord|ça marche|ok go|go ahead|yes,? go ahead|approve|commit|proceed|continue|looks good|do it|ship it|yep|yup|sure|fine|vas-y|👍)\s*[.!]*\s*$", re.I)
R = [json.loads(l) for l in open(src)]
R.sort(key=lambda r: r["p1_ts"])
out = open(review_out, "w")
ids = open(ids_out, "w")
stats = {"auto": 0, "manual": 0, "self": 0}
for n, r in enumerate(R, 1):
    rid = f"R{n:03d}"
    r["rid"] = rid
    tl = r["timeline"]
    humans = [t for t in tl if t["k"] == "human"]
    typed = [t for t in humans if not t["how"].startswith("tool-rejection") and t["how"] != "no-origin"]
    rej = [t for t in humans if t["how"].startswith("tool-rejection")]
    asks = [t for t in tl if t["k"] == "ask"]
    mem_edits = [t for t in tl if t["k"] == "edit" and re.search(r"(^|/)memory/|CLAUDE\.md|shared-claude", t["path"] + " " + (t["body"] if t["tool"] == "Bash" else ""))]
    onek = {t["ts"][:19]: t["text"] for t in tl if t["k"] == "onekeys"}
    auto = None
    if r["closed"] and not typed and not asks and not rej:
        auto = "self-approved"
        stats["self"] += 1
    elif r["closed"] and len(typed) == 1 and AFFIRM.match(typed[0]["text"]) and not rej and not asks and not mem_edits and r["n_proposals"] == 1:
        auto = "approved-as-is"
        stats["auto"] += 1
    else:
        stats["manual"] += 1
    ids.write(json.dumps({"rid": rid, "sid": r["sid"], "project": r["project"], "p1_ts": r["p1_ts"], "p1_mid": r["p1_mid"], "write_tid": r["write_tid"], "closed": r["closed"], "auto": auto, "why": r["p1_why"], "match": r["match"], "n_typed": len(typed), "n_proposals": r["n_proposals"]}) + "\n")
    if auto:
        continue
    out.write(f"\n===== {rid} {r['project'].replace('-Users-david-code-','')} {r['sid'][:8]} {r['p1_ts'][:16]} closed={r['closed']} why={r['p1_why']} match={r['match']} nprop={r['n_proposals']} via={r['gate_via']}\n")
    out.write("P1: " + r["p1_bq"][:450].replace("\n", " ⏎ ") + "\n")
    nh = 0
    for t in tl:
        k = t["k"]
        if k == "human":
            nh += 1
            lim = 600 if nh <= 6 else 200
            out.write(f"  H[{t['how']}] {t['ts'][11:16]}: " + t["text"][:lim].replace("\n", " ⏎ ") + "\n")
        elif k == "onekeys":
            out.write("    (onekeys: " + t["text"][:120].replace("\n", " ") + ")\n")
        elif k == "ask":
            out.write("  ASK q=" + t["q"][:350].replace("\n", " ") + "\n      a=" + t["a"][:500].replace("\n", " ") + "\n")
        elif k == "edit":
            if t in mem_edits or re.search(r"SKILL|TODO|todo", t["path"]):
                out.write(f"  edit {t['tool']} {t['path'][-70:]} :: " + t["body"][:90].replace("\n", " ⏎ ") + "\n")
        elif k == "reproposal":
            out.write("  REPROPOSAL: " + blockq(t["text"])[:500].replace("\n", " ⏎ ") + "\n") if False else out.write("  REPROPOSAL: " + t["text"][:260].replace("\n", " ⏎ ") + "\n")
        elif k == "write-failed":
            out.write("  write-failed: " + t["res"][:200].replace("\n", " ") + "\n")
        elif k == "slash":
            out.write("  slash " + t["text"][:150].replace("\n", " ") + "\n")
        elif k == "atext" and nh <= 5:
            out.write("  A: " + t["text"][:110].replace("\n", " ⏎ ") + "\n")
    if r["closed"]:
        out.write("WROTE: " + (r["write_msg"] or "")[:220].replace("\n", " ⏎ ") + "\n")
    for a in r["after"][:1]:
        out.write("AFTER: " + a["text"][:300].replace("\n", " ⏎ ") + "\n")
print(stats)
