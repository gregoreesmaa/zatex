#!/bin/sh
# tools/diff-oracles.sh — on-demand multi-engine differential render report.
#
# Renders a corpus through ZaTeX + 4 oracle engines (KaTeX 0.18.7,
# MathJax v3, TeX Live pdflatex, TeX Live DVI route), each in Docker from pinned images with
# no network at run time, then writes the worst-first triage report.
# Oracle renders are reused across runs while their inputs are
# unchanged (content-stamped, primed from the last successful sweep
# artifact); ZaTeX always re-renders — it is the live signal, never a
# stable reference. See "Render reuse" in docs/oracle-diff.md.
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

# Render reuse: `want` fingerprints every input that can change an
# oracle PNG byte (corpus, drivers, Dockerfiles, harness, crop, this
# script, staged fonts). `work/.inputs.sha` records the fingerprint of
# the run that produced the renders sitting in work/. A match means the
# kept PNGs are provably current, so engines skip them (ORACLE_REUSE=1)
# and the sweep crops only fresh renders. A mismatch (or first run)
# deletes the oracle renders and starts over — a failed engine still
# reports missing, never last run's PNG. ZaTeX PNGs are always deleted:
# ZaTeX is the live subject, never a stable reference.
sha256sum_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1;
  else shasum -a 256 | cut -d' ' -f1; fi
}
stamp_files="tools/oracle-diff/corpus.json tools/oracle-diff/compose.yml tools/oracle-diff/crop.py tools/oracle-diff/webshot/Dockerfile tools/oracle-diff/webshot/render-one.sh tools/oracle-diff/webshot/shot.mjs tools/oracle-diff/webshot/package.json tools/oracle-diff/webshot/package-lock.json tools/oracle-diff/webshot/public/probe.html tools/oracle-diff/texlive/Dockerfile tools/oracle-diff/texlive/render-one.sh tools/tex-geometry/Dockerfile tools/tex-geometry/extract.sh tools/tex-geometry/geometry.py tools/diff-oracles.sh packages/zatex/fixtures/fonts/latinmodern-math.otf"
stix=no
[ -f "$od/fonts/STIXTwoMath.otf" ] && stix=yes
# shellcheck disable=SC2086
want="$(for f in $stamp_files; do [ -f "$root/$f" ] && cat "$root/$f"; done | sha256sum_stdin)-$stix"
have=""
[ -f "$od/work/.inputs.sha" ] && have=$(cat "$od/work/.inputs.sha")

