#!/bin/sh
# sync_wiki.sh — regenerate wiki/ from docs/ + examples + root files.
#
# The GitHub Wiki has no git remote until enabled (Settings → Features →
# Wikis → "Create the first page"), so this repo keeps a `wiki/`
# mirror instead: same pages, synced by this script. Once the wiki
# remote exists, push with:
#   git clone <repo>.wiki.git /tmp/zatex.wiki && cp wiki/*.md /tmp/zatex.wiki/ && ...
#
# Usage: ./tools/sync_wiki.sh  (fails on drift in CI: run then `git diff --exit-code wiki/`)
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$root/wiki"

sync() { cp "$root/$2" "$root/wiki/$1.md"; }
strip_fm() {
    # Drop Jekyll front-matter (--- ... ---) so wiki pages render clean.
    if [ "$(head -n 1 "$1")" = "---" ]; then
        awk 'NR==1{skip=1;next} skip==1 && $0=="---"{skip=0;next} skip==0{print}' "$1" > "$1.tmp" \
            && mv "$1.tmp" "$1"
    fi
}

sync Home docs/index.md
sync Install docs/install.md
sync Layout-IR docs/ir.md
sync KaTeX-Parity docs/parity.md
sync Support-Table docs/support-table.md
sync Syntax-Mirror docs/katex-syntax.md
sync Examples examples/README.md
sync File-Provider docs/file-provider.md
sync Threading docs/threading.md
sync Unicode docs/unicode.md
sync Delimiter-Scanning docs/delimiter-scan.md
sync Tolerance docs/tolerance.md
sync Changelog CHANGELOG.md
sync Contributing AGENTS.md

for f in "$root"/wiki/*.md; do
    case "$f" in */_Sidebar.md) continue;; esac
    strip_fm "$f"
done
echo "wiki/ synced: $(ls "$root"/wiki/*.md | wc -l) pages"
