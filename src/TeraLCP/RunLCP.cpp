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
    std::string mode = "top";
    bool header = false;
    bool thresholdsBoundary = false;
};

void printUsage() {
    std::cout
        << "RunLCP emits per-run LCP lists using a TeraLCP index.\n"
        << "\n"
        << "Usage: RunLCP -i <input.lcp_index> [-o output.tsv] [--mode MODE] [--header] [--boundary]\n"
        << "\n"
        << "Options:\n"
        << "  -i FILE       Input LCP index file produced by TeraLCP\n"
        << "  -o FILE       Output TSV file (default: stdout)\n"
        << "  --mode MODE   Output mode: all|top|min-top|min-bot|min-range|sample|thresholds [top]\n"
        << "                For thresholds: writes base.thr and base.thr_pos (requires -o as base path)\n"
        << "  --boundary    (thresholds only) Prefer boundary positions (offset 0 or len) when minimal\n"
        << "  --header      Print a header row (always on for writeRunLCP modes)\n"
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
    options.mode = getArg("--mode", false, true);
    if (options.mode.empty()) options.mode = "top";
    options.header = (getArg("--header", false, false) != "");
    options.thresholdsBoundary = (getArg("--boundary", false, false) != "");

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

}  // namespace

int main(int argc, const char* argv[]) {
    Options options = parseOptions(argc, argv);

    TeraLCP::RunLCPMode mode;
    try {
        mode = TeraLCP::parseRunLCPMode(options.mode);
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << '\n';
        return 1;
    }

    TeraLCP index(options.inputFile);

    if (mode == TeraLCP::RunLCPMode::thresholds) {
        if (options.outputFile.empty()) {
            std::cerr << "ERROR: thresholds mode requires -o BASE (writes BASE.thr and BASE.thr_pos)\n";
            return 1;
        }
        index.writeThresholds(options.outputFile, options.thresholdsBoundary);
        return 0;
    }

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

    index.writeRunLCP(out, mode);

    return 0;
}
