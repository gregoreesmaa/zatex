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
    // kind selects the rule (C ABI order = contract.zig `RuleKind`
    // declaration order, bridged via @intFromEnum — NOT MATH-table
    // order, so fraction/over/under/radical is the wrong guess):
    //   0 = fraction_bar,
    //   1 = radical,
    //   2 = overline (also used for underlines today),
    //   3 = underline (reserved: never requested yet).
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
    // NULL reads 0 (upright accents). No right-side-bearing fallback
    // (issue #206 rejects it: measured RSB anti-correlates with MATH
    // corrections, and KaTeX reads the MATH value, never a bearing).
    int32_t (*italic_correction)(const void *ctx, uint16_t font, uint16_t glyph);
    // Optional (may be NULL, v3): MathKern cut-in for glyph at correction
    // height; corner: 0 top_right, 1 top_left, 2 bottom_right, 3 bottom_left.
    // Top-right tucks superscripts, bottom-right subscripts (clamped to
    // the script gap); other corners return 0. NULL/0: no cut-in.
    int32_t (*kern_correction)(const void *ctx, uint16_t font, uint16_t glyph, int32_t height, uint32_t corner);
    // Optional (may be NULL, v4): [height_above, depth_below] of glyph
    // at 1000 units (blank glyphs report [0, 0]). Null derives the
    // vertical slice of the ink box when one is present (issue #206:
    // ha = max(0, y1), db = max(0, -y0)), else keeps the uniform
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

// Frozen v1 run prefix (issue #203): the 20-byte head every host
// understands. Must match cabi.zig `CRunV1` field-for-field. The v1
// entry below fills arrays of exactly this shape; the `_ex` entry
// strides by the host's own element size.
typedef struct zatex_run_v1 {
    uint16_t font_id;
    uint16_t size_units;
    int32_t x;
    int32_t baseline_y;
    uint32_t glyph_start;
    uint32_t glyph_count;
} zatex_run_v1_t;

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
    // Written only when the host's run stride admits it (see
    // zatex_layout_utf8_ex): appending changes sizeof, so a new
    // dylib striding wider than an old host's slots would scramble
    // every run past the first (issue #203). Must match cabi.zig
    // `CRun` field-for-field.
    uint16_t x_scale;
    // Per-run paint in 0xRRGGBBAA (issue #251: `\color` scopes,
    // issue #35). 0 is the ambient (host default) paint — resolved
    // paints always carry opaque alpha, so 0 is unambiguous and
    // unstylized formulas cross exactly as before. Written only when
    // the host's run stride reaches past it (bytes 24..28, see
    // zatex_layout_utf8_ex); 24-stride hosts stay bit-identical.
    // (Layout: offset 24 — the 2-byte pad at 22..24 keeps this u32
    // 4-aligned — sizeof 28.) Must match cabi.zig `CRun`
    // field-for-field.
    uint32_t color;
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
// with status 7 (limit) without touching the runs buffer (the
// measured needs still cross in out->nruns/nrules — see status 6/7
// below). Status 6 (no_space) means need exceeds the smaller of
// caller buffers and these ceilings: growing caller buffers helps,
// up to the ceilings. Input is capped at 65536 bytes.
//
// Frozen v1 entry (issue #203): `runs` is an array of `runs_cap`
// 20-byte v1 slots (`zatex_run_v1_t`). The engine strides 20 and
// writes the v1 prefix only — never `x_scale`, never `color` — so
// hosts compiled against the old struct stay bit-identical across
// dylib updates (they draw unstretched in the ambient paint, exactly
// as before). Hosts compiled against the 28-byte `zatex_run_t` call
// `zatex_layout_utf8_ex`.
// (Declared with the v1 pointer type on purpose: passing a
// `zatex_run_t` array here warns and scrambles — stride 20 over
// 28-byte slots.)
int32_t zatex_layout_utf8(const char *src, size_t src_len, bool display_mode,
                          const zatex_metrics_t *metrics,
                          zatex_run_v1_t *runs, size_t runs_cap,
                          zatex_rule_t *rules, size_t rules_cap,
                          uint16_t *glyphs, size_t glyphs_cap,
                          zatex_layout_t *out);

