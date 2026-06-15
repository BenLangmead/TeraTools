#!/bin/bash
# Corner-case correctness tests for the TeraLCP -> Movi separator pipeline.
#
# The main reproducer (test/validate_against_movi.sh) only queries substrings drawn
# from *within* a single record, so it cannot exercise the one property that most
# directly depends on correct separator/terminator handling: a match must NOT span a
# record boundary. This harness drives small, adversarial fixtures whose query sets
# deliberately include boundary-spanning strings, identical records, sub-k records,
# and non-ACGT (N) runs, then checks that a Tera-built Movi index answers identically
# to a stock pfp/NPTM index. Any separator mishandling shows up as a Tera-vs-NPTM
# divergence (e.g. a boundary-spanning k-mer that Tera counts but NPTM does not).
#
# Like the main reproducer this is a guarded, non-CI cross-tool check: it needs the
# separator (grlBWT) path, so it SKIPs (exit 0) unless MOVI and GRLBWT_DIR are set.
#
# Usage: MOVI=/path/to/movi GRLBWT_DIR=/path/to/grlBWT/build \
#        bash test/corner/run_corner_tests.sh

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERALCP="$REPO_ROOT/src/TeraLCP/TeraLCP"
ADAPTER="$REPO_ROOT/src/TeraLCP/tools/grlbwt2teralcp"
export OMP_NUM_THREADS=1

MOVI="${MOVI:-$(command -v movi || true)}"
PREPARE=""
[[ -n "$MOVI" ]] && PREPARE="$(dirname "$MOVI")/bin/movi-prepare-ref"
GRLBWT_DIR="${GRLBWT_DIR:-}"

skip=0
note() { echo "  - $1"; skip=1; }
[[ -x "$TERALCP" ]] || note "TeraLCP not built (run: make -C src/TeraLCP)"
[[ -x "$ADAPTER" ]] || note "grlbwt2teralcp not built (run: make -C src/TeraLCP tools)"
[[ -n "$MOVI" && -x "$MOVI" ]] || note "movi launcher not found (set MOVI=/path/to/movi)"
[[ -n "$PREPARE" && -x "$PREPARE" ]] || note "movi-prepare-ref not found next to movi"
[[ -n "$GRLBWT_DIR" && -x "$GRLBWT_DIR/grlbwt-cli" && -x "$GRLBWT_DIR/grlbwt2rle" ]] \
    || note "grlBWT not found (set GRLBWT_DIR to a grlBWT build dir)"
command -v python3 >/dev/null 2>&1 || note "python3 not found"
if (( skip )); then
    echo "SKIP run_corner_tests.sh: missing prerequisites (see above)."
    exit 0
fi

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fails=0

# Build a stock-NPTM and a Tera --separators index for $ref, then diff --count and
# --kmer on $queries. Bumps $fails on any divergence.
# run_case LABEL REF QUERIES FTABK KMERK
run_case() {
    local label="$1" ref="$2" queries="$3" ftabk="$4" kmerk="$5"
    local d="$W/$label"; mkdir -p "$d"

    # Stock NPTM separator index.
    "$MOVI" build --separators --fasta "$ref" --index "$d/nptm" \
        --type regular-thresholds --ftab-k "$ftabk" >/dev/null 2>&1

    # Tera separator index via grlBWT -> adapter -> TeraLCP -f rlbwt.
    "$PREPARE" "$ref" "$d/clean.fa" separators >/dev/null 2>&1
    { grep -v '^>' "$d/clean.fa" | tr -d '\n'; echo; } > "$d/grl_in.txt"
    "$GRLBWT_DIR/grlbwt-cli" "$d/grl_in.txt" -o "$d/grl_out" >/dev/null 2>&1
    "$GRLBWT_DIR/grlbwt2rle" "$d/grl_out.rl_bwt" "$d/grl_rle" >/dev/null 2>&1
    "$ADAPTER" "$d/grl_rle" "$d/grl" -q
    "$TERALCP" -f rlbwt -i "$d/grl" -t "$d/t" -othresholds "$d/septera" -v quiet 2>/dev/null
    mkdir -p "$d/teraidx"
    "$ADAPTER" "$d/grl_rle" "$d/teraidx/ref.fa" --movi-sentinel -q
    cp "$d/septera.thr_pos" "$d/teraidx/ref.fa.thr_pos"
    [[ -f "$d/septera.thr" ]] && cp "$d/septera.thr" "$d/teraidx/ref.fa.thr"
    cp "$d/clean.fa" "$d/teraidx/ref.fa"
    "$MOVI" build --separators --preprocessed --skip-prepare --skip-pfp \
        --type regular-thresholds --ftab-k "$ftabk" \
        --fasta "$d/teraidx/ref.fa" --index "$d/teraidx" >/dev/null 2>&1

    local mode args name
    for spec in "count|--count" "kmer|--kmer -k $kmerk"; do
        name="${label}_${spec%%|*}"; args="${spec#*|}"
        # shellcheck disable=SC2086
        "$MOVI" query $args -i "$d/nptm"    -r "$queries" --stdout 2>/dev/null | sort > "$d/$name.nptm"
        # shellcheck disable=SC2086
        "$MOVI" query $args -i "$d/teraidx" -r "$queries" --stdout 2>/dev/null | sort > "$d/$name.tera"
        if cmp -s "$d/$name.nptm" "$d/$name.tera"; then
            echo "  PASS: $name ($(wc -l <"$d/$name.nptm") lines)"
        else
            echo "  FAIL: $name differs"; fails=$((fails+1))
            diff "$d/$name.nptm" "$d/$name.tera" | head -6 | sed 's/^/      /'
        fi
    done
}

