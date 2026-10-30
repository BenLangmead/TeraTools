#!/usr/bin/env python3
"""Brute-force reference for TeraLCP -ominima, starting from a text.

Builds the (multi-string) BWT by sorting rotations directly, computes LCP by
comparing adjacent rows character by character, and derives per-run minima.
Writes BASE.bwt.heads / BASE.bwt.len (TeraLCP -f rlbwt input, sentinel byte 0)
and BASE.expected in the text format of ms_minima_dump.py (header line omitted).

Text model:
  --mode single : one string S1<sep>S2<sep>...Sm$ with a single sentinel; the
                  separator is an ordinary character.
  --mode multi  : m strings Si$, each treated cyclically, rotations sorted with
                  $ smallest and ties broken by string index. This is the
                  multi-string BWT convention in which the k-th $ of the BWT
                  maps by LF to the k-th $ row.
LCP[k] is the longest common prefix of rows k-1 and k, where $ never matches
(extension stops at a sentinel); LCP[0] = 0. Each sentinel is its own run.
"""
import argparse
import random
import sys

SENT = "\x00"


def rotations_sorted(strings):
    maxlen = max(len(w) for w in strings)
    items = []
    for i, w in enumerate(strings):
        need = 2 * maxlen + 2
        k = need // len(w) + 2
        for p in range(len(w)):
            rot = w[p:] + w[:p]
            items.append(((rot * k)[:need], i, p))
    items.sort()
    return [(i, p) for _, i, p in items]


def row_string(strings, i, p):
    """The row's characters up to and including its first sentinel."""
    w = strings[i]
    rot = w[p:] + w[:p]
    return rot[: rot.index(SENT) + 1]


def lcp_stop(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y or x == SENT:
            break
        n += 1
    return n


def expected_minima(bwt, lcp):
    n = len(bwt)
    runs = []  # (start, length, char)
    k = 0
    while k < n:
        e = k + 1
        if bwt[k] != SENT:
            while e < n and bwt[e] == bwt[k]:
                e += 1
        runs.append((k, e - k, bwt[k]))
        k = e
    out = []
    INF = float("inf")
    for idx, (s, L, _) in enumerate(runs):
        top = lcp[s]
        nxt = lcp[runs[idx + 1][0]] if idx + 1 < len(runs) else INF
        chosen = {}
        m = top
        for o in range(1, L):
            v = lcp[s + o]
            if v < m:
                chosen[o] = v
                m = v
        m = nxt
        for o in range(L - 1, 0, -1):
            v = lcp[s + o]
            if v < m:
                chosen[o] = v
                m = v
        out.append((top, sorted(chosen.items())))
    return runs, out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="output base path")
    ap.add_argument("--mode", choices=["single", "multi"], default="single")
    ap.add_argument("--sep", default="%", help="separator for --mode single ('' for none)")
    ap.add_argument("--seqfile", help="file with one sequence per line")
    ap.add_argument("--random", help="NUM,LO,HI,SEED: random DNA sequences")
    ap.add_argument("--repeat", type=float, default=0.0,
                    help="with --random: probability that a sequence is a mutated copy of an earlier one")
    ap.add_argument("seqs", nargs="*")
    a = ap.parse_args()

    seqs = list(a.seqs)
    if a.seqfile:
        with open(a.seqfile) as f:
            seqs += [line.strip() for line in f if line.strip()]
    if a.random:
        num, lo, hi, seed = (int(x) for x in a.random.split(","))
        rng = random.Random(seed)
        for _ in range(num):
            if seqs and rng.random() < a.repeat:
                base = list(rng.choice(seqs))
                for j in range(len(base)):
                    if rng.random() < 0.03:
                        base[j] = rng.choice("ACGT")
                s = "".join(base)
                if rng.random() < 0.5 and len(s) > 4:
                    cut = rng.randrange(1, len(s) - 1)
                    s = s[cut:] + s[:cut] if rng.random() < 0.5 else s[:cut]
                seqs.append(s)
            else:
                seqs.append("".join(rng.choice("ACGT") for _ in range(rng.randint(lo, hi))))
    if not seqs:
        sys.exit("no sequences")

    if a.mode == "single":
        strings = [a.sep.join(seqs) + SENT]
    else:
        strings = [s + SENT for s in seqs]

    order = rotations_sorted(strings)
    rows = [row_string(strings, i, p) for i, p in order]
    bwt = [strings[i][p - 1] for i, p in order]
    lcp = [0] + [lcp_stop(rows[k - 1], rows[k]) for k in range(1, len(rows))]
    runs, mins = expected_minima(bwt, lcp)

    with open(a.out + ".bwt.heads", "wb") as fh, open(a.out + ".bwt.len", "wb") as fl:
        for _, L, c in runs:
            fh.write(bytes([ord(c)]))
            fl.write(L.to_bytes(5, "little"))
    with open(a.out + ".expected", "w") as f:
        for i, (top, pairs) in enumerate(mins):
            f.write("%d\t%d\t%d\t%s\n" % (i, top, len(pairs), ",".join("%d:%d" % p for p in pairs)))
    total = sum(len(p) for _, p in mins)
    print("n=%d r=%d pairs=%d" % (len(bwt), len(runs), total))


if __name__ == "__main__":
    main()
