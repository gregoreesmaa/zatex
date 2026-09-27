// zatex_testdouble.h — scripted test double for hosts (issue #274).
//
// libzatex_test implements the SAME zatex.h entry points
// (zatex_layout_utf8, zatex_layout_utf8_ex, zatex_capabilities,
// zatex_version, zatex_conform_metrics) with deterministic scripted
// responses, so hosts exercise their OK and fallback paths in CI
// without hand-rolling engine stubs. No layout math lives here —
// only fixed scripted bytes — and the metrics hooks are never
// called (NULL hooks are fine).
//
// Drop-in usage: dlopen libzatex_test where you would dlopen
// libzatex (same symbols, same structs — this header includes
// zatex.h). Capabilities report X_SCALE | RUN_COLOR | NEED_COUNTS
// and the version packs 0.0.0, matching the source the double was
// cut from.
//
// Script inputs (pass exactly these bytes as the formula):
#ifndef ZATEX_TESTDOUBLE_H
#define ZATEX_TESTDOUBLE_H

#include "zatex.h"

// The hello-formula input: STATUS_OK with a fixed 3-run / 1-rule /
// 5-glyph layout (width 2100, above 900, below 350). Run 1 carries
// x_scale 2000 and run 2 carries color 0xFF0000FF, so `_ex` hosts
// observe tail delivery; v1 readers see the same heads.
#define ZATEX_TD_HELLO "\\frac{a}{b}+x^2"
// Forced STATUS_NO_SPACE with nruns/nrules needs, buffers
// untouched: grow the buffers (to at least the needs) and retry.
#define ZATEX_TD_NOSPACE "__ZATEX_TD_NOSPACE__"
// Forced STATUS_LIMIT with over-ceiling needs (300 runs, 70 rules):
// even maximum buffers cannot succeed — fail with a message.
#define ZATEX_TD_LIMIT "__ZATEX_TD_LIMIT__"
// Forced STATUS_INVALID with err_offset 5 and a static message:
// render the source plus the message bytes as real text (the
// throwOnError:false-style fallback).
#define ZATEX_TD_BAD "__ZATEX_TD_BAD__"

// Anything else is STATUS_INVALID (offset 0): the double only
// speaks its script. zatex_conform_metrics is scripted too: font 0
// is a clean pass (0), any other font carries 1 diagnostic, NULL
// metrics is a usage error (-1).

#endif
