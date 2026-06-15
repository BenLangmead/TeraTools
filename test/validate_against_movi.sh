#!/bin/bash
# Cross-tool, end-to-end reproducer for the TeraLCP threshold pipeline.
#
# This is NOT part of `make test` / run_threshold_tests.sh: it depends on external
# tools this repository does not own, so it cannot be a CI gate. It no-ops (exit 0
# with a SKIP message) when those tools are absent. When they are present, it
# demonstrates that a Movi index built from TeraLCP's output answers queries
# identically to the reference pfp-thresholds (NPTM) pipeline, in two regimes:
#
#   Claim 1 (no separators): ropebwt3 -> TeraLCP -othresholds -> Movi index, and
#            `movi query --pml` is byte-identical to a Movi index built the usual
#            way (`movi build`, which uses pfp-thresholds internally).
#
#   Claim 2 (separators, via a compressed-space byte-alphabet builder): grlBWT
#            builds the %-separated BWT -> grlbwt2rle -> TeraLCP `-f rlbwt`
#            -othresholds -> Movi `--separators` index, and `movi query --count`
#            matches a Movi `--separators` index built the usual way. This is the
#            path ropeBWT3 cannot take (its alphabet has no room for '%').
#
# Required external tools (override via env var, else looked up on PATH):
#   MOVI         the `movi` launcher; its build dir must also contain
#                bin/movi-prepare-ref  (used to clean the reference the way Movi does)
#   GRLBWT_DIR   directory containing grlbwt-cli and grlbwt2rle   (Claim 2 only)
#   python3      for small byte-level format conversions
# Repo tools (built by `make -C src/TeraLCP`): ropebwt3, src/TeraLCP/TeraLCP.
#
# Usage:  MOVI=/path/to/movi GRLBWT_DIR=/path/to/grlBWT/build \
#         bash test/validate_against_movi.sh [reference.fa]

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RB3="$REPO_ROOT/ropebwt3/ropebwt3"
TERALCP="$REPO_ROOT/src/TeraLCP/TeraLCP"
REF="${1:-$REPO_ROOT/test/shred1_mini/minishred1_20_002.fa}"
export OMP_NUM_THREADS=1

MOVI="${MOVI:-$(command -v movi || true)}"
PREPARE=""
[[ -n "$MOVI" ]] && PREPARE="$(dirname "$MOVI")/bin/movi-prepare-ref"
GRLBWT_DIR="${GRLBWT_DIR:-}"

skip=0
note() { echo "  - $1"; skip=1; }
[[ -x "$RB3" ]]      || note "ropebwt3 not built (run: make -C src/TeraLCP)"
[[ -x "$TERALCP" ]]  || note "TeraLCP not built (run: make -C src/TeraLCP)"
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

# Query sets derived from the reference (no external data needed).
python3 - "$REF" "$W" <<'PY'
import sys, random
ref, W = sys.argv[1], sys.argv[2]
seqs, cur = [], []
for line in open(ref):
    if line.startswith('>'):
        if cur: seqs.append(''.join(cur)); cur=[]
    else: cur.append(line.strip())
if cur: seqs.append(''.join(cur))
seqs = [s for s in seqs if len(s) >= 120] or seqs
random.seed(1)
with open(f"{W}/reads.fa", "w") as f:       # longer reads for PML
    for i in range(20):
        s = random.choice(seqs); L = min(100, len(s)); p = random.randint(0, len(s)-L)
        f.write(f">r{i}\n{s[p:p+L]}\n")
with open(f"{W}/kmers.fa", "w") as f:        # short k-mers for count
    for i in range(20):
        s = random.choice(seqs); k = random.choice([6,7,8,10,12]); p = random.randint(0, len(s)-k)
        f.write(f">k{i}\n{s[p:p+k]}\n")
PY

# ---------------------------------------------------------------------------
# Claim 1: no separators, PML query
# ---------------------------------------------------------------------------
echo "== Claim 1: no-separator PML (ropebwt3 -> TeraLCP -> Movi vs NPTM) =="
"$MOVI" build --fasta "$REF" --index "$W/nptm" --type regular-thresholds >/dev/null 2>&1
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
"$MOVI" build --preprocessed --skip-prepare --skip-pfp --type regular-thresholds \
    --fasta "$W/teraidx/ref.fa" --index "$W/teraidx" >/dev/null 2>&1
