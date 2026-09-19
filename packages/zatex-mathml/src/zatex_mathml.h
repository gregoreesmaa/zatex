// zatex_mathml.h — zatex-mathml C ABI. Reentrant, zero-allocation.
//
// Caller-owned output buffer; returns bytes written, or a negative
// status (0 ok, 1 unsupported, 2 invalid, 3 too_deep, 4 too_long,
// 5 expansion_limit, 6 no_space — same integers as the core ABI).
// Link libzatex_mathml alongside libzatex (the core no longer
// provides this entry).
#ifndef ZATEX_MATHML_H
#define ZATEX_MATHML_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MathML Core serialization. Returns bytes written, or -status.
ptrdiff_t zatex_mathml_utf8(const char *src, size_t src_len, bool display_mode,
                            char *out, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif
