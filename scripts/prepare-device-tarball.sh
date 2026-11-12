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

# Rolling kernel releases can be re-uploaded while we build (kernel CI
# finishing in parallel replaces kernel.zip under the same tag). Verify
# against the digest resolved at job start, but if the asset was replaced,
# re-resolve the digest from the release and accept the current artifact
# instead of failing the whole build.
curl -L --fail --output "${archive}" "${kernel_zip_url}"
actual_sha256="$(sha256sum "${archive}" | awk '{print $1}')"
if [ -n "${KERNEL_ZIP_SHA256:-}" ] && [ "${actual_sha256}" != "${KERNEL_ZIP_SHA256}" ]; then
    echo "kernel.zip digest ${actual_sha256} != resolved ${KERNEL_ZIP_SHA256}; checking for rolling-release update" >&2
    release_tag="${KERNEL_RELEASE_TAG:?KERNEL_RELEASE_TAG is required when KERNEL_ZIP_SHA256 is set}"
    release_repo="$(printf '%s' "${KERNEL_REGISTRY_BASE:?KERNEL_REGISTRY_BASE is required}" \
        | sed -E 's#^https://github.com/([^/]+/[^/]+)/releases/download.*#\1#')"
    current_digest="$(curl -fsSL --retry 3 \
        "https://api.github.com/repos/${release_repo}/releases/tags/${release_tag}" \
        | grep -o '"digest": *"sha256:[a-f0-9]\{64\}"' | head -n 1 | cut -d'"' -f4 | cut -d: -f2)"
    if [ "${current_digest}" = "${actual_sha256}" ]; then
        echo "kernel.zip matches current release digest; continuing with updated kernel artifact" >&2
    else
        echo "kernel.zip digest mismatch and does not match release ${release_tag} either" >&2
        exit 1
    fi
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

# pKVM protected modules (exynos-pd, pkvm_s2mpu-v9) must load before pKVM
# finalizes; the kernel modprobes them from the boot ramdisk at boot
# (see BRINGUP-LOG, defect: YouTube/MFC NULL-IOMMU-domain panic). Append
# the module segment to the halium ramdisk; concatenated cpio segments
# are unpacked in order.
"${repo_root}/scripts/make-pkvm-ramdisk-segment.sh" \
    "${kernel_dir}" "${tmpdown}/pkvm-modules.cpio"
cat "${tmpdown}/halium-boot-ramdisk.img" "${tmpdown}/pkvm-modules.cpio" \
    > "${tmpdown}/halium-boot-ramdisk-pkvm.img"

if [[ -n "${deviceinfo_unified_recovery_ui_density:-}" && "${deviceinfo_unified_recovery_ui_density}" != "mdpi" ]]; then
    git_clone_if_missing "https://github.com/JamiKettunen/halium_bootable_recovery" "resource-updates" "${tmpdown}/halium_bootable_recovery"
fi

cp -f "${kernel_image}" "${kernel_obj_dir}/arch/arm64/boot/${deviceinfo_kernel_image_name}"

(
    cd "${port_tree}"
    "${repo_root}/build/make-bootimage.sh" \
        "${tmpdown}" \
        "${kernel_obj_dir}" \
        "${tmpdown}/halium-boot-ramdisk-pkvm.img" \
        "${staging_dir}/partitions/boot.img" \
        "${staging_dir}/system"
)

(
    cd "${port_tree}"
    "${repo_root}/build/build-tarball-mainline.sh" husky "${output_dir}" "${staging_dir}" usrmerge
)
ln -sf device_husky.tar.xz "${output_dir}/device_husky_usrmerge.tar.xz"
ln -sf device_husky.tar.build "${output_dir}/device_husky_usrmerge.tar.build"
