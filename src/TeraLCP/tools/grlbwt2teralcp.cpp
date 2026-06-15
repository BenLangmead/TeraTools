// grlbwt2teralcp -- adapter from grlBWT's `grlbwt2rle` output to the run-length
// BWT companion files TeraLCP (`-f rlbwt`) and Movi consume.
//
// grlbwt2rle emits two parallel, headerless files (one entry per BWT run):
//   <in>.syms : 1 byte  per run  -- the run head character
//   <in>.len  : 4 bytes per run  -- the run length, little-endian uint32
//
// TeraLCP `-f rlbwt -i <base>` and Movi both want:
//   <out>.bwt.heads : 1 byte  per run  -- run head character
//   <out>.bwt.len   : 5 bytes per run  -- run length, little-endian (THRBYTES=5)
//
// This tool widens .len 4->5 bytes and copies .syms -> .bwt.heads. It replaces the
// inline Python glue that test/validate_against_movi.sh used to carry.
//
// Sentinel handling. TeraLCP needs no head remap: buildRldFromRlbwt() remaps heads
// by ascending byte rank, so grlBWT's terminator (the smallest present byte, a
// newline 0x0a in our pipeline) is treated as code 0 / endmarker automatically.
// Movi's build, however, expects the endmarker head to be the literal byte 0x00.
// Pass --movi-sentinel to remap the smallest present head byte to 0x00 for that
// build (separators such as '%' are left untouched -- only the single minimum byte,
// i.e. the terminator, is moved). Produce TeraLCP input without the flag and the
// Movi-build heads with it; the widened .bwt.len is identical either way.
//
// Build: `make -C src/TeraLCP tools` (no SDSL/ropebwt3 dependency).
// Usage: grlbwt2teralcp <in_prefix> <out_prefix> [--movi-sentinel] [-q]

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

static std::vector<unsigned char> readAll(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) {
        std::cerr << "ERROR: cannot open " << path << "\n";
        std::exit(1);
    }
    return std::vector<unsigned char>((std::istreambuf_iterator<char>(f)),
                                       std::istreambuf_iterator<char>());
}

int main(int argc, char** argv) {
    std::string inPrefix, outPrefix;
    bool moviSentinel = false, quiet = false;
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--movi-sentinel") moviSentinel = true;
        else if (a == "-q" || a == "--quiet") quiet = true;
        else if (!inPrefix.empty() && !outPrefix.empty()) {
            std::cerr << "ERROR: unexpected extra argument: " << a << "\n";
            return 1;
        }
        else if (inPrefix.empty()) inPrefix = a;
        else outPrefix = a;
    }
    if (inPrefix.empty() || outPrefix.empty()) {
        std::cerr << "Usage: grlbwt2teralcp <in_prefix> <out_prefix> "
                     "[--movi-sentinel] [-q]\n"
                     "  reads  <in_prefix>.syms (1B/run) + <in_prefix>.len (4B LE/run)\n"
                     "  writes <out_prefix>.bwt.heads (1B/run) + <out_prefix>.bwt.len (5B LE/run)\n";
        return 1;
    }

    std::vector<unsigned char> heads = readAll(inPrefix + ".syms");
    std::vector<unsigned char> lenRaw = readAll(inPrefix + ".len");
    const uint64_t runs = heads.size();
    if (runs == 0) {
        std::cerr << "ERROR: empty heads file " << inPrefix << ".syms\n";
        return 1;
    }
    if (lenRaw.size() != runs * 4) {
        std::cerr << "ERROR: " << inPrefix << ".len is " << lenRaw.size()
                  << " bytes; expected " << (runs * 4) << " (4 bytes x " << runs
                  << " runs from .syms)\n";
        return 1;
    }

    if (moviSentinel) {
        unsigned char minByte = 255;
        for (unsigned char b : heads) if (b < minByte) minByte = b;
        if (minByte != 0) {
            for (unsigned char& b : heads) if (b == minByte) b = 0;
        }
    }

    std::ofstream hOut(outPrefix + ".bwt.heads", std::ios::binary);
    std::ofstream lOut(outPrefix + ".bwt.len", std::ios::binary);
    if (!hOut.is_open() || !lOut.is_open()) {
        std::cerr << "ERROR: cannot open output files with prefix " << outPrefix << "\n";
        return 1;
    }
    hOut.write(reinterpret_cast<const char*>(heads.data()),
               static_cast<std::streamsize>(runs));

    uint64_t total = 0;
    for (uint64_t i = 0; i < runs; ++i) {
        // little-endian 4 -> 5 byte widen
        uint64_t L = static_cast<uint64_t>(lenRaw[i * 4 + 0])
                   | (static_cast<uint64_t>(lenRaw[i * 4 + 1]) << 8)
                   | (static_cast<uint64_t>(lenRaw[i * 4 + 2]) << 16)
                   | (static_cast<uint64_t>(lenRaw[i * 4 + 3]) << 24);
        total += L;
        unsigned char out5[5];
        for (int b = 0; b < 5; ++b) out5[b] = static_cast<unsigned char>((L >> (8 * b)) & 0xFF);
        lOut.write(reinterpret_cast<const char*>(out5), 5);
    }
    hOut.close();
    lOut.close();
    if (hOut.fail() || lOut.fail()) {
        std::cerr << "ERROR: failed while writing output for prefix " << outPrefix << "\n";
        return 1;
    }

    if (!quiet) {
        std::cerr << "grlbwt2teralcp: " << runs << " runs, total length " << total
                  << (moviSentinel ? " (movi sentinel remap applied)" : "") << "\n";
    }
    return 0;
}
