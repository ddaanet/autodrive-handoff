"""Print the overflow analysis tables from labels.tsv.

Usage: python3 tally.py [labels.tsv]. Needs nothing but that file: one row
per unit (unit, repo, sha, date, era, chars, label), the unit id's prefix
naming the version. Refuses a file whose labels are not all A-E or whose unit
ids repeat.
"""

import collections
import sys
from pathlib import Path


def main() -> None:
    default = Path(__file__).with_name("labels.tsv")
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    versions = read(path)
    for name, era in (("all", None), ("era 2", 2), ("era 3", 3)):
        report(name, [v for v in versions.values() if era in (None, v["era"])])


def read(path):
    versions, seen = {}, set()
    for n, line in enumerate(path.read_text().split("\n")[1:], 2):
        if not line:
            continue
        unit, repo, _sha, _date, era, chars, label = line.split("\t")
        if label not in "ABCDE" or unit in seen:
            sys.exit(f"{path}:{n}: bad or repeated unit {unit} {label}")
        seen.add(unit)
        v = versions.setdefault(
            unit.split(".")[0], {"repo": repo, "era": int(era), "units": []}
        )
        v["units"].append((label, int(chars)))
    return versions


def report(name, sample):
    total = sum(c for v in sample for _, c in v["units"])
    print(f"\n{name}: {len(sample)} versions, {total} characters")
    for label in "ABCDE":
        chars = sum(c for v in sample for lab, c in v["units"] if lab == label)
        carrying = sum(any(lab == label for lab, _ in v["units"]) for v in sample)
        print(f"  {label}: {100 * chars / total:.1f}% of characters, {carrying} versions")
    print(
        "  any B/C/D:",
        sum(any(lab in "BCD" for lab, _ in v["units"]) for v in sample),
        " more than one D unit:",
        sum(sum(lab == "D" for lab, _ in v["units"]) > 1 for v in sample),
        " A plus at most one D:",
        sum(
            all(lab in "AD" for lab, _ in v["units"])
            and sum(lab == "D" for lab, _ in v["units"]) <= 1
            for v in sample
        ),
    )
    readings = {
        "raw body": [joined(c for _, c in v["units"]) for v in sample],
        "A only": [residual(v, done_sentences=0) for v in sample],
        "A + one D": [residual(v, done_sentences=1) for v in sample],
    }
    for reading, d in readings.items():
        cuts = " ".join(f"p{round(p * 100)}={quantile(d, p)}" for p in PERCENTILES)
        print(f"  {reading:10} {cuts} max={max(d)}")
    for cap in CAPS:
        over = ", ".join(
            f"{reading} {sum(x > cap for x in d)}" for reading, d in readings.items()
        )
        print(f"  over {cap}: {over}")


PERCENTILES = (0.5, 0.75, 0.9, 0.95, 0.99)
CAPS = (600, 800, 1000, 1200, 1500)


def residual(version, *, done_sentences):
    """Characters of the A units plus the first `done_sentences` D units."""
    kept, done = [], 0
    for label, chars in version["units"]:
        if label == "A":
            kept.append(chars)
        elif label == "D" and done < done_sentences:
            kept.append(chars)
            done += 1
    return joined(kept)


def joined(lengths):
    """Total length with one separating character between units."""
    lengths = list(lengths)
    return sum(lengths) + max(len(lengths) - 1, 0)


def quantile(values, p):
    v = sorted(values)
    k = (len(v) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(v) - 1)
    return round(v[lo] + (v[hi] - v[lo]) * (k - lo))


main()
