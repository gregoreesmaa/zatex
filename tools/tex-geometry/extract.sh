#!/bin/sh
# extract <texfile> <display:0|1> <out.json>
# extract batch <workdir>   (one container for the whole narrow corpus;
#   latex still runs per case so a TeX error sinks only its own row)
# Runs inside the tex-geometry image. Minimal article-class page with
# amsmath (the narrow corpus uses \frac); DVI output preserves
# absolute glyph/rule positions, `dvitype` dumps them as text, and
# `geometry` normalizes the dump to machine-comparable JSON (see
# docs/tex-oracle.md). A TeX error exits nonzero -> case reported as
# missing (the latex log prints on failure only).
set -eu
extract_case() {
texfile=$1; display=$2; out=$3
cwork=$(mktemp -d)
tex=$(cat "$texfile")
if [ "$display" = "1" ]; then body="\\[ $tex \\]"; else body="\$$tex\$"; fi
{
cat <<'EOF'
\documentclass{article}
\usepackage{amsmath,amssymb}
\pagestyle{empty}
\begin{document}
EOF
printf '%s\n' "$body"
cat <<'EOF'
\end{document}
EOF
} > "$cwork/case.tex"
if ! (cd "$cwork" && latex -interaction=nonstopmode -halt-on-error case.tex >latex.log 2>&1); then
  tail -20 "$cwork/latex.log"
  rm -rf "$cwork"
  return 1
fi
dvitype "$cwork/case.dvi" > "$cwork/case.dump"
version=$(tex --version | head -n 1)
geometry --tex "$tex" --display "$display" --tex-version "$version" \
  --dump "$cwork/case.dump" --out "$out"
# Raw TeX render through the DVI route (dvipdfmx + pdftoppm at the same
# -r 300 the luatex oracle uses), so the row can go through the shared
# normalize+SSIM math like every other engine. Saved beside the JSON.
if ! (cd "$cwork" && dvipdfmx -o case.pdf case.dvi >/dev/null 2>&1); then
  echo "extract: dvipdfmx failed for $texfile" >&2
  rm -rf "$cwork"
  return 1
fi
if ! pdftoppm -png -r 300 -singlefile "$cwork/case.pdf" "${out%.json}" >/dev/null 2>&1; then
  echo "extract: pdftoppm failed for $texfile" >&2
  rm -rf "$cwork"
  return 1
fi
# Keep the raw dump beside the JSON (diagnostic: absolute positions,
# font selections) — the CI artifact carries both.
cp "$cwork/case.dump" "${out%.json}.dump"
rm -rf "$cwork"
}

if [ "${1:-}" = batch ]; then
  work=$2
  fail=0
  while read -r id display; do
    [ -n "$id" ] || continue
    echo "== $id"
    extract_case "$work/$id.tex" "$display" "$work/$id.tex.json" || fail=1
  done < "$work/cases.tsv"
  exit $fail
fi
extract_case "$1" "$2" "$3"
