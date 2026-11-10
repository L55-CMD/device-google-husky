#!/usr/bin/env bash
set -euo pipefail

workspace_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
image_tag="${IMAGE_TAG:-husky-final-builder:local}"
skip_docker_build="${SKIP_DOCKER_BUILD:-0}"

if [ "${skip_docker_build}" != "1" ]; then
    docker build -t "${image_tag}" -f "${workspace_dir}/Dockerfile" "${workspace_dir}"
fi

docker_volumes=(-v "${workspace_dir}:${workspace_dir}")
if [ -n "${JOB_CONTAINER_NAME:-}" ]; then
  docker_volumes=(--volumes-from "${JOB_CONTAINER_NAME}")
fi

docker run --rm --privileged \
    -e WORKSPACE_DIR="$(pwd)" \
    -e PACKAGE_REGISTRY_BASE="${PACKAGE_REGISTRY_BASE:-}" \
    -e KERNEL_REGISTRY_BASE="${KERNEL_REGISTRY_BASE:-}" \
    -e PACKAGE_BRANCH="${PACKAGE_BRANCH:-}" \
    -e HUSKY_BUILD_VARIANT="${HUSKY_BUILD_VARIANT:-normal}" \
    -e KERNEL_RELEASE_TAG="${KERNEL_RELEASE_TAG:-}" \
    -e KERNEL_ZIP_SHA256="${KERNEL_ZIP_SHA256:-}" \
    "${docker_volumes[@]}" \
    -w "$(pwd)" \
    "${image_tag}" \
    ./scripts/run-in-container.sh
