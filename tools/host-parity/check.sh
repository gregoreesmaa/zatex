#!/bin/sh
# check.sh — host render-parity check (issue #258).
#
# Re-renders the kit corpus with the pinned configuration and fails on
# real pixel drift, so a host proves pixel parity in an afternoon and
# CI proves the kit itself never rots.
#
# Pinned configuration (see README.md): the software backend (pure Zig,
# no OS text stack) over the single vendored Latin Modern Math face at
# 48 px per em. Layout is deterministic (dimensions must match
# exactly); antialiasing coverage may vary by a few levels, so
# comparison is tolerant (tools/compare_shots.py), never byte equality.
#
# Usage: tools/host-parity/check.sh [outdir]
# Must run from the repository root.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
outdir=${1:-"$root/tools/host-parity/fresh"}
(cd "$root/packages/zatex-png" && zig build -Dbackend=software)
./packages/zatex-png/zig-out/bin/zatex-png \
    --corpus "$root/tools/host-parity/corpus.json" \
    --outdir "$outdir" --px 48 \
    --font "$root/packages/zatex/fixtures/fonts/latinmodern-math.otf"
python3 "$root/tools/compare_shots.py" "$root/tools/host-parity/reference" "$outdir"