"$MOVI" query --pml -i "$W/nptm"    -r "$W/reads.fa" -o "$W/nptm_pml"  >/dev/null 2>&1
"$MOVI" query --pml -i "$W/teraidx" -r "$W/reads.fa" -o "$W/tera_pml"  >/dev/null 2>&1
if cmp -s "$W/nptm_pml.pml.bpf" "$W/tera_pml.pml.bpf"; then
    echo "  PASS: Tera-built Movi PMLs byte-identical to NPTM"
else
    echo "  FAIL: PML output differs"; fails=$((fails+1))
fi

# ---------------------------------------------------------------------------
# Claim 2: separators via grlBWT (compressed-space), count query
# ---------------------------------------------------------------------------
if [[ -n "$GRLBWT_DIR" && -x "$GRLBWT_DIR/grlbwt-cli" && -x "$GRLBWT_DIR/grlbwt2rle" ]]; then
    echo "== Claim 2: separator count (grlBWT -> TeraLCP -f rlbwt -> Movi --separators vs NPTM) =="
    "$MOVI" build --separators --fasta "$REF" --index "$W/sep_nptm" --type regular-thresholds >/dev/null 2>&1
    "$PREPARE" "$REF" "$W/sep_clean.fa" separators >/dev/null 2>&1
    # one string of %-terminated sequences; grlBWT uses the smallest byte (the
    # trailing newline) as its sentinel -- which ranks like pfp's '$'.
    { grep -v '^>' "$W/sep_clean.fa" | tr -d '\n'; echo; } > "$W/grl_in.txt"
    "$GRLBWT_DIR/grlbwt-cli"  "$W/grl_in.txt" -o "$W/grl_out" >/dev/null 2>&1
    "$GRLBWT_DIR/grlbwt2rle"  "$W/grl_out.rl_bwt" "$W/grl_rle" >/dev/null 2>&1
    # grlbwt2rle: .syms = 1 byte/run heads; .len = 4 bytes/run. TeraLCP wants
    # .bwt.heads + .bwt.len with 5-byte lengths. -f rlbwt remaps heads by ascending
    # byte rank, so grlBWT's newline sentinel needs no change for TeraLCP.
    python3 - "$W" <<'PY'
import sys; W=sys.argv[1]
open(f"{W}/grl.bwt.heads","wb").write(open(f"{W}/grl_rle.syms","rb").read())
d=open(f"{W}/grl_rle.len","rb").read(); out=bytearray()
for i in range(len(d)//4):
    out += int.from_bytes(d[i*4:i*4+4],"little").to_bytes(5,"little")
open(f"{W}/grl.bwt.len","wb").write(out)
PY
    "$TERALCP" -f rlbwt -i "$W/grl" -t "$W/t" -othresholds "$W/septera" -v quiet 2>/dev/null
    mkdir -p "$W/sep_teraidx"
    # For the Movi build, the end marker must be byte 0; grlBWT used newline (10).
    python3 - "$W" <<'PY'
import sys; W=sys.argv[1]
h=open(f"{W}/grl.bwt.heads","rb").read().replace(b"\x0a", b"\x00")
open(f"{W}/sep_teraidx/ref.fa.bwt.heads","wb").write(h)
PY
    cp "$W/grl.bwt.len"      "$W/sep_teraidx/ref.fa.bwt.len"
    cp "$W/septera.thr_pos"  "$W/sep_teraidx/ref.fa.thr_pos"
    cp "$W/septera.thr"      "$W/sep_teraidx/ref.fa.thr"
    cp "$W/sep_clean.fa"     "$W/sep_teraidx/ref.fa"
    "$MOVI" build --separators --preprocessed --skip-prepare --skip-pfp \
        --type regular-thresholds --fasta "$W/sep_teraidx/ref.fa" --index "$W/sep_teraidx" >/dev/null 2>&1
    "$MOVI" query --count -i "$W/sep_nptm"     -r "$W/kmers.fa" --stdout 2>/dev/null | sort > "$W/nptm.cnt"
    "$MOVI" query --count -i "$W/sep_teraidx"  -r "$W/kmers.fa" --stdout 2>/dev/null | sort > "$W/tera.cnt"
    if cmp -s "$W/nptm.cnt" "$W/tera.cnt"; then
        echo "  PASS: Tera/grlBWT --separators counts identical to NPTM ($(wc -l <"$W/nptm.cnt") queries)"
    else
        echo "  FAIL: count output differs"; fails=$((fails+1))
    fi
else
    echo "== Claim 2: SKIP (set GRLBWT_DIR to a grlBWT build dir to run the separator path) =="
fi

if (( fails )); then echo "$fails cross-tool check(s) FAILED"; exit 1; fi
echo "All cross-tool checks passed."