// Stride-negotiated layout (issue #203): identical to
// `zatex_layout_utf8`, except `runs` elements are `runs_stride`
// bytes wide — pass sizeof() your run struct
// (`sizeof(zatex_run_t)`, 28 today).
//
// Stride contract: the engine writes the frozen v1 prefix (bytes
// 0..20) into every element, `x_scale` (bytes 20..22) only when
// `runs_stride >= 22`, and `color` (bytes 24..28) only when
// `runs_stride >= 28`; every other tail byte (including struct
// padding at 22..24) is left untouched. Strides below 20 fail with
// status 7 (limit) without touching the runs buffer. A future wider
// host struct keeps working: the engine never writes past its known
// 28 bytes and never strides wider than the host's own size.
//
// Pairing: hosts wanting `x_scale`/`color` need a dylib exporting
// this entry — dlsym() it and fall back to `zatex_layout_utf8` when
// absent (old dylib), drawing unstretched in the ambient paint — or
// negotiate once via zatex_capabilities() (issue #262) and branch on
// ZATEX_CAP_X_SCALE/ZATEX_CAP_RUN_COLOR. The v1 entry is safe with
// any dylib/host mix.
int32_t zatex_layout_utf8_ex(const char *src, size_t src_len, bool display_mode,
                             const zatex_metrics_t *metrics,
                             zatex_run_t *runs, size_t runs_cap, size_t runs_stride,
                             zatex_rule_t *rules, size_t rules_cap,
                             uint16_t *glyphs, size_t glyphs_cap,
                             zatex_layout_t *out);

// Space-failure needs (issue #263): on status 6 (no_space) and
// status 7 (limit), out->nruns/nrules carry the counts the formula
// actually needs (rect-projected rule count — diagonal strikes have
// no rect form and are skipped), so hosts allocate exactly once
// instead of guess-and-double. Zeroed counts mean the need exceeds
// the engine ceilings (even maximum buffers cannot succeed — fail
// with a message) or the call never reached layout (null metrics or
// source). Allocate out->nruns runs and out->nrules rules and retry
// once: runs/rules needs are exact, so a second failure on the same
// input means the glyph buffer is short — grow it (a few thousand
// u16 covers every layable formula) and retry. A null runs/rules/
// glyphs buffer is a sizing probe: status stays 6 with the needs
// when measurable. Hosts tell meaningful zeros apart from an old
// dylib (which always zeroes) via ZATEX_CAP_NEED_COUNTS below.

// Capability word (issue #262): bitmask negotiated once, so hosts
// branch on capability bits instead of per-symbol dlsym() probing.
// The _ex pairing keeps working, but new extensions stop
// multiplying loader paths: probe this one symbol and fall back to
// the v1 surface when absent (old dylib: frozen prefix only, zeroed
// counts on space failures).
#define ZATEX_CAP_X_SCALE (1u << 0) // _ex tail x_scale (stride >= 22)
#define ZATEX_CAP_RUN_COLOR (1u << 1) // run color tail (stride >= 28)
#define ZATEX_CAP_NEED_COUNTS (1u << 2) // nruns/nrules needs on status 6/7
uint32_t zatex_capabilities(void);

// Packed semantic version, ABI-stable (issue #276): major << 16 |
// minor << 8 | patch with normative widths major 16 bits, minor 8
// bits, patch 8 bits (minor and patch stay below 256: a larger
// patch would bleed into minor — 0.0.300 would read as 0.1.44).
// Unpack with (w >> 16), ((w >> 8) & 0xFF), (w & 0xFF). Pre-1.0
// requires an exact match, not a range. Library version only — the
// provider word is separate.
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
