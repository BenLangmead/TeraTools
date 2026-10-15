/*
 * Writes a BWT as an FMD (ropebwt3's rld format) in which runs are split into
 * several adjacent rld entries with the same symbol, which rld_enc never
 * produces but a reader must accept. Used to test that TeraLCP's -ominima and
 * -ophi outputs still follow the BWT's maximal runs.
 *
 * Usage: fmd_split_writer BWT_FILE OUT.fmd SEED
 * BWT_FILE holds the BWT as the characters $ACGTN. About half of the maximal
 * non-separator runs of length l > 1 are written as 2 or 3 pieces, chosen by
 * SEED; separator runs are written whole.
 *
 * Built with the ropebwt3 sources on the include path; rld0.c is included so
 * that its static single-entry encoder rld_enc1 is available.
 */
#include "rld0.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc != 4) { fprintf(stderr, "Usage: fmd_split_writer BWT_FILE OUT.fmd SEED\n"); return 2; }
    FILE* f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    static char s[1 << 24];
    size_t n = fread(s, 1, sizeof(s), f);
    fclose(f);
    while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r')) --n;
    srand((unsigned)atoi(argv[3]));
    const char* alpha = "$ACGTN";
    rld_t* e = rld_init(6, 3);
    rlditr_t itr;
    rld_itr_init(e, &itr, 0);
    size_t i = 0;
    while (i < n) {
        size_t j = i + 1;
        while (j < n && s[j] == s[i]) ++j;
        const char* p = strchr(alpha, s[i]);
        if (!p || !s[i]) { fprintf(stderr, "bad symbol at %zu\n", i); return 2; }
        const int c = (int)(p - alpha);
        int64_t l = (int64_t)(j - i);
        if (c != 0 && l > 1 && rand() % 2) {
            /* 2 or 3 pieces with the same symbol. */
            int pieces = 2 + rand() % 2;
            if (pieces > l) pieces = (int)l;
            for (; pieces > 1; --pieces) {
                const int64_t take = 1 + rand() % (l - (pieces - 1));
                rld_enc1(e, &itr, take, (uint8_t)c);
                l -= take;
            }
            rld_enc1(e, &itr, l, (uint8_t)c);
        } else {
            rld_enc1(e, &itr, l, (uint8_t)c);
        }
        i = j;
    }
    rld_enc_finish(e, &itr);
    if (rld_dump(e, argv[2]) < 0) { fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    rld_destroy(e);
    return 0;
}
