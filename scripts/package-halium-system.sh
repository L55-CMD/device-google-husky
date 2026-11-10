#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 <halium-system-zip-url> <output-tarball> [work-dir]" >&2
    exit 64
fi

repo_root="$(realpath "$(dirname "$0")/..")"
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
if [ -n "${SYSTEM_IMG_ZIP_SHA256:-}" ]; then
    echo "${SYSTEM_IMG_ZIP_SHA256}  ${archive}" | sha256sum --check --quiet
fi
unzip -oq "${archive}" -d "${extract_dir}"

system_img="$(find "${extract_dir}" -type f -name 'system.img' | head -n 1)"
if [ -z "${system_img}" ]; then
    system_img="$(find "${extract_dir}" -type f -name '*.img' | head -n 1)"
fi

if [ -z "${system_img}" ]; then
    echo "No system image found in ${archive}" >&2
    exit 1
fi

android_img="${staging_dir}/system/var/lib/lxc/android/android-rootfs.img"
cp -f "${system_img}" "${android_img}"

# The generic GSI has no first-stage device fstab. The Halium initrd reads
# /fstab* from the Android rootfs to mount vendor and the other dynamic
# partitions, so inject the files from the pinned LOS zuma vendor image.
for fstab in fstab.zuma fstab.zuma-fips; do
    debugfs -w -R "write ${repo_root}/android-rootfs/${fstab} /${fstab}" "${android_img}"
done
debugfs -R "stat /fstab.zuma" "${android_img}" >/dev/null

tar -C "${staging_dir}" --owner=root --group=root -cJf "${output_tar}" system/
