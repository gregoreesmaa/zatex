#!/bin/sh
# tools/diff-oracles.sh — on-demand multi-engine differential render report.
#
# Renders a corpus through ZaTeX + 3 oracle engines (KaTeX 0.18.7,
# MathJax v3, TeX Live pdflatex), each in Docker from pinned images with
# no network at run time, then writes the worst-first triage report.
#
# INFORMATIONAL ONLY. This is never a CI gate (AGENTS.md section 4 bans
# pixel tests from required gates) and its output is never an oracle over
# pinned KaTeX: when oracles disagree, that marks spec ambiguity, not a
# ZaTeX bug. See docs/oracle-diff.md.
#
# Usage (run from the repo root):
#   tools/diff-oracles.sh [--corpus tools/oracle-diff/corpus.json]
#                         [--out zig-out/oracle-diff]
#                         [--cases id1,id2] [--skip-build]
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
corpus=$root/tools/oracle-diff/corpus.json
out=$root/zig-out/oracle-diff
cases=""
skip_build=0

while [ $# -gt 0 ]; do
  case $1 in
    --corpus) corpus=$2; shift 2;;
    --out) out=$2; shift 2;;
    --cases) cases=$2; shift 2;;
    --skip-build) skip_build=1; shift;;
    *) echo "usage: diff-oracles.sh [--corpus F] [--out D] [--cases a,b] [--skip-build]" >&2; exit 2;;
  esac
done

command -v docker >/dev/null || { echo "diff-oracles: docker not found" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "diff-oracles: docker compose not found" >&2; exit 1; }

od=$root/tools/oracle-diff
raw=$out/raw
mkdir -p "$raw" "$od/work" "$od/fonts"

# Stage fonts: Latin Modern Math fixture first, STIX Two fallback —
# the same order refhost.zig resolves (see docs/oracle-diff.md).
cp "$root/packages/zatex/fixtures/fonts/latinmodern-math.otf" "$od/fonts/LatinModernMath.otf"
for cand in \
    /System/Library/Fonts/Supplemental/STIXTwoMath.otf \
    /usr/share/fonts/opentype/stix/STIXTwoMath-Regular.otf \
    /usr/share/fonts/STIXTwoMath.otf; do
  if [ -f "$cand" ]; then cp "$cand" "$od/fonts/STIXTwoMath.otf"; break; fi
done
if [ ! -f "$od/fonts/STIXTwoMath.otf" ]; then
  echo "diff-oracles: no STIX Two fallback found on host; continuing with LM fixture only" >&2
fi

compose="docker compose -f $od/compose.yml"
if [ "$skip_build" = "0" ]; then
  $compose build
fi

# Stage one /work/<id>.tex per selected case (python owns the escaping
# so the shell never sees a backslash).
CASES=$cases WORK=$od/work CORPUS=$corpus python3 - <<'EOF'
import json, os
corpus = os.environ["CORPUS"]
only = os.environ.get("CASES") or ""
want = set(only.split(",")) if only else None
work = os.environ["WORK"]
ids = []
for row in json.load(open(corpus)):
    if want is not None and row["id"] not in want:
        continue
    with open(os.path.join(work, row["id"] + ".tex"), "w") as f:
        f.write(row["tex"])
    ids.append("%s %s" % (row["id"], "1" if row.get("display") else "0"))
with open(os.path.join(work, "cases.tsv"), "w") as f:
    f.write("\n".join(ids) + "\n")
EOF

fail=0
while read -r id display; do
  [ -n "$id" ] || continue
  echo "== $id"
  # Drop stale renders first: a failed engine must report missing,
  # never silently compare last run's PNG.
  rm -f "$od/work/$id.zatex.png" "$od/work/$id.katex.png" \
        "$od/work/$id.mathjax.png" "$od/work/$id.luatex.png"
  $compose run --rm zatex-shot \
      "/work/$id.tex" "$display" "/work/$id.zatex.png" < /dev/null || fail=1
  $compose run --rm katex-shot \
      "/work/$id.tex" "$display" "/work/$id.katex.png" < /dev/null || fail=1
  $compose run --rm mathjax-shot \
      "/work/$id.tex" "$display" "/work/$id.mathjax.png" < /dev/null || fail=1
  $compose run --rm luatex-shot \
      "/work/$id.tex" "$display" "/work/$id.luatex.png" < /dev/null || fail=1
done < "$od/work/cases.tsv"

# Showcase crop (PR #52 review): tight ink-bbox crop of every engine
# render before comparing and showcasing (luatex arrives full-page;
# the webshot oracles already clip at capture, re-crop is uniform).
# Unmatched globs are skipped quietly by crop.py.
# shellcheck disable=SC2086
if ls "$od/work"/*.zatex.png "$od/work"/*.katex.png \
      "$od/work"/*.mathjax.png "$od/work"/*.luatex.png >/dev/null 2>&1; then
  python3 "$od/crop.py" "$od/work"/*.zatex.png "$od/work"/*.katex.png \
      "$od/work"/*.mathjax.png "$od/work"/*.luatex.png || fail=1
fi

for f in "$od/work"/*.zatex.png "$od/work"/*.katex.png \
         "$od/work"/*.mathjax.png "$od/work"/*.luatex.png; do
  [ -f "$f" ] && cp "$f" "$raw/"
done

python3 "$od/report.py" --raw "$raw" --out "$out" --corpus "$corpus"
echo "report: $out/report.md"
if [ "$fail" != "0" ]; then
  echo "note: some engine renders failed (rows marked missing)" >&2
fi
