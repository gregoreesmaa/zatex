#!/bin/sh
# render-one <texfile> <display:0|1> <out.png> [--font PATH]
# Runs inside the zatex image: the repo is mounted at /repo (read-only),
# case I/O lives under /work. Builds zatex-png into /tmp on first use so
# the checkout stays clean.
set -eu
texfile=$1; display=$2; out=$3; font=${4:-}
if [ -z "$font" ]; then
  if [ -f /repo/packages/zatex/fixtures/fonts/latinmodern-math.otf ]; then
    font=/repo/packages/zatex/fixtures/fonts/latinmodern-math.otf
  elif [ -f /fonts/STIXTwoMath.otf ]; then
    font=/fonts/STIXTwoMath.otf
  else
    echo "zatex oracle: no font (LM fixture or /fonts/STIXTwoMath.otf)" >&2
    exit 1
  fi
fi
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-local-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
if [ ! -x /tmp/zp/bin/zatex-png ]; then
  (cd /repo/packages/zatex-png && zig build --prefix /tmp/zp)
fi
tex=$(cat "$texfile")
if [ "$display" = "1" ]; then dflag="--display"; else dflag=""; fi
exec /tmp/zp/bin/zatex-png $dflag \
    --px 48 --font "$font" "$tex" "$out"
