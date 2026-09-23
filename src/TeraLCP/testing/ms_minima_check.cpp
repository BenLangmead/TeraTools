// Independent checker for TeraLCP -ominima output, starting from an RLBWT.
//
// Usage: ms_minima_check BASE [MINIMA_FILE] [--dump]
//
// Reads BASE.bwt.heads / BASE.bwt.len (smallest head byte is the sentinel),
// inverts the BWT with rank-based LF to recover every string and the suffix
// array, computes LCP with Kasai's algorithm (extension stops at a sentinel),
// forms runs (maximal blocks of equal non-sentinel characters, one run per
// sentinel), and computes each run's top and prefix/suffix minima directly from
// their definitions. With MINIMA_FILE it compares against that file; with --dump
// it prints the expected records in ms_minima_dump.py's format.
//
// Needs about 11 bytes of RAM per BWT character; n must be below 2^32.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

static bool readVarint(const std::vector<unsigned char>& d, size_t& pos, uint64_t& x) {
    x = 0;
    unsigned shift = 0;
    while (pos < d.size()) {
        unsigned char c = d[pos++];
        x |= static_cast<uint64_t>(c & 0x7f) << shift;
        if (!(c & 0x80)) return true;
        shift += 7;
    }
    return false;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: ms_minima_check BASE [MINIMA_FILE] [--dump]\n";
        return 2;
    }
    std::string base = argv[1], minPath;
    bool dump = false;
    for (int i = 2; i < argc; ++i) {
        if (std::string(argv[i]) == "--dump") dump = true;
        else minPath = argv[i];
    }

    std::ifstream hf(base + ".bwt.heads", std::ios::binary), lf(base + ".bwt.len", std::ios::binary);
    if (!hf || !lf) { std::cerr << "cannot open " << base << ".bwt.heads/.bwt.len\n"; return 2; }
    std::vector<unsigned char> heads((std::istreambuf_iterator<char>(hf)), std::istreambuf_iterator<char>());
    std::vector<uint64_t> lens(heads.size());
    uint64_t n = 0;
    for (size_t i = 0; i < heads.size(); ++i) {
        uint64_t L = 0;
        lf.read(reinterpret_cast<char*>(&L), 5);
        if (!lf) { std::cerr << "short len file\n"; return 2; }
        lens[i] = L;
        n += L;
    }
    if (n >= (1ULL << 32) - 1) { std::cerr << "n too large for this checker\n"; return 2; }

    // Byte -> code in ascending byte order; code 0 is the sentinel.
    int code[256];
    std::fill(code, code + 256, -1);
    {
        bool present[256] = {false};
        for (unsigned char b : heads) present[b] = true;
        int k = 0;
        for (int b = 0; b < 256; ++b) if (present[b]) code[b] = k++;
    }

    std::vector<uint8_t> F(n);
    std::vector<uint32_t> psi(n);
    {
        std::vector<uint8_t> bwt(n);
        uint64_t k = 0;
        for (size_t i = 0; i < heads.size(); ++i)
            for (uint64_t j = 0; j < lens[i]; ++j) bwt[k++] = static_cast<uint8_t>(code[heads[i]]);
        std::vector<uint64_t> C(257, 0);
        for (uint64_t i = 0; i < n; ++i) ++C[bwt[i] + 1];
        for (int c = 1; c <= 256; ++c) C[c] += C[c - 1];
        for (int c = 0; c < 256; ++c)
            for (uint64_t r = C[c]; r < C[c + 1]; ++r) F[r] = static_cast<uint8_t>(c);
        std::vector<uint64_t> occ(C.begin(), C.end() - 1);
        for (uint64_t i = 0; i < n; ++i) psi[occ[bwt[i]]++] = static_cast<uint32_t>(i);
    }

    // Text and suffix array. The string after sentinel row s is read by following
    // Psi from s up to the next sentinel row. Rank-based LF on sentinels need not
    // close each string into its own cycle (ropebwt3 orders sentinels differently),
    // but the rows up to the next sentinel are the same either way, and so are
    // the LCP values, which never extend past a sentinel.
    std::vector<uint8_t> T(n);
    std::vector<uint32_t> SA(n);
    {
        uint64_t pos = 0;
        for (uint64_t s = 0; s < n && F[s] == 0; ++s) {
            uint64_t k = psi[s];
            while (pos < n) {
                T[pos] = F[k];
                SA[k] = static_cast<uint32_t>(pos);
                ++pos;
                if (F[k] == 0) break;
                k = psi[k];
            }
        }
        if (pos != n) { std::cerr << "strings cover " << pos << " of " << n << " rows\n"; return 1; }
        std::vector<char> seen(n, 0);
        for (uint64_t k = 0; k < n; ++k) {
            if (SA[k] >= n || seen[SA[k]]) { std::cerr << "rows do not map one-to-one to text positions\n"; return 1; }
            seen[SA[k]] = 1;
        }
    }
    std::vector<uint8_t>().swap(F);

    // Kasai via Phi, reusing psi's memory: phi[SA[k]] = SA[k-1], then PLCP in place.
    std::vector<uint32_t>& plcp = psi;
    plcp[SA[0]] = static_cast<uint32_t>(n);   // row 0 has no predecessor
    for (uint64_t k = 1; k < n; ++k) plcp[SA[k]] = SA[k - 1];
    {
        uint64_t h = 0;
        for (uint64_t p = 0; p < n; ++p) {
            const uint64_t q = plcp[p];
            if (q == n) { h = 0; plcp[p] = 0; continue; }
            while (T[p + h] != 0 && T[p + h] == T[q + h]) ++h;
            plcp[p] = static_cast<uint32_t>(h);
            h = (h > 0 && T[p] != 0) ? h - 1 : 0;
        }
    }
    auto LCP = [&](uint64_t row) -> uint64_t { return plcp[SA[row]]; };

    // Runs: maximal equal non-sentinel blocks; each sentinel its own run.
    std::vector<std::pair<uint64_t, uint64_t>> runs;   // (start, length)
    {
        uint64_t k = 0;
        int prevCode = -1;
        for (size_t i = 0; i < heads.size(); ++i) {
            const int c = code[heads[i]];
            for (uint64_t j = 0; j < lens[i]; ++j, ++k) {
                if (c == 0 || c != prevCode || runs.empty()) runs.push_back({k, 1});
                else ++runs.back().second;
                prevCode = c;
            }
        }
    }
    const uint64_t r = runs.size();

    std::vector<unsigned char> file;
    size_t fpos = 48;
    if (!minPath.empty()) {
        std::ifstream mf(minPath, std::ios::binary);
        if (!mf) { std::cerr << "cannot open " << minPath << "\n"; return 2; }
        file.assign(std::istreambuf_iterator<char>(mf), std::istreambuf_iterator<char>());
        static const unsigned char MAGIC[8] = {0x93, 'T', 'L', 'M', 'S', 'M', 0x00, 0x01};
        if (file.size() < 48 || std::memcmp(file.data(), MAGIC, 8) != 0) { std::cerr << "bad magic\n"; return 1; }
        uint64_t fr, fn;
        std::memcpy(&fr, file.data() + 16, 8);
        std::memcpy(&fn, file.data() + 24, 8);
        if (fr != r || fn != n) {
            std::cerr << "header mismatch: file r=" << fr << " n=" << fn << ", expected r=" << r << " n=" << n << "\n";
            return 1;
        }
    }

    const uint64_t INF = static_cast<uint64_t>(-1);
    uint64_t totalPairs = 0, mismatches = 0, maxCount = 0;
    std::vector<std::pair<uint64_t, uint64_t>> chosen, got;
    for (uint64_t i = 0; i < r; ++i) {
        const uint64_t s = runs[i].first, L = runs[i].second;
        const uint64_t top = LCP(s);
        const uint64_t nextTop = (i + 1 < r) ? LCP(runs[i + 1].first) : INF;
        std::vector<char> mark(L, 0);
        uint64_t m = top;
        for (uint64_t o = 1; o < L; ++o) { uint64_t v = LCP(s + o); if (v < m) { mark[o] = 1; m = v; } }
        m = nextTop;
        for (uint64_t o = L; o-- > 1; ) { uint64_t v = LCP(s + o); if (v < m) { mark[o] = 1; m = v; } }
        chosen.clear();
        for (uint64_t o = 1; o < L; ++o) if (mark[o]) chosen.push_back({o, LCP(s + o)});
        totalPairs += chosen.size();
        maxCount = std::max<uint64_t>(maxCount, chosen.size());
        if (dump) {
            std::cout << i << '\t' << top << '\t' << chosen.size() << '\t';
            for (size_t k = 0; k < chosen.size(); ++k)
                std::cout << (k ? "," : "") << chosen[k].first << ':' << chosen[k].second;
            std::cout << '\n';
        }
        if (!file.empty()) {
            uint64_t ftop = 0, fcnt = 0, off = 0, g, v;
            bool ok = readVarint(file, fpos, ftop) && readVarint(file, fpos, fcnt);
            got.clear();
            for (uint64_t k = 0; ok && k < fcnt; ++k) {
                ok = readVarint(file, fpos, g) && readVarint(file, fpos, v);
                off += g;
                got.push_back({off, v});
            }
            if (!ok) { std::cerr << "truncated minima file at run " << i << "\n"; return 1; }
            if (ftop != top || got != chosen) {
                if (++mismatches <= 10) {
                    std::cerr << "MISMATCH run " << i << " (start " << s << ", len " << L << "): expected top " << top
                              << " with " << chosen.size() << " pairs, file top " << ftop << " with " << got.size() << " pairs\n";
                }
            }
        }
    }
    if (!file.empty() && fpos != file.size()) { std::cerr << "trailing bytes in minima file\n"; ++mismatches; }
    std::cerr << "checker: n=" << n << " r=" << r << " input_runs=" << heads.size() << " stored_pairs=" << totalPairs
              << " (" << (r ? static_cast<double>(totalPairs) / r : 0.0) << " per run, max " << maxCount << ")";
    if (!file.empty()) std::cerr << (mismatches ? " MISMATCHES=" + std::to_string(mismatches) : std::string(" file matches"));
    std::cerr << "\n";
    return mismatches ? 1 : 0;
}
