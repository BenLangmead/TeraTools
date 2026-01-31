// Author: Ben Langmead with assistance from Codex
// Copyright 2026
// Description: Emit per-run LCP lists from a TeraLCP index in TSV format.

#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "TeraLCP/TeraLCP.h"
#include "util/util.h"

namespace {
struct Options {
    std::string inputFile;
    std::string outputFile;
    bool header = false;
};

void printUsage() {
    std::cout
        << "RunLCP emits per-run LCP lists using a TeraLCP index.\n"
        << "\n"
        << "Usage: RunLCP -i <input.lcp_index> [-o output.tsv] [--header]\n"
        << "\n"
        << "Options:\n"
        << "  -i FILE       Input LCP index file produced by TeraLCP\n"
        << "  -o FILE       Output TSV file (default: stdout)\n"
        << "  --header      Print a header row\n"
        << "  -h, --help    Show this help message\n";
}

Options parseOptions(int argc, const char* argv[]) {
    Options options;
    std::vector<bool> used(argc);
    used[0] = true;

    auto getArg = [&](const std::string& arg, bool required, bool hasArg) -> std::string {
        return getArgument(argc, argv, used, arg, required, hasArg);
    };

    if (argc == 1 || getArg("-h", false, false) != "" || getArg("--help", false, false) != "") {
        printUsage();
        std::exit(0);
    }

    options.inputFile = getArg("-i", true, true);
    options.outputFile = getArg("-o", false, true);
    options.header = (getArg("--header", false, false) != "");

    for (int i = 0; i < argc; ++i) {
        if (!used[i]) {
            std::cerr << "Argument " << i << ", '" << argv[i]
                      << "' not recognized or used as an argument for another option.\n";
            std::exit(1);
        }
    }

    testInFile(options.inputFile);
    if (!options.outputFile.empty()) {
        testOutFile(options.outputFile);
    }
    return options;
}

std::string symbolToString(uint64_t symbol) {
    static const char* alphabet = "$ACGTN";
    if (symbol < 6) {
        return std::string(1, alphabet[symbol]);
    }
    return std::to_string(symbol);
}
}  // namespace

int main(int argc, const char* argv[]) {
    Options options = parseOptions(argc, argv);

    TeraLCP index(options.inputFile);
    auto lcp = index.buildLCPArray();
    auto runInfo = index.buildRunInfo();

    std::ostream* outPtr = &std::cout;
    std::ofstream outFile;
    if (!options.outputFile.empty()) {
        outFile.open(options.outputFile);
        if (!outFile.is_open()) {
            std::cerr << "ERROR: failed to open output file '" << options.outputFile << "'\n";
            return 1;
        }
        outPtr = &outFile;
    }
    std::ostream& out = *outPtr;

    if (options.header) {
        out << "run_id\trun_offset\trun_length\tchar\tlcp_values\n";
    }

    uint64_t runOffset = 0;
    const uint64_t runCount = runInfo.lengths.size();
    for (uint64_t runId = 0; runId < runCount; ++runId) {
        uint64_t runLength = runInfo.lengths[runId];
        uint64_t start = runOffset;
        uint64_t end = start + runLength;
        if (end > lcp.size()) {
            std::cerr << "ERROR: run length exceeds LCP array length.\n";
            return 1;
        }
        out << runId << '\t'
            << runOffset << '\t'
            << runLength << '\t'
            << symbolToString(runInfo.symbols[runId]) << '\t';

        for (uint64_t i = start; i < end; ++i) {
            if (i != start) {
                out << ',';
            }
            out << lcp[i];
        }
        out << '\n';
        runOffset = end;
    }

    return 0;
}
