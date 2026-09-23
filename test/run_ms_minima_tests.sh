#!/bin/bash
# Tests for TeraLCP -ominima (per-run LCP minima for the ms index).
#
# Requires TeraLCP and ropebwt3 (make -C src/TeraLCP), python3 and a C++
# compiler (CXX, default c++) for the BWT-inversion checker. From the repo root:
#   bash test/run_ms_minima_tests.sh      (or: make -C src/TeraLCP test-minima)
#
# Checks:
#   (1) texts with '%' separators and one sentinel, and with several sentinels,
#       against a brute-force reference built by sorting rotations
#       (src/TeraLCP/testing/ms_minima_brute.py), via -f rlbwt;
#   (2) FMD inputs (test FASTAs via ropebwt3, data/testing) against the
#       BWT-inversion checker (src/TeraLCP/testing/ms_minima_check.cpp);
#   (3) byte-identical output for 1 and 4 threads and with tiny reorder buckets;
#   (4) identical output when -ominima is combined with -orlcp, -othresholds,
#       -oindex, and from a saved lcp_index, with the other outputs unchanged;
#   (5) -f rlbwt input whose run numbering TeraLCP would change is rejected.

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RB3="${REPO_ROOT}/ropebwt3/ropebwt3"
TERALCP="${REPO_ROOT}/src/TeraLCP/TeraLCP"
TDIR="${REPO_ROOT}/src/TeraLCP/testing"
DUMP="${REPO_ROOT}/src/TeraLCP/ms_minima_dump.py"

