#!/bin/bash
# Cross-tool, end-to-end reproducer for the TeraLCP threshold pipeline.
#
# This is NOT part of `make test` / run_threshold_tests.sh: it depends on external
# tools this repository does not own, so it cannot be a CI gate. It no-ops (exit 0
# with a SKIP message) when those tools are absent. When they are present, it
# demonstrates that a Movi index built from TeraLCP's output answers queries
# identically to the reference pfp-thresholds (NPTM) pipeline, across every major
# Movi query mode -- including the bidirectional ones.
#
# Movi query modes and what they exercise (see test/MOVI_QUERY_MODES.md):
#   --pml             pseudo-matching lengths   (backward search)
#   --count           count queries             (backward search)
#   --kmer  -k K      per-kmer found/positions  (BIDIRECTIONAL engine, sequitur)
#   --mem   -l L      maximal exact matches     (BIDIRECTIONAL engine, mem_finder)
# There is no standalone "bidirectional" query flag in Movi; --kmer and --mem are
# how the bidirectional move-structure search is reached from the CLI. Both need an
# ftab (built with --ftab-k) and the reverse complement present in the index.
#
# Two index-construction regimes are covered:
#   Claim set A (no separators): ropebwt3 -> TeraLCP -othresholds -> Movi index, vs a
#            Movi index built the usual way (`movi build`, which uses pfp-thresholds
#            internally). PML/k-mer/MEM outputs must match byte-for-byte.
#   Claim set B (separators, compressed-space byte-alphabet builder): grlBWT builds the
#            %-separated BWT -> grlbwt2rle -> grlbwt2teralcp adapter -> TeraLCP `-f rlbwt`
#            -othresholds -> Movi `--separators` index, vs a Movi `--separators` index
#            built the usual way. count/k-mer/MEM outputs must match. This is the path
#            ropeBWT3 cannot take (its alphabet has no room for '%').
#
# Required external tools (override via env var, else looked up on PATH):
#   MOVI         the `movi` launcher; its build dir must also contain
#                bin/movi-prepare-ref  (used to clean the reference the way Movi does)
#   GRLBWT_DIR   directory containing grlbwt-cli and grlbwt2rle   (Claim set B only)
#   python3      for generating query sets from the reference
# Repo tools (built by `make -C src/TeraLCP`): ropebwt3, src/TeraLCP/TeraLCP,
#   src/TeraLCP/tools/grlbwt2teralcp.
#
# Usage:  MOVI=/path/to/movi GRLBWT_DIR=/path/to/grlBWT/build \
#         bash test/validate_against_movi.sh [reference.fa]

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RB3="$REPO_ROOT/ropebwt3/ropebwt3"
TERALCP="$REPO_ROOT/src/TeraLCP/TeraLCP"
ADAPTER="$REPO_ROOT/src/TeraLCP/tools/grlbwt2teralcp"
REF="${1:-$REPO_ROOT/test/shred1_mini/minishred1_20_002.fa}"
FTABK="${FTABK:-5}"          # ftab kmer length; must be small enough for tiny refs
KMERK="${KMERK:-10}"         # length for --kmer queries
MEML="${MEML:-8}"            # min length for --mem queries
export OMP_NUM_THREADS=1

MOVI="${MOVI:-$(command -v movi || true)}"
PREPARE=""
[[ -n "$MOVI" ]] && PREPARE="$(dirname "$MOVI")/bin/movi-prepare-ref"
GRLBWT_DIR="${GRLBWT_DIR:-}"

skip=0
note() { echo "  - $1"; skip=1; }
[[ -x "$RB3" ]]      || note "ropebwt3 not built (run: make -C src/TeraLCP)"
[[ -x "$TERALCP" ]]  || note "TeraLCP not built (run: make -C src/TeraLCP)"
[[ -x "$ADAPTER" ]]  || note "grlbwt2teralcp not built (run: make -C src/TeraLCP tools)"
[[ -n "$MOVI" && -x "$MOVI" ]] || note "movi launcher not found (set MOVI=/path/to/movi)"
[[ -n "$PREPARE" && -x "$PREPARE" ]] || note "movi-prepare-ref not found next to movi"
command -v python3 >/dev/null 2>&1 || note "python3 not found"
[[ -f "$REF" ]]      || note "reference FASTA not found: $REF"
if (( skip )); then
    echo "SKIP validate_against_movi.sh: missing prerequisites (see above)."
    exit 0