# Prime work/ from the latest successful sweep artifact (same branch,
# else main): the artifact's raw/ holds the cropped finals, byte-ready
# for reuse. Content-checked via the primed .inputs.sha below, so a
# stale prime only costs a download, never a wrong comparison. Skipped
# silently without `gh`, without auth, or with no prior artifact — and
# skipped entirely when the local workdir already matches (consecutive
# runs reuse with no download at all).
if [ "$have" != "$want" ] && command -v gh >/dev/null 2>&1; then
  branch=${GITHUB_REF_NAME:-$(git branch --show-current 2>/dev/null || true)}
  for b in "$branch" main; do
    [ -n "$b" ] || continue
    run=$(gh run list --workflow oracle-diff.yml --branch "$b" \
      --status success --limit 1 --json databaseId \
      --jq '.[0].databaseId' 2>/dev/null || true)
    [ -n "$run" ] && [ "$run" != "null" ] || continue
    pdir=$(mktemp -d)
    if gh run download "$run" -n oracle-diff -D "$pdir" >/dev/null 2>&1 \
       && [ -f "$pdir/oracle-diff/oracle-inputs.sha" ]; then
      for f in "$pdir"/oracle-diff/raw/*.katex.png \
               "$pdir"/oracle-diff/raw/*.mathjax.png \
               "$pdir"/oracle-diff/raw/*.luatex.png \
               "$pdir"/oracle-diff/raw/*.tex.png; do
        [ -f "$f" ] && cp "$f" "$od/work/"
      done
      cp "$pdir/oracle-diff/oracle-inputs.sha" "$od/work/.inputs.sha"
      have=$(cat "$od/work/.inputs.sha")
      echo "diff-oracles: primed oracle renders from run $run (branch $b)" >&2
      rm -rf "$pdir"
      break
    fi
    rm -rf "$pdir"
  done
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

# Drop stale renders: ZaTeX always re-renders (live signal), and tmp
# leftovers from killed runs are never trusted. Oracle renders survive
# only on a stamp match (see above) — anything else is deleted, so a
# failed engine reports missing, never silently compares last run's PNG.
rm -f "$od"/work/*.zatex.png "$od"/work/*.tmp "$od"/work/*.png.tmp \
      "$od"/work/*.tmp.png
if [ "$have" = "$want" ]; then
  echo "diff-oracles: oracle inputs unchanged — reusing existing renders" >&2
else
  rm -f "$od"/work/*.katex.png "$od"/work/*.mathjax.png \
        "$od"/work/*.luatex.png "$od"/work/*.tex.png \
        "$od"/work/*.tex.json "$od"/work/*.tex.dump
fi
# One container per engine for the whole cases.tsv (issue #69: ~4
# container starts and ~2 browser launches instead of ~4 per case).
# Engines run concurrently — each `compose run` is its own container
# with its own browser/build dir, so they share nothing but the
# read-only repo mount and their own /work output names. A per-engine
# .status file records failure (a background failure must not trigger
# `set -e`, and `wait` alone only reports the last job).
fail=0
rm -f "$od"/work/*.status
$compose run --rm zatex-shot batch /work < /dev/null \
    >"$od/work/zatex.log" 2>&1 || echo "$?" >"$od/work/zatex.status" &
$compose run -e ORACLE_REUSE=1 --rm katex-shot batch /work < /dev/null \
    >"$od/work/katex.log" 2>&1 || echo "$?" >"$od/work/katex.status" &
$compose run -e ORACLE_REUSE=1 --rm mathjax-shot batch /work < /dev/null \
    >"$od/work/mathjax.log" 2>&1 || echo "$?" >"$od/work/mathjax.status" &
$compose run -e ORACLE_REUSE=1 --rm luatex-shot batch /work < /dev/null \
    >"$od/work/luatex.log" 2>&1 || echo "$?" >"$od/work/luatex.status" &
$compose run -e ORACLE_REUSE=1 --rm tex-shot batch /work < /dev/null \
    >"$od/work/tex.log" 2>&1 || echo "$?" >"$od/work/tex.status" &
wait
for e in zatex katex mathjax luatex tex; do
  if [ -f "$od/work/$e.status" ]; then
    echo "diff-oracles: $e batch failed (see $od/work/$e.log)" >&2
    fail=1
  fi
done

# Showcase crop (PR #52 review): tight ink-bbox crop of fresh renders
# before comparing and showcasing (luatex arrives full-page; the
# webshot oracles already clip at capture, re-crop is uniform).
# Reused renders arrive already cropped (kept or primed post-crop
# finals), so only rows this run actually rendered are cropped: the
# `== <id>` lines each driver prints per real render in its fresh log.
# crop.py deletes undecodable files so they report missing, never
# trusted. Missing files (failed rows) are skipped quietly.
# shellcheck disable=SC2086
crop_list=""
for e in zatex katex mathjax luatex tex; do
  ids=$(grep '^== ' "$od/work/$e.log" 2>/dev/null | awk '{print $2}' || true)
  for id in $ids; do
    f="$od/work/$id.$e.png"
    [ -f "$f" ] && crop_list="$crop_list $f"
  done
done
if [ -n "$crop_list" ]; then
  python3 "$od/crop.py" $crop_list || fail=1
fi

# Copy exactly the selected rows (cases.tsv, not globs): with reuse,
# work/ may hold renders from rows outside a --cases filter, and raw/
# is wiped first so deleted rows cannot leak in from a previous run.
rm -f "$raw"/*.png
while read -r id _rest; do
  [ -n "$id" ] || continue
  for e in zatex katex mathjax luatex tex; do
    f="$od/work/$id.$e.png"
    [ -f "$f" ] && cp "$f" "$raw/"
  done
done < "$od/work/cases.tsv"

# Record the inputs fingerprint for the next run (and for artifact
# primes via oracle-inputs.sha in the report dir): written only after
# render+crop+copy complete, so a killed sweep leaves the old stamp and
# re-renders fully rather than trusting half-finished outputs. Missing
# rows retry next run; every kept file was inputs-proven, non-empty,
# and crop-decodable.
printf '%s\n' "$want" > "$od/work/.inputs.sha"
cp "$od/work/.inputs.sha" "$out/oracle-inputs.sha"

python3 "$od/report.py" --raw "$raw" --out "$out" --corpus "$corpus"
echo "report: $out/report.md"
if [ "$fail" != "0" ]; then
  echo "note: some engine renders failed (rows marked missing)" >&2
fi
