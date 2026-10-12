#!/usr/bin/env python3
"""Survey origin/promptSource values on string-content user entries and queued_command attachments, by month."""
import json, os, sys, collections
root, listfile = sys.argv[1], sys.argv[2]
c1 = collections.Counter(); ex = {}
for f in open(listfile).read().split("\n"):
    if not f or "subagents" in f or "/-tmp" in f: continue
    with open(f, errors="replace") as fh:
        for line in fh:
            if '"type":"user"' not in line and 'queued_command' not in line: continue
            if len(line) > 200000: continue
            try: e = json.loads(line)
            except Exception: continue
            if not isinstance(e, dict): continue
            mo = (e.get("timestamp") or "")[:7]
            if e.get("type") == "attachment":
                a = e.get("attachment") or {}
                if a.get("type") != "queued_command": continue
                k = ("qc", a.get("commandMode"), json.dumps(a.get("origin")), type(a.get("prompt")).__name__)
                c1[(k, mo)] += 1; ex.setdefault(k, str(a.get("prompt"))[:70]); continue
            if e.get("type") != "user": continue
            c = (e.get("message") or {}).get("content")
            if isinstance(c, list):
                if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c): continue
                txt = " ".join(b.get("text", "") for b in c if isinstance(b, dict))
                sh = "list"
            else:
                txt = str(c); sh = "str"
            pre = "plain"
            for p in ("<command-", "<task-notification", "<local-command", "<bash-", "Another Claude session", "[Request interrupted", "<system-reminder", "Caveat", "<teammate", "Base directory"):
                if txt.lstrip().startswith(p): pre = p
            k = ("u", sh, pre, bool(e.get("isMeta")), bool(e.get("isCompactSummary")), json.dumps(e.get("origin")), e.get("promptSource"))
            c1[(k, mo)] += 1; ex.setdefault(k, txt[:70])
agg = collections.defaultdict(dict)
for (k, mo), v in c1.items(): agg[k][mo] = v
for k, d in sorted(agg.items(), key=lambda kv: -sum(kv[1].values())):
    print(sum(d.values()), k, sorted(d.items()), repr(ex[k]))
