#!/usr/bin/env python3
"""Mechanical classification of handoff frame versions.

usage: frames.py <dir holding versions.tsv and blobs/> [<commit-verdicts.tsv>]

Reads the inventory `collect.py` wrote, deduplicates to distinct written
versions (repo, kind, blob), decides which are plugin-authored, and applies
every check a regex can decide. Each check carries the date its rule came into
force (the release that shipped it); a hit before that date is recorded as
"would fail today", never as a deviation.

Writes, beside the inventory:
  frames.tsv            one row per distinct version, all flags
  hits.tsv              one row per (frame, class) hit, with an excerpt
  commit-candidates.tsv unique sentences the commit-status filter matched,
                        for hand verification (verdicts come back through the
                        optional second argument: key<TAB>verdict)
"""

import csv
import hashlib
import os
import re
import sys
from collections import defaultdict

PRIVATE = {
    "Emploi",  # gh: PRIVATE
    # no remote: visibility cannot be determined, treated as private
    "ddaanet", "devddaanet", "emojipack", "emojipack-old", "freebox",
    "fzf-utils", "general", "home", "iliad", "micro", "oklch-theme",
    "openrouter-examples", "super-sdd-cached", "tuick",
}

# The release that shipped each rule (tag date in ddaanet/handoff).
IN_FORCE = {
    "no_h1": "2026-04-20",
    "template_heading": "2026-04-20",
    "extra_section": "2026-04-20",
    "empty_open_decisions": "2026-04-20",
    "one_sentence": "2026-04-20",  # until ONE_SENTENCE_END
    "commit_status_task": "2026-06-24",  # v0.8.3
    "list_in_task": "2026-07-22",  # v0.11.0, "threads, not steps"
    "todo_template": "2026-07-22",
    "todo_completion_state": "2026-07-22",
    "commit_status_todo": "2026-07-27",  # v0.11.4
    "open_decisions_in_task": "2026-08-13",  # v0.13.0
    "raised_n_times": "2026-09-17",  # v0.14.0
    "fr13_length": "2026-10-11",  # v0.16.0
    "fr13_list": "2026-10-11",
}
ONE_SENTENCE_END = "2026-07-21"  # v0.10.0 relaxed it to "usually"
ROOT_MOVE = "2026-10-11"

ERAS = [
    ("e1", "0000-00-00", "2026-06-23"),
    ("e2", "2026-06-24", "2026-07-20"),
    ("e3", "2026-07-21", "2026-08-12"),
    ("e4", "2026-08-13", "2026-10-10"),
    ("e5", "2026-10-11", "9999-99-99"),
]

