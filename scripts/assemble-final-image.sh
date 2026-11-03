#!/usr/bin/env bash
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
cd "${repo_root}"

build_tools_repo="${BUILD_TOOLS_REPO:-https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools.git}"
build_tools_branch="${BUILD_TOOLS_BRANCH:-unified-recovery}"
build_dir="${BUILD_TOOLS_DIR:-${repo_root}/build}"

output_dir="${OUTPUT_DIR:-${repo_root}/out}"
ota_input_dir="${OTA_INPUT_DIR:-${repo_root}/ota}"
ota_dir="${OTA_DIR:-${repo_root}/ota-16}"
artifacts_dir="${ARTIFACTS_DIR:-${repo_root}/artifacts}"
work_dir="${WORK_DIR:-${repo_root}/workdir/forgejo-final}"

package_registry_base="${PACKAGE_REGISTRY_BASE:?PACKAGE_REGISTRY_BASE is required}"
package_branch="${PACKAGE_BRANCH:?PACKAGE_BRANCH is required}"

resolve_package_url() {
    local filename="$1"
    local primary="${package_registry_base}/${package_branch}/${filename}"
    local fallback="${package_registry_base}/main/${filename}"
    local status
    status="$(curl -sS -L -o /dev/null -r 0-0 -w '%{http_code}' "${primary}")"
    case "${status}" in
        200|206)
            printf '%s\n' "${primary}"
            return 0
            ;;
        404)
            if [ "${package_branch}" = "main" ]; then
                echo "${filename} not found in registry on branch 'main'" >&2
                return 1
            fi
            echo "Branch '${package_branch}' has no ${filename}, falling back to main" >&2
            printf '%s\n' "${fallback}"
            return 0
            ;;
    esac
    echo "Unexpected HTTP ${status} probing ${primary}" >&2
    return 1
}

halium_system_url="$(resolve_package_url system.img.zip)"
kernel_images_url="$(resolve_package_url kernel.zip)"
libhybris_update_url="$(resolve_package_url libhybris-16-update.tar.xz)"

build_patches_dir="${repo_root}/build-patches/halium-generic-adaptation-build-tools"
kernel_work_dir="${work_dir}/kernel"

mkdir -p "${work_dir}" "${ota_input_dir}" "${output_dir}"
rm -rf "${ota_dir}" "${artifacts_dir}"

if [ -d "${build_dir}/.git" ]; then
    git -C "${build_dir}" fetch --depth 1 origin "${build_tools_branch}"
    git -C "${build_dir}" checkout -B "${build_tools_branch}" "origin/${build_tools_branch}"
    git -C "${build_dir}" reset --hard "origin/${build_tools_branch}"
    git -C "${build_dir}" clean -fdx
else
    rm -rf "${build_dir}"
    git clone --depth 1 --branch "${build_tools_branch}" "${build_tools_repo}" "${build_dir}"
fi

"${repo_root}/scripts/apply-patches.sh" "${build_patches_dir}" "${build_dir}"
"${repo_root}/scripts/package-halium-system.sh" \
    "${halium_system_url}" \
    "${ota_input_dir}/halium_halium_arm64-16.tar.xz" \
    "${work_dir}/halium-system"
curl -L --fail --output "${ota_input_dir}/libhybris-16-update.tar.xz" "${libhybris_update_url}"
"${repo_root}/scripts/prepare-device-tarball.sh" \
    "${kernel_images_url}" \
    "${output_dir}" \
    "${kernel_work_dir}"

"${build_dir}/prepare-fake-ota.sh" "${output_dir}/device_tegu_usrmerge.tar.xz" "${ota_dir}"
sudo env PATH="${PATH}" "${build_dir}/system-image-from-ota.sh" "${ota_dir}/ubuntu_command" "${output_dir}"

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
    "${output_dir}/device_tegu.tar.xz" \
    "${output_dir}/device_tegu.tar.build" \
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
