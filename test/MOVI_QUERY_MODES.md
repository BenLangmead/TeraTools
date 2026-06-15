# Movi query modes — interface notes for TeraLCP validation

Findings from inspecting `movi query --help-all` and the Movi sources on
devlangmead1 (`~/git/movi-langmead`), validated by running each mode on the
`shred1_mini` reference. These drive which modes the cross-tool reproducer must
diff and how to build/invoke each. **Key result: there is no standalone
"bidirectional" query mode — bidirectional search is the internal engine behind
`--kmer`/`--kmer-count` and `--mem`, so exercising those two modes is how we test
bidirectional end-to-end.** (This resolves the "bidirectional NOT yet exercised"
caveat in `PR_HANDOFF.md`.)

## Mode matrix

| Mode | Invocation (query) | Output | Bidirectional? | Build/query requirements |
|------|--------------------|--------|----------------|--------------------------|
| PML  | `--pml` (default), `-o PFX` | `PFX.pml.bpf` (binary) | no (backward only) | thresholds index |
| ZML  | `--zml` | matching lengths | no | thresholds index |
| count | `--count --stdout` | per-read text | no | `--separators` build for cross-record counts |
| **k-mer** | `--kmer -k K --stdout` | per-read `name<TAB>found/total<TAB>pos:cnt …` | **yes** (`sequitur.cpp::query_kmers_from_bidirectional`) | ftab (`--ftab-k K` at build); RC present |
| k-mer count | `--kmer-count -k K` | **aggregate stats only** (no per-read stdout) | yes | ftab |
| **MEM** | `--mem -l L --ftab-k K --stdout` | per-read `name<TAB>start<TAB>end<TAB>val` | **yes** (`mem_finder.cpp` → `initialize_bidirectional_search`) | ftab at **both build and query**; RC present; prefetching auto-disabled |

Source anchors (Movi):
- `src/move_structure_search.cpp` — `extend_bidirectional`, `backward_search_bidirectional`,
  `initialize_bidirectional_search` (throws if the reverse complement is absent, ~line 255).
- `src/sequitur.cpp` — `query_kmers_from_bidirectional` (k-mer engine).
- `src/mem_finder.cpp` — MEM finder, calls `initialize_bidirectional_search`.
- `src/movi.cpp` — `handle_kmer` skips per-read output when `--kmer-count` is set;
  `handle_mem` → `output_mems`.

## Gotchas that affect the reproducer

1. **`--mem` requires `--ftab-k K` at query time**, not just at build. Without it:
   `[ERROR] MEM finding requires ftab`. So build with `--ftab-k K` and pass the same
   `--ftab-k K` to the `--mem` query.
2. **`--kmer-count` has no per-read stdout** — only an aggregate summary. For a
   strong per-read byte-diff, use `--kmer` (not `--kmer-count`).
3. **Reverse complement must be present** for bidirectional modes. Movi's
   `prepare_ref` adds the RC; the preprocessed Tera path must preserve the same
   fwd+RC content the NPTM path uses, or bidirectional init throws / diverges.
4. **MEM prefetching is auto-disabled** (harmless warning); output is deterministic.
5. Confirmed deterministic per-read output for `--kmer` and `--mem` on `shred1_mini`,
   e.g. `--mem -l 8 --ftab-k 5` → `m0  0  40  19` / `m0  49  90  19`.

## N / non-ACGT handling (relevant to commit 2a49fd0)

**Reference-side N.** `movi-prepare-ref` **substitutes N → A before the BWT is built**
(observed: a run of 8 N's becomes `AAAAAAAA`). The prepared alphabet is just
`%,A,C,G,T` and the `.bwt.heads` carry bytes `{0, '%'(37), A, C, G, T}` — no N (78).
So N never reaches TeraLCP on the Movi path, and the removed DNA-N special case in
TeraLCP's LCP computation is moot here. Both NPTM and Tera pipelines apply the same
substitution, so N in the input FASTA flows through identically. (Caveat for users:
the N→A mapping is silent and can create spurious poly-A matches; it is a Movi
behavior, not something our threshold work introduces or can change.)

**Read-side N.** Verified per mode against an index with N-containing reads (clean /
N-in-middle / all-N):
- `--pml`, `--count`, `--mem`: **graceful** — all reads processed; matching resets or
  splits around the N (e.g. `--mem` reports two MEMs flanking the N run).
- `--kmer` / `--kmer-count`: **silently emit no output for the whole read file** (and
  print no "reads processed" success line) when any read contains N, unless
  `--ignore-illegal-chars {1=>A, 2=>random}` is passed. This is the only mode with an
  N cliff; with `--ignore-illegal-chars 1` it processes normally. Keep cross-tool
  k-mer query sets pure-ACGT, and see the user-facing caveat below.

## Implication for the validation plan

- Add a **k-mer claim** (`--kmer -k K --stdout`) and a **MEM claim**
  (`--mem -l L --ftab-k K --stdout`) to `test/validate_against_movi.sh`, diffing
  Tera-built vs stock-NPTM-built indexes. Both exercise the bidirectional engine.
- Build both indexes with a fixed `--ftab-k` and confirm RC handling is identical.