ATX = re.compile(r"^ {0,3}(#{1,6})(?:\s+(.*?))?\s*$")
LIST_ITEM = re.compile(r"^\s*([-*+]|\d+[.)])\s")  # checkpoint.py's own
CHECKED = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[[xX]\]")
UNCHECKED = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[ \]")
DONE_PREFIX = re.compile(
    r"^\s*(?:[-*+]|\d+[.)])\s+(?:\*\*|__)?\s*"
    r"(?:done|fait|termin[ée]e?s?|completed?|landed|shipped|fixed|resolved|"
    r"r[ée]solu|closed)\s*(?:\*\*|__)?\s*[:：—–]"
    r"|^\s*(?:[-*+]|\d+[.)])\s+(?:✅|☑|✔|✓)",
    re.I,
)
STRIKE = re.compile(r"~~\S.*?~~")
RAISED = re.compile(
    r"\b(?:raised|asked|carried|surfaced|listed|open|pending|unanswered)\b[^.\n]{0,40}"
    r"\b(?:\d+|two|three|four|five|six|several)\s+(?:times|frames|sessions|handoffs)\b"
    r"|\bfor\s+the\s+(?:second|third|fourth|fifth|\d+(?:st|nd|rd|th))\s+(?:time|frame|session)\b"
    r"|\b(?:pos[ée]e?s?|demand[ée]e?s?|soulev[ée]e?s?)\s+(?:\d+|deux|trois|quatre)\s+fois\b",
    re.I,
)
COMMIT = re.compile(
    r"\buncommit+ed\b|\bunpushed\b|\bunstaged\b|\bunmerged\b"
    r"|\bnot\s+(?:yet\s+)?(?:been\s+)?(?:commit+ed|pushed|staged|merged|released|tagged)\b"
    r"|\b(?:commit+ed|pushed|staged|merged)\b"
    r"|\bready\s+(?:to|for)\s+(?:be\s+)?(?:commit|push|merge|release)"
    r"|\b(?:commit|push)\s+(?:the|this|these|those|it|them|all|everything|both|"
    r"when|once|after|before|to\s+origin|is\s+pending|pending)\b"
    r"|\b(?:needs?|awaits?|awaiting|pending|owed|to)\s+(?:a\s+|the\s+|be\s+)?(?:commit|push)\b"
    r"|\bworking\s+tree\b|\b(?:ahead|behind)\s+(?:of\s+)?(?:origin|main|upstream)\b"
    r"|\bgit\s+(?:status|push|commit)\b|\bdirty\b|\bclean\s+tree\b"
    r"|\bnon\s+(?:commit[ée]e?s?|pouss[ée]e?s?)\b|\bcommit[ée]e?s?\b|\bpouss[ée]e?s?\b"
    r"|\bpas\s+(?:encore\s+)?(?:commit|pouss)|\b[àa]\s+(?:commit(?:t)?er|pousser)\b",
    re.I,
)
# Hand verdicts on a candidate sentence that count as a hit, and their class.
VERDICT_CLASS = {
    "status": "commit_status_pending",
    "log": "commit_status_done",
    "act": "commit_act_item",
}
SENT_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-ZÀ-Ý`*\[(\"'])")


def era_of(date):
    for name, lo, hi in ERAS:
        if lo <= date <= hi:
            return name
    return "?"


def sections(text):
    """Split into (level, title, lines) blocks; the preamble has level 0."""
    out = [(0, "", [])]
    for line in text.split("\n"):
        m = ATX.match(line)
        if m:
            out.append((len(m.group(1)), (m.group(2) or "").strip(), []))
        else:
            out[-1][2].append(line)
    return out


def units(lines):
    """Yield sentences: list items whole, prose unwrapped and split."""
    block, kind = [], None
    def flush():
        if not block:
            return []
        text = " ".join(s.strip() for s in block)
        return [text] if kind == "item" else [
            s.strip() for s in SENT_SPLIT.split(text) if s.strip()
        ]
    for line in lines:
        if not line.strip():
            yield from flush()
            block, kind = [], None
        elif LIST_ITEM.match(line):
            yield from flush()
            block, kind = [line], "item"
        else:
            if kind is None:
                kind = "prose"
            block.append(line)
    yield from flush()


def norm(s):
    return re.sub(r"\s+", " ", s.strip().lower())


def key(s):
    return hashlib.sha1(norm(s).encode()).hexdigest()[:12]


def fr13_body(text):
    lines = text.split("\n")
    prose = [l for l in lines if not re.fullmatch(r" {0,3}#{1,6}(\s.*)?", l.rstrip())]
    return "\n".join(prose).strip()


def load(base):
    rows = list(csv.DictReader(open(os.path.join(base, "versions.tsv")), delimiter="\t"))
    merged = {}
    for r in rows:
        if r["kind"] == "generated":
            continue
        k = (r["repo"], r["kind"], r["blob"])
        hist = r["source"] == "history"
        cur = merged.get(k)
        cand = {
            "repo": r["repo"], "kind": r["kind"], "blob": r["blob"],
            "paths": {r["path"]}, "date": r["adate"][:10],
            "commit": r["commit"][:10] if hist else "working copy",
            "hist": hist, "wc": not hist, "ncommits": int(r["ncommits"]),
        }
        if cur is None:
            merged[k] = cand
            continue
        cur["paths"] |= cand["paths"]
        cur["hist"] |= hist
        cur["wc"] |= not hist
        cur["ncommits"] += cand["ncommits"]
        # A committed appearance dates the version; a working copy only when
        # nothing else does.
        if hist and (cur["commit"] == "working copy" or cand["date"] < cur["date"]):
            cur["date"], cur["commit"] = cand["date"], cand["commit"]
    return list(merged.values())


def main():
    base = sys.argv[1]
    verdicts = {}
    if len(sys.argv) > 2 and os.path.exists(sys.argv[2]):
        for line in open(sys.argv[2], encoding="utf-8"):
            p = line.rstrip("\n").split("\t")
            if len(p) >= 2 and p[0] and not p[0].startswith("#"):
                verdicts[p[0]] = p[1]
    frames = load(base)
    hits = []
    cands = defaultdict(lambda: {"n": 0, "repos": set(), "kinds": set(), "text": ""})
    out_rows = []
    # One blob in several repositories is one written version: the vendored
    # toolkit subtree carried its own frame into its consumers. The earliest
    # appearance is the version; the rest are copies and are not classified.
    origin = {}
    for f in sorted(frames, key=lambda x: (x["date"], x["repo"])):
        origin.setdefault((f["kind"], f["blob"]), f["repo"])
    for f in sorted(frames, key=lambda x: (x["kind"], x["repo"], x["date"], x["blob"])):
        text = open(
            os.path.join(base, "blobs", f["repo"], f["blob"]),
            encoding="utf-8", errors="replace",
        ).read()
        kind, date = f["kind"], f["date"]
        legacy = any(p.startswith(".claude/") for p in f["paths"])
        secs = sections(text)
        h1 = [t for lv, t, _ in secs if lv == 1]
        h2 = [t for lv, t, _ in secs if lv == 2]
        h3 = [t for lv, t, _ in secs if lv >= 3]
        body = fr13_body(text)
        template = (
            "Current task" in h2 if kind == "task"
            else ("Remaining" in h2 or "Open decisions" in h2)
        )
        if legacy:
            authored = "plugin"
        elif date >= ROOT_MOVE and (template or kind == "task"):
            # A root TODO.md is the plugin's only when it carries the template;
            # TASK.md is no project's own name, so it is the plugin's as found.
            authored = "plugin"
        else:
            authored = "hand"
        if authored == "plugin" and len(body) < 30:
            authored = "placeholder"
        if authored == "plugin" and origin[(kind, f["blob"])] != f["repo"]:
            authored = "copy"
        row = {
            "repo": f["repo"], "private": int(f["repo"] in PRIVATE), "kind": kind,
            "paths": "|".join(sorted(f["paths"])), "blob": f["blob"][:10],
            "commit": f["commit"], "date": date, "era": era_of(date),
            "in_history": int(f["hist"]), "in_wc": int(f["wc"]),
            "authored": authored, "body_chars": len(body),
            "h2": "|".join(h2),
        }
        flags = {}

        def hit(cls, excerpt, rule):
            in_force = date >= IN_FORCE[rule]
            if rule == "one_sentence" and date >= ONE_SENTENCE_END:
                in_force = False
            # FR13 shipped with the move to the root: a frame still written to
            # the legacy path came from a release without it.
            if rule.startswith("fr13") and legacy:
                in_force = False
            flags.setdefault(cls, in_force)
            hits.append({
                "repo": f["repo"], "private": row["private"], "kind": kind,
                "path": row["paths"], "commit": f["commit"], "date": date,
                "era": row["era"], "blob": row["blob"], "class": cls,
                "in_force": int(in_force), "excerpt": excerpt.strip()[:400],
            })

        if authored == "plugin":
            if h1:
                hit("h1_heading", "# " + h1[0], "no_h1")
            if not template:
                hit("no_template_heading", "headings: " + (" | ".join(h2) or "(none)"),
                    "template_heading")
            if h3:
                hit("subheading", "### " + " | ### ".join(h3[:4]), "extra_section")
            od = [(t, ls) for lv, t, ls in secs if lv == 2 and t == "Open decisions"]
            for _, ls in od:
                if not any(LIST_ITEM.match(l) for l in ls) and len(norm(" ".join(ls))) < 60:
                    hit("empty_open_decisions", "## Open decisions / " + norm(" ".join(ls)),
                        "empty_open_decisions")
            for i, line in enumerate(text.split("\n")):
                if CHECKED.match(line):
                    hit("checked_item", line, "todo_completion_state")
                    break
            n_unchecked = sum(1 for l in text.split("\n") if UNCHECKED.match(l))
            row["unchecked_boxes"] = n_unchecked
            if kind == "task":
                allowed = {"Current task"} | (
                    {"Open decisions"} if date < IN_FORCE["open_decisions_in_task"] else set()
                )
                extra = [t for t in h2 if t not in {"Current task", "Open decisions"}]
                if extra:
                    hit("extra_section", "## " + " | ## ".join(extra), "extra_section")
                if "Open decisions" in h2:
                    # Not a deviation before the move; recorded for the era table.
                    row["has_open_decisions"] = 1
                    if date >= IN_FORCE["open_decisions_in_task"]:
                        hit("open_decisions_in_task", "## Open decisions",
                            "open_decisions_in_task")
                ct = [ls for lv, t, ls in secs if lv == 2 and t == "Current task"]
                ct_lines = ct[0] if ct else []
                # Sub-sections under Current task belong to it for counting.
                if ct:
                    idx = next(i for i, s in enumerate(secs) if s[0] == 2 and s[1] == "Current task")
                    for lv, t, ls in secs[idx + 1:]:
                        if lv <= 2:
                            break
                        ct_lines = ct_lines + ls
                ct_units = list(units(ct_lines))
                ct_items = [l for l in ct_lines if LIST_ITEM.match(l)]
                row["ct_chars"] = len("\n".join(ct_lines).strip())
                row["ct_sentences"] = len(ct_units)
                row["ct_list_items"] = len(ct_items)
                if len(ct_units) > 1:
                    hit("multi_sentence_task",
                        f"{len(ct_units)} sentences, {row['ct_chars']} chars: "
                        + (ct_units[0][:200] if ct_units else ""), "one_sentence")
                if ct_items:
                    hit("list_in_current_task",
                        f"{len(ct_items)} items; first: {ct_items[0]}", "list_in_task")
                first = next((l for l in text.split("\n") if LIST_ITEM.match(l)), None)
                if first is not None:
                    hit("fr13_list", first, "fr13_list")
                if len(body) > 1000:
                    hit("fr13_length", f"body is {len(body)} characters", "fr13_length")
                rule = "commit_status_task"
            else:
                expect = ["Remaining"] if date < IN_FORCE["open_decisions_in_task"] else [
                    "Open decisions", "Remaining"]
                extra = [t for t in h2 if t not in expect]
                if extra:
                    hit("extra_section", "## " + " | ## ".join(extra[:5]), "todo_template")
                if "Open decisions" in h2 and "Remaining" in h2 and (
                    h2.index("Open decisions") > h2.index("Remaining")
                ):
                    hit("section_order", "## Remaining before ## Open decisions",
                        "todo_template")
                for line in text.split("\n"):
                    if DONE_PREFIX.match(line):
                        hit("done_prefix", line, "todo_completion_state")
                        break
                for line in text.split("\n"):
                    if STRIKE.search(line):
                        hit("struck_item", line, "todo_completion_state")
                        break
                m = RAISED.search(text)
                if m:
                    lo = max(0, m.start() - 120)
                    hit("raised_n_times", text[lo:m.end() + 60].replace("\n", " "),
                        "raised_n_times")
                items = [u for lv, t, ls in secs for u in units(ls) if LIST_ITEM.match(u)]
                prose = [u for lv, t, ls in secs for u in units(ls) if not LIST_ITEM.match(u)]
                row["todo_items"] = len(items)
                row["todo_prose_units"] = len(prose)
                row["todo_item_median"] = (
                    sorted(len(i) for i in items)[len(items) // 2] if items else 0
                )
                row["todo_items_over_300"] = sum(1 for i in items if len(i) > 300)
                rule = "commit_status_todo"
            # Commit status: a candidate filter. Each unique sentence is judged
            # by hand; only a "status" verdict becomes a hit.
            seen = set()
            for lv, t, ls in secs:
                for u in units(ls):
                    if not COMMIT.search(u):
                        continue
                    k = key(u)
                    c = cands[k]
                    c["n"] += 1
                    c["repos"].add(f["repo"])
                    c["kinds"].add(kind)
                    c["text"] = u
                    row["commit_candidates"] = row.get("commit_candidates", 0) + 1
                    v = verdicts.get(k, "")
                    if v in VERDICT_CLASS:
                        if v not in seen:
                            seen.add(v)
                            hit(VERDICT_CLASS[v], u, rule)
                    elif v in ("decision", "border"):
                        row["commit_" + v] = row.get("commit_" + v, 0) + 1
        for cls, in_force in flags.items():
            row["x_" + cls] = "dev" if in_force else "today"
        out_rows.append(row)

    cols = []
    for r in out_rows:
        for k in r:
            if k not in cols:
                cols.append(k)
    with open(os.path.join(base, "frames.tsv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, cols, delimiter="\t", restval="")
        w.writeheader()
        w.writerows(out_rows)
    with open(os.path.join(base, "hits.tsv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, list(hits[0]), delimiter="\t")
        w.writeheader()
        w.writerows(hits)
    with open(os.path.join(base, "commit-candidates.tsv"), "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["key", "verdict", "n", "kinds", "repos", "text"])
        for k, c in sorted(cands.items(), key=lambda x: (-x[1]["n"], x[0])):
            w.writerow([k, verdicts.get(k, ""), c["n"], "|".join(sorted(c["kinds"])),
                        "|".join(sorted(c["repos"])), c["text"]])
    print(len(out_rows), "frames;", len(hits), "hits;", len(cands), "commit candidates")


if __name__ == "__main__":
    main()
