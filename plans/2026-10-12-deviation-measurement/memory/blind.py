#!/usr/bin/env python3
"""Build the blind-test material: proposal records with the human's reply withheld.

usage: blind.py <rounds.jsonl> <ids.jsonl> <outdir> <skill.md> <tier-index.md> <shared-claude.md> <seed>

Writes, under <outdir>:
  blind/rules.md            the written rules, section-labelled
  blind/records-N.md        shuffled, unlabelled proposal records (opaque ids)
  withheld/key.jsonl        opaque id -> round id, class, date, project
  withheld/replies.jsonl    the human replies and what was finally written
  all-rounds.jsonl          every round (and sub-round) with its class
"""

import json
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from labels import LABELS  # noqa: E402

ROUNDS, IDS, OUTDIR, SKILL, TIERIDX, SHARED, SEED = sys.argv[1:8]
rng = random.Random(int(SEED))

APPROVED_QUOTA = {"2026-06": 3, "2026-07": 11, "2026-08": 4, "2026-09": 12, "2026-10": 6}
TIER_SINCE = "2026-07-20"  # first mount of the shared tier
SHARED_CLAUDE_SINCE = "2026-07-31"  # first commit of the always-loaded shared file

ids = {}
for line in open(IDS):
    d = json.loads(line)
    ids[(d["sid"], d["p1_mid"], d["write_tid"])] = d
rounds = {}
for line in open(ROUNDS):
    r = json.loads(line)
    d = ids[(r["sid"], r["p1_mid"], r["write_tid"])]
    r["rid"] = d["rid"]
    r["auto"] = d["auto"]
    rounds[d["rid"]] = r


def pick_proposal(r, sub):
    """Return (proposal text, timeline index it sits at, or -1 for the first proposal)."""
    if not sub:
        return r["p1_text"], -1
    for i, t in enumerate(r["timeline"]):
        if t["k"] == "reproposal" and sub in t["text"]:
            return t["text"], i
    raise SystemExit(f"{r['rid']}: no re-proposal contains {sub!r}")


def replies_after(r, idx, stop):
    out = []
    for i, t in enumerate(r["timeline"]):
        if i <= idx:
            continue
        if stop is not None and i >= stop:
            break
        if t["k"] == "human":
            out.append({"how": t["how"], "ts": t["ts"], "text": t["text"]})
        elif t["k"] == "ask":
            out.append({"how": "ask", "ts": t["ts"], "text": t["a"]})
        elif t["k"] == "slash":
            out.append({"how": "slash", "ts": t["ts"], "text": t["text"]})
    return out


def edits_before(r, idx):
    out = list(r["pre_edits"])
    for i, t in enumerate(r["timeline"]):
        if i >= idx >= 0 and True:
            break
        if idx < 0:
            break
        if t["k"] == "edit" and re.search(r"(^|/)memory/|CLAUDE\.md$", t["path"]):
            out.append({"tool": t["tool"], "path": t["path"], "body": t["body"], "ts": t["ts"]})
    return out


units = []  # one per round or sub-round
for rid, r in sorted(rounds.items()):
    if r["auto"] == "self-approved":
        units.append({"rid": rid, "c": "SELF", "r": r, "prop": None})
        continue
    if r["auto"] == "approved-as-is":
        units.append({"rid": rid, "c": "A", "r": r, "prop": None, "auto": True})
        continue
    L = LABELS[rid]
    subs = L.get("sub", [])
    units.append({"rid": rid, "c": L["c"], "r": r, "prop": L.get("prop"), "L": L, "nsub": len(subs)})
    for s in subs:
        units.append({"rid": s["id"], "c": s["c"], "r": r, "prop": s["prop"], "L": s, "is_sub": True})

