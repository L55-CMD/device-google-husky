#!/usr/bin/env bash
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
cd "${repo_root}"

# Coordinated dependency versions and checksums.
# shellcheck disable=SC1091
source "${repo_root}/dependencies.lock"

build_tools_repo="${BUILD_TOOLS_REPO:?BUILD_TOOLS_REPO is required}"
build_tools_revision="${BUILD_TOOLS_REVISION:?BUILD_TOOLS_REVISION is required}"
build_dir="${BUILD_TOOLS_DIR:-${repo_root}/build}"

output_dir="${OUTPUT_DIR:-${repo_root}/out}"
ota_input_dir="${OTA_INPUT_DIR:-${repo_root}/ota}"
ota_dir="${OTA_DIR:-${repo_root}/ota-16}"
artifacts_dir="${ARTIFACTS_DIR:-${repo_root}/artifacts}"
work_dir="${WORK_DIR:-${repo_root}/workdir/forgejo-final}"

require_url() {
    local url="$1"
    local status
    status="$(curl -sS -L -o /dev/null -r 0-0 -w '%{http_code}' "${url}")"
    case "${status}" in
        200|206) return 0 ;;
    esac
    echo "Required package not available at ${url} (HTTP ${status})" >&2
    return 1
}

halium_system_url="${PACKAGE_REGISTRY_BASE:?}/main/${HALIUM_SYSTEM_FILE:?}"
libhybris_update_url="${PACKAGE_REGISTRY_BASE}/main/${LIBHYBRIS_FILE:?}"
# kernel.zip must come from the exact coordinated release tag; never fall back
# to another branch/kernel silently.
kernel_registry_base="${KERNEL_REGISTRY_BASE:?KERNEL_REGISTRY_BASE is required}"
kernel_release_tag="${KERNEL_RELEASE_TAG:?KERNEL_RELEASE_TAG is required}"
kernel_images_url="${kernel_registry_base}/${kernel_release_tag}/kernel.zip"
require_url "${halium_system_url}"
require_url "${libhybris_update_url}"
require_url "${kernel_images_url}"

build_patches_dir="${repo_root}/build-patches/halium-generic-adaptation-build-tools"
kernel_work_dir="${work_dir}/kernel"

mkdir -p "${work_dir}" "${ota_input_dir}" "${output_dir}"
rm -rf "${ota_dir}" "${artifacts_dir}"

rm -rf "${build_dir}"
mkdir -p "${build_dir}"
git -C "${build_dir}" init -q
git -C "${build_dir}" remote add origin "${build_tools_repo}"
git -C "${build_dir}" fetch --depth 1 origin "${build_tools_revision}"
git -C "${build_dir}" checkout -q --detach FETCH_HEAD

"${repo_root}/scripts/apply-patches.sh" "${build_patches_dir}" "${build_dir}"
SYSTEM_IMG_ZIP_SHA256="${HALIUM_SYSTEM_SHA256:?}" \
    "${repo_root}/scripts/package-halium-system.sh" \
    "${halium_system_url}" \
    "${ota_input_dir}/halium_halium_arm64-16.tar.xz" \
    "${work_dir}/halium-system"
curl -L --fail --output "${ota_input_dir}/libhybris-16-update.tar.xz" "${libhybris_update_url}"
echo "${LIBHYBRIS_SHA256:?}  ${ota_input_dir}/libhybris-16-update.tar.xz" | sha256sum --check --quiet
KERNEL_ZIP_SHA256="${KERNEL_ZIP_SHA256:-}" \
INITRD_URL="${INITRD_URL:?}" INITRD_SHA256="${INITRD_SHA256:?}" \
RECOVERY_IMAGE_URL="${RECOVERY_IMAGE_URL:?}" RECOVERY_IMAGE_SHA256="${RECOVERY_IMAGE_SHA256:?}" \
    "${repo_root}/scripts/prepare-device-tarball.sh" \
    "${kernel_images_url}" \
    "${output_dir}" \
    "${kernel_work_dir}"

"${build_dir}/prepare-fake-ota.sh" "${output_dir}/device_husky_usrmerge.tar.xz" "${ota_dir}"
sudo env PATH="${PATH}" "${build_dir}/system-image-from-ota.sh" "${ota_dir}/ubuntu_command" "${output_dir}"

android_rootfs_img="${work_dir}/halium-system/staging/system/var/lib/lxc/android/android-rootfs.img"
if [ ! -f "${android_rootfs_img}" ]; then
    echo "Expected android-rootfs.img at ${android_rootfs_img}" >&2
    exit 1
fi
cp -f "${android_rootfs_img}" "${output_dir}/android-rootfs.img"

kernel_extract_dir="${kernel_work_dir}/kernel-extracted"
for image in dtb.img dtbo.img system_dlkm.img vendor_dlkm.flatten.img vendor_kernel_boot.img; do
    match="$(find "${kernel_extract_dir}" -type f -name "${image}" | head -n 1)"
    if [ -z "${match}" ]; then
        echo "Expected ${image} in extracted kernel artifacts under ${kernel_extract_dir}" >&2
        exit 1
    fi
    cp -f "${match}" "${output_dir}/${image}"
done

mkdir -p "${artifacts_dir}"
for file in \
    "${output_dir}/system.img" \
    "${output_dir}/boot.img" \
    "${output_dir}/init_boot.img" \
    "${output_dir}/vendor_boot.img" \
    "${output_dir}/vendor_kernel_boot.img" \
    "${output_dir}/dtb.img" \
    "${output_dir}/dtbo.img" \
    "${output_dir}/system_dlkm.img" \
    "${output_dir}/vendor_dlkm.flatten.img" \
    "${output_dir}/device_husky.tar.xz" \
    "${output_dir}/device_husky.tar.build" \
    "${output_dir}/android-rootfs.img" \
    "${ota_input_dir}/libhybris-16-update.tar.xz" \
    "${ota_input_dir}/halium_halium_arm64-16.tar.xz" \
    "${ota_dir}/ubuntu_command"; do
    if [ -f "${file}" ]; then
        cp -f "${file}" "${artifacts_dir}/"
    fi
done

(
    cd "${artifacts_dir}"
    sha256sum ./* > SHA256SUMS
)
