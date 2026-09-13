#!/bin/sh
# render-one <texfile> <display:0|1> <out.png>
# Runs inside the texlive image. Plain minimal-class page (no preview
# package needed — the report tight-crops to the ink bbox anyway);
# pdftoppm -r 300 fixes the DPI. TeX errors exit nonzero -> case
# reported as missing (the pdflatex log prints on failure only).
set -eu
texfile=$1; display=$2; out=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
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
} > "$work/case.tex"
if ! (cd "$work" && pdflatex -interaction=nonstopmode -halt-on-error case.tex >pdflatex.log 2>&1); then
  tail -20 "$work/pdflatex.log"
  exit 1
fi
pdftoppm -png -r 300 -singlefile "$work/case.pdf" "${out%.png}" >/dev/null
