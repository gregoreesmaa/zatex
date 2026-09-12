// matex.h — MaTeX C ABI (issue 9). Reentrant, zero-allocation.
//
// All buffers are caller-owned. Runs reference the caller's glyph
// buffer by (start, count) indices: outputs stay valid as long as the
// caller's buffers do. Status codes mirror LayoutError. Positions are
// integer font units; y grows downward from the formula top-left and
// glyphs sit on their alphabetic baseline (see docs/ir.md).
#ifndef MATEX_H
#define MATEX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct matex_metrics {
    const void *ctx;
    uint16_t (*glyph_id)(const void *ctx, uint16_t font, uint32_t cp);
    int32_t (*advance)(const void *ctx, uint16_t font, uint16_t glyph);
    // kind: 0 fraction_bar, 1 radical, 2 overline, 3 underline
    int32_t (*rule_thickness)(const void *ctx, uint16_t font, uint32_t kind);
    // Optional (may be NULL): taller glyph variant, italic correction.
    uint16_t (*glyph_variant)(const void *ctx, uint16_t font, uint16_t glyph, int32_t min_height);
    int32_t (*italic_correction)(const void *ctx, uint16_t font, uint16_t glyph);
} matex_metrics_t;

typedef struct matex_run {
    uint16_t font_id;
    uint16_t size_units;
    int32_t x;
    int32_t baseline_y;
    uint32_t glyph_start;
    uint32_t glyph_count;
} matex_run_t;

typedef struct matex_rule {
    int32_t x, y;
    uint32_t w, h;
} matex_rule_t;

typedef struct matex_layout {
    uint32_t width, height_above, depth_below;
    uint32_t nruns, nrules;
    int32_t status; // 0 ok, 1 unsupported, 2 invalid, 3 too_deep,
                    // 4 too_long, 5 expansion_limit, 6 no_space
    uint32_t err_offset; // byte offset on invalid
} matex_layout_t;

// Caps: at most 256 runs / 64 rules per call even when the caller
// buffers are larger (STATUS_NO_SPACE beyond that).
int32_t matex_layout_utf8(const char *src, size_t src_len, bool display_mode,
                          const matex_metrics_t *metrics,
                          matex_run_t *runs, size_t runs_cap,
                          matex_rule_t *rules, size_t rules_cap,
                          uint16_t *glyphs, size_t glyphs_cap,
                          matex_layout_t *out);

// MathML Core serialization. Returns bytes written, or -status.
ptrdiff_t matex_mathml_utf8(const char *src, size_t src_len, bool display_mode,
                            char *out, size_t out_cap);

// Packed semantic version: major << 16 | minor << 8 | patch.
uint32_t matex_version(void);

#ifdef __cplusplus
}
#endif

#endif
