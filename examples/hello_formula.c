// hello_formula.c — minimal C example host (issue #257).
//
// Loads the blessed file provider, lays out one formula, prints the
// runs/rules. The whole C embedding contract in ~150 lines: build it
// with `zig build hello` (in packages/zatex) and run it from there:
//
//   ./zig-out/bin/hello-formula [font.otf] ["<tex>"]
//
// Defaults: the vendored Latin Modern Math face and `\frac{a}{b}+x^2`.
// Exit 0 prints the layout; exit 1 is a usage, font, or layout error
// (all three look the same to a host: report and stop).
//
// Linking: this file plus the host bridge (fileprovider_c.zig compiled
// to a static lib, which brings the engine along) — see the `hello`
// step in packages/zatex/build.zig. Link EITHER the bridge OR
// libzatex.a into one binary, never both (duplicate symbols).
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "zatex.h"
#include "zatex_fileprovider.h"

#define MAX_RUNS 256
#define MAX_RULES 64
#define MAX_GLYPHS 4096

static const char *fp_code_name(int code) {
    switch (code) {
    case ZATEX_FP_OK: return "ok";
    case ZATEX_FP_BAD_ARG: return "bad argument";
    case ZATEX_FP_NO_MEMORY: return "out of memory";
    case ZATEX_FP_NOT_A_FONT: return "not a font";
    case ZATEX_FP_IO: return "unreadable file";
    case ZATEX_FP_TOO_BIG: return "file over the cap";
    default: return "unknown";
    }
}

static const char *layout_status_name(int32_t status) {
    switch (status) {
    case 0: return "ok";
    case 1: return "unsupported";
    case 2: return "invalid";
    case 3: return "too deep";
    case 4: return "too long";
    case 5: return "expansion limit";
    case 6: return "no space (grow the buffers)";
    case 7: return "limit (over the engine ceilings)";
    default: return "unknown";
    }
}

int main(int argc, char **argv) {
    const char *font_path = (argc > 1) ? argv[1] : "fixtures/fonts/latinmodern-math.otf";
    const char *tex = (argc > 2) ? argv[2] : "\\frac{a}{b}+x^2";
    if (argc > 3) {
        fprintf(stderr, "usage: hello-formula [font.otf] [\"<tex>\"]\n");
        return 1;
    }

    // 1. Font bytes in: the blessed provider answers every hook from
    //    the file (cmap, hmtx, MATH table, outline ink) — no font
    //    parsing on the host side. The handle owns its copy.
    int code = ZATEX_FP_OK;
    zatex_fp_t *fp = zatex_fp_load_path(font_path, &code);
    if (fp == NULL) {
        fprintf(stderr, "hello: cannot open %s: %s\n", font_path, fp_code_name(code));
        return 1;
    }

    // 2. Ready metrics out: one plain struct, all hooks filled.
    zatex_metrics_t metrics;
    zatex_fp_metrics(fp, &metrics);

    // 3. Optional self-test: the #194 corpus over this struct. A lone
    //    Latin Modern file misses U+203E (it lives in the full stack's
    //    KaTeX Main face), so nonzero here is informational, not fatal
    //    — full-stack hosts demand zero.
    char diag[4096];
    int32_t n_bad = zatex_conform_metrics(&metrics, 0, diag, sizeof(diag));
    if (n_bad < 0) {
        fprintf(stderr, "hello: conformance misuse\n");
        zatex_fp_free(fp);
        return 1;
    }
    printf("provider: %s conform diagnostics: %" PRId32 "\n", font_path, n_bad);
    if (n_bad > 0) fwrite(diag, 1, strlen(diag), stdout);

    // 4. Lay out: caller-owned buffers, indices into `glyphs`, no
    //    allocation inside. The `_ex` entry strides runs by our own
    //    struct size so wider fields (x_scale) stay aligned.
    static zatex_run_t runs[MAX_RUNS];
    static zatex_rule_t rules[MAX_RULES];
    static uint16_t glyphs[MAX_GLYPHS];
    zatex_layout_t out;
    memset(&out, 0, sizeof(out));
    zatex_layout_utf8_ex(tex, strlen(tex), false, &metrics,
                         runs, MAX_RUNS, sizeof(runs[0]),
                         rules, MAX_RULES, glyphs, MAX_GLYPHS, &out);
    if (out.status != 0) {
        fprintf(stderr, "hello: layout %s", layout_status_name(out.status));
        if (out.err_msg_len > 0) fprintf(stderr, " at byte %u: %.*s", out.err_offset, (int)out.err_msg_len, out.err_msg);
        fprintf(stderr, "\n");
        zatex_fp_free(fp);
        return 1;
    }

    // 5. Draw (here: print). Runs reference `glyphs` by (start,
    //    count); rules are filled rects in font units, y down from
    //    the formula top-left. y grows downward; glyphs sit on their
    //    alphabetic baseline (see docs/ir.md).
    printf("formula: %s\n", tex);
    printf("extents: width=%u above=%u below=%u runs=%u rules=%u\n",
           out.width, out.height_above, out.depth_below, out.nruns, out.nrules);
    for (uint32_t i = 0; i < out.nruns; i++) {
        printf("run %u: font=%u size=%u x=%d baseline=%d x_scale=%u glyphs=[",
               i, runs[i].font_id, runs[i].size_units,
               runs[i].x, runs[i].baseline_y, runs[i].x_scale);
        for (uint32_t j = 0; j < runs[i].glyph_count; j++) {
            printf("%s%u", j ? "," : "", glyphs[runs[i].glyph_start + j]);
        }
        printf("]\n");
    }
    for (uint32_t i = 0; i < out.nrules; i++) {
        printf("rule %u: x=%d y=%d w=%u h=%u\n",
               i, rules[i].x, rules[i].y, rules[i].w, rules[i].h);
    }

    zatex_fp_free(fp);
    return 0;
}
