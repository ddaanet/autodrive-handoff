#!/usr/bin/env python3
"""Survey gate-instruction wordings in tool results and hook attachments (main sessions)."""
import json, os, sys, collections, re
root, listfile = sys.argv[1], sys.argv[2]
pat = re.compile(r"[^.\n]{0,80}(?:approv|confirm)[^.\n]{0,80}", re.I)
seen = collections.Counter(); first = {}; last = {}
def texts(e):
    t = e.get("type")
    if t == "user":
        c = (e.get("message") or {}).get("content")
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    cc = b.get("content")
                    if isinstance(cc, list): cc = "\n".join(x.get("text", "") for x in cc if isinstance(x, dict))
                    yield "res", str(cc)
    elif t == "attachment":
        a = e.get("attachment") or {}
        c = a.get("content")
        if isinstance(c, list): c = "\n".join(map(str, c))
        yield "att:" + str(a.get("type")), str(c)
for f in open(listfile).read().split("\n"):
    if not f: continue
    rel = os.path.relpath(f, root).split(os.sep)
    if len(rel) != 2 or rel[0].startswith("-tmp"): continue
    with open(f, errors="replace") as fh:
        for line in fh:
            if "memory" not in line or "gitlore" not in line: continue
            try: e = json.loads(line)
            except Exception: continue
            if not isinstance(e, dict): continue
            for kind, s in texts(e):
                if len(s) > 6000 or "gitlore" not in s: continue
                m = re.search(r"(gitlore[^\n]{0,30}memory[^\n]{0,90}|memory is dirty[^\n]{0,90}|memory has uncommitted[^\n]{0,60}|Summarize[^\n]{0,80})", s)
                if not m or not re.search(r"approv|confirm", s, re.I): continue
                key = (kind, re.sub(r"/\S+", "<p>", m.group(1))[:110])
                seen[key] += 1
                d = (e.get("timestamp") or "")[:10]
                first.setdefault(key, d); last[key] = max(last.get(key, d), d); first[key] = min(first[key], d)
for k, n in sorted(seen.items(), key=lambda kv: first[kv[0]]):
    if n >= 2: print(n, first[k], last[k], k)
