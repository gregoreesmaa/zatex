#!/bin/sh
# check_dist_closure.sh — dist libs carry no test-only code (issue #288).
#
# The shipped static archives must contain the engine closure only:
# no fuzz/parity/qa/refhost/conform-test/test-double/inspector/
# gallery/ir-dump symbols unless explicitly blessed. `conform` itself
# IS blessed: `zatex_conform_metrics` is frozen C ABI (zatex.h,
# CHANGELOG.md "Unreleased"), so its strings legitimately ride the
# archive — the gate asserts the test-only set around it stays out.
#
# Mechanism (check_backends.sh precedent): case-insensitive `strings`
# over the just-built dist archives. Runs in CI on macos-14 (same
# runner as the size gate, so the measurement is comparable); the
# source-level comment next to each dist root names the blessed set.
set -eu
cd "$(dirname "$0")/.."

fail=0
check() { # <archive> <marker> <must_be:present|absent>
  bin=$1; marker=$2; want=$3
  if strings "$bin" 2>/dev/null | grep -qi "$marker"; then have=present; else have=absent; fi
  if [ "$have" = "$want" ]; then
    echo "ok: $bin [$marker $want]"
  else
    echo "FAIL: $bin [$marker is $have, want $want]"; fail=1
  fi
}

(cd packages/zatex && zig build) || { echo "FAIL: core dist build failed"; exit 1; }
(cd packages/zatex-mathml && zig build) || { echo "FAIL: mathml dist build failed"; exit 1; }
CORE=$(ls packages/zatex/zig-out/lib/libz*.a packages/zatex/zig-out/lib/zatex_static.lib 2>/dev/null | head -n 1)
MML=$(ls packages/zatex-mathml/zig-out/lib/libz*_mathml.a packages/zatex-mathml/zig-out/lib/zatex_mathml_static.lib 2>/dev/null | head -n 1)
if [ -z "$CORE" ]; then echo "FAIL: no core dist archive found"; exit 1; fi
if [ -z "$MML" ]; then echo "FAIL: no mathml dist archive found"; exit 1; fi

# Blessed: the engine entry points and the conformance ABI. COFF
# import/static `.lib` files carry no GNU-strings-visible symbol
# names, so the present-checks only run on the Unix archives (the
# gate CI runs on macOS); the absent-checks below run on either
# archive kind (leaked test strings would show in both).
case "$CORE" in
  *.lib) echo "skip: $CORE [COFF present-checks need GNU strings; CI runs this gate on macOS]" ;;
  *) check "$CORE" "zatex_layout_utf8" present
     check "$CORE" "zatex_conform_metrics" present
     check "$CORE" "zatex_version" present ;;
esac

# Test-only: never in the shipped archive.
for marker in "fuzz" "parity" "refhost" "delimvectors" "fileprovider_c" \
  "testdouble" "zatex_test" "inspect" "gallery" "ir_dump" "irdump" \
  "qa40" "energy hook" "test-double" "hello-formula"; do
  check "$CORE" "$marker" absent
done
for marker in "fuzz" "parity" "refhost" "delimvectors" "fileprovider_c" \
  "testdouble" "inspect" "gallery" "ir_dump" "irdump"; do
  check "$MML" "$marker" absent
done

exit $fail
