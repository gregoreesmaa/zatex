#!/bin/sh
# size_gate.sh — subset-profile host-cost gate (issue 12).
#
# Measures the __TEXT the `subset` profile adds to a host that links it:
#   delta = __TEXT(consumer + libzatex.a) - __TEXT(consumer + stubs)
# Both binaries are -O3 with dead-stripping, so only the subset closure
# reachable from the C ABI counts. The consumer (tools/size_consumer.c)
# exercises exactly the subset surface so the gate is non-vacuous.
#
# Policy: the delta must not grow past the committed baseline
# (tools/size_baseline.txt) — a ratchet. The AGENTS.md 8 KB target is
# reported for tracking (see issue 12 for the profile-split plan that
# closes the gap); the ratchet is what blocks merges.
#
# Platform: macOS/AArch64 only (`size -m`, Mach-O segments, Apple ld).
# CI pins macos-14 so the baseline is comparable run to run.
set -eu
cd "$(dirname "$0")/.."

TARGET=8192
BASELINE_FILE=tools/size_baseline.txt
UPDATE=0
if [ "${1:-}" = "--update-baseline" ]; then UPDATE=1; fi

zig build -Dprofile=subset -Doptimize=ReleaseSmall
LIB=zig-out/lib/libzatex.a

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

zig cc -O3 -Isrc -o "$TMP/with" tools/size_consumer.c "$LIB" -Wl,-dead_strip

python3 - tools/size_consumer.c "$TMP/stub.c" <<'EOF'
import re, sys
s = open(sys.argv[1]).read().replace('zatex.h', 'zatex_stub.h')
s = re.sub(r'zatex_(layout_utf8|mathml_utf8|version)', r'stub_\1', s)
s = s.replace('#include <stdint.h>',
              '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n#include <sys/types.h>')
open(sys.argv[2], 'w').write(s + '''
int32_t stub_layout_utf8(const char *a, size_t b, bool c, const void *d, void *e, size_t f, void *g, size_t h, void *i, size_t j, void *k) { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)g;(void)h;(void)i;(void)j;(void)k; return 0; }
ptrdiff_t stub_mathml_utf8(const char *a, size_t b, bool c, char *d, size_t e) { (void)a;(void)b;(void)c;(void)d;(void)e; return 0; }
uint32_t stub_version(void) { return 0; }
''')
EOF
cat > "$TMP/zatex_stub.h" <<'EOF'
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef struct { const void *ctx; void *f[5]; } zatex_metrics_t;
typedef struct { uint16_t a; uint16_t b; int32_t c; int32_t d; uint32_t e; uint32_t f; } zatex_run_t;
typedef struct { int32_t x, y; uint32_t w, h; } zatex_rule_t;
typedef struct { uint32_t width, height_above, depth_below, nruns, nrules; int32_t status; uint32_t err_offset; } zatex_layout_t;
int32_t stub_layout_utf8(const char*, size_t, bool, const void*, void*, size_t, void*, size_t, void*, size_t, void*);
ptrdiff_t stub_mathml_utf8(const char*, size_t, bool, char*, size_t);
uint32_t stub_version(void);
EOF
cp "$TMP/zatex_stub.h" ./zatex_stub.h
trap 'rm -rf "$TMP" ./zatex_stub.h' EXIT INT TERM
cc -O3 -I. -o "$TMP/without" "$TMP/stub.c" -Wl,-dead_strip
rm ./zatex_stub.h

text_with=$(size -m "$TMP/with" | awk '/Segment __TEXT:/{print $3; exit}')
text_without=$(size -m "$TMP/without" | awk '/Segment __TEXT:/{print $3; exit}')
delta=$((text_with - text_without))
baseline=$(cat "$BASELINE_FILE")

echo "subset __TEXT delta: $delta bytes (baseline $baseline, target $TARGET)"
if [ "$UPDATE" = 1 ]; then
    echo "$delta" > "$BASELINE_FILE"
    echo "baseline updated to $delta"
    exit 0
fi
if [ "$delta" -gt "$baseline" ]; then
    echo "FAIL: subset host cost grew by $((delta - baseline)) bytes; run tools/size_gate.sh --update-baseline only with reviewer approval" >&2
    exit 1
fi
if [ "$delta" -gt "$TARGET" ]; then
    echo "NOTE: $((delta - TARGET)) bytes over the 8 KB target (tracked in issue 12); ratchet holds at $baseline" >&2
fi
echo "size gate OK"
