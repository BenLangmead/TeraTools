#include"util/util.h"
#include"TeraLCP/TeraLCP.h"

static constexpr const char* rlcp_extension = ".rlcp";

void printUsage() {
    std::cout << 
        "TeraLCP computes the minimum LCP values in each run of the BWT of a text.\n"
        "It does so by computing the Psi and Phi move data structures in compressed space.\n"
        "It can optionally output the computed index to avoid later recomputation or for downstream analysis.\n"
        "\n"
        "Usage: TeraLCP <arguments>\n"
        "Options:\n"
        "  Input:\n"
        "    -f          [text,bwt,rlbwt,fmd,lcp_index]  REQUIRED       Format of input. 'text' is the original text, 'bwt' is the bwt of the text, 'rlbwt' is the rlbwt of the text, 'fmd' is the rlbwt in the ropebwt3 fmd format of the text, and 'lcp_index' is the index outputted by TeraLCP -oindex\n"
        "    -i          FILE                            REQUIRED       File name of input file\n"
        "    -t          FILE                            REQUIRED       Name of a file this program can read and write to temporarily\n"
        "\n"
        "  Output:\n"
        "    -oindex     FILE                            optional       Output constructed index to FILE" << lcp_index_extension << "\n"
        "    -orlcp      FILE                            optional       Output (position, minLCP) pairs per run to FILE" << rlcp_extension << "\n"
        "    -otsv       FILE                            optional       Output TSV per BWT run in BWT order to FILE\n"
        "    -tsvmode    MODE                            optional       Mode for -otsv: all|top|min-top|min-bot|min-range|sample|thresholds [top]\n"
        "                                                              Modes:\n"
        "                                                                all         : Outputs all LCPs for each run (in reverse run order).\n"
        "                                                                top         : Outputs only the maximal LCP for each run (default).\n"
        "                                                                min-top     : Outputs top-most minimal LCPs per run.\n"
        "                                                                min-bot     : Outputs bottom-most minimal LCPs per run.\n"
        "                                                                min-range   : Outputs top-most and bottom-most LCPs per run.\n"
        "                                                                sample      : Outputs top, min, and a sample of interior LCPs sufficient\n"
        "                                                                              for matching statistics (in reverse run order).\n"
        "                                                                thresholds  : Outputs MONI-style .thr and .thr_pos files\n"
        "                                                                              (-otsv specifies base path).\n"
        "    -threshbound                                optional       (thresholds only) Prefer row boundarues (offsets 0 or len) when minimal\n"
        "\n"
        "  Behavior:\n"
        "    -p          INT                             optional       Limit the program to (nonnegative) INT threads. By default uses maximum available. Maximum on this hardware is " << omp_get_max_threads() << "\n"
        "    -mmap                                       optional       read input using memory mapping (only avaiable for fmd) default: no memory mapping\n"
        #ifndef BENCHFASTONLY
        "    -v          [quiet,time,verb]               optional       Verbosity, verb for most verbose output, time for timer info, and quiet for no output. time is default.\n"
        #else
        "    -bench                                      optional       Has no effect. required if no outputs specified.\n"
        #endif
        "    -h, --help                                  optional       Print this help message.\n"
        ;
    //add verification of psi and phi options
    //add sdsl::memory_monitor output option
    //add timer depth option? or remove many timer calls.
    //add move data structure output options?
    //TODO: either fix minor bug in TeraLCP when numthreads > max threads or limit num threads to at most max threads
    //TODO: add more BENCHFASTONLY ifs
    //TODO: add DNDEBUG ifs
}

struct options{
    enum inputFormat { text, bwt, rlbwt, fmd, lcp_index }inputFormat;
    std::string inputFile, tempFile, oindex="", orlcp="", otsv="", tsvmode="top";
    unsigned numThreads = omp_get_max_threads();
    bool mmap;
    bool threshbound = false;
    #ifndef BENCHFASTONLY
    verbosity v = TIME;
    #endif
}o;

