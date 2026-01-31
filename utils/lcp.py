#!/usr/bin/env python3

"""
Build suffix array, LCP array, and BWT for threshold investigation.
Supports inline strings or FASTA input; optional reverse-complement sequences.

The Kasai algorithm (pydivsufsort.kasai) takes only text and suffix array; it has
no notion of separators or sequence boundaries and cannot end LCPs at concatenation
points. We optionally truncate LCP values ourselves so common prefixes do not span
past the current sequence segment (for comparison with tools that stop at boundaries).
"""

import argparse
import sys
from typing import List, Optional

from pydivsufsort import divsufsort, kasai

# Valid DNA bases for FASTA (ACGT only, no N)
ACGT = frozenset("ACGTacgt")
FASTA_SEP = "$"


def _segment_end(pos: int, boundaries: List[int], n: int) -> int:
    """Return the end index of the segment containing pos (exclusive). Use n for positions past last boundary."""
    for b in boundaries:
        if b > pos:
            return b
    return n


def truncate_lcp_at_boundaries(
    lcp: List[int], sa: List[int], boundaries: List[int], n: int
) -> List[int]:
    """
    Truncate LCP so no common prefix spans past the segment containing that suffix.
    boundaries = cumulative sequence lengths (segment ends); n = text length.
    """
    out = [0] * len(lcp)
    for i in range(len(lcp)):
        pos = sa[i]
        end = _segment_end(pos, boundaries, n)
        out[i] = min(lcp[i], end - pos)
    return out


def sa_lcp_bwt(s: str, terminator: Optional[str] = None):
    """
    Build suffix array, LCP array, and BWT for string s. Returns (sa, lcp, bwt).

    If terminator is None, uses '#' and appends it when absent.
    If terminator is given (e.g. '$'), appends it only when s does not already end with it.
    Raises ValueError if the string has a character lexicographically smaller than the last.
    """
    if terminator is None:
        terminator = "#"
    if not s.endswith(terminator):
        s = s + terminator
    if s[-1] > min(s):
        raise ValueError("s has a character less than the terminator")
    s_bytes = s.encode("ascii")
    sa = divsufsort(s_bytes)
    lcp = kasai(s_bytes, sa)
    bwt = "".join(s[(i - 1) % len(s)] for i in sa)
    return sa, lcp, bwt


def lcp_bwt(s: str, boundaries: Optional[List[int]] = None):
    """
    Build suffix array, LCP array, and BWT for string s.
    Raises ValueError if the string has a character lexicographically smaller
    than the last. If boundaries is provided (segment end indices, cumulative
    sequence lengths), LCP values are truncated so common prefixes do not
    extend past the segment containing each suffix.
    """
    if not s.endswith('#'):
        s += '#'
    if s[-1] > min(s):
        raise ValueError("s has a character less than the terminator")
    s_bytes = s.encode("ascii")
    sa = divsufsort(s_bytes)
    lcp = kasai(s_bytes, sa)
    if boundaries is not None:
        lcp = truncate_lcp_at_boundaries(lcp, sa, boundaries, len(s))
    bwt = "".join(s[(i - 1) % len(s)] for i in sa)
    assert len(bwt) == len(lcp) == len(sa)
    assert lcp[-1] == 0
    lcp = [0] + list(lcp[:-1])
    run_id = 0
    run_offset = 0
    n = len(bwt)
    if n == 0:
        print("No BWT runs found.")
    else:
        i = 0
        while i < n:
            curr_char = bwt[i]
            start = i
            while i < n and bwt[i] == curr_char:
                i += 1
            end = i
            run_lcp = map(int, lcp[start:end]) if end > start else []
            yield (run_id, run_offset, curr_char, list(run_lcp))
            run_id += 1
            run_offset += (end - start)


def reverse_complement(seq: str) -> str:
    """Reverse complement of DNA sequence (ACGT only)."""
    comp = {"A": "T", "T": "A", "G": "C", "C": "G", "a": "t", "t": "a", "g": "c", "c": "g"}
    return "".join(comp[b] for b in reversed(seq))


