#!/usr/bin/env python3
"""Print a compact timeline around the Nth artefact write in one transcript."""
import json, sys
f, nth, back, fwd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
W = int(sys.argv[5]) if len(sys.argv) > 5 else 300
ents = []
hits = []
with open(f, errors="replace") as fh:
    for i, line in enumerate(fh):
        try: e = json.loads(line)
        except Exception: continue
        if not isinstance(e, dict): continue
        t = e.get("type")
        if t not in ("user", "assistant", "system", "attachment"): continue
        m = e.get("message") or {}
        c = m.get("content")
        flags = "".join(k[2] for k in ("isMeta", "isSidechain", "isCompactSummary") if e.get(k))
        parts = []
        if isinstance(c, str): parts.append(("str", c))
        elif isinstance(c, list):
            for b in c:
                if not isinstance(b, dict): continue
                bt = b.get("type")
                if bt == "text": parts.append(("text", b.get("text", "")))
                elif bt == "tool_use":
                    s = json.dumps(b.get("input"), ensure_ascii=False)
                    parts.append(("USE:" + str(b.get("name")), s))
                    if b.get("name") in ("Write", "Bash") and ("gitlore-memory-message" in s or "gitlore-commit-msg" in s or "commit-memory.sh" in s):
                        hits.append(len(ents))
                elif bt == "tool_result":
                    cc = b.get("content")
                    if isinstance(cc, list): cc = " ".join(x.get("text", "") for x in cc if isinstance(x, dict))
                    parts.append(("RES", str(cc)))
                elif bt == "thinking": parts.append(("think", ""))
        elif t == "attachment":
            parts.append(("att", json.dumps(e.get("attachment"), ensure_ascii=False)))
        elif t == "system":
            parts.append(("sys:" + str(e.get("subtype")), str(e.get("content"))))
        ents.append((i, (e.get("timestamp") or "")[:19], t, flags, (m.get("id") or "")[-6:], parts))
print("hits", len(hits), hits[:50])
if nth < len(hits):
    h = hits[nth]
    for i, ts, t, flags, mid, parts in ents[max(0, h - back): h + fwd]:
        for k, s in parts:
            print(f"{i} {ts} {t[:4]} [{flags}] {mid} {k}: {s[:W]!r}")