for bin in "$RB3" "$TERALCP"; do
    [[ -x "$bin" ]] || { echo "ERROR: $bin not found; build it first (make -C src/TeraLCP)." >&2; exit 2; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
CHECK="${tmp}/ms_minima_check"
"${CXX:-c++}" -O2 -std=c++11 -o "$CHECK" "${TDIR}/ms_minima_check.cpp" || { echo "ERROR: cannot build checker" >&2; exit 2; }

failures=0
fail() { echo "FAIL $*"; failures=$((failures+1)); }
records() { python3 "$DUMP" "$1" | grep -v '^#'; }

# Runs TeraLCP -ominima on an input with 1 and 4 threads and tiny buckets and
# checks that all outputs are byte-identical. Leaves the output in $3.min.
minima_all_ways() { # format input outbase
    local fmt=$1 in=$2 out=$3
    OMP_NUM_THREADS=1 "$TERALCP" -f "$fmt" -i "$in" -t "${tmp}/t" -ominima "${out}.min" -v quiet 2>/dev/null \
        || { fail "$out: TeraLCP -ominima failed"; return 1; }
    OMP_NUM_THREADS=4 "$TERALCP" -f "$fmt" -i "$in" -t "${tmp}/t" -ominima "${out}.min4" -v quiet 2>/dev/null
    cmp -s "${out}.min" "${out}.min4" || fail "$out: 1 vs 4 threads differ"
    OMP_NUM_THREADS=4 "$TERALCP" -f "$fmt" -i "$in" -t "${tmp}/t" -ominima "${out}.minb" --minima-bucket-kb 1 -v quiet 2>/dev/null
    cmp -s "${out}.min" "${out}.minb" || fail "$out: small-bucket reorder differs"
    ls "${out}".min*.tmp.* >/dev/null 2>&1 && fail "$out: temporary files left behind"
    return 0
}

# (1) brute force from text
n1=0
for seed in 1 2 3 4 5 6; do
    for spec in "single:--mode single --random $((2+seed)),5,120,${seed}" \
                "rep:--mode single --repeat 0.8 --random $((20+seed)),60,300,${seed}" \
                "nosep:--mode single --sep= --repeat 0.6 --random $((3+seed)),10,150,${seed}" \
                "multi:--mode multi --random $((2+seed)),1,80,${seed}" \
                "multirep:--mode multi --repeat 0.8 --random $((30+seed)),40,200,${seed}"; do
        name="${tmp}/${spec%%:*}${seed}"
        # shellcheck disable=SC2086
        python3 "${TDIR}/ms_minima_brute.py" --out "$name" ${spec#*:} >/dev/null || { fail "$name: brute force"; continue; }
        minima_all_ways rlbwt "$name" "$name" || continue
        records "${name}.min" | cmp -s - "${name}.expected" || fail "$(basename "$name"): differs from brute force"
        "$CHECK" "$name" --dump 2>/dev/null | cmp -s - "${name}.expected" || fail "$(basename "$name"): checker disagrees with brute force"
        n1=$((n1+1))
    done
done
for edge in "e1:--mode single TTTTTTTTTTTT" "e2:--mode single ACGTTTTTTTTTTACGTTTTTTT TTTTTTTTTTTTT" \
            "e3:--mode multi TTTTTTTT TTTTTTTTTTT TTTT GTTTTT" "e4:--mode multi A A A A AC" "e5:--mode single A"; do
    name="${tmp}/${edge%%:*}"
    # shellcheck disable=SC2086
    python3 "${TDIR}/ms_minima_brute.py" --out "$name" ${edge#*:} >/dev/null
    OMP_NUM_THREADS=1 "$TERALCP" -f rlbwt -i "$name" -t "${tmp}/t" -ominima "${name}.min" -v quiet 2>/dev/null || { fail "${edge%%:*}: TeraLCP failed"; continue; }
    records "${name}.min" | cmp -s - "${name}.expected" || fail "${edge%%:*}: differs from brute force"
    n1=$((n1+1))
done
echo "(1) brute-force text cases: ${n1}"

# (2) FMD inputs vs the BWT-inversion checker. -othresholds writes the RLBWT.
n2=0
fmds=()
for c in single_string:single_string.fa gattacat:gattacat.fa shred1_mini:minishred1_20_002.fa; do
    d=${c%%:*}; fa=${c##*:}
    "$RB3" build -R -d -o "${tmp}/${d}.fmd" "${REPO_ROOT}/test/${d}/${fa}" 2>/dev/null && fmds+=("${tmp}/${d}.fmd")
done
fmds+=("${REPO_ROOT}/data/testing/idx.fmd" "${REPO_ROOT}/data/testing/single.fmd" "${REPO_ROOT}/data/testing/0.03crop_mtb152.fmd")
for fmd in "${fmds[@]}"; do
    name="${tmp}/fmd_$(basename "$fmd" .fmd)"
    OMP_NUM_THREADS=1 "$TERALCP" -f fmd -i "$fmd" -t "${tmp}/t" -othresholds "${name}.ref" -v quiet 2>/dev/null || { fail "$fmd: thresholds"; continue; }
    minima_all_ways fmd "$fmd" "$name" || continue
    "$CHECK" "${name}.ref" "${name}.min" 2>/dev/null || fail "$(basename "$fmd"): differs from checker"
    n2=$((n2+1))
done
echo "(2) FMD cases: ${n2}"

# (4) combinations with the other outputs (on the shred1_mini FMD)
fmd="${tmp}/shred1_mini.fmd"
c="${tmp}/combo"
run() { OMP_NUM_THREADS=4 "$TERALCP" -f fmd -i "$fmd" -t "${tmp}/t" -v quiet "$@" 2>/dev/null || fail "combo: TeraLCP $*"; }
run -ominima "${c}A"
run -orlcp "${c}R0"
run -othresholds "${c}T0"
run -oindex "${c}I0"
run -ominima "${c}B" -orlcp "${c}R1"
run -ominima "${c}C" -othresholds "${c}T1"
run -ominima "${c}D" -oindex "${c}I1"
run -ominima "${c}E" -orlcp "${c}R2" -othresholds "${c}T2" -oindex "${c}I2"
for x in B C D E; do cmp -s "${c}A" "${c}${x}" || fail "combo: -ominima output ${x} differs"; done
for x in 1 2; do cmp -s "${c}R0.rlcp" "${c}R${x}.rlcp" || fail "combo: .rlcp ${x} differs"; done
for x in 1 2; do for e in thr thr_pos; do cmp -s "${c}T0.${e}" "${c}T${x}.${e}" || fail "combo: .${e} ${x} differs"; done; done
for x in 1 2; do cmp -s "${c}I0.lcp_index" "${c}I${x}.lcp_index" || fail "combo: .lcp_index ${x} differs"; done
OMP_NUM_THREADS=4 "$TERALCP" -f lcp_index -i "${c}I0.lcp_index" -t "${tmp}/t" -ominima "${c}F" -v quiet 2>/dev/null || fail "combo: -f lcp_index"
records "${c}F" | cmp -s - <(records "${c}A") || fail "combo: -f lcp_index records differ"
echo "(4) combinations checked"

# (5) run numbering that TeraLCP would change is rejected for -f rlbwt
bad="${tmp}/bad"
python3 -c "import sys; sys.stdout.buffer.write(b''.join(x.to_bytes(5,'little') for x in [1,1,1,1]))" > "${bad}.bwt.len"
printf 'AAC\0' > "${bad}.bwt.heads"            # adjacent equal heads: rejected
"$TERALCP" -f rlbwt -i "$bad" -t "${tmp}/t" -ominima "${bad}.min" -v quiet >/dev/null 2>&1 && fail "adjacent equal heads accepted"
printf 'AC\0' > "${bad}.bwt.heads"             # sentinel run of length 2: rejected
python3 -c "import sys; sys.stdout.buffer.write(b''.join(x.to_bytes(5,'little') for x in [1,1,2]))" > "${bad}.bwt.len"
"$TERALCP" -f rlbwt -i "$bad" -t "${tmp}/t" -ominima "${bad}.min" -v quiet >/dev/null 2>&1 && fail "sentinel run of length 2 accepted"
echo "(5) numbering checks done"

if [[ $failures -gt 0 ]]; then echo "${failures} check(s) FAILED"; exit 1; fi
echo "All ms minima tests passed."
