#!/bin/sh
# size_gate.sh — distribution-size ratchet (issue 12).
#
# Measures the shipped on-disk static distribution artifact and ratchets
# its size: the artifact may never grow past the committed baseline
# (tools/size_baseline.txt). This is the real shipped artifact the
# consumer links, so the gate directly enforces the reduction goal in
# AGENTS.md (native, zero-deps, small binary footprint).
#
# We count raw on-disk bytes of `zig-out/lib/libzetex.a`, not the size
# of the full binary. The static archive is the full product: an
# archive can only grow when zetex's compiled output grows. It is not
# subject to the linker's segment accounting (`size -m` only reports
# the __TEXT segment, and that count can drift between macOS SDKs and
# linkers even when zetex's code is byte-identical). Reading the bytes
# directly sidesteps both.
#
# Platform: any where Zig works. CI pins macos-14 so the baseline is
# comparable run to run; the baseline is the committed ratchet regardless.
set -eu
cd "$(dirname "$0")/../packages/zatex"

BASELINE_FILE=../../tools/size_baseline.txt
UPDATE=0
if [ "${1:-}" = "--update-baseline" ]; then UPDATE=1; fi

# Build the default distribution artifact (full profile, shipped
# ReleaseSmall — see build.zig).
zig build
# Measure on-disk bytes. The static archive is a single opaque file,
# so `ls -l` reports the exact shipped artifact size; no per-segment
# math. (A glob is used so the command resolves even when the default
# artifact name does not survive a shell brace expansion on some hosts.)
SIZE=$(ls -l zig-out/lib/libz*.a | awk 'BEGIN{n=0} {if ($5 > n) n=$5} END{print n}')
baseline=$(cat "$BASELINE_FILE")

echo "static distribution artifact: $SIZE bytes (baseline $baseline)"
if [ "$UPDATE" = 1 ]; then
    echo "$SIZE" > "$BASELINE_FILE"
    echo "baseline updated to $SIZE"
    exit 0
fi
if [ "$SIZE" -gt "$baseline" ]; then
    echo "FAIL: shipped artifact grew by $((SIZE - baseline)) bytes; run tools/size_gate.sh --update-baseline only with reviewer approval" >&2
    exit 1
fi
echo "size gate OK"
