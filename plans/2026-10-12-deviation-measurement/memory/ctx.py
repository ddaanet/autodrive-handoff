#!/usr/bin/env python3
"""Show what preceded a given tool_use id in a transcript: last assistant texts and human turns."""
import json, sys, glob, os
root, sid, tid, back = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
W = int(sys.argv[5]) if len(sys.argv) > 5 else 400
f = glob.glob(os.path.join(root, "*", sid + ".jsonl"))[0]
buf = []
with open(f, errors="replace") as fh:
    for line in fh:
        try: e = json.loads(line)
        except Exception: continue
        if not isinstance(e, dict) or e.get("type") not in ("user", "assistant"): continue
        if e.get("isMeta"): continue
        c = (e.get("message") or {}).get("content")
        ts = (e.get("timestamp") or "")[11:19]
        if isinstance(c, str):
            buf.append(f"{ts} U[{(e.get('origin') or {}).get('kind')}]: {c[:W]!r}"); continue
        if not isinstance(c, list): continue
        hit = False
        for b in c:
            if not isinstance(b, dict): continue
            if b.get("type") == "text": buf.append(f"{ts} {e['type'][:1].upper()}: {b.get('text','')[:W]!r}")
            elif b.get("type") == "tool_use":
                buf.append(f"{ts} use {b.get('name')}: {json.dumps(b.get('input'), ensure_ascii=False)[:160]}")
                if b.get("id") == tid: hit = True
            elif b.get("type") == "tool_result":
                cc = b.get("content")
                if isinstance(cc, list): cc = " ".join(x.get("text", "") for x in cc if isinstance(x, dict))
                buf.append(f"{ts} res: {str(cc)[:140]!r}")
        if hit:
            print("\n".join(buf[-back:])); break
