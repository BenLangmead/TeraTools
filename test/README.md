# TeraLCP threshold tests

Self-contained checks for TeraLCP's Movi-compatible threshold output
(`-othresholds`). They need only tools this repository builds — ropebwt3 and
`src/TeraLCP/TeraLCP` — and no external dependencies at run time.

Run from the repo root:

```
make -C src/TeraLCP        # builds TeraLCP (and ropebwt3)
bash test/run_threshold_tests.sh
# or: make -C src/TeraLCP test-thresholds
```

## What is checked

For each case the runner builds the FMD with `ropebwt3 build -R -d` and then:

1. **Correctness vs an independent reference.** TeraLCP's `.thr`/`.thr_pos` must
   match the committed goldens, which were produced **by pfp-thresholds** (the
   reference MONI-family implementation), not by TeraLCP. Because `ropebwt3 build
   -R -d` produces the same BWT pfp built for these inputs, an exact byte match is
   expected.
2. **Path agreement.** The fast parallel path (default) and the non-destructive
   phi-walk path (used when `-orlcp` is also requested) must produce identical
   `.thr`/`.thr_pos`.
3. **`-f rlbwt` round-trip.** Feeding TeraLCP's own `.bwt.heads`/`.bwt.len` back
   through the generic run-length-BWT input must reproduce the `.thr`/`.thr_pos`.

## Cases / fixtures

Each `<case>/` directory holds the input FASTA and the pfp-thresholds goldens:

| file | meaning |
|------|---------|
| `<name>.fa` | input sequence(s) |
| `<name>.fa.thr` | golden threshold values (5-byte LE per BWT run), from pfp-thresholds |
| `<name>.fa.thr_pos` | golden threshold positions (5-byte LE per BWT run), from pfp-thresholds |

- `single_string` — a single short sequence.
- `gattacat` — small repetitive sequence (117 runs).
- `shred1_mini` — shredded reads (~14.9k runs), a larger non-trivial case.

## Broader validation (cross-tool reproducers)

Beyond these dependency-free checks, two guarded reproducers validate the threshold
output and `-f rlbwt` ingest end-to-end against external tools. They are **not** part
of `make test`: they depend on tools this repo does not own (Movi, grlBWT), so they
SKIP (exit 0) when those are absent. Set `MOVI=/path/to/movi` and, for the separator
path, `GRLBWT_DIR=/path/to/grlBWT/build`.

```
MOVI=… GRLBWT_DIR=… bash test/validate_against_movi.sh        # all query modes
MOVI=… GRLBWT_DIR=… bash test/corner/run_corner_tests.sh      # separator corner cases
```

- **`test/validate_against_movi.sh`** builds a Movi index from TeraLCP's output and
  diffs every major Movi query mode against a stock pfp/NPTM index, in two regimes:
  no-separator (ropeBWT3) and separator (grlBWT). Modes covered: `--pml`, `--count`,
  `--kmer`, and `--mem`. The last two reach Movi's **bidirectional** move-structure
  search (there is no standalone bidirectional flag — see
  [`MOVI_QUERY_MODES.md`](MOVI_QUERY_MODES.md)). The grlBWT path uses the
  `grlbwt2teralcp` adapter (built by `make -C src/TeraLCP tools`).
- **`test/corner/run_corner_tests.sh`** drives small adversarial fixtures that the
  main reproducer cannot reach (boundary-spanning queries, identical records, sub-k
  records, N-runs), confirming Tera-built == NPTM for each. These exercise correct
  separator/terminator handling: a boundary-spanning match must not cross a separator.
