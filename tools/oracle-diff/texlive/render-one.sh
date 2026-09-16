#!/bin/sh
# render-one <texfile> <display:0|1> <out.png>
# render-one batch <workdir>   (issue #69: one container for the whole
#   cases.tsv instead of one per case; pdflatex still runs per case so
#   a TeX error sinks only its own row)
# Runs inside the texlive image. Plain minimal-class page (no preview
# package needed — the report tight-crops to the ink bbox anyway);
# pdftoppm -r 300 fixes the DPI. TeX errors exit nonzero -> case
# reported as missing (the pdflatex log prints on failure only).
set -eu
render_case() {
texfile=$1; display=$2; out=$3
cwork=$(mktemp -d)
tex=$(cat "$texfile")
# KaTeX `#RRGGBB` hex colors have no pdflatex/xcolor spelling: translate
# the oracle side to the equivalent `[HTML]` form (the compared property
# — the rendered color — is unchanged; ZaTeX still gets the raw string).
# Short `#rgb` is expanded to `#rrggbb` first: xcolor's HTML model needs
# six digits, and the expansion is safe corpus-wide (`#` elsewhere only
# starts macro parameters like `#1`, never `{#hhh}`).
tex=$(printf '%s' "$tex" | sed -e 's/\({\)#\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)}/\1#\2\2\3\3\4\4}/g' -e 's/\\color{#\([0-9A-Fa-f]\{6\}\)}/\\color[HTML]{\1}/g' -e 's/\\colorbox{#\([0-9A-Fa-f]\{6\}\)}/\\colorbox[HTML]{\1}/g' -e 's/\\fcolorbox{\([^}]*\)}{#\([0-9A-Fa-f]\{6\}\)}/\\fcolorbox{\1}[HTML]{\2}/g' -e 's/\\textcolor{#\([0-9A-Fa-f]\{6\}\)}/\\textcolor[HTML]{\1}/g')
if [ "$display" = "1" ]; then body="\\[ $tex \\]"; else body="\$$tex\$"; fi
{
cat <<'EOF'
\documentclass{minimal}
\usepackage{amsmath,amssymb,xcolor,mathrsfs,hyperref}
\begin{document}
EOF
printf '%s\n' "$body"
cat <<'EOF'
\end{document}
EOF
} > "$cwork/case.tex"
if ! (cd "$cwork" && pdflatex -interaction=nonstopmode -halt-on-error case.tex >pdflatex.log 2>&1); then
  tail -20 "$cwork/pdflatex.log"
  rm -rf "$cwork"
  return 1
fi
pdftoppm -png -r 300 -singlefile "$cwork/case.pdf" "${out%.png}" >/dev/null
rm -rf "$cwork"
}

if [ "${1:-}" = batch ]; then
  work=$2
  fail=0
  while read -r id display; do
    [ -n "$id" ] || continue
    echo "== $id"
    render_case "$work/$id.tex" "$display" "$work/$id.luatex.png" || fail=1
  done < "$work/cases.tsv"
  exit $fail
fi
render_case "$1" "$2" "$3"
