#!/usr/bin/env python3
"""Print the sha256 digest of a NAMED asset from a GitHub release JSON.

The release assets of a rolling kernel tag carry several digests; the
kernel.zip digest must be selected by asset name, never by position
(another asset listed first would silently pin the wrong artifact).

usage: resolve-release-asset-digest.py <release.json> <asset-name>

Prints the hex digest without the "sha256:" prefix. Exits 1 (with a
diagnostic on stderr) if the asset or a usable sha256 digest is missing.
"""
import json
import sys

def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 64
    path, name = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as handle:
        release = json.load(handle)
    for asset in release.get("assets", []):
        if asset.get("name") != name:
            continue
        digest = asset.get("digest") or ""
        prefix, _, hex_digest = digest.partition(":")
        if prefix == "sha256" and len(hex_digest) == 64:
            print(hex_digest)
            return 0
        print(f"asset '{name}' has no usable sha256 digest: '{digest}'",
              file=sys.stderr)
        return 1
    print(f"asset '{name}' not found in release", file=sys.stderr)
    return 1

if __name__ == "__main__":
    sys.exit(main())
