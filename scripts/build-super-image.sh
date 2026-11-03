#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    cat >&2 <<USAGE
usage: $0 <lineage-zip-url> <halium-artifacts-dir> <output-super-img> [work-dir]

Assembles a flashable super.img for tegu (Pixel 9a) by:
  1. Downloading the LineageOS zip, extracting payload.bin
  2. Running vm03/payload_dumper (via docker) to extract vendor/system_ext/product
  3. Combining those with the Halium-built system/system_dlkm/vendor_dlkm using lpmake

Halium artifacts dir must contain:
  system.img, system_dlkm.img, vendor_dlkm.flatten.img

Requires: docker, curl, unzip, lpmake (apk: android-tools).
USAGE
    exit 64
fi

lineage_zip_url="$1"
halium_artifacts_dir="$(realpath "$2")"
output_super_img="$(realpath -m "$3")"
work_dir="${4:-$(pwd)/workdir/super}"
work_dir="$(realpath -m "${work_dir}")"

# tegu super layout (from lpdump of stock super_empty.img):
SUPER_SIZE=8531214336
GROUP_SIZE=8527020032
METADATA_SIZE=65536
METADATA_SLOTS=3

PAYLOAD_DUMPER_IMAGE="${PAYLOAD_DUMPER_IMAGE:-vm03/payload_dumper}"

if ! command -v lpmake >/dev/null 2>&1; then
    echo "lpmake not in PATH; install android-tools (apk add android-tools)" >&2
    exit 1
fi

mkdir -p "${work_dir}"
zip_cache="${work_dir}/lineage.zip"
payload_dir="${work_dir}/payload"
dump_dir="${work_dir}/dumped"
mkdir -p "${payload_dir}" "${dump_dir}"

echo "==> Downloading LineageOS zip"
if [ ! -f "${zip_cache}" ]; then
    curl -L --fail --output "${zip_cache}.part" "${lineage_zip_url}"
    mv "${zip_cache}.part" "${zip_cache}"
fi

echo "==> Extracting payload.bin"
rm -f "${payload_dir}/payload.bin"
unzip -oq "${zip_cache}" payload.bin -d "${payload_dir}"

echo "==> Dumping needed partitions from payload.bin"
# Only extract what we don't get from Halium; saves time and disk.
# Use --volumes-from when we're inside a job container so the spawned
# payload_dumper container sees the same paths as us.
docker_volume_args=()
if [ -n "${JOB_CONTAINER_NAME:-}" ]; then
    docker_volume_args+=(--volumes-from "${JOB_CONTAINER_NAME}")
else
    docker_volume_args+=(-v "${payload_dir}:${payload_dir}:ro" -v "${dump_dir}:${dump_dir}")
fi

docker run --rm \
    "${docker_volume_args[@]}" \
    "${PAYLOAD_DUMPER_IMAGE}" \
    "${payload_dir}/payload.bin" --out "${dump_dir}" --images vendor,system_ext,product

for img in vendor.img system_ext.img product.img; do
    if [ ! -f "${dump_dir}/${img}" ]; then
        echo "Expected ${img} after payload dump" >&2
        exit 1
    fi
done

echo "==> Verifying Halium-built inputs"
for img in system.img system_dlkm.img vendor_dlkm.flatten.img; do
    if [ ! -f "${halium_artifacts_dir}/${img}" ]; then
        echo "Missing ${img} in ${halium_artifacts_dir}" >&2
        exit 1
    fi
done

# Halium ships system.img in Android sparse format; lpmake's size auto-detection
# disagrees with the sparse file's reported total bytes. Flatten to raw ext4.
system_img_flat="${work_dir}/system.flat.img"
echo "==> Flattening system.img (sparse -> raw)"
rm -f "${system_img_flat}"
simg2img "${halium_artifacts_dir}/system.img" "${system_img_flat}"

echo "==> Running lpmake"
mkdir -p "$(dirname "${output_super_img}")"
lpmake \
    --metadata-size "${METADATA_SIZE}" \
    --metadata-slots "${METADATA_SLOTS}" \
    --super-name super \
    --virtual-ab \
    --device "super:${SUPER_SIZE}" \
    --group "google_dynamic_partitions_a:${GROUP_SIZE}" \
    --group "google_dynamic_partitions_b:${GROUP_SIZE}" \
    --partition system_a:readonly:0:google_dynamic_partitions_a \
        --image "system_a=${system_img_flat}" \
    --partition system_ext_a:readonly:0:google_dynamic_partitions_a \
        --image "system_ext_a=${dump_dir}/system_ext.img" \
    --partition product_a:readonly:0:google_dynamic_partitions_a \
        --image "product_a=${dump_dir}/product.img" \
    --partition vendor_a:readonly:0:google_dynamic_partitions_a \
        --image "vendor_a=${dump_dir}/vendor.img" \
    --partition vendor_dlkm_a:readonly:0:google_dynamic_partitions_a \
        --image "vendor_dlkm_a=${halium_artifacts_dir}/vendor_dlkm.flatten.img" \
    --partition system_dlkm_a:readonly:0:google_dynamic_partitions_a \
        --image "system_dlkm_a=${halium_artifacts_dir}/system_dlkm.img" \
    --partition system_b:readonly:0:google_dynamic_partitions_b \
    --partition system_ext_b:readonly:0:google_dynamic_partitions_b \
    --partition product_b:readonly:0:google_dynamic_partitions_b \
    --partition vendor_b:readonly:0:google_dynamic_partitions_b \
    --partition vendor_dlkm_b:readonly:0:google_dynamic_partitions_b \
    --partition system_dlkm_b:readonly:0:google_dynamic_partitions_b \
    --output "${output_super_img}" \
    --sparse

echo "==> super.img written to ${output_super_img}"
ls -lh "${output_super_img}"
