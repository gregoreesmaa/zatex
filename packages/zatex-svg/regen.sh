#!/bin/sh
# Regenerate the checked-in SVG goldens from src/corpus.txt.
#
# Each `src/corpus.txt` row is `<id> <tex>` (split on the FIRST space —
# tex contains spaces). Every row renders through the freshly built CLI
# to `src/goldens/<id>.svg`, with `--display` iff the id ends in `-d`
# (the snapshot test in src/svg.zig keys display mode off the same
# suffix, so regen and the test agree by construction). The id list is
# rewritten to `src/golden_ids.zig` in corpus order.
#
# Any render error fails the script (a corpus row must always render).
# Run from anywhere: paths anchor at this script's directory, and the
# CLI itself must run from packages/zatex-svg/ (CWD-relative stack).
set -eu
here=$(dirname "$0")
cd "$here"

zig build
mkdir -p src/goldens

ids=""
while IFS= read -r row || [ -n "$row" ]; do
    case "$row" in ''|\#*) continue ;; esac
    id=${row%% *}
    tex=${row#* }
    if [ -z "$ids" ]; then ids="\"$id\""; else ids="$ids, \"$id\""; fi
    case "$id" in
        *-d) ./zig-out/bin/zatex-svg --display "$tex" "src/goldens/$id.svg" ;;
        *) ./zig-out/bin/zatex-svg "$tex" "src/goldens/$id.svg" ;;
    esac || { echo "regen.sh: render failed for '$id'" >&2; exit 1; }
done < src/corpus.txt

printf 'pub const ids = [_][]const u8{ %s };\n' "$ids" > src/golden_ids.zig
echo "regen.sh: $(ls src/goldens/*.svg | wc -l | tr -d ' ') goldens + src/golden_ids.zig"
