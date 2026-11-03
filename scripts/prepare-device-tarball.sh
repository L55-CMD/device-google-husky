#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 <kernel-images-zip-url> <output-dir> [work-dir]" >&2
    exit 64
fi

repo_root="$(realpath "$(dirname "$0")/..")"
kernel_zip_url="$1"
output_dir="$(realpath -m "$2")"
work_dir="${3:-${repo_root}/workdir/device-tarball}"
work_dir="$(realpath -m "${work_dir}")"

archive="${work_dir}/kernel-husky.zip"
kernel_dir="${work_dir}/kernel-extracted"
kernel_obj_dir="${work_dir}/KERNEL_OBJ"
port_tree="${work_dir}/port-tree"
staging_dir="${work_dir}/staging"
tmpdown="${work_dir}/downloads"

rm -rf "${kernel_dir}" "${kernel_obj_dir}" "${port_tree}" "${staging_dir}" "${tmpdown}"
mkdir -p "${kernel_dir}" "${kernel_obj_dir}/arch/arm64/boot" "${port_tree}" "${staging_dir}/partitions" "${staging_dir}/system" "${output_dir}" "${tmpdown}"

curl -L --fail --output "${archive}" "${kernel_zip_url}"
unzip -oq "${archive}" -d "${kernel_dir}"

source "${repo_root}/deviceinfo"

kernel_image="$(find "${kernel_dir}" -type f -name "${deviceinfo_kernel_image_name:-Image.lz4}" | head -n 1)"
if [ -z "${kernel_image}" ]; then
    echo "${deviceinfo_kernel_image_name:-Image.lz4} not found in ${archive}" >&2
    exit 1
fi

tar -C "${repo_root}" \
    --exclude=.git \
    --exclude=workdir \
    --exclude=out \
    --exclude=ota \
    --exclude=ota-16 \
    --exclude=artifacts \
    -cf - . | tar -C "${port_tree}" -xf -

dtb_img="$(find "${kernel_dir}" -type f -name 'dtb.img' | head -n 1)"
if [ -z "${dtb_img}" ]; then
    echo "dtb.img not found in ${archive}" >&2
    exit 1
fi

if [ -n "${deviceinfo_bootimg_prebuilt_dtb:-}" ]; then
    cp -f "${dtb_img}" "${port_tree}/${deviceinfo_bootimg_prebuilt_dtb}"
fi

git_clone_if_missing() {
    local url="$1"
    local branch="$2"
    local target="$3"
    if [ -d "${target}/.git" ]; then
        return
    fi
    git clone --depth 1 --branch "${branch}" "${url}" "${target}"
}

download_if_missing() {
    local url="$1"
    local target="$2"
    if [ -f "${target}" ]; then
        return
    fi
    curl -L --fail --output "${target}" "${url}"
}

git_clone_if_missing "https://android.googlesource.com/platform/external/avb" "android13-gsi" "${tmpdown}/avb"
git_clone_if_missing "https://github.com/LineageOS/android_system_tools_mkbootimg" "lineage-20.0" "${tmpdown}/android_system_tools_mkbootimg"

download_if_missing \
    "https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64" \
    "${tmpdown}/halium-boot-ramdisk.img"
download_if_missing \
    "https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%2Fporting%2Fcommunity-ports%2Fjenkins-ci%2Fgeneric_arm64/job/halium-14.0/lastSuccessfulBuild/artifact/ramdisk-recovery.img" \
    "${tmpdown}/ramdisk-recovery.img"

if [[ -n "${deviceinfo_unified_recovery_ui_density:-}" && "${deviceinfo_unified_recovery_ui_density}" != "mdpi" ]]; then
    git_clone_if_missing "https://github.com/JamiKettunen/halium_bootable_recovery" "resource-updates" "${tmpdown}/halium_bootable_recovery"
fi

cp -f "${kernel_image}" "${kernel_obj_dir}/arch/arm64/boot/${deviceinfo_kernel_image_name}"

(
    cd "${port_tree}"
    "${repo_root}/build/make-bootimage.sh" \
        "${tmpdown}" \
        "${kernel_obj_dir}" \
        "${tmpdown}/halium-boot-ramdisk.img" \
        "${staging_dir}/partitions/boot.img" \
        "${staging_dir}/system"
)

(
    cd "${port_tree}"
    "${repo_root}/build/build-tarball-mainline.sh" husky "${output_dir}" "${staging_dir}" usrmerge
)
ln -sf device_husky.tar.xz "${output_dir}/device_husky_usrmerge.tar.xz"
ln -sf device_husky.tar.build "${output_dir}/device_husky_usrmerge.tar.build"
