#!/bin/sh
# check_release_docs.sh — release workflow, install recipe, changelog,
# and package version agree (issues #275, #276).
#
# Issue #275 was a contradiction: #259 (versioned dylib artifacts) is
# closed, yet the changelog read as if no release machinery existed.
# The workflow exists; only the first `v*` tag is still missing. This
# gate fails loudly if the three surfaces ever disagree again:
#   - .github/workflows/release.yml publishes on `v*` tags with
#     versioned libzatex-<tag>-<target> assets + header + SHA256SUMS,
#   - docs/install.md names those same assets and states the same
#     first-tag trigger plus the until-then source-pin recipe,
#   - CHANGELOG.md states #259 closed / first-tag trigger,
#   - packages/zatex/build.zig.zon and contract.version agree,
#   - the zatex_version() 16/8/8 widths are documented in
#     contract.zig, cabi.zig, and zatex.h (issue #276).
set -eu
cd "$(dirname "$0")/.."

fail=0
need() {
  if ! grep -qF "$2" "$1"; then
    echo "FAIL: $1 lacks: $2"
    fail=1
  fi
}

WF=.github/workflows/release.yml
INSTALL=docs/install.md
LOG=CHANGELOG.md
ZON=packages/zatex/build.zig.zon
CONTRACT=packages/zatex/src/contract.zig
CABI=packages/zatex/src/cabi.zig
HEADER=packages/zatex/src/zatex.h

need "$WF" 'tags: ["v*"]'
need "$WF" 'libzatex-${TAG}-${{ matrix.target }}'
need "$WF" 'SHA256SUMS'
need "$INSTALL" 'libzatex-<tag>-<target>'
need "$INSTALL" 'SHA256SUMS'
need "$INSTALL" 'first `v*` tag'
need "$INSTALL" 'issue #259 is closed'
need "$LOG" 'first `v*` tag'
need "$LOG" 'issue #259 is closed'

# Package version pin: zon "0.0.0" must equal contract major.minor.patch.
zon_ver=$(sed -n 's/^[[:space:]]*\.version = "\([^"]*\)".*/\1/p' "$ZON" | head -n 1)
contract_ver=$(sed -n 's/.*\.major = \([0-9]*\), \.minor = \([0-9]*\), \.patch = \([0-9]*\).*/\1.\2.\3/p' "$CONTRACT" | head -n 1)
if [ -z "$zon_ver" ] || [ -z "$contract_ver" ]; then
  echo "FAIL: could not parse version from $ZON ($zon_ver) or $CONTRACT ($contract_ver)"
  fail=1
elif [ "$zon_ver" != "$contract_ver" ]; then
  echo "FAIL: $ZON version $zon_ver != $CONTRACT version $contract_ver"
  fail=1
fi

# Issue #276: normative 16/8/8 widths documented at every surface hosts read.
need "$CONTRACT" 'minor 8 bits'
need "$CONTRACT" 'issue #276'
need "$CABI" 'minor 8'
need "$HEADER" 'patch 8 bits'
need "$LOG" 'patch 8 bits'

if [ "$fail" = "1" ]; then exit 1; fi
echo "release docs OK: workflow, install recipe, changelog, and versions agree"
