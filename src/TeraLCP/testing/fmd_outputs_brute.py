#!/usr/bin/env python3
"""Brute-force reference for TeraLCP -ominima and -ophi on a ropebwt3 FMD.

Given the FASTA an FMD was built from (ropebwt3 build -d), builds the text
TeraLCP indexes,

    T = S_0 $_0 S_1 $_1 ... S_{N-1} $_{N-1},

where S_0, S_1, ... are each record followed by its reverse complement (unless
--no-rc), uppercased, with every non-ACGT character mapped to N, and where the
separators are distinct symbols, $_i < $_j for i < j, all smaller than A. It
sorts the suffixes of T directly, derives the BWT (cyclically, BWT[k] =
T[SA[k] - 1]) and LCP (a common prefix never extends over a separator), and
compares:

  * with --heads BASE: the BWT's runs, with each separator its own run, against
    BASE.bwt.heads / BASE.bwt.len as TeraLCP -othresholds writes them (head
    byte 0 for a separator, ASCII for a base);
  * with --minima FILE: the -ominima file, whose records are the BWT's maximal
    runs (a run of separators is one record);
  * with --phi FILE: the -ophi file, one record (SA[top], SA[bottom], LCP[top])
    per run with each separator its own run;
  * with --write-bwt FILE: writes the BWT as the characters $ACGTN, for
    fmd_split_writer.

Exits 1 on any difference. Meant for texts of a few thousand characters.
"""
import argparse
import struct
import sys
from bisect import bisect_left

CODE = {"A": 1, "C": 2, "G": 3, "T": 4}
COMP = {1: 4, 2: 3, 3: 2, 4: 1, 5: 5}


def read_fasta(path):
    seqs, cur = [], None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if cur is not None:
                    seqs.append("".join(cur))
                cur = []
            elif cur is not None:
                cur.append(line)
    if cur is not None:
        seqs.append("".join(cur))
    return seqs


def varint(d, pos):
    x = shift = 0
    while True:
        c = d[pos]
        pos += 1
        x |= (c & 0x7F) << shift
        if not c & 0x80:
            return x, pos
        shift += 7


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fasta")
    ap.add_argument("--no-rc", action="store_true", help="the FMD was built without reverse complements (-R)")
    ap.add_argument("--heads", help="BASE of TeraLCP's .bwt.heads/.bwt.len")
    ap.add_argument("--minima", help="-ominima file")
    ap.add_argument("--phi", help="-ophi file")
    ap.add_argument("--write-bwt", help="write the BWT as the characters $ACGTN to this file")
    a = ap.parse_args()

    strings = []
    for s in read_fasta(a.fasta):
        codes = [CODE.get(ch, 5) for ch in s.upper()]
        strings.append(codes)
        if not a.no_rc:
            strings.append([COMP[c] for c in reversed(codes)])
    N = len(strings)
    # Separator i is coded i - N: negative, increasing in i, below every base.
    T = []
    for i, w in enumerate(strings):
        T.extend(w)
        T.append(i - N)
    n = len(T)
    ends = [p for p in range(n) if T[p] < 0]

    def suffix(p):
        e = ends[bisect_left(ends, p)]
        return T[p:e + 1]

    SA = sorted(range(n), key=suffix)
    bwt = [max(T[p - 1], 0) for p in SA]

    def lcp(p, q):
        k = 0
        while T[p + k] >= 0 and T[p + k] == T[q + k]:
            k += 1
        return k

    LCP = [0] + [lcp(SA[k - 1], SA[k]) for k in range(1, n)]

    # Runs with each separator its own run, and maximal runs.
    split, maximal = [], []
    for k in range(n):
        if k == 0 or bwt[k] != bwt[k - 1] or bwt[k] == 0:
            split.append([k, 1])
        else:
            split[-1][1] += 1
        if k == 0 or bwt[k] != bwt[k - 1]:
            maximal.append([k, 1])
        else:
            maximal[-1][1] += 1

    if a.write_bwt:
        with open(a.write_bwt, "w") as f:
            f.write("".join("$ACGTN"[c] for c in bwt))

    bad = 0

    def fail(msg):
        nonlocal bad
        bad += 1
        if bad <= 10:
            print("MISMATCH " + msg, file=sys.stderr)

    if a.heads:
        heads = open(a.heads + ".bwt.heads", "rb").read()
        lens = open(a.heads + ".bwt.len", "rb").read()
        got = [(heads[i], int.from_bytes(lens[5 * i:5 * i + 5], "little")) for i in range(len(heads))]
        want = [(b"\x00ACGTN"[bwt[s]], L) for s, L in split]
        if got != want:
            fail("heads/len: %d runs in file, %d expected" % (len(got), len(want)))

    if a.minima:
        d = open(a.minima, "rb").read()
        if d[:8] != bytes([0x93]) + b"TLMSM\x00\x01":
            fail("minima: bad magic")
        r, fn, pairs = struct.unpack_from("<QQQ", d, 16)
        if r != len(maximal) or fn != n:
            fail("minima header: r=%d n=%d, expected r=%d n=%d" % (r, fn, len(maximal), n))
        pos, total = 48, 0
        for i, (s, L) in enumerate(maximal):
            top = LCP[s]
            nxt = LCP[maximal[i + 1][0]] if i + 1 < len(maximal) else float("inf")
            keep = {}
            m = top
            for o in range(1, L):
                if LCP[s + o] < m:
                    keep[o] = LCP[s + o]
                    m = LCP[s + o]
            m = nxt
            for o in range(L - 1, 0, -1):
                if LCP[s + o] < m:
                    keep[o] = LCP[s + o]
                    m = LCP[s + o]
            want = (top, sorted(keep.items()))
            total += len(keep)
            if pos >= len(d):
                fail("minima: file ends at record %d" % i)
                break
            ftop, pos = varint(d, pos)
            cnt, pos = varint(d, pos)
            off, got = 0, []
            for _ in range(cnt):
                g, pos = varint(d, pos)
                v, pos = varint(d, pos)
                off += g
                got.append((off, v))
            if (ftop, got) != want:
                fail("minima record %d (rows %d..%d): file %s, expected %s" % (i, s, s + L - 1, (ftop, got), want))
        if pos != len(d):
            fail("minima: trailing bytes")
        if pairs != total:
            fail("minima header: %d pairs, expected %d" % (pairs, total))

    if a.phi:
        d = open(a.phi, "rb").read()
        if d[:8] != bytes([0x93]) + b"TLPHI\x00\x01":
            fail("phi: bad magic")
        w = d[9]
        recs, fn, mx = struct.unpack_from("<QQQ", d, 16)
        if recs != len(split) or fn != n or mx != len(maximal):
            fail("phi header: records=%d n=%d maximal=%d, expected %d %d %d" % (recs, fn, mx, len(split), n, len(maximal)))
        if len(d) != 48 + 3 * w * recs:
            fail("phi: file size")
        for i, (s, L) in enumerate(split[:recs]):
            o = 48 + 3 * w * i
            got = tuple(int.from_bytes(d[o + f * w:o + (f + 1) * w], "little") for f in range(3))
            want = (SA[s], SA[s + L - 1], LCP[s])
            if got != want:
                fail("phi record %d (rows %d..%d): file %s, expected %s" % (i, s, s + L - 1, got, want))

    sep_runs = sum(1 for s, L in maximal if bwt[s] == 0 and L > 1)
    print("n=%d strings=%d runs=%d maximal=%d separator runs longer than 1: %d %s"
          % (n, N, len(split), len(maximal), sep_runs, "MISMATCHES=%d" % bad if bad else "ok"), file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