fi

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fails=0
echo "Reference: $REF"
echo "Workdir:   $W"
echo "Params:    ftab-k=$FTABK kmer-k=$KMERK mem-l=$MEML"

# Query sets derived from the reference (no external data needed).
python3 - "$REF" "$W" "$KMERK" <<'PY'
import sys, random
ref, W, kk = sys.argv[1], sys.argv[2], int(sys.argv[3])
seqs, cur = [], []
for line in open(ref):
    if line.startswith('>'):
        if cur: seqs.append(''.join(cur)); cur=[]
    else: cur.append(line.strip())
if cur: seqs.append(''.join(cur))
seqs = [s for s in seqs if len(s) >= 120] or seqs
random.seed(1)
with open(f"{W}/reads.fa", "w") as f:       # longer reads for PML / MEM
    for i in range(20):
        s = random.choice(seqs); L = min(100, len(s)); p = random.randint(0, len(s)-L)
        f.write(f">r{i}\n{s[p:p+L]}\n")
with open(f"{W}/kmers.fa", "w") as f:        # short k-mers for count / kmer
    for i in range(20):
        s = random.choice(seqs); k = max(kk, 6);
        if len(s) < k: continue
        p = random.randint(0, len(s)-k)
        f.write(f">k{i}\n{s[p:p+k]}\n")
PY

# ---------------------------------------------------------------------------
# Per-mode comparison helpers. Each diffs a Tera-built index against an
# NPTM-built index and bumps $fails on mismatch.
# ---------------------------------------------------------------------------

# diff_stdout NAME NPTM_IDX TERA_IDX QUERYFILE [movi query flags...]
# For modes whose results go to --stdout (count, kmer, mem). Sorted set-compare.
diff_stdout() {
    local name="$1" a="$2" b="$3" rf="$4"; shift 4
    "$MOVI" query "$@" -i "$a" -r "$rf" --stdout 2>/dev/null | sort > "$W/$name.nptm"
    "$MOVI" query "$@" -i "$b" -r "$rf" --stdout 2>/dev/null | sort > "$W/$name.tera"
    if cmp -s "$W/$name.nptm" "$W/$name.tera"; then
        echo "  PASS: $name identical ($(wc -l <"$W/$name.nptm") lines)"
    else
        echo "  FAIL: $name differs"; fails=$((fails+1))
    fi
}

# diff_pml NAME NPTM_IDX TERA_IDX QUERYFILE
# PML output is a binary .pml.bpf file written via -o.
diff_pml() {
    local name="$1" a="$2" b="$3" rf="$4"
    "$MOVI" query --pml -i "$a" -r "$rf" -o "$W/$name.nptm" >/dev/null 2>&1
    "$MOVI" query --pml -i "$b" -r "$rf" -o "$W/$name.tera" >/dev/null 2>&1
    if cmp -s "$W/$name.nptm.pml.bpf" "$W/$name.tera.pml.bpf"; then
        echo "  PASS: $name PMLs byte-identical"
    else
        echo "  FAIL: $name PML output differs"; fails=$((fails+1))
    fi
}

# Run every query mode that applies to a built index pair.
# compare_all_modes LABEL NPTM_IDX TERA_IDX
compare_all_modes() {
    local label="$1" a="$2" b="$3"
    diff_pml    "${label}_pml"  "$a" "$b" "$W/reads.fa"
    diff_stdout "${label}_kmer" "$a" "$b" "$W/kmers.fa" --kmer -k "$KMERK"
    diff_stdout "${label}_mem"  "$a" "$b" "$W/reads.fa" --mem  -l "$MEML" --ftab-k "$FTABK"
}

# ---------------------------------------------------------------------------
# Claim set A: no separators (ropebwt3). PML + k-mer + MEM.
# ---------------------------------------------------------------------------
echo "== Claim set A: no-separator (ropebwt3 -> TeraLCP -> Movi vs NPTM) =="
"$MOVI" build --fasta "$REF" --index "$W/nptm" --type regular-thresholds \
    --ftab-k "$FTABK" >/dev/null 2>&1
