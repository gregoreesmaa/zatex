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

// [height_above, depth_below] at 1000 units. Must match cabi.zig
// `CExtents` field-for-field.
typedef struct zatex_extents {
    int32_t ha, db;
} zatex_extents_t;

// True ink box at 1000 units, y up from the baseline. Must match
// cabi.zig `CInkBox` field-for-field.
typedef struct zatex_inkbox {
    int32_t x0, y0, x1, y1;
} zatex_inkbox_t;

typedef struct zatex_metrics {
    const void *ctx;
    // Glyph id for (font, codepoint). Id 0 means missing (issue
    // #142): the core still lays the run out, so boxes/tofu on screen
    // mean this callback returned 0 — log the (font, cp) pairs to
    // enumerate coverage (see docs/parity.md font troubleshooting).
    uint16_t (*glyph_id)(const void *ctx, uint16_t font, uint32_t cp);
    // Per-hook exactness contract (issue #193; normative text in
    // contract.zig, host guide in docs/ir.md). Every numeric value is
    // in thousandths of an em; the core scales to the ambient size.
    // advance: hmtx bit-for-bit, INCLUDING 0 for zero-width combining
    // marks (e.g. U+20D7). The core branches on adv == 0 (ink-center
    // vs advance-box accent path): a nonzero fallback for zero-width
    // glyphs mis-centers accents by ~half an em. The bridge's 500 for
    // a NULL advance hook is totality, not correctness.
    int32_t (*advance)(const void *ctx, uint16_t font, uint16_t glyph);
    // kind: 0 fraction_bar, 1 radical, 2 overline, 3 underline.
    // Thousandths; <= 0 reads as 40 (floored further by the caller's
    // min_rule_thickness option).
    int32_t (*rule_thickness)(const void *ctx, uint16_t font, uint32_t kind);
    // Optional (may be NULL): taller glyph variant whose extent is at
    // least min_height (thousandths), or the input glyph when unknown.
    // Feeds fences and radicals; always-identity under-grows them.
    uint16_t (*glyph_variant)(const void *ctx, uint16_t font, uint16_t glyph, int32_t min_height);
    // Optional (may be NULL): OpenType MATH italic correction scaled to
    // thousandths (truncate toward zero). The core looks it up on the
    // laid-out glyph, halves it, and adds the KaTeX Math-Italic skew;
    // NULL reads 0 (upright accents).
    int32_t (*italic_correction)(const void *ctx, uint16_t font, uint16_t glyph);
    // Optional (may be NULL, v3): MathKern cut-in for glyph at correction
    // height; corner: 0 top_right, 1 top_left, 2 bottom_right, 3 bottom_left.
    // Top-right tucks superscripts, bottom-right subscripts (clamped to
    // the script gap); other corners return 0. NULL/0: no cut-in.
    int32_t (*kern_correction)(const void *ctx, uint16_t font, uint16_t glyph, int32_t height, uint32_t corner);
    // Optional (may be NULL, v4): [height_above, depth_below] of glyph
    // at 1000 units (blank glyphs report [0, 0]). Null keeps the uniform
    // 700/250 approximation, bit-identical to v3. True extents shift
    // vertical clearance (e.g. accent clearance) versus the reference.
    zatex_extents_t (*extents)(const void *ctx, uint16_t font, uint16_t glyph);
    // Optional (may be NULL, v4): true ink box at 1000 units, y up from
    // the baseline, unclipped — negatives preserved (blank glyphs
    // report all zeros, which the core ignores). Feeds accent
    // ink-centering, low-accent lift (>= 130 clear), wide-accent ink
    // scaling, dot lift, brace kerns, and the sqrt junction. Null
    // keeps exact v3 behavior per construct (e.g. advance-edge
    // vinculum starts).
    zatex_inkbox_t (*ink_bounds)(const void *ctx, uint16_t font, uint16_t glyph);
} zatex_metrics_t;

typedef struct zatex_run {
    uint16_t font_id;
    uint16_t size_units;
    int32_t x;
    int32_t baseline_y;
    uint32_t glyph_start;
    uint32_t glyph_count;
    // Horizontal raster scale in per-mille (1000 = identity), the
    // ir.Run.x_scale stretch factor (issue #197: wide accents,
    // braces, arrows). The host stretches the run's ink AND its
    // intra-run pen advances by x_scale/1000 about the run origin
    // (x, baseline_y) — CoreText: save, translate to the origin,
    // scale x, draw, restore (same recipe as zatex-png render.zig).
    // Appended — old readers ignore the tail and draw unstretched,
    // exactly as before. Must match cabi.zig `CRun` field-for-field.
    uint16_t x_scale;
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

// Host metrics conformance check (issue #194): runs the diagnostic
// corpus against the host's metrics at font id `font` — no rendering,
// no engine rebuild. Returns the diagnostic count (0 is a clean pass;
// -1 is a usage error: null metrics, or non-null buf with zero cap).
// When buf is non-null, newline-separated diagnostics fill
// buf[0..buf_cap], truncated to fit and always NUL-terminated (pass a
// null buf to count only). Expectations are calibrated for rm (font
// 0) on the reference font; see docs/ir.md "Metrics conformance".
int32_t zatex_conform_metrics(const zatex_metrics_t *metrics, uint16_t font,
                              char *buf, size_t buf_cap);

#ifdef __cplusplus
}
#endif

#endif