for u in units:
    r = u["r"]
    text, idx = pick_proposal(r, u["prop"])
    u["proposal"] = text
    u["idx"] = idx
    u["date"] = (r["timeline"][idx]["ts"] if idx >= 0 else r["p1_ts"])[:10]
    # replies run to the next sub-round's proposal, if any
    nxt = None
    for v in units:
        if v is not u and v["r"] is r and v.get("prop"):
            _, j = pick_proposal(r, v["prop"])
            if j > idx and (nxt is None or j < nxt):
                nxt = j
    u["replies"] = replies_after(r, idx, nxt)
    u["edits"] = edits_before(r, idx)

with open(os.path.join(OUTDIR, "all-rounds.jsonl"), "w") as fh:
    for u in units:
        r = u["r"]
        L = u.get("L", {})
        fh.write(
            json.dumps(
                {
                    "rid": u["rid"],
                    "class": u["c"],
                    "date": u["date"],
                    "project": r["project"],
                    "sid": r["sid"],
                    "closed": r["closed"],
                    "auto": bool(u.get("auto")),
                    "redirects": L.get("redirects", []),
                    "rejects": L.get("rejects", []),
                    "note": L.get("note", ""),
                    "amb": L.get("amb", ""),
                    "rules_invoked": bool(L.get("rules_invoked")),
                    "proposal": u["proposal"],
                    "replies": u["replies"],
                    "written": r["write_msg"] if r["closed"] else None,
                    "why": r["p1_why"],
                },
                ensure_ascii=False,
            )
            + "\n"
        )

# ---- the sample
sample = [u for u in units if u["c"] in ("D", "D+", "Dd", "X", "S", "Q")]
pool = {}
for u in units:
    if u["c"] != "A" or u.get("is_sub") or u.get("nsub"):
        continue
    L = u.get("L", {})
    if L.get("amb") or u.get("prop"):
        continue
    r = u["r"]
    if r["p1_why"] not in ("gate", "write-match") or (r["closed"] and r["match"] < 0.6):
        continue
    pool.setdefault(u["date"][:7], []).append(u)
picked = []
for month, quota in sorted(APPROVED_QUOTA.items()):
    cands = sorted(pool.get(month, []), key=lambda u: u["rid"])
    picked += rng.sample(cands, min(quota, len(cands)))
    print(f"approved pool {month}: {len(cands)} eligible, {min(quota, len(cands))} sampled")
sample += picked
rng.shuffle(sample)
print("sample size", len(sample), "redirect/reject/other:", len(sample) - len(picked), "approved:", len(picked))


def repo_name(project):
    return project.replace("-Users-david-code-", "").replace("-Users-david-", "~/")


def status_lines(gate):
    out = []
    for ln in gate.split("\n"):
        if re.match(r"^[ MADRCU?!]{2} [^ ]", ln) and len(ln) < 200:
            out.append(ln.rstrip())
    return out[:40]


def render(pid, u):
    r = u["r"]
    date = u["date"]
    tiers = "project memory only"
    if date >= TIER_SINCE:
        tiers = "project memory (`memory/`) and the shared tier (`memory/ddaanet/`)"
    al = "the repository's `CLAUDE.md`"
    if date >= SHARED_CLAUDE_SINCE:
        al += " and the shared always-loaded `memory/ddaanet/shared-claude.md`"
    parts = [f"## {pid}", "", f"- Repository: `{repo_name(r['project'])}`", f"- Stores available: {tiers}", f"- Always-loaded files: {al}", ""]
    sl = status_lines(r["gate"]) if u["idx"] < 0 else []
    if sl:
        parts += ["Pending memory changes as the gate listed them (`git status --porcelain` inside `memory/`):", "", "```"] + sl + ["```", ""]
    parts += ["### Proposed summary (the agent's message to the user)", "", u["proposal"][:6500].rstrip(), ""]
    seen = {}
    for e in u["edits"]:
        key = e["path"] or e["body"][:60]
        if os.path.basename(e["path"]) == "MEMORY.md":
            continue
        if e["tool"] == "Bash" and "handoff-checkpoint" in e["body"]:
            continue  # a checkpoint payload, not a memory edit
        seen.setdefault(key, []).append(e)
    if seen:
        parts += ["### Memory edits made in this session before the proposal (excerpts)", ""]
        n = 0
        for key, es in seen.items():
            if n >= 6:
                parts.append(f"… {len(seen) - n} more file(s) not shown")
                break
            n += 1
            e = es[-1] if es[-1]["tool"] == "Write" else es[0]
            path = e["path"]
            m = re.search(r"/memory/.*$|/CLAUDE\.md$", path)
            label = (m.group(0).lstrip("/") if m else path) or "(shell command)"
            parts += [f"`{label}` — {e['tool']}" + (f", {len(es)} edits" if len(es) > 1 else ""), "", "```", e["body"][:520].rstrip(), "```", ""]
    return "\n".join(parts) + "\n"


