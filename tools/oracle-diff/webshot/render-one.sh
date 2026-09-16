#!/bin/sh
# render-one <engine:katex|mathjax> <texfile> <display:0|1> <out.png>
# render-one <engine:katex|mathjax> batch <workdir>   (issue #69: one
#   browser for the whole cases.tsv instead of one container per case)
# Runs inside the webshot image (working dir /oracle). Reads the TeX
# string from a file so callers never fight shell quoting.
set -eu
engine=$1
if [ "${2:-}" = batch ]; then
  work=$3
  exec node /oracle/shot.mjs --engine "$engine" --batch "$work/cases.tsv" \
      --work "$work" --chrome "${CHROME_PATH:-/usr/bin/chromium}"
fi
texfile=$2; display=$3; out=$4
tex=$(cat "$texfile")
if [ "$display" = "1" ]; then dflag="--display"; else dflag=""; fi
exec node /oracle/shot.mjs --engine "$engine" --tex "$tex" $dflag \
    --out "$out" --chrome "${CHROME_PATH:-/usr/bin/chromium}"