void processOptions(const int argc, const char* argv[]) {
    std::vector<bool> used(argc);
    used[0] = true;
    auto getArg = [&] (std::string arg, bool required, bool argument) -> std::string {
        return getArgument(argc, argv, used, arg, required, argument);
    };

    if (argc == 1 || getArg("-h", false, false) != "" || getArg("--help", false, false) != "") {
        printUsage();
        exit(0);
    }

    auto s = getArg("-f", true, true);
    if (s == "text") o.inputFormat=options::text;
    else if (s == "bwt") o.inputFormat=options::bwt;
    else if (s == "rlbwt") o.inputFormat=options::rlbwt;
    else if (s == "fmd") o.inputFormat=options::fmd;
    else if (s == "lcp_index") o.inputFormat=options::lcp_index;
    else {
        std::cout << "Invalid value passed to -f '" << s << "'\n";
        exit(1);
    }
    o.inputFile = getArg("-i", true, true);
    o.tempFile = getArg("-t", true, true);
    o.oindex = getArg("-oindex", false, true);
    if (o.oindex != "") 
        o.oindex += lcp_index_extension;
    o.orlcp = getArg("-orlcp", false, true);
    if (o.orlcp != "")
        o.orlcp += rlcp_extension;
    o.otsv = getArg("-otsv", false, true);
    o.tsvmode = getArg("-tsvmode", false, true);
    if (o.tsvmode == "") o.tsvmode = "top";
    o.threshbound = (getArg("-threshbound", false, false) != "");
    s = getArg("-p", false, true);
    if (s != "")
        o.numThreads = std::stoul(s);
    o.mmap = ("-mmap" == getArg("-mmap", false, false));
#ifndef BENCHFASTONLY
    s = getArg("-v", false, true);
    if (s == "quiet")
        o.v = QUIET;
    else if (s == "time" || s == "")
        o.v = TIME;
    else if (s == "verb")
        o.v = VERB;
    else {
        std::cout << "Invalid value passed to -v '" << s << "'\n";
        exit(1);
    }
#else
    s = getArg("-bench", false, false);
    if (o.oindex == "" && o.orlcp == "" && o.otsv == "" && s == "") {
        std::cout << "No output formats passed. If you want to construct the index but not output anything (for benchmarking purposes, typically), then '-bench' must be explictly passed.\n";
        exit(1);
    }
#endif
    for (int i = 0; i < argc; ++i)
        if (!used[i]) {
            std::cout << "Argument " << i << ", '" << argv[i] << "' not recognized or used as an argument for another option. It might have been passed more than once (invalid).\n";
            exit(1);
        }
    testInFile(o.inputFile);
    testInFile(o.tempFile);
    testOutFile(o.tempFile);
    testOutFile(o.oindex);
    testOutFile(o.orlcp);
    testOutFile(o.otsv);
}