os.makedirs(os.path.join(OUTDIR, "blind"), exist_ok=True)
os.makedirs(os.path.join(OUTDIR, "withheld"), exist_ok=True)
NFILES = 6
per = (len(sample) + NFILES - 1) // NFILES
with open(os.path.join(OUTDIR, "withheld", "key.jsonl"), "w") as key, open(os.path.join(OUTDIR, "withheld", "replies.jsonl"), "w") as rep:
    for n in range(NFILES):
        chunk = sample[n * per: (n + 1) * per]
        with open(os.path.join(OUTDIR, "blind", f"records-{n + 1}.md"), "w") as fh:
            fh.write(f"# Proposal records, part {n + 1} of {NFILES}\n\n")
            for k, u in enumerate(chunk):
                pid = f"P{n * per + k + 1:03d}"
                fh.write(render(pid, u))
                L = u.get("L", {})
                key.write(json.dumps({"pid": pid, "rid": u["rid"], "class": u["c"], "date": u["date"], "project": u["r"]["project"], "redirects": L.get("redirects", []), "rejects": L.get("rejects", [])}) + "\n")
                rep.write(json.dumps({"pid": pid, "rid": u["rid"], "replies": u["replies"], "written": u["r"]["write_msg"]}, ensure_ascii=False) + "\n")
        print(f"records-{n + 1}.md", len(chunk), os.path.getsize(os.path.join(OUTDIR, "blind", f"records-{n + 1}.md")))

# ---- the rules
skill = open(SKILL).read()
skill = skill.split("\n---\n", 1)[1] if skill.startswith("---") else skill
tier = open(TIERIDX).read()
m = re.search(r"# ddaanet tier index\n(.*?)\n- \[", tier, re.S)
tier_header = "# ddaanet tier index\n" + (m.group(1) if m else "")
shared = open(SHARED).read().split("\n## Standing defaults", 1)[0]
TIER_CTX = (
    "gitlore memory tiers: shared memory stores mounted inside the memory submodule. Write a portable fact into the "
    "matching tier's directory (same one-file-per-fact format), and add its index line to the ROOT memory/MEMORY.md "
    "with the tier prefix — '- [Title](<tier>/<file>.md) — hook'. gitlore mirrors that line down into the tier's own "
    "index for you. Facts specific to this project stay in memory/ with a bare path.\n"
    "- `memory/ddaanet/` — Cross-project facts shared by all ddaanet repositories"
)
with open(os.path.join(OUTDIR, "blind", "rules.md"), "w") as fh:
    fh.write("# The written rules\n\nThree sources. Cite them as `SKILL §<n>` (add `Q<k>` for a numbered question of §1), `TIER`, or `SHARED`.\n\n")
    fh.write("---\n\n# SKILL — the body of the `gitlore:memory-writing` skill\n\n" + skill.strip() + "\n\n")
    fh.write("---\n\n# TIER — what the memory index says about tiers\n\nHeader of the shared tier's index (`memory/ddaanet/MEMORY.md`):\n\n" + tier_header.strip() + "\n\nTier guidance a session receives at start:\n\n" + TIER_CTX + "\n\n")
    fh.write("---\n\n# SHARED — opening section of `memory/ddaanet/shared-claude.md`\n\n" + shared.strip() + "\n")
print("rules.md", os.path.getsize(os.path.join(OUTDIR, "blind", "rules.md")))
