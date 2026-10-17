# TeraLCP `-ophi` file format (TLPHI v1)

`TeraLCP -ophi FILE` writes, for every BWT run, the text positions of its top
and bottom rows and the LCP value at its top row. These are the suffix array
samples and irreducible PLCP samples from which a reader builds phi and
phi_inverse as move structures over text positions, with an integrated PLCP
column, in O(r) space and without walking LF over all n rows. Orbit-tms
(`ms tms-build --phi FILE`) is the intended reader.

## Text and coordinates

Positions are in the text TeraLCP indexes, which is the text whose positions
TeraMS reports. For `-f fmd` input (ropebwt3 FMD, built with or without `-d`)
the text is

```
T = S_0 $_0 S_1 $_1 ... S_{N-1} $_{N-1}
```

where `S_0, S_1, ...` are ropebwt3's sequences in its id order (with `-d`: each
input record followed by its reverse complement), `n = |T|`, and the separators
`$_i` are distinct symbols with `$_i < $_j` for `i < j`, all smaller than every
base. Sequence `S_k` starts at position `sum over j < k of (|S_j| + 1)`. For
`-f rlbwt` input with one sentinel, `T` is the text of the heads/len files and
the sentinel is at position `n - 1`.

`SA[k]` is the starting position of the `k`-th smallest suffix of `T`, and
`LCP[k]` (for `k >= 1`) the length of the longest common prefix of the suffixes
at rows `k - 1` and `k`; a common prefix never extends over a separator.
`LCP[0] = 0`. In the BWT, `BWT[k] = T[SA[k] - 1]`, cyclically.

## Records

Records follow the BWT's maximal runs in row order (the numbering of
`-ominima` and of fmd2rlbwt's heads/len files), except that **every separator
row is its own record**: a maximal block of rows with equal non-separator BWT
symbols is one record (even when the FMD stores it as several rld entries),
and a maximal block of `l` rows whose BWT symbol is a separator is `l`
records. So the record count is the number of maximal runs (the numbering of
`-ominima` and of an FMD run dump, where a separator run is one line) plus, for
each separator run of length `l`, `l - 1`. A reader holding the maximal runs
consumes `l` records for a separator run of length `l` and one record for any
other run.

Record `i`, for the run with rows `s_i .. e_i`, holds three fields:

| field | value |
|-------|-------|
| `head` | `SA[s_i]`, the text position of the run's top row |
| `tail` | `SA[e_i]`, the text position of the run's bottom row |
| `top`  | `LCP[s_i]` (0 for the first record) |

Splitting separator runs makes every separator row a run head. That is what
phi needs: phi maps `SA[k]` to `SA[k - 1]`, and on the text positions it is a
shift on intervals that start at `SA[s_i]` for the run heads `s_i` of this
numbering, with `PLCP[SA[s_i] + o] = top_i - o` inside the interval starting
at `SA[s_i]`. With a separator run kept whole, `T[p - 1]` could be a separator
inside an interval, where the LCP does not drop by one.

From the records, with `R` records and indices taken cyclically:

* phi: intervals start at `head_i`, the interval starting at `head_i` maps to
  `tail_{i-1}` (`tail_{R-1}` for `i = 0`, that is `SA[0]` maps to `SA[n-1]`),
  and its PLCP sample is `top_i`;
* phi_inverse: intervals start at `tail_i`, the interval starting at `tail_i`
  maps to `head_{i+1}` (`head_0` for `i = R - 1`), and its sample, the LCP of
  the row with the row below, is `top_{i+1}` (0 for `i = R - 1`).

Each list of starts is a permutation of the interval starts of its structure;
sort by start to build it. Position 0 is always a start of both, since the row
of position 0 has a separator in the BWT.

## Layout

All integers are unsigned little-endian. Header, 48 bytes:

| bytes  | field |
|--------|-------|
| 0..7   | magic `93 54 4C 50 48 49 00 01` (`0x93 'T' 'L' 'P' 'H' 'I' 0x00`, then version 1) |
| 8      | flags: bit 0, integers are little-endian (always set) |
| 9      | `w`, bytes per field: the fewest bytes that hold `n` |
| 10..15 | reserved, 0 |
| 16..23 | `R`, the number of records |
| 24..31 | `n`, the text length |
| 32..39 | the number of maximal runs (separator runs counted once) |
| 40..47 | reserved, 0 |

Then `R` records of `3 * w` bytes: `head`, `tail`, `top`, each `w` bytes. The
file is exactly `48 + 3 * w * R` bytes. For `n < 2^40`, `w = 5`; for the full
HPRC2 FMD (`n` about `2.84e12`), `w = 6`, or 18 bytes per record.

## Production

`-ophi` is written by the per-run pass that also writes `-ominima`, from the
same spill and bucket files (see MS_MINIMA_FORMAT.md, Resources): the pass
walks phi through each run from its bottom row to its top row, which visits
`SA[e_i]` first and `SA[s_i]` last, together with the LCP at every row. Run it
in the same TeraLCP invocation as `-oindex` and `-ominima`.

## Tools

* `src/TeraLCP/phi_export_dump.py FILE [--summary]` prints the header and one
  line per record: `record<TAB>head<TAB>tail<TAB>top`.
* `src/TeraLCP/testing/fmd_outputs_brute.py FASTA --phi FILE` checks the file
  against suffix sorting of the text built from the FMD's FASTA.
