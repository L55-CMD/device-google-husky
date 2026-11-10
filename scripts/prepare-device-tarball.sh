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
if [ -n "${KERNEL_ZIP_SHA256:-}" ]; then
    echo "${KERNEL_ZIP_SHA256}  ${archive}" | sha256sum --check --quiet
fi
unzip -oq "${archive}" -d "${kernel_dir}"

# shellcheck disable=SC1091
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

build_variant="${HUSKY_BUILD_VARIANT:-normal}"
case "${build_variant}" in
    normal)
        ;;
    debug)
        if [ -d "${repo_root}/overlay-debug" ]; then
            cp -a "${repo_root}/overlay-debug/." "${port_tree}/overlay/"
        fi
        ;;
    *)
        echo "Unknown HUSKY_BUILD_VARIANT '${build_variant}'" >&2
        exit 64
        ;;
esac

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

download_verified() {
    local url="$1"
    local target="$2"
    local expected_sha256="$3"
    curl -L --fail --output "${target}.part" "${url}"
    mv "${target}.part" "${target}"
    echo "${expected_sha256}  ${target}" | sha256sum --check --quiet
}

git_clone_if_missing "https://android.googlesource.com/platform/external/avb" "android13-gsi" "${tmpdown}/avb"
git_clone_if_missing "https://github.com/LineageOS/android_system_tools_mkbootimg" "lineage-20.0" "${tmpdown}/android_system_tools_mkbootimg"

download_verified "${INITRD_URL:?INITRD_URL is required}" \
    "${tmpdown}/halium-boot-ramdisk.img" "${INITRD_SHA256:?INITRD_SHA256 is required}"
download_verified "${RECOVERY_IMAGE_URL:?RECOVERY_IMAGE_URL is required}" \
    "${tmpdown}/ramdisk-recovery.img" "${RECOVERY_IMAGE_SHA256:?RECOVERY_IMAGE_SHA256 is required}"

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
