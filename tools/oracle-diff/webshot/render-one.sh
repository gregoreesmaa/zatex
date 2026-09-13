#!/bin/sh
# render-one <engine:katex|mathjax> <texfile> <display:0|1> <out.png>
# Runs inside the webshot image (working dir /oracle). Reads the TeX
# string from a file so callers never fight shell quoting.
set -eu
engine=$1; texfile=$2; display=$3; out=$4
tex=$(cat "$texfile")
if [ "$display" = "1" ]; then dflag="--display"; else dflag=""; fi
exec node /oracle/shot.mjs --engine "$engine" --tex "$tex" $dflag \
    --out "$out" --chrome "${CHROME_PATH:-/usr/bin/chromium}"