"$PREPARE" "$REF" "$W/clean.fa" >/dev/null 2>&1
# pfp concatenates the cleaned records (fwd+revcomp) into one string with a single
# sentinel; feed ropebwt3 the same single concatenated record so the BWTs agree.
{ echo ">cat"; grep -v '^>' "$W/clean.fa" | tr -d '\n'; echo; } > "$W/single.fa"
"$RB3" build -R -d -o "$W/single.fmd" "$W/single.fa" 2>/dev/null
"$TERALCP" -f fmd -i "$W/single.fmd" -t "$W/t" -othresholds "$W/tera" -v quiet 2>/dev/null
mkdir -p "$W/teraidx"
cp "$W/single.fa"      "$W/teraidx/ref.fa"
cp "$W/tera.bwt.heads" "$W/teraidx/ref.fa.bwt.heads"
cp "$W/tera.bwt.len"   "$W/teraidx/ref.fa.bwt.len"
cp "$W/tera.thr_pos"   "$W/teraidx/ref.fa.thr_pos"
[[ -f "$W/tera.thr" ]] && cp "$W/tera.thr" "$W/teraidx/ref.fa.thr"
"$MOVI" build --preprocessed --skip-prepare --skip-pfp --type regular-thresholds \
    --ftab-k "$FTABK" --fasta "$W/teraidx/ref.fa" --index "$W/teraidx" >/dev/null 2>&1
compare_all_modes A "$W/nptm" "$W/teraidx"

# ---------------------------------------------------------------------------
# Claim set B: separators via grlBWT (compressed-space). count + k-mer + MEM.
# ---------------------------------------------------------------------------
if [[ -n "$GRLBWT_DIR" && -x "$GRLBWT_DIR/grlbwt-cli" && -x "$GRLBWT_DIR/grlbwt2rle" ]]; then
    echo "== Claim set B: separators (grlBWT -> adapter -> TeraLCP -f rlbwt -> Movi --separators vs NPTM) =="
    "$MOVI" build --separators --fasta "$REF" --index "$W/sep_nptm" \
        --type regular-thresholds --ftab-k "$FTABK" >/dev/null 2>&1
    "$PREPARE" "$REF" "$W/sep_clean.fa" separators >/dev/null 2>&1
    # one string of %-terminated sequences; grlBWT uses the smallest byte (the
    # trailing newline) as its sentinel -- which ranks like pfp's '$'.
    { grep -v '^>' "$W/sep_clean.fa" | tr -d '\n'; echo; } > "$W/grl_in.txt"
    "$GRLBWT_DIR/grlbwt-cli"  "$W/grl_in.txt" -o "$W/grl_out" >/dev/null 2>&1
    "$GRLBWT_DIR/grlbwt2rle"  "$W/grl_out.rl_bwt" "$W/grl_rle" >/dev/null 2>&1
    # Adapter: widen .len 4->5 and copy heads. Default form feeds TeraLCP -f rlbwt
    # (which remaps heads by ascending byte rank, so the sentinel needs no change).
    "$ADAPTER" "$W/grl_rle" "$W/grl" -q
    "$TERALCP" -f rlbwt -i "$W/grl" -t "$W/t" -othresholds "$W/septera" -v quiet 2>/dev/null
    mkdir -p "$W/sep_teraidx"
    # For the Movi build the end marker must be byte 0; --movi-sentinel remaps the
    # smallest head byte (grlBWT's newline terminator) to 0x00.
    "$ADAPTER" "$W/grl_rle" "$W/sep_teraidx/ref.fa" --movi-sentinel -q
    cp "$W/septera.thr_pos"  "$W/sep_teraidx/ref.fa.thr_pos"
    [[ -f "$W/septera.thr" ]] && cp "$W/septera.thr" "$W/sep_teraidx/ref.fa.thr"
    cp "$W/sep_clean.fa"     "$W/sep_teraidx/ref.fa"
    "$MOVI" build --separators --preprocessed --skip-prepare --skip-pfp \
        --type regular-thresholds --ftab-k "$FTABK" \
        --fasta "$W/sep_teraidx/ref.fa" --index "$W/sep_teraidx" >/dev/null 2>&1
    diff_stdout B_count "$W/sep_nptm" "$W/sep_teraidx" "$W/kmers.fa" --count
    diff_stdout B_kmer  "$W/sep_nptm" "$W/sep_teraidx" "$W/kmers.fa" --kmer -k "$KMERK"
    diff_stdout B_mem   "$W/sep_nptm" "$W/sep_teraidx" "$W/reads.fa" --mem -l "$MEML" --ftab-k "$FTABK"
else
    echo "== Claim set B: SKIP (set GRLBWT_DIR to a grlBWT build dir to run the separator path) =="
fi

if (( fails )); then echo "$fails cross-tool check(s) FAILED"; exit 1; fi
echo "All cross-tool checks passed."
