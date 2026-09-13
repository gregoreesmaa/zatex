#!/usr/bin/env python3
"""Row-level diff of two gallery HTML files (issue 13).

Compares the `<!-- row:ID -->...<!-- /row:ID -->` blocks produced by
tools/gallery.zig and prints a reviewer summary: changed-row ids plus
the head/base artifact names. Informational only, never a gate.
Exits 0 even when galleries differ (difference is the payload).
"""
import re
import sys

BLOCK = re.compile(r"<!-- row:(.*?)-->(.*?)<!-- /row:\1-->", re.S)


def blocks(path):
    with open(path, encoding="utf-8") as f:
        html = f.read()
    return dict(BLOCK.findall(html))


def main():
    base_path, head_path = sys.argv[1], sys.argv[2]
    base, head = blocks(base_path), blocks(head_path)
    ids = sorted(set(base) | set(head))
    changed = [i for i in ids if base.get(i) != head.get(i)]
    print("## Gallery diff (informational — pinned KaTeX output is truth)");
    print()
    print(f"rows: {len(ids)} total, {len(changed)} changed (base vs head)")
    print()
    for i in changed:
        if i not in base:
            print(f"- `{i}`: ADDED at head")
        elif i not in head:
            print(f"- `{i}`: REMOVED at head")
        else:
            print(f"- `{i}`: output changed")
    if not changed:
        print("No gallery changes.")
    print()
    print("Full side-by-side: download the `gallery` CI artifact"
          " (`gallery-base.html` vs `gallery-head.html`).")


main()
