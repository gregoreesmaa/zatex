#!/bin/sh
# check_test_roots.sh — every source test executes (issue #106).
#
# Zig only analyzes an imported file's tests when its declarations are
# referenced, so a file with `test` blocks that no suite root forces
# into analysis silently never runs (sw_png.zig proved it: a false
# expectation stayed green). This gate fails loudly on that shape.
#
# Rule (sound, static): every packages/zatex-png/src/*.zig and
# packages/zatex-mathml/src/*.zig containing a `test` block must
# either be a test root in its package build.zig (root_source_file of
# an addTest call) or be named in a refAllDecls(@import("...")) line
# inside a root.
# Raw test-count comparison is NOT sound here: suites honestly execute
# shared tests under several binaries (sw + linux), and core uses
# name filters — so this checks file coverage, never totals.
# Core is excluded: its engine tests execute today (red-verified) via
# lazy analysis through the zatex root, which no static rule can prove.
set -eu
cd "$(dirname "$0")/.."

fail=0
for PKG in packages/zatex-png packages/zatex-mathml; do
BUILD=$PKG/build.zig
SRC=$PKG/src

# Roots are root_source_file entries plus .file entries: the win/linux
# test modules are built in a loop from .file paths (same build.zig).
roots=$(sed -n -e 's/.*root_source_file = b.path("\([^"]*\)").*/\1/p' -e 's/.*\.file = "\([^"]*\)".*/\1/p' "$BUILD" | sed 's|^|'"$PKG"'/|')
[ -n "$roots" ] || { echo "FAIL: no test roots found in $BUILD"; exit 1; }

for f in "$SRC"/*.zig; do
  base=$(basename "$f")
  if ! grep -q '^test [{\"]' "$f"; then continue; fi
  rel="$PKG/src/$base"
  ok=0
  for r in $roots; do
    if [ "$r" = "$rel" ]; then ok=1; break; fi
    # A refAllDecls line inside a root forces the file into analysis,
    # which is what makes its tests execute (issue #106 mechanism).
    if grep -q "refAllDecls(@import(\"$base\"))" "$r" 2>/dev/null; then ok=1; break; fi
  done
  if [ "$ok" = "0" ]; then
    echo "FAIL: $rel has tests but no suite root references it"
    fail=1
  fi
done
done
if [ "$fail" = "1" ]; then exit 1; fi
echo "test roots OK: every test-bearing png/mathml source is root- or refAllDecls-covered"
