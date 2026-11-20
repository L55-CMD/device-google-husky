#!/usr/bin/env bash
# Tests for require_files (scripts/build-helpers.sh), used by
# assemble-final-image.sh to gate the release artifact set.
#
# Negative focus: a missing vendor_kernel_boot.img (the image whose
# absence once booted a new kernel against a STALE on-device module
# tree, see husky-verify preflight history) must fail the build with
# the missing filename, not silently publish a partial set.
set -euo pipefail

repo_root="$(realpath "$(dirname "$0")/..")"
# shellcheck source=scripts/build-helpers.sh
source "${repo_root}/scripts/build-helpers.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# The release artifact list as assembled by assemble-final-image.sh.
artifacts=(
    system.img boot.img init_boot.img vendor_boot.img
    vendor_kernel_boot.img dtb.img dtbo.img
    system_dlkm.img vendor_dlkm.flatten.img
    device_husky.tar.xz device_husky.tar.build
    android-rootfs.img
    libhybris-16-update.tar.xz halium_halium_arm64-16.tar.xz
    ubuntu_command
)

paths=()
for f in "${artifacts[@]}"; do
    paths+=("${work}/${f}")
done

# --- case 1 (negative): everything present except vendor_kernel_boot.img ---
for f in "${artifacts[@]}"; do
    [ "${f}" = "vendor_kernel_boot.img" ] && continue
    : > "${work}/${f}"
done
if require_files "${paths[@]}" > "${work}/c1.log" 2>&1; then
    echo "require_files succeeded despite missing vendor_kernel_boot.img"
    exit 1
fi
grep -q "vendor_kernel_boot.img" "${work}/c1.log" \
    || { echo "missing filename not reported:"; cat "${work}/c1.log"; exit 1; }
echo "missing vendor_kernel_boot.img: failed as expected, filename reported"

# --- case 2 (negative): several missing files are all reported ------------
rm -f "${work}/dtb.img" "${work}/super.img" 2>/dev/null || true
rm -f "${work}/dtb.img"
if require_files "${paths[@]}" > "${work}/c2.log" 2>&1; then
    echo "require_files succeeded despite multiple missing artifacts"
    exit 1
fi
grep -q "vendor_kernel_boot.img" "${work}/c2.log" \
    && grep -q "dtb.img" "${work}/c2.log" \
    || { echo "not all missing filenames reported:"; cat "${work}/c2.log"; exit 1; }
echo "multiple missing artifacts: all filenames reported"

# --- case 3 (positive): complete set passes ---------------------------------
: > "${work}/vendor_kernel_boot.img"
: > "${work}/dtb.img"
require_files "${paths[@]}"
echo "complete artifact set: passed"

echo "PASS"
