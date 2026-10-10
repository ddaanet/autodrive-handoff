"""Split every task-file version since 2026-07-22 into labelable units.

Writes units.tsv (vid, uid, repo, sha, date, era, chars, text) and
batch-NN.txt files a labeller reads. Run from /tmp/claude/survey.
"""
import csv, re, hashlib, sys

LI = re.compile(r"^\s*([-*+]|\d+[.)])\s")
H = re.compile(r"^\s{0,3}#{1,6}\s")
SENT = re.compile(r"(?<=[.!?;])[\"')*`]*\s+(?=[A-ZÀ-Ý`*\[(\"'0-9])")
BATCH_CHARS = 45000
CALIB = {"df2c4c05", "fb542dc2", "a8abf8b6", "ae54c1b9", "914fec13", "25a137c3",
         "a0a9b4f7", "06a431ec", "b5b1b30c", "7c4f8114", "0b7ef2e2", "3ef9c9c0",
         "a61e788d", "926e372d", "4c10e5e4"}


def units(text):
    """Yield ('H', heading) and ('U', unit) in order."""
    block, kind = [], None

    def flush():
        nonlocal block, kind
        if block:
            joined = " ".join(s.strip() for s in block)
            if kind == "li":
                yield ("U", joined)
            else:
                for s in SENT.split(joined):
                    if s.strip():
                        yield ("U", s.strip())
        block, kind = [], None

    for line in text.split("\n"):
        if H.match(line):
            yield from flush()
            yield ("H", line.strip())
        elif not line.strip():
            yield from flush()
        elif LI.match(line):
            yield from flush()
            block, kind = [line], "li"
        else:
            if kind is None:
                kind = "p"
            block.append(line)
    yield from flush()


rows = [r for r in csv.DictReader(open("versions.tsv"), delimiter="\t")
        if r["date"][:10] >= "2026-07-22"]
rows.sort(key=lambda r: (r["repo"], r["date"]))
seen, out, versions = set(), [], []
for r in rows:
    t = open(f"blobs/{r['repo']}_{r['sha']}.md").read()
    h = hashlib.sha1(t.strip().encode()).hexdigest()
    if h in seen:
        continue
    seen.add(h)
    vid = f"v{len(versions) + 1:03d}"
    era = 2 if r["date"][:10] < "2026-08-12" else 3
    lines, n, chars = [f"=== {vid} {r['repo']} {r['date'][:10]}"], 0, 0
    for k, s in units(t):
        if k == "H":
            lines.append(s)
        else:
            n += 1
            uid = f"{vid}.{n:02d}"
            lines.append(f"{uid}\t{s}")
            out.append([vid, uid, r["repo"], r["sha"], r["date"][:10], era, len(s), s])
            chars += len(s)
    versions.append((vid, r["sha"], chars, "\n".join(lines)))

with open("overflow/units.tsv", "w") as f:
    w = csv.writer(f, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\")
    w.writerow("vid uid repo sha date era chars text".split())
    w.writerows(out)

open("overflow/calib.txt", "w").write(
    "\n\n".join(v[3] for v in versions if v[1] in CALIB) + "\n")
b, size, cur = 1, 0, []
for v in versions:
    if cur and size + v[2] > BATCH_CHARS:
        open(f"overflow/batch-{b:02d}.txt", "w").write("\n\n".join(cur) + "\n")
        b, size, cur = b + 1, 0, []
    cur.append(v[3]); size += v[2]
open(f"overflow/batch-{b:02d}.txt", "w").write("\n\n".join(cur) + "\n")
print(len(versions), "versions", len(out), "units", b, "batches")
