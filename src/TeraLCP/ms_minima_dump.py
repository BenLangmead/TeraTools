#!/usr/bin/env python3
"""Dump a TeraLCP -ominima file (format: MS_MINIMA_FORMAT.md) as text.

Output: one header line starting with '#', then one line per BWT run:

    <run>\t<top>\t<count>\t<off>:<val>,<off>:<val>,...

Offsets are absolute offsets within the run (the gaps are summed). With
--summary only the header line and totals are printed.
"""
import argparse
import struct
import sys

MAGIC = bytes([0x93, ord('T'), ord('L'), ord('M'), ord('S'), ord('M'), 0x00, 0x01])
HEADER_BYTES = 48


def read_header(data):
    if len(data) < HEADER_BYTES or data[:8] != MAGIC:
        raise ValueError("not a TeraLCP ms minima file (bad magic)")
    flags = data[8]
    r, n, pairs, input_runs = struct.unpack_from("<QQQQ", data, 16)
    return {"flags": flags, "r": r, "n": n, "pairs": pairs, "input_runs": input_runs}


def records(data, r):
    """Yields (top, [(offset, value), ...]) for each of the r runs."""
    pos = HEADER_BYTES
    end = len(data)

    def varint():
        nonlocal pos
        x = 0
        shift = 0
        while True:
            if pos >= end:
                raise ValueError("truncated record at byte %d" % pos)
            c = data[pos]
            pos += 1
            x |= (c & 0x7F) << shift
            if c < 0x80:
                return x
            shift += 7

    for _ in range(r):
        top = varint()
        cnt = varint()
        pairs = []
        off = 0
        for _ in range(cnt):
            off += varint()
            pairs.append((off, varint()))
        yield top, pairs
    if pos != end:
        raise ValueError("%d trailing bytes after %d runs" % (end - pos, r))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--summary", action="store_true", help="print only the header and totals")
    args = ap.parse_args()
    with open(args.file, "rb") as f:
        data = f.read()
    h = read_header(data)
    out = sys.stdout
    out.write("# r=%d n=%d pairs=%d input_runs=%d flags=%d\n" % (h["r"], h["n"], h["pairs"], h["input_runs"], h["flags"]))
    total = 0
    for i, (top, pairs) in enumerate(records(data, h["r"])):
        total += len(pairs)
        if not args.summary:
            out.write("%d\t%d\t%d\t%s\n" % (i, top, len(pairs), ",".join("%d:%d" % p for p in pairs)))
    if total != h["pairs"]:
        raise ValueError("header says %d pairs, records hold %d" % (h["pairs"], total))
    if args.summary:
        r = h["r"]
        out.write("# runs=%d stored_pairs=%d pairs_per_run=%.3f\n" % (r, total, total / r if r else 0.0))


if __name__ == "__main__":
    main()
