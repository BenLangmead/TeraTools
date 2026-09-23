#!/usr/bin/env python3
"""Reference minima from a per-run LCP table (TSV), independent of TeraLCP.

Input TSV: '#' lines are metadata; a header line 'id off len c sa lcp'; then one
line per BWT run with the run's character c, its length len and its LCP values
(comma separated, one per row of the run, top row first).

Writes BASE.bwt.heads / BASE.bwt.len (the RLBWT, for TeraLCP -f rlbwt) and
BASE.expected in ms_minima_dump.py's text format (header line omitted):
prefix minima are strict running minima from the run's top value, suffix minima
strict running minima from the next run's top (+infinity after the last run).
"""
import argparse


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tsv")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    runs = []
    with open(a.tsv) as f:
        for line in f:
            if line.startswith("#") or line.startswith("id\t"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 6:
                continue
            length, c = int(fields[2]), fields[3]
            lcp = [int(x) for x in fields[5].split(",")]
            if len(lcp) != length or len(c) != 1:
                raise SystemExit("bad line: " + line[:80])
            runs.append((c, lcp))

    with open(a.out + ".bwt.heads", "wb") as fh, open(a.out + ".bwt.len", "wb") as fl:
        for c, lcp in runs:
            fh.write(c.encode())
            fl.write(len(lcp).to_bytes(5, "little"))

    total = 0
    with open(a.out + ".expected", "w") as f:
        for i, (_, lcp) in enumerate(runs):
            top = lcp[0]
            nxt = runs[i + 1][1][0] if i + 1 < len(runs) else float("inf")
            chosen = {}
            m = top
            for o in range(1, len(lcp)):
                if lcp[o] < m:
                    chosen[o] = lcp[o]
                    m = lcp[o]
            m = nxt
            for o in range(len(lcp) - 1, 0, -1):
                if lcp[o] < m:
                    chosen[o] = lcp[o]
                    m = lcp[o]
            pairs = sorted(chosen.items())
            total += len(pairs)
            f.write("%d\t%d\t%d\t%s\n" % (i, top, len(pairs), ",".join("%d:%d" % p for p in pairs)))
    n = sum(len(l) for _, l in runs)
    print("n=%d r=%d pairs=%d (%.3f per run)" % (n, len(runs), total, total / len(runs)))


if __name__ == "__main__":
    main()
