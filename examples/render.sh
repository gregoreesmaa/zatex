#!/bin/sh
# render.sh — minimal CLI gallery: PNG + SVG for a few showcase formulas.
#
# Usage (run from the repo root):
#   ./examples/render.sh [outdir]
#
# Builds zatex-png + zatex-svg if needed, then renders one PNG and one
# SVG per formula below. Font paths are CWD-relative inside each
# package, so the script cds there (same assumption as the READMEs).
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-"$root/examples/out"}
mkdir -p "$out"

(cd "$root/packages/zatex-png" && zig build)
PNG="$root/packages/zatex-png/zig-out/bin/zatex-png"
(cd "$root/packages/zatex-svg" && zig build)
SVG="$root/packages/zatex-svg/zig-out/bin/zatex-svg"

render() {
    id=$1; tex=$2
    (cd "$root/packages/zatex-png" && "$PNG" --display "$tex" "$out/$id.png")
    (cd "$root/packages/zatex-svg" && "$SVG" --display "$tex" "$out/$id.svg")
    echo "rendered $id"
}

render frac '\frac{a}{b}+x^2'
render sum '\sum_{i=1}^n i^2 = \frac{n(n+1)(2n+1)}{6}'
render gauss '\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}'
render cauchy '\left( \sum_{k=1}^n a_k b_k \right)^2 \leq \left( \sum_{k=1}^n a_k^2 \right) \left( \sum_{k=1}^n b_k^2 \right)'
render fourier 'f(x) = \int_{-\infty}^\infty\hat f(\xi)\,e^{2 \pi i \xi x}\,d\xi'
render matrix '\begin{pmatrix}a & b \\ c & d\end{pmatrix}'
echo "gallery: $out"
