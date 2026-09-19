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
# Same oracle-side adaptations as the luatex sweep oracle
# (tools/oracle-diff/texlive/render-one.sh): KaTeX `#RRGGBB` hex
# colors have no pdflatex/xcolor spelling, so translate to the
# equivalent `[HTML]` form (the compared property — the rendered
# color — is unchanged). Short `#rgb` expands first for the same
# reason. Packages mirror luatex-shot (article keeps `\pagestyle`,
# which stays `empty` so no folio glyph pollutes the DVI counts).
tex=$(printf '%s' "$tex" | sed -e 's/\({\)#\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)}/\1#\2\2\3\3\4\4}/g' -e 's/\\color{#\([0-9A-Fa-f]\{6\}\)}/\\color[HTML]{\1}/g' -e 's/\\colorbox{#\([0-9A-Fa-f]\{6\}\)}/\\colorbox[HTML]{\1}/g' -e 's/\\fcolorbox{\([^}]*\)}{#\([0-9A-Fa-f]\{6\}\)}/\\fcolorbox{\1}[HTML]{\2}/g' -e 's/\\textcolor{#\([0-9A-Fa-f]\{6\}\)}/\\textcolor[HTML]{\1}/g')
if [ "$display" = "1" ]; then body="\\[ $tex \\]"; else body="\$$tex\$"; fi
{
cat <<'EOF'
\documentclass{article}
\usepackage{amsmath,amssymb,xcolor,mathrsfs,hyperref}
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
# Atomic publish (tmp + rename): a killed run must never leave a
# partial PNG that a later reuse pass mistakes for a finished render.
if ! pdftoppm -png -r 300 -singlefile "$cwork/case.pdf" "${out%.json}.tmp" >/dev/null 2>&1; then
  echo "extract: pdftoppm failed for $texfile" >&2
  rm -rf "$cwork"
  return 1
fi
mv "${out%.json}.tmp.png" "${out%.json}.png"
# Keep the raw dump beside the JSON (diagnostic: absolute positions,
# font selections) — the CI artifact carries both.
cp "$cwork/case.dump" "${out%.json}.dump"
rm -rf "$cwork"
}

if [ "${1:-}" = batch ]; then
  work=$2
  fail=0
  reused=0
  rendered=0
  while read -r id display; do
    [ -n "$id" ] || continue
    out="$work/$id.tex.png"
    # Render reuse, opt-in via ORACLE_REUSE=1 (see tools/diff-oracles.sh).
    # Off by default so other batch consumers (notably the tex-oracle
    # workflow, whose force-refresh runs on a restored workdir) always
    # re-extract. `==` prints on actual renders only.
    if [ "${ORACLE_REUSE:-0}" = "1" ] && [ -s "$out" ]; then
      reused=$((reused + 1))
      continue
    fi
    echo "== $id"
    if extract_case "$work/$id.tex" "$display" "$work/$id.tex.json"; then
      rendered=$((rendered + 1))
    else
      fail=1
    fi
  done < "$work/cases.tsv"
  echo "tex: reused $reused, rendered $rendered"
  exit $fail
fi
extract_case "$1" "$2" "$3"
