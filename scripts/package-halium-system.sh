#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 <halium-system-zip-url> <output-tarball> [work-dir]" >&2
    exit 64
fi

source_url="$1"
output_tar="$(realpath -m "$2")"
work_dir="${3:-$(pwd)/workdir/package-halium-system}"
work_dir="$(realpath -m "${work_dir}")"

archive="${work_dir}/halium-system.zip"
extract_dir="${work_dir}/extract"
staging_dir="${work_dir}/staging"

rm -rf "${extract_dir}" "${staging_dir}"
mkdir -p "${extract_dir}" "${staging_dir}/system/var/lib/lxc/android" "$(dirname "${output_tar}")"

curl -L --fail --output "${archive}" "${source_url}"
unzip -oq "${archive}" -d "${extract_dir}"

system_img="$(find "${extract_dir}" -type f -name 'system.img' | head -n 1)"
if [ -z "${system_img}" ]; then
    system_img="$(find "${extract_dir}" -type f -name '*.img' | head -n 1)"
fi

if [ -z "${system_img}" ]; then
    echo "No system image found in ${archive}" >&2
    exit 1
fi

cp -f "${system_img}" "${staging_dir}/system/var/lib/lxc/android/android-rootfs.img"
tar -C "${staging_dir}" --owner=root --group=root -cJf "${output_tar}" system/
