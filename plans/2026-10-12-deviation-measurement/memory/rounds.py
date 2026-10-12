#!/usr/bin/env python3
"""Extract memory-approval rounds from Claude Code session transcripts.

usage: rounds.py <projects-root> <shortlist.txt> <out-rounds.jsonl> <out-other.jsonl>

Streams each main-session JSONL line by line (one json.loads per line), builds a
compact event list per file, then cuts it into approval episodes:

  proposal (assistant text carrying a blockquote, tied to a gate instruction in
  the same turn or to the text of a later artefact write)
  -> every genuine human reply
  -> the successful artefact write (round closed) or end of file (unfinished).

The artefact is a write of `.claude/gitlore-memory-message`, of its earlier name
`gitlore-commit-msg`, or a `commit-memory.sh -m/-F` call carrying the summary.
"""

import json
import os
import re
import sys

ROOT, LISTFILE, OUT, OUT_OTHER = sys.argv[1:5]

MSG_NAMES = ("gitlore-memory-message", "gitlore-commit-msg")
GATE_RE = re.compile(
    r"gitlore memory has uncommitted changes:"
    r"|gitlore: memory \([^)]*\) has uncommitted changes"
    r"|memory is dirty and has no approved commit summary"
    r"|commit-memory is pending but no approved summary"
    r"|direct commits inside the memory submodule are blocked"
    r"|memory commit deferred"
    r"|To commit memory, summarize the pending changes"
)
BQ_LINE = re.compile(r"^\s{0,3}>\s?(.*)$")
WORD = re.compile(r"[A-Za-zÀ-ÿ0-9_]{4,}")
NOISE_REDIR = re.compile(r"\d?>\s*/dev/null|2>&1|&>\s*/dev/null|\d?>\s*&\d")
HEREDOC = re.compile(r"<<-?\s*([\"']?)(\w+)\1.*?\n\2\s*(\n|$)", re.S)
REPLY_KEY1 = re.compile(r"memory|mémoire", re.I)
REPLY_KEY2 = re.compile(r"summary|résumé|approv|sign-off|go-ahead", re.I)
COMMIT_ARG = re.compile(r"(commit-memory\.sh|gitlore\.commitCommand\)?)[\"']?\s+(-m|-F)\b")
MEM_PATH = re.compile(r"(^|/)memory/|CLAUDE\.md$|shared-claude\.md$")
MID_PATH = re.compile(r"(^|/)memory/|CLAUDE\.md$|SKILL\.md$|TODO\.md$|handoff-todo\.md$|/skills/|/docs/")
BASH_MOVE = re.compile(r"\b(git\s+mv|git\s+rm|mv|rm|cp)\b")
WRAPPERS = (
    "<command-",
    "<task-notification",
    "<local-command",
    "<bash-",
    "Another Claude session",
    "[Request interrupted",
    "<system-reminder",
    "<teammate",
)


def toks(s):
    return set(w.lower() for w in WORD.findall(s))


