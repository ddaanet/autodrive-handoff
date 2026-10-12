#!/usr/bin/env python3
"""Survey attachment types, queue-operation shapes and user-entry key sets."""
import json, os, sys, collections
root, listfile, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
att = collections.Counter(); ex = {}; ukeys = collections.Counter(); uex = {}
n = 0
for f in open(listfile).read().split("\n"):
    if not f or "subagents" in f or "/-tmp" in f: continue
    n += 1
    if n > limit: break
    with open(f, errors="replace") as fh:
        for line in fh:
            if '"type":"attachment"' not in line and '"type":"queue-operation"' not in line and '"type":"user"' not in line: continue
            try: e = json.loads(line)
            except Exception: continue
            if not isinstance(e, dict): continue
            t = e.get("type")
            if t == "attachment":
                a = e.get("attachment") or {}
                k = ("att", a.get("type"))
                att[k] += 1
                if k not in ex: ex[k] = json.dumps(a, ensure_ascii=False)[:260]
            elif t == "queue-operation":
                k = ("q", e.get("operation"))
                att[k] += 1
                if k not in ex: ex[k] = json.dumps({x: e[x] for x in e if x != "content"})[:200] + " content=" + str(e.get("content"))[:60]
            elif t == "user":
                c = (e.get("message") or {}).get("content")
                shape = "str" if isinstance(c, str) else ",".join(sorted({b.get("type", "?") for b in c if isinstance(b, dict)})) if isinstance(c, list) else type(c).__name__
                extra = tuple(sorted(k for k in e if k in ("isMeta", "isSidechain", "isCompactSummary", "promptSource", "origin", "isVisibleInTranscriptOnly", "sourceToolUseID", "toolUseResult", "permissionMode") and e[k] not in (None, False)))
                k = (shape, extra)
                ukeys[k] += 1
                if k not in uex: uex[k] = (c if isinstance(c, str) else json.dumps(c, ensure_ascii=False))[:120]
for k, v in att.most_common(): print(v, k, ex[k])
print()
for k, v in ukeys.most_common(): print(v, k, repr(uex[k]))
