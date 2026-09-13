#!/bin/sh
# Per-OS backend isolation check (issue #67): every shippable
# zatex-png binary must bundle only its selected backend. Builds the
# backend/OS matrix and asserts foreign text-stack symbols are absent
# (case-insensitive `strings` over the linked binary):
#   - no DirectWrite anywhere (no Windows runner exists to validate a
#     DW backend; windows+native is GDI by documented decision),
#   - no CoreText outside Apple autoselect,
#   - no fontconfig/FreeType symbol references outside linux+native
#     (they bind at runtime via dlopen even there — no link refs, only
#     the library-name strings, which is what keeps cross-compiles
#     sysroot-free),
#   - no GDI outside windows+native.
# Software builds must additionally carry none of the above: that is
# the zero-host-dependency promise that lets any host cross-link them.
# Companion: the `backends` CI job runs this on macos-14 (which also
# covers the x86_64-linux/windows cross-links).
set -eu
cd "$(dirname "$0")/.."
P=packages/zatex-png
fail=0
check() { # <binary> <marker> <must_be:present|absent>
  bin=$1; marker=$2; want=$3
  if strings "$bin" 2>/dev/null | grep -qi "$marker"; then have=present; else have=absent; fi
  if [ "$have" = "$want" ]; then
    echo "ok: $bin [$marker $want]"
  else
    echo "FAIL: $bin [$marker is $have, want $want]"; fail=1
  fi
}
build() { # <target-flag-or-empty> <backend> <prefix>
  if [ -z "$1" ]; then
    (cd $P && zig build -Dbackend="$2" --prefix "$3" >/dev/null 2>&1)
  else
    (cd $P && zig build -Dtarget="$1" -Dbackend="$2" --prefix "$3" >/dev/null 2>&1)
  fi
}
# macOS combos build for the host (cross-linking mac targets needs the
# Xcode SDK, which CI runners provide for their own arch only).
build "" auto /tmp/bk-mac-auto
build "" software /tmp/bk-mac-sw
build x86_64-linux native /tmp/bk-lin-nat
build x86_64-linux software /tmp/bk-lin-sw
build x86_64-windows native /tmp/bk-win-nat
build x86_64-windows software /tmp/bk-win-sw
MAC_AUTO=/tmp/bk-mac-auto/bin/zatex-png
MAC_SW=/tmp/bk-mac-sw/bin/zatex-png
LIN_NAT=/tmp/bk-lin-nat/bin/zatex-png
LIN_SW=/tmp/bk-lin-sw/bin/zatex-png
WIN_NAT=/tmp/bk-win-nat/bin/zatex-png.exe
WIN_SW=/tmp/bk-win-sw/bin/zatex-png.exe
for b in "$MAC_AUTO" "$MAC_SW" "$LIN_NAT" "$LIN_SW" "$WIN_NAT" "$WIN_SW"; do
  check "$b" "dwrite" absent
  check "$b" "directwrite" absent
done
check "$MAC_SW" "coretext" absent
check "$LIN_SW" "coretext" absent
check "$WIN_SW" "coretext" absent
check "$LIN_NAT" "coretext" absent
check "$WIN_NAT" "coretext" absent
check "$MAC_SW" "fontconfig" absent
check "$MAC_AUTO" "fontconfig" absent
check "$LIN_SW" "fontconfig" absent
check "$WIN_SW" "fontconfig" absent
check "$WIN_NAT" "fontconfig" absent
check "$MAC_SW" "freetype" absent
check "$MAC_AUTO" "freetype" absent
check "$LIN_SW" "freetype" absent
check "$WIN_SW" "freetype" absent
check "$WIN_NAT" "freetype" absent
check "$MAC_AUTO" "gdi32\|addfont" absent
check "$MAC_SW" "gdi32\|addfont" absent
check "$LIN_NAT" "gdi32\|addfont" absent
check "$LIN_SW" "gdi32\|addfont" absent
check "$WIN_SW" "gdi32\|addfont" absent
# Positive controls: the selected native surface is really wired in.
check "$LIN_NAT" "freetype" present
check "$WIN_NAT" "addfont" present
exit $fail
