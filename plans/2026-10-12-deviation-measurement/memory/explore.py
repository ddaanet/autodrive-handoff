#!/usr/bin/env python3
"""Survey tool_use shapes that name a memory-approval artefact (main sessions)."""
import json, os, sys, collections, re
root, listfile = sys.argv[1], sys.argv[2]
ANCH = ("gitlore-memory-message", "gitlore-commit-msg", "commit-memory.sh", "gitlore-commit-memory")
shapes = collections.Counter(); months = collections.Counter(); ex = collections.defaultdict(list)
entry_types = collections.Counter()
for f in open(listfile).read().split("\n"):
    if not f: continue
    rel = os.path.relpath(f, root).split(os.sep)
    if len(rel) != 2: continue
    with open(f, errors="replace") as fh:
        for line in fh:
            if not any(a in line for a in ANCH): continue
            try: e = json.loads(line)
            except Exception: continue
            if not isinstance(e, dict): continue
            entry_types[(e.get("type"), bool(e.get("isMeta")), bool(e.get("isSidechain")))] += 1
            if e.get("type") != "assistant": continue
            c = (e.get("message") or {}).get("content")
            if not isinstance(c, list): continue
            for b in c:
                if not isinstance(b, dict) or b.get("type") != "tool_use": continue
                inp = b.get("input") or {}
                s = json.dumps(inp)
                hit = [a for a in ANCH if a in s]
                if not hit: continue
                name = b.get("name")
                if name in ("Write", "Edit", "Read"):
                    key = (name, os.path.basename(inp.get("file_path", "")))
                elif name == "Bash":
                    cmd = inp.get("command", "")
                    tags = []
                    if re.search(r">\s*\S*gitlore-memory-message", cmd): tags.append("redir-msg")
                    if re.search(r">\s*\S*gitlore-commit-memory", cmd) or re.search(r"touch\s+\S*gitlore-commit-memory", cmd): tags.append("trigger")
                    if re.search(r"commit-memory\.sh\S*\s+(-m|-F)", cmd) or re.search(r'commitCommand\)"?\s+(-m|-F)', cmd): tags.append("commit-memory-arg")
                    elif "commit-memory.sh" in cmd: tags.append("commit-memory-mention")
                    if "gitlore-commit-msg" in cmd: tags.append("old-msg")
                    key = ("Bash", ",".join(tags) or "mention")
                else:
                    key = (name, ",".join(hit))
                shapes[key] += 1
                months[(key, (e.get("timestamp") or "")[:7])] += 1
                if len(ex[key]) < 3:
                    ex[key].append((rel[0][-20:], rel[1][:8], (e.get("timestamp") or "")[:10], s[:300]))
print(entry_types.most_common())
for k, n in shapes.most_common():
    print(n, k, sorted((m[1], c) for m, c in months.items() if m[0] == k))
    for x in ex[k]: print("    ", x)
