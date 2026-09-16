#!/bin/sh
# render-one <texfile> <display:0|1> <out.png> [--font PATH]
# render-one batch <workdir> [--font PATH]   (issue #69: one build and
#   one container for the whole cases.tsv instead of one per case)
# Runs inside the zatex image: the repo is mounted at /repo (read-only),
# case I/O lives under /work. Builds zatex-png into /tmp on first use so
# the checkout stays clean.
set -eu
if [ "${1:-}" = batch ]; then
  work=$2; font=${3:-}
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
  export ZIG_LOCAL_CACHE_DIR=/tmp/zp/cache/local
  export ZIG_GLOBAL_CACHE_DIR=/tmp/zp/cache/global
  # One build for the whole batch (see below).
  (cd /repo/packages/zatex-png && zig build --prefix /tmp/zp)
  fail=0
  while read -r id display; do
    [ -n "$id" ] || continue
    echo "== $id"
    tex=$(cat "$work/$id.tex")
    if [ "$display" = "1" ]; then dflag="--display"; else dflag=""; fi
    /tmp/zp/bin/zatex-png $dflag \
        --px 48 --font "$font" "$tex" "$work/$id.zatex.png" || fail=1
  done < "$work/cases.tsv"
  exit $fail
fi
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
export ZIG_LOCAL_CACHE_DIR=/tmp/zp/cache/local
export ZIG_GLOBAL_CACHE_DIR=/tmp/zp/cache/global
# Always build: /tmp/zp persists on a named volume (see compose.yml), so
# a warm cache makes the no-change rebuild seconds; skipping the build
# when a binary exists would test a stale checkout after tree changes.
(cd /repo/packages/zatex-png && zig build --prefix /tmp/zp)
tex=$(cat "$texfile")
if [ "$display" = "1" ]; then dflag="--display"; else dflag=""; fi
exec /tmp/zp/bin/zatex-png $dflag \
    --px 48 --font "$font" "$tex" "$out"
