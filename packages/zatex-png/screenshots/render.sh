#!/bin/sh
# Render the screenshots regression corpus to PNGs.
# Usage: screenshots/render.sh [outdir] [px_per_em]
# Defaults: screenshots/png at 48 px per em (the checked-in baseline).
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
outdir=${1:-"$root/screenshots/png"}
px=${2:-48}
(cd "$root" && zig build)
# The CLI resolves its default font relative to the working directory.
cd "$root"
exec "$root/zig-out/bin/zatex-png" \
    --corpus "$root/screenshots/corpus.json" \
    --outdir "$outdir" --px "$px"