def load_fasta(path: str) -> list:
    """
    Load sequences from a FASTA file. Returns list of non-empty ACGT-only
    sequences.  Raises ValueError if any sequence contains a character other
    than A, C, G, T (e.g. N).
    """
    sequences = []
    current = []
    with open(path) as f:
        for line in f:
            if line.startswith(">"):
                if current:
                    seq = "".join(current).strip().replace(" ", "")
                    if seq:
                        for c in seq:
                            if c not in ACGT:
                                raise ValueError(
                                    f"FASTA must contain only ACGT; found '{c}' in sequence"
                                )
                        sequences.append(seq)
                current = []
            else:
                current.append(line)
        if current:
            seq = "".join(current).strip().replace(" ", "")
            if seq:
                for c in seq:
                    if c not in ACGT:
                        raise ValueError(
                            f"FASTA must contain only ACGT; found '{c}' in sequence"
                        )
                sequences.append(seq)
    return sequences


def build_text(
    sequences: list, with_rc: bool = False, separators: bool = True
):
    """
    Build the concatenated text and optional boundaries.
    If separators=True: text = S1$S2$...$Sn (and optionally $ + RC block + $), no boundaries.
    If separators=False: text = S1+S2+...+Sn (no $), optionally + RC block; boundaries = cumulative segment ends.
    Returns (text, boundaries) where boundaries is None when separators=True.
    """
    if not sequences:
        return ("", None)
    if separators:
        forward = FASTA_SEP.join(sequences)
        if not with_rc:
            return (forward + FASTA_SEP, None)
        rc_seqs = [reverse_complement(s) for s in reversed(sequences)]
        rc_part = FASTA_SEP.join(rc_seqs)
        return (forward + FASTA_SEP + rc_part + FASTA_SEP, None)
    # No separators: raw concatenation and cumulative boundaries
    order = list(sequences)
    if with_rc:
        order = order + [reverse_complement(s) for s in reversed(sequences)]
    lengths = [len(seq) for seq in order]
    boundaries = []
    total = 0
    for L in lengths:
        total += L
        boundaries.append(total)
    text = "".join(order)
    return (text, boundaries)


def main():
    parser = argparse.ArgumentParser(
        description="Build SA, LCP, and BWT for threshold investigation."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default=None,
        metavar="STRING_OR_FILE",
        help="Input string, or path to .fa file (if omitted, use --string or --fasta)",
    )
    parser.add_argument(
        "--string",
        metavar="S",
        help="Input string (terminator # added if missing)",
    )
    parser.add_argument(
        "--fasta",
        metavar="FILE",
        help="Input FASTA file (ACGT only); sequences concatenated with $ by default",
    )
    parser.add_argument(
        "--with-rc",
        action="store_true",
        dest="with_rc",
        help="Include reverse-complement sequences (forward then RC in reverse order); only with --fasta",
    )
    parser.add_argument(
        "--separators",
        action="store_true",
        dest="separators",
        help="Use explicit $ between sequences (default: no separators, single # terminator only)",
    )
    parser.add_argument(
        "--no-truncate-lcp",
        action="store_true",
        dest="no_truncate_lcp",
        help="Do not truncate LCP at sequence boundaries (default: truncate when no separators)",
    )
    args = parser.parse_args()

    use_fasta, use_string = None, None
    if args.fasta is not None:
        use_fasta = args.fasta
    elif args.string is not None:
        use_string = args.string
    elif args.input is not None:
        if args.input.endswith(".fa"):
            use_fasta = args.input
        else:
            use_string = args.input
    else:
        parser.error("No input: provide a positional string/.fa path, or --string or --fasta")

    if use_string is not None:
        text = use_string
        boundaries = None
        if args.with_rc:
            parser.error("--with-rc is only valid with --fasta")
    else:
        sequences = load_fasta(use_fasta)
        if not sequences:
            print("Error: FASTA file contains no sequences", file=sys.stderr)
            sys.exit(1)
        text, boundaries = build_text(
            sequences, with_rc=args.with_rc, separators=args.separators
        )
        if not text:
            print("Error: no text to index", file=sys.stderr)
            sys.exit(1)
        if boundaries is not None and args.no_truncate_lcp:
            boundaries = None

    print('\t'.join(['id', 'len', 'off', 'c', 'lcp']))
    for run_id, run_offset, curr_char, run_lcp in lcp_bwt(text, boundaries=boundaries):
        print('\t'.join([str(run_id), str(len(run_lcp)), str(run_offset), curr_char, ','.join(map(str, run_lcp))]))


if __name__ == "__main__":
    main()
