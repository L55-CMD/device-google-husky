#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <patch-dir> <repo-dir>" >&2
    exit 64
fi

patch_dir="$(realpath "$1")"
repo_dir="$(realpath "$2")"

shopt -s nullglob
patches=("${patch_dir}"/*.patch)

if [ "${#patches[@]}" -eq 0 ]; then
    echo "No patches found in ${patch_dir}"
    exit 0
fi

for patch in "${patches[@]}"; do
    echo "Applying $(basename "${patch}")"
    git -C "${repo_dir}" apply --3way --whitespace=nowarn "${patch}"
done