# ---------------------------------------------------------------------------
# Fixtures (defined inline; written to the workdir). Sequences are padded so the
# tiny BWTs are well-formed for grlBWT, while keeping distinctive boundaries.
# ---------------------------------------------------------------------------

# 1. Cross-separator non-matching: a query that straddles the s1|s2 boundary must
#    NOT match. s1 ends ...ACACAC, s2 starts GTGTGT; "ACACACGTGTGT" exists only if a
#    match is (wrongly) allowed to cross the separator.
cat > "$W/cross.fa" <<'FA'
>s1
ACGTACGTACGTACGTACGTACGTACACAC
>s2
GTGTGTACGTACGTACGTACGTACGTACGT
FA
cat > "$W/cross.q.fa" <<'FA'
>within1
ACGTACGTACGT
>within2
GTGTGTACGTAC
>span_boundary
ACACACGTGTGT
>span_short
CACGTG
FA

# 2. Identical records: repeated sequences -> counts must agree exactly.
cat > "$W/ident.fa" <<'FA'
>a
ACGTACGTACGTACGTACGTACGT
>b
ACGTACGTACGTACGTACGTACGT
>c
ACGTACGTACGTACGTACGTACGT
FA
cat > "$W/ident.q.fa" <<'FA'
>k1
ACGTACGT
>k2
GTACGTAC
FA

# 3. Sub-k / degenerate records: records at or below the kmer length.
cat > "$W/short.fa" <<'FA'
>p
ACGTACGTAC
>q
TTGGTTGGTT
>r
CCAACCAACC
FA
cat > "$W/short.q.fa" <<'FA'
>m1
ACGT
>m2
TTGG
>m3
GGGG
FA

# 4. Non-ACGT (N) runs in the reference: the DNA-N special case was removed (commit
#    2a49fd0). Note that movi-prepare-ref substitutes N before the BWT (the prepared
#    alphabet is %,A,C,G,T -- N never reaches TeraLCP), so this confirms the
#    end-to-end path is robust to N in the input FASTA and that the identical
#    prepare-ref substitution flows through both pipelines. Queries are pure ACGT
#    (Movi's --kmer aborts read files containing illegal/N characters).
cat > "$W/nrun.fa" <<'FA'
>w
ACGTACGTNNNNACGTACGTACGTNNNNACGT
>x
TTTTNNNNGGGGNNNNCCCCNNNNAAAANNNN
FA
cat > "$W/nrun.q.fa" <<'FA'
>q1
ACGTACGT
>q2
GTACGTAC
>q3
TTTTAAAA
FA

echo "== Corner case 1: cross-separator non-matching =="
run_case cross "$W/cross.fa" "$W/cross.q.fa" 3 6
echo "== Corner case 2: identical records (multi-occurrence) =="
run_case ident "$W/ident.fa" "$W/ident.q.fa" 3 8
echo "== Corner case 3: sub-k / degenerate record sizes =="
run_case short "$W/short.fa" "$W/short.q.fa" 3 4
echo "== Corner case 4: non-ACGT (N) runs =="
run_case nrun  "$W/nrun.fa"  "$W/nrun.q.fa"  3 4

# Sanity: confirm the boundary-spanning query is genuinely absent (count 0) in the
# stock index, so the cross-separator PASS is meaningful and not vacuous.
echo "== Sanity: boundary-spanning query count in stock index =="
sp=$("$MOVI" query --count -i "$W/cross/nptm" -r "$W/cross.q.fa" --stdout 2>/dev/null \
     | grep -i span_boundary | head -1)
echo "  stock count line for span_boundary: ${sp:-<none>}"

if (( fails )); then echo "$fails corner-case check(s) FAILED"; exit 1; fi
echo "All corner-case checks passed."
