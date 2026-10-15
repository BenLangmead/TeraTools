# TeraLCP `-ominima` file format (TLMSM v1)

`TeraLCP -ominima FILE` writes, for every BWT run, the LCP information the `ms`
matching-statistics index needs: the LCP value at the run's top row and the
run's interior prefix and suffix minima.

## Definitions

`LCP[k]` is the length of the longest common prefix of the suffixes at BWT rows
`k-1` and `k`, exactly as TeraLCP computes it: extension stops only at the
end-of-sequence symbol (code 0, the sentinel), and any other symbol, including
separators such as `%`, is an ordinary character. `LCP[0] = 0`.

For run `i` with rows `s_i .. s_i + L_i - 1`:

* `top_i = LCP[s_i]` (0 for the first run);
* `top_{i+1}` is the next run's top, and `+infinity` for the last run;
* an interior offset `o` (`1 <= o < L_i`) with value `v = LCP[s_i + o]` is a
  **prefix minimum** if `v < top_i` and `v` is strictly below every interior
  value at a smaller offset;
* it is a **suffix minimum** if `v < top_{i+1}` and `v` is strictly below
  every interior value at a larger offset.

The stored set of run `i` is the union of its prefix and suffix minima, in
increasing offset order, each offset once. The run minimum equals
`min(top_i, stored values)`, so it is not stored separately.

## Layout

All fixed-width integers are unsigned little-endian. Variable-length integers
are ULEB128 (7 bits per byte, low bits first, high bit set on every byte but
the last).

Header, 48 bytes:

| bytes  | field |
|--------|-------|
| 0..7   | magic `93 54 4C 4D 53 4D 00 01` (`0x93 'T' 'L' 'M' 'S' 'M' 0x00`, then version 1) |
| 8      | flags (see below) |
| 9..15  | reserved, 0 |
| 16..23 | `r`, number of runs (records) |
| 24..31 | `n`, total BWT length |
| 32..39 | total number of stored (offset, value) pairs over all runs |
| 40..47 | `input_runs`, the number of maximal runs of the input BWT, or 0 if unknown |

Flags:

* bit 0: header integers are little-endian (always set);
* bit 1: `input_runs` is filled in;
* bit 2: the records follow TeraLCP's internal runs, in which every separator
  is its own run, rather than the input's runs (only for `-f lcp_index` input
  given neither `--fmd` nor `--rlbwt-meta`; see below).

Then `r` records, one per BWT run in BWT order (run 0 holds row 0):

```
ULEB128 top_i
ULEB128 count
count times:
    ULEB128 offset gap   (offset minus the previous stored offset; the first gap is from 0)
    ULEB128 value
```

Offsets are in-run offsets (0 is the run's top row), so the first gap is at
least 1 and every later gap is at least 1. There is no padding and no trailer;
the file ends right after record `r - 1`.

## Run numbering

TeraLCP numbers runs internally as its input decodes them, except that every
separator (code 0) is its own run of length 1, even where several separators
are adjacent in the BWT. The records of this file follow the input's runs
instead:

* `-f fmd FILE`: record `i` describes the `i`-th **maximal run** of the BWT in
  row order: a maximal block of rows with equal BWT symbols, where all
  separators count as one symbol. A run of `l > 1` separators is therefore one
  record of length `l`, whose interior LCP values are the LCP values at its rows
  after the first (the tops of TeraLCP's split runs). Adjacent rld entries with
  the same symbol, which TeraLCP holds as separate runs, are likewise one
  record. This is the numbering of the `.bwt.heads`/`.bwt.len` files that
  fmd2rlbwt writes for Orbit (one line per maximal run, a separator run written
  as one `$` head byte; see Orbit's `src/ms/tools/fmd2rlbwt/FMD_RUNS.md`), so
  Orbit-ms reads record `i` for its run `i`. `input_runs = r`, and flag bit 2
  is clear. A merged run's stored values are found among its pieces' stored
  values and the tops of its pieces after the first: a prefix (suffix) minimum
  of the merged run inside a piece is also one of that piece, relative to the
  piece's own top (to the next piece's top).
* `-f rlbwt BASE`: record `i` describes line `i` of `BASE.bwt.heads`. TeraLCP
  requires that no two adjacent non-sentinel runs share a head, that every
  sentinel run has length 1 and that no run is empty, and exits with an error
  before construction otherwise, so a successful run always has
  `r == input_runs`. (The sentinel is the smallest head byte present.) For a
  text with one sentinel this is again the maximal-run numbering. Heads/len
  files written by TeraLCP itself (`-othresholds`) follow this convention.
* `-f lcp_index FILE`: with `--fmd FMD` (the FMD the index was built from) the
  records follow the FMD's maximal runs as for `-f fmd`; with
  `--rlbwt-meta BASE` they follow `BASE.bwt.heads` as for `-f rlbwt`; with
  neither they follow TeraLCP's internal runs, `input_runs` is 0 and flag bit 2
  is set.

LCP values are those of the text TeraLCP indexes, in which separators are
distinct symbols, so a common prefix never extends over a separator, whatever
symbol a run dump writes for it.

## Interaction with other outputs

`-ominima` is computed inside the same per-run pass as `-orlcp` and the fast
`-othresholds` path, so asking for several of them costs one pass:

* with `-othresholds` and neither `-orlcp` nor `-oindex`: the minima are
  produced by the destructive parallel thresholds pass;
* with `-orlcp`: one pass writes both files;
* with `-oindex`: the index is written before the pass, so the pass can free
  it as it goes.

`-ophi` (src/TeraLCP/PHI_EXPORT_FORMAT.md) comes from the same pass and the same
spill and bucket files: requesting both outputs costs one pass and one reorder.

## Resources

The per-run pass appends records to one spill file per thread
(`FILE.tmp.t<i>`, next to the `-ominima` file, or next to the `-ophi` file when
only that is requested), keyed by the Phi-interval index that produced them. The
serial chain walk that orders runs then turns an existing packed per-run array
(`r * ceil(log2 r)` bits) into the map from Phi interval to run number, so no
additional run-sized array is allocated. The records are distributed into at
most 128 bucket files (`FILE.tmp.b<j>`) by run-number range, and each bucket is
sorted in memory (its bytes plus 8 bytes per run) and appended to `FILE`. The
bucket count is chosen to keep that below `--minima-bucket-mb` (default
2048 MiB). Spill files are deleted as they are distributed and buckets as they
are written, so temporary disk peaks at about twice the final file size. All
temporary files are removed on success.

## Tools

* `src/TeraLCP/ms_minima_dump.py FILE [--summary]` prints the header and one
  line per run: `run<TAB>top<TAB>count<TAB>off:val,off:val,...`.
* `src/TeraLCP/testing/ms_minima_check.cpp` recomputes the expected records
  from `BASE.bwt.heads`/`BASE.bwt.len` by BWT inversion and compares (pass
  `--maximal` for an FMD's heads/len as `-othresholds` writes them).
* `src/TeraLCP/testing/fmd_outputs_brute.py FASTA --minima FILE --phi FILE`
  builds the text of an FMD from the FASTA it was built from, sorts its
  suffixes and compares both outputs.
* `src/TeraLCP/testing/ms_minima_brute.py` builds a BWT and the expected records
  from a text by sorting rotations; `ms_minima_tsv.py` derives them from a
  per-run LCP table.