def overlap(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


def blockquote(text):
    out = []
    for ln in text.split("\n"):
        m = BQ_LINE.match(ln)
        if m:
            out.append(m.group(1))
    return "\n".join(out)


def result_text(b):
    c = b.get("content")
    if isinstance(c, list):
        c = "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return "" if c is None else str(c)


def artefact_write(name, inp):
    """Return the message text when this tool_use writes the approved summary."""
    if name in ("Write", "Edit"):
        fp = str(inp.get("file_path", ""))
        if os.path.basename(fp) in MSG_NAMES:
            return str(inp.get("content") or inp.get("new_string") or ""), fp
        return None
    if name == "Bash":
        cmd = str(inp.get("command", ""))
        # Detect on the command line alone: a heredoc body that merely mentions
        # the names (a plan, a checkpoint payload, a test) is not a write.
        line = HEREDOC.sub(" ", cmd)
        if COMMIT_ARG.search(line):
            return cmd, "commit-memory-arg"
        if any(n in line for n in MSG_NAMES):
            stripped = NOISE_REDIR.sub("", line)
            if ">" in stripped.replace("<<", "").replace("->", "") or re.search(
                r"\b(tee|cp|mv)\b", stripped
            ):
                return cmd, "bash-redirect"
    return None


def parse_file(path):
    """Yield compact events for one transcript."""
    events = []
    tool_names = {}
    pending = {}  # tool_use id -> event awaiting its result
    with open(path, errors="replace") as fh:
        for lineno, line in enumerate(fh):
            try:
                e = json.loads(line)
            except Exception:
                continue
            if not isinstance(e, dict):
                continue
            t = e.get("type")
            if t not in ("user", "assistant", "attachment"):
                continue
            if e.get("isSidechain"):
                continue
            ts = e.get("timestamp") or ""
            base = {"line": lineno, "ts": ts, "cwd": e.get("cwd")}
            if t == "attachment":
                a = e.get("attachment") or {}
                at = a.get("type")
                if at == "queued_command":
                    org = a.get("origin") or {}
                    if a.get("commandMode") == "prompt" and org.get("kind") == "human":
                        events.append(dict(base, kind="human", how="mid-turn", text=str(a.get("prompt"))))
                    continue
                if at and at.startswith("hook_"):
                    if str(a.get("hookEvent")) == "SessionStart":
                        continue
                    c = a.get("content")
                    if isinstance(c, list):
                        c = "\n".join(map(str, c))
                    c = str(c or "") + "\n" + str(a.get("stdout") or "") + "\n" + json.dumps(a.get("blockingError") or "")
                    if "onekeys" in c and at == "hook_additional_context":
                        events.append(dict(base, kind="onekeys", text=c[:300]))
                    if len(c) < 12000 and GATE_RE.search(c):
                        events.append(dict(base, kind="gate", via="hook:" + str(a.get("hookEvent")), text=c[:5000]))
                continue
            m = e.get("message") or {}
            c = m.get("content")
            if t == "assistant":
                if not isinstance(c, list):
                    continue
                for b in c:
                    if not isinstance(b, dict):
                        continue
                    bt = b.get("type")
                    if bt == "text":
                        txt = b.get("text") or ""
                        if txt.strip():
                            events.append(dict(base, kind="atext", mid=m.get("id"), text=txt))
                    elif bt == "tool_use":
                        name = b.get("name")
                        inp = b.get("input") or {}
                        tid = b.get("id")
                        tool_names[tid] = name
                        aw = artefact_write(name, inp)
                        if aw:
                            ev = dict(base, kind="write", tool=name, target=aw[1], msg=aw[0], tid=tid, ok=None, res="")
                            events.append(ev)
                            pending[tid] = ev
                            continue
                        if name == "AskUserQuestion":
                            ev = dict(base, kind="ask", q=json.dumps(inp, ensure_ascii=False)[:3000], tid=tid, res="")
                            events.append(ev)
                            pending[tid] = ev
                            continue
                        if name in ("Write", "Edit", "MultiEdit"):
                            fp = str(inp.get("file_path", ""))
                            if MID_PATH.search(fp):
                                if name == "Write":
                                    body = str(inp.get("content", ""))
                                else:
                                    body = "--- old\n" + str(inp.get("old_string", "")) + "\n+++ new\n" + str(inp.get("new_string", ""))
                                events.append(dict(base, kind="edit", tool=name, path=fp, body=body[:6000], tid=tid))
                        elif name == "Bash":
                            cmd = str(inp.get("command", ""))
                            if BASH_MOVE.search(cmd) and ("memory/" in cmd or "CLAUDE.md" in cmd):
                                events.append(dict(base, kind="edit", tool="Bash", path="", body=cmd[:1500], tid=tid))
                continue
            # t == "user"
            if isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                for b in c:
                    if not isinstance(b, dict) or b.get("type") != "tool_result":
                        continue
                    tid = b.get("tool_use_id")
                    txt = result_text(b)
                    rejected = "doesn't want to proceed with this tool use" in txt or "The user doesn't want to take this action" in txt
                    if tid in pending:
                        ev = pending.pop(tid)
                        ev["res"] = txt[:3000]
                        if ev["kind"] == "write":
                            ev["ok"] = not (rejected or b.get("is_error"))
                            ev["rejected"] = rejected
                    if rejected:
                        events.append(dict(base, kind="human", how="tool-rejection:" + str(tool_names.get(tid)), text=txt[:3000]))
                    if tool_names.get(tid) in ("Bash", None) and len(txt) < 12000 and GATE_RE.search(txt):
                        events.append(dict(base, kind="gate", via="result:" + str(tool_names.get(tid)), text=txt[:5000]))
                continue
            if e.get("isMeta") or e.get("isCompactSummary"):
                if e.get("isCompactSummary"):
                    events.append(dict(base, kind="compact"))
                continue
            if isinstance(c, list):
                txt = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
            else:
                txt = str(c or "")
            head = txt.lstrip()
            org = e.get("origin")
            okind = org.get("kind") if isinstance(org, dict) else None
            if head.startswith("<command-"):
                if okind in ("human", None):
                    nm = re.search(r"<command-name>(.*?)</command-name>", txt, re.S)
                    ar = re.search(r"<command-args>(.*?)</command-args>", txt, re.S)
                    events.append(dict(base, kind="slash", text=(nm.group(1) if nm else "?") + " " + (ar.group(1) if ar else "")))
                continue
            if any(head.startswith(w) for w in WRAPPERS):
                continue
            if okind == "human":
                events.append(dict(base, kind="human", how=str(e.get("promptSource")), text=txt))
            elif org is None and e.get("promptSource") is None:
                events.append(dict(base, kind="human", how="no-origin", text=txt))
    return events


def cut(events):
    """Cut one file's events into rounds, unfinished episodes and stray writes."""
    n = len(events)
    # (a) blockquote text in a turn where a gate instruction fired
    gate_live = False
    for ev in events:
        k = ev["kind"]
        if k == "human" and not ev["how"].startswith("tool-rejection") and ev["how"] != "mid-turn":
            gate_live = False
        elif k == "gate":
            gate_live = True
        elif k == "atext":
            bq = blockquote(ev["text"])
            ev["bq"] = bq
            ev["bqt"] = toks(bq)
            ev["prop"] = bool(gate_live and len(ev["bqt"]) >= 5)
            ev["why"] = "gate" if ev["prop"] else ""
    rounds, others = [], []
    seg = 0
    prev_msg = None
    for i, ev in enumerate(events):
        if ev["kind"] != "write" or not ev["ok"]:
            continue
        mt = toks(ev["msg"])
        # (b) blockquote text matching this write
        for j in range(seg, i):
            x = events[j]
            if x["kind"] == "atext" and not x["prop"] and len(x["bqt"]) >= 5 and overlap(x["bqt"], mt) >= 0.5:
                x["prop"] = True
                x["why"] = "write-match"
        props = [j for j in range(seg, i) if events[j]["kind"] == "atext" and events[j]["prop"]]
        if not props and len(mt) >= 5:
            # (b') no blockquote anywhere: a prose or fenced proposal that
            # contains most of the written message
            for j in range(seg, i):
                x = events[j]
                if x["kind"] == "atext":
                    tt = toks(x["text"])
                    if len(mt & tt) / len(mt) >= 0.6:
                        x["prop"] = True
                        x["why"] = "prose-match"
                        x["bq"] = x["text"]
                        x["bqt"] = tt
            props = [j for j in range(seg, i) if events[j]["kind"] == "atext" and events[j]["prop"]]
        if not props:
            # (d) nothing matched: the assistant text the human last replied to
            # before this write, when it reads as a memory-summary proposal
            humans = [j for j in range(seg, i) if events[j]["kind"] == "human" and events[j]["how"] in ("typed", "queued", "suggestion_accepted", "mid-turn")]
            if humans:
                seen_texts = 0
                for j in range(humans[-1] - 1, seg - 1, -1):
                    x = events[j]
                    if x["kind"] != "atext":
                        continue
                    seen_texts += 1
                    if seen_texts > 8:
                        break
                    if REPLY_KEY1.search(x["text"]) and REPLY_KEY2.search(x["text"]):
                        x["prop"] = True
                        x["why"] = "reply-anchor"
                        x["bq"] = x["text"]
                        x["bqt"] = toks(x["text"])
                        props = [j]
                        break
        best = max((overlap(events[j]["bqt"], mt) for j in props), default=0.0)
        scratch = bool(re.search(r"/tmp|TMPDIR|mktemp|scratchpad|fixture|BATS", ev["msg"][:400] + ev["target"]))
        if re.search(r"commit-memory\.sh[\"']?\s+-F\s+(-\s*<\s*)?[\"']?[^-\s<]", HEREDOC.sub(" ", ev["msg"])):
            scratch = False  # the summary came from a file the command names
        if props and (best >= 0.3 or not scratch):
            rounds.append(build(events, seg, props, i, best))
            seg = i + 1
            prev_msg = mt
        elif prev_msg is not None and overlap(mt, prev_msg) >= 0.6:
            others.append({"what": "repeat-write", "ts": ev["ts"], "target": ev["target"], "tid": ev["tid"]})
        else:
            others.append(
                {
                    "what": "write-without-proposal" if not props else "write-unlike-proposal",
                    "ts": ev["ts"],
                    "target": ev["target"],
                    "tid": ev["tid"],
                    "msg": ev["msg"][:600],
                    "cwd": ev["cwd"],
                }
            )
    props = [j for j in range(seg, n) if events[j]["kind"] == "atext" and events[j]["prop"]]
    if props:
        rounds.append(build(events, seg, props, None, 0.0))
    return rounds, others


def build(events, seg, props, close, best):
    p1 = props[0]
    end = close if close is not None else len(events)
    # (c) later blockquote texts resembling an accepted proposal are re-proposals
    plist = list(props)
    base = [events[j]["bqt"] for j in props]
    for j in range(p1 + 1, end):
        x = events[j]
        if x["kind"] == "atext" and not x["prop"] and len(x["bqt"]) >= 5 and any(overlap(x["bqt"], b) >= 0.5 for b in base):
            plist.append(j)
    plist.sort()
    # the whole assistant message of the first proposal
    mid = events[p1].get("mid")
    first_text = "\n\n".join(x["text"] for x in events[max(seg, p1 - 6): p1 + 7] if x["kind"] == "atext" and x.get("mid") == mid)
    gates = [events[j] for j in range(seg, p1) if events[j]["kind"] == "gate"]
    pre = [events[j] for j in range(seg, p1) if events[j]["kind"] == "edit" and (MEM_PATH.search(events[j]["path"]) or events[j]["tool"] == "Bash")]
    timeline = []
    for j in range(p1 + 1, end):
        x = events[j]
        k = x["kind"]
        if k == "human":
            timeline.append({"k": "human", "how": x["how"], "ts": x["ts"], "text": x["text"][:2500]})
        elif k == "onekeys":
            timeline.append({"k": "onekeys", "ts": x["ts"], "text": x["text"]})
        elif k == "slash":
            timeline.append({"k": "slash", "ts": x["ts"], "text": x["text"][:400]})
        elif k == "ask":
            timeline.append({"k": "ask", "ts": x["ts"], "q": x["q"][:1500], "a": x["res"][:1500]})
        elif k == "edit":
            timeline.append({"k": "edit", "ts": x["ts"], "tool": x["tool"], "path": x["path"], "body": x["body"][:1200]})
        elif k == "write":
            timeline.append({"k": "write-failed", "ts": x["ts"], "target": x["target"], "res": x["res"][:600]})
        elif k == "gate":
            timeline.append({"k": "gate", "ts": x["ts"], "text": x["text"][:300]})
        elif k == "compact":
            timeline.append({"k": "compact", "ts": x["ts"]})
        elif k == "atext" and j in plist:
            timeline.append({"k": "reproposal", "ts": x["ts"], "text": x["text"][:6000]})
        elif k == "atext":
            timeline.append({"k": "atext", "ts": x["ts"], "text": x["text"][:500]})
    after = []
    if close is not None:
        for x in events[close + 1:]:
            if x["kind"] == "human" and not x["how"].startswith("tool-rejection"):
                after.append({"ts": x["ts"], "text": x["text"][:800]})
                if len(after) >= 2:
                    break
    w = events[close] if close is not None else None
    return {
        "closed": close is not None,
        "p1_ts": events[p1]["ts"],
        "p1_mid": mid,
        "p1_why": events[p1]["why"],
        "p1_text": first_text[:12000],
        "p1_bq": events[p1]["bq"][:8000],
        "n_proposals": len(plist),
        "gate": gates[-1]["text"] if gates else "",
        "gate_via": gates[-1]["via"] if gates else "",
        "pre_edits": [{"tool": x["tool"], "path": x["path"], "body": x["body"], "ts": x["ts"]} for x in pre][-30:],
        "timeline": timeline,
        "write_ts": w["ts"] if w else None,
        "write_tid": w["tid"] if w else None,
        "write_target": w["target"] if w else None,
        "write_msg": w["msg"][:8000] if w else None,
        "match": round(best, 2),
        "cwd": events[p1]["cwd"],
        "after": after,
    }


def main():
    seen = set()
    nfiles = 0
    with open(OUT, "w") as out, open(OUT_OTHER, "w") as oth:
        for f in open(LISTFILE).read().split("\n"):
            if not f:
                continue
            rel = os.path.relpath(f, ROOT).split(os.sep)
            if len(rel) != 2:
                continue
            proj, sid = rel[0], rel[1][:-6]
            if proj.startswith("-tmp"):
                oth.write(json.dumps({"what": "excluded-tmp-project", "project": proj, "sid": sid}) + "\n")
                continue
            nfiles += 1
            events = parse_file(f)
            rounds, others = cut(events)
            del events
            for r in rounds:
                key = r["write_tid"] or ("open:" + str(r["p1_mid"]))
                if key in seen:
                    oth.write(json.dumps({"what": "duplicate-round", "project": proj, "sid": sid, "key": key}) + "\n")
                    continue
                seen.add(key)
                r["project"] = proj
                r["sid"] = sid
                out.write(json.dumps(r, ensure_ascii=False) + "\n")
            for o in others:
                key = "o:" + str(o.get("tid"))
                if key in seen:
                    continue
                seen.add(key)
                o["project"] = proj
                o["sid"] = sid
                oth.write(json.dumps(o, ensure_ascii=False) + "\n")
    print("main-session files scanned:", nfiles)


main()
