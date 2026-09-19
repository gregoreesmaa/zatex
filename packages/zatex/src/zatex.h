// zatex.h — ZaTeX C ABI (issue 9). Reentrant, zero-allocation.
//
// All buffers are caller-owned. Runs reference the caller's glyph
// buffer by (start, count) indices: outputs stay valid as long as the
// caller's buffers do. Status codes mirror LayoutError. Positions are
// integer font units; y grows downward from the formula top-left and
// glyphs sit on their alphabetic baseline (see docs/ir.md).
#ifndef ZATEX_H
#define ZATEX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct zatex_metrics {
    const void *ctx;
    // Glyph id for (font, codepoint). Id 0 means missing (issue
    // #142): the core still lays the run out, so boxes/tofu on screen
    // mean this callback returned 0 — log the (font, cp) pairs to
    // enumerate coverage (see docs/parity.md font troubleshooting).
    uint16_t (*glyph_id)(const void *ctx, uint16_t font, uint32_t cp);
    int32_t (*advance)(const void *ctx, uint16_t font, uint16_t glyph);
    // kind: 0 fraction_bar, 1 radical, 2 overline, 3 underline
    int32_t (*rule_thickness)(const void *ctx, uint16_t font, uint32_t kind);
    // Optional (may be NULL): taller glyph variant, italic correction.
    uint16_t (*glyph_variant)(const void *ctx, uint16_t font, uint16_t glyph, int32_t min_height);
    int32_t (*italic_correction)(const void *ctx, uint16_t font, uint16_t glyph);
    // Optional (may be NULL, v3): MathKern cut-in for glyph at correction
    // height; corner: 0 top_right, 1 top_left, 2 bottom_right, 3 bottom_left.
    int32_t (*kern_correction)(const void *ctx, uint16_t font, uint16_t glyph, int32_t height, uint32_t corner);
} zatex_metrics_t;

typedef struct zatex_run {
    uint16_t font_id;
    uint16_t size_units;
    int32_t x;
    int32_t baseline_y;
    uint32_t glyph_start;
    uint32_t glyph_count;
} zatex_run_t;

typedef struct zatex_rule {
    int32_t x, y;
    uint32_t w, h;
} zatex_rule_t;

typedef struct zatex_layout {
    uint32_t width, height_above, depth_below;
    uint32_t nruns, nrules;
    int32_t status; // 0 ok, 1 unsupported, 2 invalid, 3 too_deep,
                    // 4 too_long, 5 expansion_limit, 6 no_space,
                    // 7 limit (request exceeds engine ceilings below)
    uint32_t err_offset; // byte offset on invalid
    // ParseError message on failure (issues #126/#136): err_msg
    // points at err_msg_len bytes of static storage (always valid,
    // never freed; NOT null-terminated — use the length). NULL/0 on
    // success or when no message applies. Appended — old readers
    // ignore the tail. Hosts building the throwOnError:false-style
    // fallback render the source plus these bytes as real text (see
    // docs/parity.md "Error fallback (host recipe)").
    const char *err_msg;
    size_t err_msg_len;
} zatex_layout_t;

// Caps: at most 256 runs / 64 rules per call; larger requests fail
// with status 7 (limit) without touching the buffers. Status 6
// (no_space) means need exceeds the smaller of caller buffers and
// these ceilings: growing caller buffers helps, up to the ceilings.
// Input is capped at 65536 bytes.
int32_t zatex_layout_utf8(const char *src, size_t src_len, bool display_mode,
                          const zatex_metrics_t *metrics,
                          zatex_run_t *runs, size_t runs_cap,
                          zatex_rule_t *rules, size_t rules_cap,
                          uint16_t *glyphs, size_t glyphs_cap,
                          zatex_layout_t *out);

// Packed semantic version: major << 16 | minor << 8 | patch.
uint32_t zatex_version(void);

#ifdef __cplusplus
}
#endif

#endif
