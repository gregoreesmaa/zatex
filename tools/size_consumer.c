// Subset-profile size-gate consumer: exercises exactly the `subset`
// surface (issue 12: sup/sub, frac, sqrt, sum/int/lim, Greek + common
// symbols, `\text`) through the C ABI so the linker keeps the real
// subset closure and strips everything else.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "zatex.h"

static uint16_t gid(const void *ctx, uint16_t font, uint32_t cp) {
    (void)ctx;
    (void)font;
    return (uint16_t)(cp & 0xFFFF);
}
static int32_t adv(const void *ctx, uint16_t font, uint16_t glyph) {
    (void)ctx;
    (void)font;
    (void)glyph;
    return 500;
}
static int32_t rule(const void *ctx, uint16_t font, uint32_t kind) {
    (void)ctx;
    (void)font;
    (void)kind;
    return 50;
}

static const char *const kCorpus[] = {
    "x^2 + y_1",
    "\\frac{a}{b}",
    "\\sqrt{x+1}",
    "\\sum_{i=1}^{n} i",
    "\\int_0^1 x\\,dx",
    "\\lim_{x\\to 0} f(x)",
    "\\alpha + \\beta = \\gamma",
    "\\text{for all } x",
    "a \\times b \\cdot c",
};

int main(void) {
    zatex_metrics_t m = {0, gid, adv, rule, 0, 0};
    zatex_run_t runs[64];
    zatex_rule_t rules[16];
    uint16_t glyphs[512];
    char mbuf[2048];
    uint64_t hash = 1469598103934665603ULL;
    for (size_t i = 0; i < sizeof(kCorpus) / sizeof(kCorpus[0]); i++) {
        zatex_layout_t lay;
        int32_t st = zatex_layout_utf8(kCorpus[i], strlen(kCorpus[i]), 0,
                                       &m, runs, 64, rules, 16, glyphs, 512, &lay);
        hash ^= (uint64_t)(st + lay.width + lay.nruns);
        hash *= 1099511628211ULL;
        ptrdiff_t n = zatex_mathml_utf8(kCorpus[i], strlen(kCorpus[i]), 0, mbuf, sizeof mbuf);
        hash ^= (uint64_t)(n + (n > 0 ? mbuf[0] + mbuf[n - 1] : 0));
        hash *= 1099511628211ULL;
    }
    hash ^= zatex_version();
    printf("%llx\n", (unsigned long long)hash);
    return 0;
}
