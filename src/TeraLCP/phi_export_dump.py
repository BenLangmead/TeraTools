#!/usr/bin/env python3
"""Print a TeraLCP -ophi file (format: MsMinimaWriter in
src/include/TeraLCP/TeraLCP.h).

One line per record: record, head (SA at the run's top row), tail (SA at its
bottom row) and top (LCP at its top row), tab-separated, after a header line
starting with '#'. With --summary, print only the header.
"""
import argparse
import struct
import sys

MAGIC = bytes([0x93]) + b"TLPHI\x00\x01"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    with open(a.file, "rb") as f:
        h = f.read(48)
        if len(h) != 48 or h[:8] != MAGIC:
            sys.exit("not a TLPHI v1 file")
        w = h[9]
        records, n, maximal = struct.unpack_from("<QQQ", h, 16)
        print("# records=%d n=%d maximal_runs=%d field_bytes=%d" % (records, n, maximal, w))
        if a.summary:
            return
        out = sys.stdout
        for i in range(records):
            rec = f.read(3 * w)
            if len(rec) != 3 * w:
                sys.exit("truncated at record %d" % i)
            v = [int.from_bytes(rec[k * w:(k + 1) * w], "little") for k in range(3)]
            out.write("%d\t%d\t%d\t%d\n" % (i, v[0], v[1], v[2]))
        if f.read(1):
            sys.exit("trailing bytes")


if __name__ == "__main__":
    main()
