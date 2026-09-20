#!/bin/sh
# render-one <texfile> <display:0|1> <out.png> [--font PATH]
# render-one batch <workdir> [--font PATH]   (issue #69: one build and
#   one container for the whole cases.tsv instead of one per case)
# Runs inside the zatex image: the repo is mounted at /repo (read-only),
# case I/O lives under /work. Builds zatex-png into /tmp on first use so
# the checkout stays clean.
#
# Font policy (issue #195): default is the full fixture stack — no
# --font is passed, so zatex-png loads its default stack (Latin Modern
# first, then the KaTeX faces including Size1/Size2, then system STIX)
# and every Size/AMS role resolves to KaTeX outlines exactly like the
# web oracle's bundled fonts. A single --font stays available only as
# an explicit opt-in for single-face experiments (there the one face
# answers everything: Size1/Size2/AMS roles collapse onto it).
set -eu

# Steal the optional explicit single-face opt-in, leaving "$@" holding
# the positional args. A bare PATH (no --font flag) is accepted as the
# legacy spelling. Empty result means the full fixture stack.
take_font() {
  font=""
  while [ $# -gt 0 ]; do
    case $1 in
      --font) font=${2:-}; shift 2;;
      *) font=$1; shift;;
    esac
  done
}

if [ "${1:-}" = batch ]; then
  work=$2; shift 2
  font=""
  if [ $# -gt 0 ]; then take_font "$@"; fi
  export ZIG_LOCAL_CACHE_DIR=/tmp/zp/cache/local
  export ZIG_GLOBAL_CACHE_DIR=/tmp/zp/cache/global
  # One build for the whole batch (see below).
  (cd /repo/packages/zatex-png && zig build --prefix /tmp/zp)
  # The default stack resolves CWD-relative (../zatex/fixtures/...),
  # so render from the package dir; case I/O paths are absolute.
  cd /repo/packages/zatex-png
  fail=0
  while read -r id display; do
    [ -n "$id" ] || continue
    echo "== $id"
    tex=$(cat "$work/$id.tex")
    if [ "$display" = "1" ]; then dflag="--display"; else dflag=""; fi
    # shellcheck disable=SC2086
    if [ -n "$font" ]; then
      /tmp/zp/bin/zatex-png $dflag \
          --px 48 --font "$font" "$tex" "$work/$id.zatex.png" || fail=1
    else
      /tmp/zp/bin/zatex-png $dflag \
          --px 48 "$tex" "$work/$id.zatex.png" || fail=1
    fi
  done < "$work/cases.tsv"
  exit $fail
fi
texfile=$1; display=$2; out=$3; shift 3
font=""
if [ $# -gt 0 ]; then take_font "$@"; fi
export ZIG_LOCAL_CACHE_DIR=/tmp/zp/cache/local
export ZIG_GLOBAL_CACHE_DIR=/tmp/zp/cache/global
# Always build: /tmp/zp persists on a named volume (see compose.yml), so
# a warm cache makes the no-change rebuild seconds; skipping the build
# when a binary exists would test a stale checkout after tree changes.
(cd /repo/packages/zatex-png && zig build --prefix /tmp/zp)
# See batch mode: the default stack resolves CWD-relative.
cd /repo/packages/zatex-png
tex=$(cat "$texfile")
if [ "$display" = "1" ]; then dflag="--display"; else dflag=""; fi
# shellcheck disable=SC2086
if [ -n "$font" ]; then
  exec /tmp/zp/bin/zatex-png $dflag \
      --px 48 --font "$font" "$tex" "$out"
else
  exec /tmp/zp/bin/zatex-png $dflag \
      --px 48 "$tex" "$out"
fi
