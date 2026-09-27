// zatex_fileprovider.h — C-callable blessed metrics provider (issue #256).
//
// Font bytes or a font path in, ready `zatex_metrics_t` out: a new C
// host goes from zero to first formula without reimplementing font
// plumbing (cmap ids, hmtx advances, MATH corrections, outline ink).
// Every value answers from the font file through the same code as the
// reference host, so advances/italic/ink match it bit-for-bit.
//
// This is HOST-side code: compiling it brings the engine along (the
// bridge links the same core the dist lib ships), so link EITHER this
// bridge OR libzatex.a into one binary — never both (duplicate
// symbols). Build: compile `fileprovider_c.zig` to a static lib with
// `zig build-lib fileprovider_c.zig -lc` (resolving its `zatex`,
// `otmath`, `fontstack`, `cff` imports), then `cc host.c libbridge.a`.
// The `hello` step in packages/zatex/build.zig is the worked example.
//
// Lifetime: every successful load returns an owned opaque handle.
// `zatex_fp_metrics` borrows it (the filled struct's `ctx` points at
// the handle); the struct stays valid until `zatex_fp_free`. Handles
// are independent (no globals): two fonts means two handles. Neither
// entry allocates after load; every query is bounded like the core.
#ifndef ZATEX_FILEPROVIDER_H
#define ZATEX_FILEPROVIDER_H

#include <stddef.h>
#include <stdint.h>

#include "zatex.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct zatex_fp zatex_fp_t;

// Load status: 0 is success, anything else means NULL was returned.
enum {
    ZATEX_FP_OK = 0,
    ZATEX_FP_BAD_ARG = 1,  // NULL bytes (len > 0), NULL path/code misuse
    ZATEX_FP_NO_MEMORY = 2,
    ZATEX_FP_NOT_A_FONT = 3, // bytes are not a font (never a panic)
    ZATEX_FP_IO = 4,         // path unreadable (load_path only)
    ZATEX_FP_TOO_BIG = 5     // file over the 64 MiB input cap
};

// Copy `len` bytes and open the font inside. The copy is owned: the
// caller may free or reuse `bytes` immediately after return.
zatex_fp_t *zatex_fp_load_bytes(const uint8_t *bytes, size_t len, int *code);

// Read the whole file at `path` (absolute, or relative to the process
// working directory) and open the font inside. Missing/unreadable
// files report ZATEX_FP_IO; corrupt ones ZATEX_FP_NOT_A_FONT.
zatex_fp_t *zatex_fp_load_path(const char *path, int *code);

// Fill `*out` with the ready provider (all eight hooks non-NULL; its
// `ctx` borrows the handle). No-op on NULL arguments. The struct is a
// plain value: copy it, store it, pass its address to
// `zatex_layout_utf8*` and `zatex_conform_metrics`.
void zatex_fp_metrics(const zatex_fp_t *fp, zatex_metrics_t *out);

// Destroy the handle and its owned bytes. NULL is a no-op. After this
// every `zatex_metrics_t` filled from the handle dangles.
void zatex_fp_free(zatex_fp_t *fp);

// Self-test recipe (no new ABI): the filled struct feeds the existing
// conformance entry directly —
//   zatex_fp_metrics(fp, &m);
//   char buf[4096]; int32_t n = zatex_conform_metrics(&m, 0, buf, sizeof buf);
// `n == 0` is a clean pass; otherwise `buf` holds newline-separated
// diagnostics. Expectations are calibrated for rm (font 0) on the
// reference font (see docs/ir.md "Metrics conformance").

#ifdef __cplusplus
}
#endif

#endif