int main(const int argc, const char*argv[]) {
    processOptions(argc, argv);
    omp_set_num_threads(o.numThreads);
    #ifndef BENCHFASTONLY
    if (o.v >= TIME) { Timer.start("TeraLCP"); }
    if (o.v >= TIME) { Timer.start("Program Initialization"); }
    #endif
    rb3_fmi_t fmi;
    {
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.start("Reading Arguments"); }
        #endif
        if (o.inputFormat != options::fmd && o.inputFormat != options::lcp_index) {
            std::cerr << "Only fmd and lcp_index input currently implemented!" << std::endl;
            exit(1);
        }
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.stop(); } //Reading Arguments 
        #endif
        if (o.inputFormat == options::fmd) {
            #ifndef BENCHFASTONLY
            if (o.v >= TIME) { Timer.start((o.mmap)? "Loading fmd with mmap" : "Loading fmd"); }
            #endif

            rb3_fmi_restore(&fmi, o.inputFile.c_str(), o.mmap);
            if (fmi.e == 0 && fmi.r == 0) {
                std::cerr << "ERROR: failed to load fmd from index file " << o.inputFile << std::endl;
                exit(1);
            }

            #ifndef BENCHFASTONLY
            if (o.v >= TIME) { Timer.stop(); } //(o.mmap)? "Loading fmd with mmap" : "Loading fmd" 
            #endif

            if (!TeraLCP::validateRB3(&fmi)) {
                std::cerr << "ERROR: invalid ropebwt3 inputted!" << std::endl;
                exit(1);
            }
        }
    }
    #ifndef BENCHFASTONLY
    if (o.v >= TIME) { Timer.stop(); } //Program Initialization 
    #endif

    TeraLCP ourIndex;
    if (o.inputFormat == options::fmd) {
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.start("LCP index construction"); }
        #endif
        ourIndex = TeraLCP(&fmi, o.tempFile
                #ifndef BENCHFASTONLY
                , o.v
                #endif
                );
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.stop(); } //LCP index construction 
        #endif
    }
    else if (o.inputFormat == options::lcp_index) {
        ourIndex = TeraLCP(o.inputFile, o.v);
    }


    if (o.orlcp != "") {
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.start("min LCP per run computation"); }
        #endif
        std::ofstream lcpOut(o.orlcp);
        if (!lcpOut.is_open()) {
            std::cerr << "ERROR: File '" << o.orlcp << "' failed to open for writing!\n";
            exit(1);
        }
        auto l = ourIndex.ComputeMinLCPRunParallelDestructive(o.v);
        assert(l.first.size() == l.second.size());
        uint64_t runs = l.first.size();
        if (o.v >= TIME) { Timer.start("sequential output min LCP per run"); }
        for (uint64_t i = 0; i < runs; ++i) 
            lcpOut << "( " << l.first[i] << ", " << l.second[i] << ")\n";
        if (o.v >= TIME) { Timer.stop(); } //sequential output min LCP per run
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.stop(); } //min LCP per run computation
        #endif
    }

    // Handle TSV / MONI-style thresholds output
    if (o.otsv != "") {
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.start("run LCP / thresholds output"); }
        #endif
        TeraLCP::RunLCPMode mode = TeraLCP::RunLCPMode::top;
        try {
            mode = TeraLCP::parseRunLCPMode(o.tsvmode);
        } catch (const std::exception& e) {
            std::cerr << "ERROR: " << e.what() << std::endl;
            exit(1);
        }
        if (mode == TeraLCP::RunLCPMode::thresholds) {
            std::string base = o.otsv;
            ourIndex.writeThresholds(base, o.threshbound);
        } else {
            std::ofstream runLcpOut(o.otsv);
            if (!runLcpOut.is_open()) {
                std::cerr << "ERROR: File '" << o.otsv << "' failed to open for writing!\n";
                exit(1);
            }
            ourIndex.writeRunLCP(runLcpOut, mode);
            runLcpOut.close();
        }
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.stop(); } //run LCP / thresholds output
        #endif
    }

    /*
    if (o.v >= TIME) { Timer.start("Printing Raw"); }
    ourIndex.printRaw();
    if (o.v >= TIME) { Timer.stop(); } //Printing Raw 
    */

    #ifndef BENCHFASTONLY
    if (o.v >= TIME) { Timer.start("Measure size"); }
    if (o.v >= VERB) { std::cout << "Size of our index: " << sdsl::size_in_bytes(ourIndex) << std::endl; }
    if (o.v >= TIME) { Timer.stop(); } //Measure size 
    #endif


    if (o.oindex != "") {
        std::ofstream indOut;
        indOut.open(o.oindex);
        if (!indOut.is_open()) {
            std::cerr << "ERROR: File '" << o.oindex << ".optbwtrl' failed to open for writing!\n";
            exit(1);
        }
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.start("Writing Index"); }
        #endif
        ourIndex.serialize(indOut);
        indOut.close();
        #ifndef BENCHFASTONLY
        if (o.v >= TIME) { Timer.stop(); } //Writing Index 
        #endif
    }

    /*
    #ifndef BENCHFASTONLY
    if (o.v >= TIME) { Timer.start("Writing Structure Tree"); }
    #endif
    sdsl::write_structure<sdsl::HTML_FORMAT>(ourIndex, treeOut);
    treeOut.close();
    #ifndef BENCHFASTONLY
    if (o.v >= TIME) { Timer.stop(); } //Writing Structure Tree 
    #endif
    */

    #ifndef BENCHFASTONLY
    if (o.v >= TIME) { Timer.stop(); } //TeraLCP 
    #endif
}
